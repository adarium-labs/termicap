# HYPERLINK: OSC 8 Hyperlink Support Detection

**Feature:** Tier 4 OSC 8 hyperlink support classification (passive heuristic + XTVERSION refinement) plus a new shared `Termicap.Version` utility.
**Requirements:** FUNC-HYP-001 through FUNC-HYP-022 (`docs/requirements/hyperlink.sdoc`).
**Parent Requirements:** TERM-ID (REQ-TID), XTVERSION (REQ-XTV), CAP (REQ-CAP), SXL (REQ-SXL — refactor target).
**Status:** Proposed.
**Date:** 2026-05-07.

---

## 1. Overview & Scope

OSC 8 is a one-way hyperlink markup sequence (`ESC ] 8 ; params ; url ST text ESC ] 8 ; ; ST`). No standardised query mechanism exists for OSC 8 capability discovery, so every reference framework either emits unconditionally (termenv, rich, termcolor, lipgloss) or excludes a small list of legacy `TERM` patterns and emits otherwise (tcell, wezterm/termwiz, with hyperlinks defaulting to `true`). Termicap follows the second school but adds two extra refinements:

1. A **`Terminal_Kind` exclusion** layer that catches Apple Terminal (which advertises `TERM=xterm-256color` and would otherwise leak through the legacy-`TERM` filter while rendering OSC 8 as visible text).
2. An **XTVERSION-version-gated** refinement layer that promotes `Likely_Supported -> Supported` when the active XTVERSION probe confirms an emulator+version on a known-good list, and demotes `* -> Unsupported` for known-too-old VTE / Alacritty / xterm builds that render raw OSC 8 as garbage.

Two-tier delivery aligns with the existing `Terminal_Capabilities` / `Full_Terminal_Capabilities` split (FUNC-CAP-001, FUNC-HYP-014, FUNC-HYP-015):

| Tier | Where | Source | Latency |
|------|-------|--------|---------|
| 1 | `Terminal_Capabilities.Hyperlinks` | `Classify_Hyperlinks_Support (Env, Identity)` — pure SPARK Silver | 0 ms (no I/O) |
| 2 | `Full_Terminal_Capabilities.Hyperlinks` | `Refine_With_XTVERSION (Passive, XTV)` over the existing Step-9 XTVERSION result | 0 ms (consumes already-fetched XTV) |

**Tier 2 reuses the XTVERSION result already collected by `Detect_Full` Step 9** (mirrors the DA1 reuse precedent set by ADR-0027 for Sixel) — no new probe session, no new FFI, no new platform body. ADR-0038 in this iteration formalises the precedent.

**Cross-cutting deliverable**: a new shared `Termicap.Version` package (FUNC-HYP-013) provides `Version`, `Parse`, `Compare`, and `Version_Ordering`. The same package will be adopted by the existing `Termicap.Graphics` to satisfy FUNC-HYP-022 (the Sixel refactor).

### Out of scope

- **No OSC 8 protocol probe** (FUNC-HYP-019). Terminals do not respond to OSC 8 capability queries; a probe would be impossible.
- **No terminfo / termcap lookup** (FUNC-HYP-020). No standard capability for OSC 8 exists.
- **No multiplexer passthrough heuristic** (FUNC-HYP-021). Tmux / Screen always classify as `Unknown` until and unless a follow-up requirement adds a `tmux allow-passthrough` inspector.

---

## 2. Framework Survey

Every comparable library either (a) emits OSC 8 unconditionally trusting silent ignore, or (b) suppresses on a fixed legacy-`TERM` exclusion list. **None performs a protocol-level detection probe.** The table below cites primary source for each row.

| Framework | Approach | Default | Known-bad list | Cite |
|-----------|----------|---------|----------------|------|
| termenv (Go) | Unconditional emit | n/a | none | `reference-frameworks/termenv/hyperlink.go:9-11` (the entire emit logic; no detection helper) |
| rich (Python) | Unconditional emit, suppressed only on legacy Windows | yes | legacy Windows console | `reference-frameworks/analysis/rich-analysis.md:34, :275` |
| termcolor (Rust) | Unconditional emit (ANSI mode); Windows console mode skipped | yes | Windows console | `reference-frameworks/analysis/termcolor-analysis.md:46, :267-274` |
| lipgloss (Go) | Inherits termenv behaviour | yes | inherited | `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md:326-336` |
| tcell (Go) | Exclusion list on legacy `TERM` | "supported" | `vt*`, `ansi`, `linux`, `sun` | `reference-frameworks/analysis/tcell-analysis.md:37` |
| wezterm/termwiz (Rust) | Defaults to `true`; user can override via `ProbeHints` | yes | none built in | `reference-frameworks/wezterm/termwiz/src/caps/mod.rs:89-91` (hint), `:266-270` (default), `:339-342` (accessor) |
| notcurses (C) | Does not probe; emits if `terminfo` Su present (proxy capability) | partial | terminfo-driven | `reference-frameworks/analysis/notcurses-analysis.md` (general) |

Quoted from termwiz comment block (`reference-frameworks/wezterm/termwiz/src/caps/mod.rs:266-270`):

```rust
// The use of OSC 8 for hyperlinks means that it is generally
// safe to assume yes: if the terminal doesn't support it,
// the text will look "OK", although some versions of VTE based
// terminals had a bug where it look like garbage.
let hyperlinks = hints.hyperlinks.unwrap_or(true);
```

This explicitly motivates Termicap's XTVERSION demotion step (FUNC-HYP-010 / §6.B): the failure mode termwiz documents ("some versions of VTE based terminals had a bug where it look like garbage") is exactly what `XTVERSION_Rejected` rules out.

Global synthesis confirms: *"No detection protocol exists. Libraries emit OSC 8 sequences unconditionally when configured, suppressing them only on known-unsupported terminals (legacy Windows, TERM matching `vt*|ansi|linux|sun` per tcell)."* (`reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md:326`).

### What Termicap adopts vs invents

| Pattern | Borrowed from | Adaptation in Termicap |
|---------|---------------|------------------------|
| Legacy `TERM` exclusion (`vt*`, `ansi`, `linux`, `sun`, `dumb`) | tcell exclusion list, GLOBAL-SYNTHESIS §2.8 | Encoded as named String constants `TERM_PREFIX_VT` etc. (FUNC-HYP-006) |
| Default to "support" when no exclusion fires | termwiz, termenv, rich | Mapped to `Likely_Supported` (FUNC-HYP-005) for known-good kinds; `Unknown` otherwise. `Unknown` is callable as "may emit" per FUNC-HYP-001 final paragraph |
| VTE garbled-output failure mode | termwiz comment | Encoded as XTVERSION demotion rule for `VTE < 0.50.0` (FUNC-HYP-010) |
| Apple Terminal exclusion | Termicap.Graphics precedent | Re-used here as `Terminal_Kind` exclusion (FUNC-HYP-005b) |
| Known-good list extension to Ghostty / VSCode / WarpTerminal / JediTerm | Alhadis OSC 8 adoption tracker (cited in FUNC-HYP-005 comment) | All emulators must already exist in `Terminal_Kind`; no new enum literals introduced |
| **Two-tier passive + active version gate** | None (novel) | New: only Termicap consumes XTVERSION to refine the OSC 8 verdict. Mirrors how `Termicap.Graphics` consumes XTVERSION for the Sixel name match (FUNC-SXL-007) |

**Conclusion:** Termicap implements the strict superset of tcell's exclusion model + termwiz's "default true" model, augmented by an XTVERSION-version refinement that none of the surveyed libraries implements. The added refinement is the only way to surface the well-documented "VTE < 0.50 prints OSC 8 as visible junk" failure mode without an actual protocol probe.

---

## 3. Requirements Traceability

| UID | Priority | Summary | Design element |
|-----|----------|---------|----------------|
| FUNC-HYP-001 | Must | `Hyperlinks_Support` enum (`Unsupported / Likely_Supported / Supported / Unknown`, ordered) | §5.1, `Termicap.Hyperlinks` spec |
| FUNC-HYP-002 | Must | `Hyperlinks_Result` record (Support, Provenance, Terminal_Version_Known) | §5.2 |
| FUNC-HYP-003 | Must | `Hyperlinks_Provenance` enum (7 values) | §5.3 |
| FUNC-HYP-004 | Must | `TERM` legacy-prefix exclusion (vt, ansi, linux, sun, dumb) | §6.A step 1; named constants §5.4 |
| FUNC-HYP-005 | Must | Known-good `Terminal_Kind` list -> `Likely_Supported` | §6.A step 3; §7 known-good table |
| FUNC-HYP-005b | Must | `Terminal_Kind` exclusion (Apple_Terminal, Dumb, Linux_Console) | §6.A step 2 |
| FUNC-HYP-006 | Must | Named constants `TERM_PREFIX_VT` etc. | §5.4 |
| FUNC-HYP-007 | Must | `Classify_Hyperlinks_Support (Env, Identity)` — pure SPARK | §5.5; §8 |
| FUNC-HYP-008 | Must | No global state in passive function | §8 |
| FUNC-HYP-009 | Must | XTVERSION promotion to `Supported` (version >= min) | §6.B; §7 known-good table |
| FUNC-HYP-010 | Must | XTVERSION demotion to `Unsupported` (version < min) | §6.B |
| FUNC-HYP-011 | Must | `Refine_With_XTVERSION` (SPARK_Mode Off because of `Unbounded_String`) | §5.6 |
| FUNC-HYP-012 | Must | Allowed state-transition table — exhaustive | §6.B transition table |
| FUNC-HYP-013 | Must | New `Termicap.Version` package: `Version`, `Parse`, `Compare`, `Version_Ordering` | §4.3, §5.7, §6.C |
| FUNC-HYP-014 | Must | `Hyperlinks` field in `Terminal_Capabilities`; `Assemble` parameter | §9.1 |
| FUNC-HYP-015 | Must | `Hyperlinks` field in `Full_Terminal_Capabilities`; `Assemble_Full` parameter; `Detect_Full` calls `Refine_With_XTVERSION` | §9.2, §9.3 |
| FUNC-HYP-016 | Must | Package structure `Termicap.Hyperlinks` (mixed SPARK) + `Termicap.Hyperlinks.IO` for active refinement | §4.1, §4.2, §8 |
| FUNC-HYP-017 | Must | Cross-platform parity (no platform body) | §4.4 |
| FUNC-HYP-018 | Must | SPARK Silver provability of `Classify_Hyperlinks_Support` | §8 |
| FUNC-HYP-019 | Wont | Out-of-scope: no OSC 8 protocol probe | §1 |
| FUNC-HYP-020 | Wont | Out-of-scope: no terminfo lookup | §1 |
| FUNC-HYP-021 | Wont | Out-of-scope: no multiplexer passthrough | §1, §6.A |
| FUNC-HYP-022 | Must | Sixel refactor: `Termicap.Graphics` consumes `Termicap.Version` for any version comparison | §10 |

---

## 4. Package Decomposition

### 4.1 New package: `Termicap.Hyperlinks` (`src/termicap-hyperlinks.ads`, `.adb`)

- **Spec** carries `pragma SPARK_Mode (On)` at package level. Declares `Hyperlinks_Support`, `Hyperlinks_Provenance`, `Hyperlinks_Result`, the named `TERM_*` constants, and the two public functions `Classify_Hyperlinks_Support` (SPARK On, `Global => null`) and `Refine_With_XTVERSION` (SPARK Off, because of `Unbounded_String` in `XTVERSION_Result`).
- **Body** carries `pragma SPARK_Mode (Off)` at package level. The body of `Classify_Hyperlinks_Support` carries a locally-applied `pragma SPARK_Mode (On)` (mixed SPARK pattern, see ADR-0013 and FUNC-HYP-016). `Refine_With_XTVERSION` body is plain Ada.
- **No platform-specific body files** — the entire package is platform-neutral. The XTVERSION result already abstracts the POSIX/Windows split (FUNC-HYP-017).
- Withed packages: `Termicap.Environment`, `Termicap.Terminal_Id`, `Termicap.XTVERSION`, `Termicap.Version`, `Ada.Strings.Unbounded` (for the XTVERSION name comparison only — used inside `Refine_With_XTVERSION` body, not in the SPARK On region), `Ada.Characters.Handling` (case folding).

### 4.2 New child package: `Termicap.Hyperlinks.IO` — **NOT created**

The original feature brief asked us to consider a `Termicap.Hyperlinks.IO` child package "for the active refinement". After reading FUNC-HYP-011 carefully, the active refinement is `Refine_With_XTVERSION (Passive, XTV)` — a pure value-to-value transformation that does **no I/O**. The XTVERSION I/O is already provided by `Termicap.XTVERSION.IO` (xtversion tech-spec §G), and `Detect_Full` already calls `Query_And_Identify` in Step 9 (capabilities body, line 252-253). The refinement function consumes the *value* of that result — there is no probe to perform.

Creating an empty `Termicap.Hyperlinks.IO` child would add a package solely to host one wrapper that calls `Refine_With_XTVERSION`. We reject that. `Refine_With_XTVERSION` lives directly in `Termicap.Hyperlinks` (spec line ~80, body locally `SPARK_Mode Off`). The package structure thus matches MOUSE/KKB *less* than it matches `Termicap.DECRPM` (single SPARK-mixed package, no `.IO` child) — see ADR-0038 for the explicit rationale.

### 4.3 New shared package: `Termicap.Version` (`src/termicap-version.ads`, `.adb`)

- **Spec** carries `pragma SPARK_Mode (On)` at package level. Declares `Version` (private if useful; flat record otherwise — see §5.7), `Version_Ordering`, `Parse` and `Compare`, `Make` constructors, plus `Compare_Strings` convenience that combines parse+compare with a `Comparable` Boolean out parameter for callers that want a one-shot.
- **Body** carries `pragma SPARK_Mode (On)` at package level. The body is pure arithmetic on bounded fixed-size storage (an array of `Natural` indexed by a small subtype). No FFI, no I/O, no allocation, no `Unbounded_String`. SPARK Silver target.
- **No platform body files**.
- Withed packages: none from Termicap — fully self-contained. May `with Interfaces` only if we need bounded `Natural_64` (we do not — `Natural` is sufficient for any version component we'll see in practice).

The decision to make this a top-level shared utility rather than a private helper inside `Termicap.Hyperlinks` is recorded in ADR-0036.

### 4.4 Modifications to `Termicap.Capabilities`

- Add a `Hyperlinks : Termicap.Hyperlinks.Hyperlinks_Result` field to `Terminal_Capabilities` (ads line 78-88) and to `Full_Terminal_Capabilities` (ads line 202-217).
- Extend `Assemble` with a new `Hyperlinks : Termicap.Hyperlinks.Hyperlinks_Result` parameter, defaulted to the canonical default value.
- Extend `Assemble_Full` with the same parameter (which the body of `Detect_Full` will pass after computing `Refine_With_XTVERSION (Base.Hyperlinks, XTV)`).
- Detect (`src/posix/termicap-capabilities.adb` line 95-147 and the Windows mirror) computes `Hyperlinks` after Step 4 (color) and before Step 5 (size) using the already-captured `Env` and `Id`, and passes it to `Assemble`.
- Detect_Full (line 244-272) calls `Refine_With_XTVERSION (Base_Caps.Hyperlinks, XTV)` between Step 9 (XTVERSION) and Step 10 (Graphics), per FUNC-HYP-015. The refined value goes into `Assemble_Full`.

### 4.5 Modifications to `Termicap.Graphics` (FUNC-HYP-022)

See §10. The Graphics package currently does no version comparison (the body is a stub for the APC parser; the I/O bodies have no version logic). The refactor therefore reduces to: *when version-gated logic is added in any future Graphics work, it MUST go through `Termicap.Version`*. We will additionally add a `with Termicap.Version;` line in `src/termicap-graphics.ads` and a single helper that demonstrates the wiring (parsing `XTV.Terminal_Version` from the kitty XTVERSION reply for the FUNC-SXL-003 `Kitty_Graphics_Version` field), even though this helper currently goes unused. ADR-0036 covers why we do not introduce a parallel local utility.

### 4.6 File layout

| File | Purpose | SPARK_Mode | Approx LOC |
|------|---------|------------|-----------|
| `src/termicap-version.ads` | Shared version utility spec | On (package level) | 90 |
| `src/termicap-version.adb` | Body — `Parse`, `Compare`, `Make` | On (package level) | 130 |
| `src/termicap-hyperlinks.ads` | Spec — types, constants, `Classify_Hyperlinks_Support`, `Refine_With_XTVERSION` | On (package level) | 200 |
| `src/termicap-hyperlinks.adb` | Body — classifier (locally SPARK On), refinement (Off) | Off (package); On (Classify body) | 220 |
| `src/termicap-capabilities.ads` (modified) | Add field + Assemble param to both records | unchanged | +30 |
| `src/posix/termicap-capabilities.adb` (modified) | Wire passive call into `Detect`, refinement call into `Detect_Full` | unchanged | +25 |
| `src/windows/termicap-capabilities.adb` (modified) | Same as POSIX | unchanged | +25 |
| `src/termicap-graphics.ads` (modified) | `with Termicap.Version;` + optional helper | unchanged | +15 |

**Total new code:** ~640 LOC across two new packages plus ~95 LOC of integration. Test files and example are listed in §11.

---

## 5. Type Design

### 5.1 `Hyperlinks_Support` enumeration (FUNC-HYP-001)

```ada
type Hyperlinks_Support is (Unsupported, Likely_Supported, Supported, Unknown);
```

Ordering follows the requirement: `Unsupported < Likely_Supported < Supported < Unknown` in `'Pos`. The requirement explicitly says callers should treat `Unknown` as "may emit" (equivalent to `Likely_Supported` for output purposes), so its position at the high end of `'Pos` is **not** semantic — it is purely a sentinel. Threshold tests (`Support >= Likely_Supported`) include `Supported` but **not** `Unknown`; documentation will warn callers to compare with explicit literals when they want to fold `Unknown` in.

A flat enum is preferred over a discriminated record for `Support` because all four values share the same payload (none) and the entire interpretation is value-based. This mirrors `XTVERSION_Status` and the `Unicode_Level` enums.

### 5.2 `Hyperlinks_Result` record (FUNC-HYP-002)

```ada
type Hyperlinks_Result is record
   Support                : Hyperlinks_Support := Unknown;
   Provenance             : Hyperlinks_Provenance := Default;
   Terminal_Version_Known : Boolean := False;
end record;

DEFAULT_HYPERLINKS_RESULT : constant Hyperlinks_Result :=
  (Support => Unknown, Provenance => Default, Terminal_Version_Known => False);
```

A **flat record**, not a discriminated record, is chosen — see ADR-0037. Rationale summary: every `Provenance` value is meaningful regardless of `Support`, the field shapes are identical across all combinations, and SPARK provability is simpler when all fields are unconditionally accessible. The discriminated approach (one variant per `Provenance`) would offer no compile-time safety because there is no per-variant payload to protect.

### 5.3 `Hyperlinks_Provenance` enumeration (FUNC-HYP-003)

```ada
type Hyperlinks_Provenance is
  (Default,
   Env_Excluded,
   Env_Known_Good,
   Env_Unknown,
   XTVERSION_Confirmed,
   XTVERSION_Rejected,
   XTVERSION_Unresolved);
```

Linear chain — exclusion -> known-good -> XTVERSION refinement — yields seven distinct, reachable states. This contrasts with the SIXEL parallel-flags approach (`Sixel_Via_DA1`, `Kitty_Via_Active_Probe`) and is justified by FUNC-HYP-003 comment: the hyperlink chain is linear, not parallel.

### 5.4 Named constants (FUNC-HYP-006)

```ada
TERM_PREFIX_VT     : constant String := "vt";
TERM_PREFIX_ANSI   : constant String := "ansi";
TERM_LINUX         : constant String := "linux";
TERM_PREFIX_SUN    : constant String := "sun";
TERM_DUMB          : constant String := "dumb";
```

All declared in `Termicap.Hyperlinks` spec under SPARK_Mode On. Naming follows ALL_CAPS_WITH_UNDERSCORES per the project coding standard. Mirrors `Termicap.Graphics`'s `TERM_*` block.

### 5.5 `Classify_Hyperlinks_Support` signature (FUNC-HYP-007)

```ada
function Classify_Hyperlinks_Support
  (Env      : Termicap.Environment.Environment;
   Identity : Termicap.Terminal_Id.Terminal_Identity)
   return Hyperlinks_Result
with
  SPARK_Mode => On,
  Global     => null;
```

The function reads `Env` (specifically the `TERM` value) and `Identity.Kind`. It is fully deterministic with respect to those inputs. SPARK Silver is the verification target (FUNC-HYP-018).

### 5.6 `Refine_With_XTVERSION` signature (FUNC-HYP-011)

```ada
function Refine_With_XTVERSION
  (Passive : Hyperlinks_Result;
   XTV     : Termicap.XTVERSION.XTVERSION_Result)
   return Hyperlinks_Result
with SPARK_Mode => Off;
```

Body is plain Ada. Performs `XTV.Status = Success` discriminator check, case-insensitive name match against the known-good table, version parse via `Termicap.Version.Parse`, version compare via `Termicap.Version.Compare`, and produces the refined `Hyperlinks_Result`. No I/O. Outer `exception when others => return Passive` handler guarantees no exception leaks (defence in depth — the body should never raise since it does no I/O and Compare is total).

### 5.7 `Termicap.Version` types (FUNC-HYP-013)

```ada
MAX_VERSION_COMPONENTS : constant := 8;
--  Sufficient for every version we have ever observed (the longest in the
--  known-good table is "1.72.0" -- 3 components).  Bounded at 8 to keep the
--  type stack-allocatable.

subtype Component_Index is Positive range 1 .. MAX_VERSION_COMPONENTS;
type Component_Array is array (Component_Index) of Natural;

type Version is record
   Count : Natural := 0;        --  Number of valid components (0 .. MAX_VERSION_COMPONENTS).
   Parts : Component_Array := [others => 0];
end record;

ZERO_VERSION : constant Version := (Count => 0, Parts => [others => 0]);

type Version_Ordering is (Less_Than, Equal, Greater_Than);

function Parse (S : String; Result : out Version) return Boolean
with SPARK_Mode => On, Global => null;
--  True on success and Result populated; False on any malformed input
--  (Result undefined / Result = ZERO_VERSION).

function Compare (Left, Right : Version) return Version_Ordering
with SPARK_Mode => On, Global => null;
--  Component-wise lexicographic compare; shorter version with all matching
--  leading components is Less_Than longer (FUNC-HYP-013 rule 2).
```

Rejected alternative: `Unbounded_String`-backed type. Rejected because `Unbounded_String` is outside the SPARK 2014 subset; the requirement asks for SPARK Silver explicitly.

Rejected alternative: `Vector` (Ada.Containers). Same SPARK reason.

A fixed-bound array of `Natural` is sufficient, allocation-free, copy-cheap, and SPARK-provable.

---

## 6. Algorithm Details

### 6.A Passive classification cascade (FUNC-HYP-004 / -005 / -005b / -007)

Pseudocode for `Classify_Hyperlinks_Support`:

```
function Classify_Hyperlinks_Support (Env, Identity) return Hyperlinks_Result is
   T : constant String := lowercase(Env.Value("TERM"));
begin
   --  Step 1: TERM legacy-prefix exclusion (FUNC-HYP-004) -- BEFORE Kind check.
   if Has_Prefix (T, TERM_PREFIX_VT)
     or Has_Prefix (T, TERM_PREFIX_ANSI)
     or T = TERM_LINUX
     or Has_Prefix (T, TERM_PREFIX_SUN)
     or T = TERM_DUMB
   then
      return (Unsupported, Env_Excluded, Terminal_Version_Known => False);
   end if;

   --  Step 2: Terminal_Kind exclusion (FUNC-HYP-005b) -- runs even when TERM is benign.
   case Identity.Kind is
      when Apple_Terminal | Dumb | Linux_Console =>
         return (Unsupported, Env_Excluded, False);
      when others =>
         null;
   end case;

   --  Step 3: Known-good Terminal_Kind list (FUNC-HYP-005).
   case Identity.Kind is
      when Alacritty | Foot | Ghostty | ITerm2 | JediTerm | Kitty | Konsole
         | Mintty | VSCode | VTE | WarpTerminal | WezTerm | Windows_Terminal
         | Xterm =>
         return (Likely_Supported, Env_Known_Good, False);
      when others =>
         --  Rxvt, Screen, Tmux, Unknown, Apple_Terminal/Dumb/Linux_Console
         --  (already handled), and any future Terminal_Kind not yet classified.
         return (Unknown, Env_Unknown, False);
   end case;
end Classify_Hyperlinks_Support;
```

Step ordering is normative. `Is_Multiplexer` (per FUNC-HYP-021) drops out for free: `Tmux` and `Screen` fall through to the `others` arm of step 3 and yield `Unknown`. The body never inspects `Identity.Is_Multiplexer` directly.

### 6.B Active refinement state transitions (FUNC-HYP-009 / -010 / -012)

Pseudocode for `Refine_With_XTVERSION`:

```
function Refine_With_XTVERSION (Passive, XTV) return Hyperlinks_Result is
begin
   --  No active refinement when the passive heuristic positively excluded.
   if Passive.Support = Unsupported and Passive.Provenance = Env_Excluded then
      return Passive;     --  FUNC-HYP-012 invariant: Unsupported is terminal.
   end if;

   --  No active refinement when XTVERSION did not succeed.
   if XTV.Status /= Success then
      return (Passive.Support, XTVERSION_Unresolved, Passive.Terminal_Version_Known);
   end if;

   --  Look up emulator in the known-good version table (case-insensitive).
   declare
      Entry_Found : Boolean;
      Min_Version : Version;
      Treat_Any   : Boolean;     --  True for "(any)" minimum-version emulators.
   begin
      Lookup_Known_Good (XTV.Terminal_Name, Entry_Found, Min_Version, Treat_Any);
      if not Entry_Found then
         return (Passive.Support, XTVERSION_Unresolved,
                 Terminal_Version_Known => False);
      end if;

      --  Parse the version string.
      declare
         Reported    : Version;
         Ok          : constant Boolean := Termicap.Version.Parse
                                              (To_String (XTV.Terminal_Version), Reported);
      begin
         if not Ok then
            --  Name recognised, version unparseable: stay on passive support, mark version_known.
            return (Passive.Support, Env_Known_Good, Terminal_Version_Known => True);
         end if;

         --  "(any)" entries: any successfully parsed version satisfies the minimum.
         if Treat_Any then
            return (Promote (Passive), XTVERSION_Confirmed, True);
         end if;

         --  Compare reported vs minimum.
         case Termicap.Version.Compare (Reported, Min_Version) is
            when Less_Than =>
               --  Demotion (FUNC-HYP-010).
               return (Unsupported, XTVERSION_Rejected, True);
            when Equal | Greater_Than =>
               return (Promote (Passive), XTVERSION_Confirmed, True);
         end case;
      end;
   end;
end Refine_With_XTVERSION;

function Promote (P : Hyperlinks_Result) return Hyperlinks_Support is
   --  Likely_Supported -> Supported; Unknown -> Supported; otherwise unchanged.
   case P.Support is
      when Likely_Supported | Unknown => return Supported;
      when Supported                  => return Supported;     --  unreachable in practice
      when Unsupported                => return Unsupported;   --  blocked by guard above
   end case;
end Promote;
```

**Complete state-transition table (FUNC-HYP-012):**

| Passive Support | XTVERSION outcome | Refined Support | Refined Provenance | Terminal_Version_Known |
|-----------------|-------------------|-----------------|--------------------|-------------------------|
| Unsupported (Env_Excluded) | Any | Unsupported | Env_Excluded (unchanged) | False (unchanged) |
| Likely_Supported | Status /= Success | Likely_Supported | XTVERSION_Unresolved | False |
| Likely_Supported | Confirmed name, version >= min | Supported | XTVERSION_Confirmed | True |
| Likely_Supported | Confirmed name, version < min | Unsupported | XTVERSION_Rejected | True |
| Likely_Supported | Confirmed name, "(any)" min | Supported | XTVERSION_Confirmed | True |
| Likely_Supported | Confirmed name, version unparseable | Likely_Supported | Env_Known_Good (unchanged) | True |
| Likely_Supported | Unrecognised name | Likely_Supported | XTVERSION_Unresolved | False |
| Unknown | Status /= Success | Unknown | XTVERSION_Unresolved | False |
| Unknown | Confirmed name, version >= min | Supported | XTVERSION_Confirmed | True |
| Unknown | Confirmed name, version < min | Unsupported | XTVERSION_Rejected | True |
| Unknown | Confirmed name, "(any)" min | Supported | XTVERSION_Confirmed | True |
| Unknown | Confirmed name, version unparseable | Unknown | XTVERSION_Unresolved | True |
| Unknown | Unrecognised name | Unknown | XTVERSION_Unresolved | False |

The "Unsupported is terminal" invariant (last row of FUNC-HYP-012 table) is enforced by the early return in the pseudocode above. ADR-0038 documents the XTVERSION reuse-not-reprobe choice.

### 6.C Version parser & comparator (FUNC-HYP-013)

`Termicap.Version.Parse (S, Result)`:

```
function Parse (S : String; Result : out Version) return Boolean is
   Cursor : Natural := S'First;
   Comp   : Natural := 0;
   N      : Natural := 0;
   Has_Digit : Boolean := False;
begin
   Result := ZERO_VERSION;
   if S'Length = 0 then return False; end if;

   loop
      exit when Cursor > S'Last;
      if S (Cursor) in '0' .. '9' then
         --  Bound check: prevent overflow on absurd input.
         if N > (Natural'Last - Character'Pos (S (Cursor)) + Character'Pos ('0')) / 10 then
            return False;
         end if;
         N := N * 10 + (Character'Pos (S (Cursor)) - Character'Pos ('0'));
         Has_Digit := True;
         Cursor := Cursor + 1;
      elsif S (Cursor) = '.' then
         if not Has_Digit then return False; end if;       --  leading or double dot
         if Comp = MAX_VERSION_COMPONENTS then return False; end if;
         Comp := Comp + 1;
         Result.Parts (Comp) := N;
         N := 0;
         Has_Digit := False;
         Cursor := Cursor + 1;
      else
         return False;     --  any other character invalidates the input
      end if;
   end loop;

   if not Has_Digit then return False; end if;             --  trailing dot
   if Comp = MAX_VERSION_COMPONENTS then return False; end if;
   Comp := Comp + 1;
   Result.Parts (Comp) := N;
   Result.Count := Comp;
   return True;
end Parse;
```

**Constraints for SPARK Silver:** no allocation; bounded loops (over `S'Range` and `Component_Index`); `Pre => True` (no precondition besides type constraints); `Post => True` initially, with stronger postconditions added as proof obligations are discharged.

`Termicap.Version.Compare (Left, Right)`:

```
function Compare (Left, Right : Version) return Version_Ordering is
   I : Component_Index'Base := 1;
begin
   loop
      exit when I > Left.Count and I > Right.Count;       --  both exhausted -> Equal
      if I > Left.Count  then return Less_Than; end if;   --  shorter is less (FUNC-HYP-013 rule 2)
      if I > Right.Count then return Greater_Than; end if;
      if Left.Parts (I) < Right.Parts (I)  then return Less_Than;    end if;
      if Left.Parts (I) > Right.Parts (I)  then return Greater_Than; end if;
      I := I + 1;
   end loop;
   return Equal;
end Compare;
```

`Compare` is total — no input falsifies it. SPARK postcondition will assert antisymmetry and reflexivity as Silver-level proof obligations.

---

## 7. Known-Good Version Database (FUNC-HYP-009 / -010)

Encoded as a static lookup table inside `Termicap.Hyperlinks` body. Each entry holds a case-insensitive name token, a parsed `Termicap.Version.Version`, and a `Treat_Any : Boolean` flag for "(any)" entries.

| XTVERSION name token (case-insensitive substring) | Min version | "Any?" | Source / citation |
|---|---|---|---|
| `iTerm2` | 3.1.0 | no | iTerm2 release notes — OSC 8 added in iTerm2 3.1 (Aug 2017). Aligned with `reference-frameworks/analysis/00-Terminal_Capability_Detection.md`. |
| `kitty` | 0.19.0 | no | kitty changelog — OSC 8 added in 0.19 (Sept 2020). Cross-referenced via Alhadis OSC 8 adoption tracker. |
| `WezTerm` | 0.0.0 | yes | OSC 8 advertised from initial public release; **no precise minimum known**. `reference-frameworks/analysis/wezterm-analysis.md:49` confirms "Full support". |
| `VTE` | 0.50.0 | no | VTE 0.50 / gnome-terminal 3.26 (Sept 2017). The reference-source flag for the `XTVERSION_Rejected` case; see termwiz `caps/mod.rs:266-270` motivating comment. |
| `foot` | 0.0.0 | yes | OSC 8 from initial public release; **no precise minimum known**. |
| `Alacritty` | 0.11.0 | no | Alacritty 0.11 (Oct 2022). Comment in FUNC-HYP-010 documents `Alacritty < 0.12.0` as known-too-old; minimum here is the *first version that added it* (0.11), demotion is `Reported < 0.11.0`. |
| `mintty` | 3.4.0 | no | mintty 3.4 (Aug 2020). |
| `xterm` | 357.0 | no | xterm patch 357 (May 2020). xterm patch levels are single integers; `Termicap.Version` handles single-component versions natively (FUNC-HYP-013 comparison rule 1 + 3). |
| `Windows_Terminal` | 1.4.0 | no | Windows Terminal 1.4 (Sept 2020). |
| `VSCode` | 1.72.0 | no | VSCode 1.72 (Oct 2022). |
| `Ghostty` | 0.0.0 | yes | OSC 8 from initial public release; **no precise minimum known**. |
| `Konsole` | 0.0.0 | yes | OSC 8 via VTE; any current Konsole; **no precise minimum known**. |

**Entries explicitly outside the table:**
- Apple_Terminal / Dumb / Linux_Console — never reach this table (already excluded by FUNC-HYP-005b before XTVERSION refinement).
- Rxvt / Screen / Tmux / JediTerm / WarpTerminal — passive heuristic gives `Likely_Supported` (for the latter two) or `Unknown`; XTVERSION refinement leaves them at `XTVERSION_Unresolved` because the table has no entry. This is the correct safe behaviour.

The table is encoded as an immutable constant array of records:

```ada
type Known_Good_Entry is record
   Name        : access constant String;       --  pointer into a string-literal pool
   Min_Version : Termicap.Version.Version;
   Treat_Any   : Boolean;
end record;

KNOWN_GOOD : constant array (Positive range <>) of Known_Good_Entry := [...];
```

(Or equivalent — final encoding will avoid `access` if SPARK constraints in the body make it awkward; an enumerated `Token_Kind` plus a mapping is also acceptable. This is an implementation detail to be settled in Phase 6.)

---

## 8. SPARK Strategy

The feature has **no FFI**. All impure calls live in already-isolated packages (`Termicap.XTVERSION.IO` for the active probe; `Termicap.Environment.Capture` for env capture, called by the upstream `Detect`/`Detect_Full`). The SPARK boundary in this feature is therefore internal to the package body.

| Region | SPARK_Mode | Reason |
|--------|-----------|--------|
| `Termicap.Version` spec | On (package level) | Pure types and pure function signatures |
| `Termicap.Version` body | On (package level) | Bounded arithmetic; no allocation; SPARK Silver target |
| `Termicap.Hyperlinks` spec | On (package level) | All public types and constants are SPARK-friendly. `Refine_With_XTVERSION` carries `with SPARK_Mode => Off` aspect on its declaration (legal — declarations may opt out individually) because its body needs `Unbounded_String`. |
| `Termicap.Hyperlinks` body | Off (package level) | Allows `Unbounded_String` and `Ada.Strings.Fixed.Index` usage in `Refine_With_XTVERSION`. |
| `Classify_Hyperlinks_Support` body | On (locally applied via `pragma SPARK_Mode (On)` inside the subprogram) | SPARK Silver target; mixed pattern per ADR-0013 / FUNC-HYP-016 |
| `Refine_With_XTVERSION` body | Off | Uses `Unbounded_String` |

**Silver-level proof obligations** (to be discharged by GNATprove):

1. `Classify_Hyperlinks_Support` has `Global => null` and never raises.
2. `Termicap.Version.Parse` never raises and produces `Result.Count <= MAX_VERSION_COMPONENTS`.
3. `Termicap.Version.Compare` never raises and is total.

GNATprove invocation (added to existing target):
```
alr exec -- gnatprove -P termicap.gpr --level=2
```

---

## 9. Capability Integration

### 9.1 `Terminal_Capabilities` change (FUNC-HYP-014)

**Spec change** (`src/termicap-capabilities.ads`):

```ada
with Termicap.Hyperlinks;       --  added near other withs

type Terminal_Capabilities is record
   ...                                                        --  existing fields
   DA1                    : Termicap.DA1.DA1_Capabilities;
   Hyperlinks             : Termicap.Hyperlinks.Hyperlinks_Result :=
                              Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT;
end record;

function Assemble
  (TTY_Stdin   : Boolean;
   ...                                                        --  existing parameters
   DA1         : Termicap.DA1.DA1_Capabilities;
   Hyperlinks  : Termicap.Hyperlinks.Hyperlinks_Result :=
                   Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT)
  return Terminal_Capabilities
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    Assemble'Result.Downsampling_Available
    = (Assemble'Result.Color >= Termicap.Color.Extended_256);
```

**Body change** (`src/posix/termicap-capabilities.adb`, mirrored in Windows body):

`Detect` body, after Step 4 (color) and before Step 5 (size):

```ada
HL : constant Termicap.Hyperlinks.Hyperlinks_Result :=
       Termicap.Hyperlinks.Classify_Hyperlinks_Support (Env, Id);
```

Then in the call to `Assemble`, append `Hyperlinks => HL`. No additional I/O.

### 9.2 `Full_Terminal_Capabilities` change (FUNC-HYP-015)

**Spec change**:

```ada
type Full_Terminal_Capabilities is record
   ...
   Clipboard  : Termicap.Clipboard.Clipboard_Capabilities;
   Hyperlinks : Termicap.Hyperlinks.Hyperlinks_Result :=
                  Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT;
end record;

function Assemble_Full
  (Base       : Terminal_Capabilities;
   ...                                                        --  existing parameters
   Clipboard  : Termicap.Clipboard.Clipboard_Capabilities;
   Hyperlinks : Termicap.Hyperlinks.Hyperlinks_Result :=
                  Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT)
   return Full_Terminal_Capabilities;
```

The `Hyperlinks` field on `Full_Terminal_Capabilities` shadows the one in `Base.Hyperlinks` — i.e., `Assemble_Full` populates the top-level `Hyperlinks` from its parameter, **not** from `Base.Hyperlinks`. This matches the flat projection rule explicitly stated in FUNC-HYP-015.

### 9.3 `Detect_Full` change (FUNC-HYP-015 step ordering)

In `src/posix/termicap-capabilities.adb` `Detect_Full` body, between the existing line 252 (XTV) and line 256 (GFX):

```ada
--  Step 9.5: Refine the passive Hyperlinks classification with the XTVERSION result.
HL_Refined : constant Termicap.Hyperlinks.Hyperlinks_Result :=
   Termicap.Hyperlinks.Refine_With_XTVERSION
     (Passive => Base_Caps.Hyperlinks, XTV => XTV);
```

Then in the call to `Assemble_Full` (line 271), append `Hyperlinks => HL_Refined`. The Windows mirror (`src/windows/termicap-capabilities.adb`) receives the identical change.

### 9.4 Caching impact

No new caches. The existing `Cache` and `Full_Cache` already store the entire records; the new `Hyperlinks` field is part of the cached record value. The "Unsupported is terminal" invariant means the refinement is stable across calls for a given environment+identity, so caching is safe.

---

## 10. Sixel Refactor Plan (FUNC-HYP-022)

### 10.1 Current state of `Termicap.Graphics`

**Inspection of the current source** (read in this iteration):
- `src/termicap-graphics.ads` — declares only types, constants, and `Parse_Kitty_APC_Response`. **No version comparison.**
- `src/termicap-graphics.adb` — implements `Parse_Kitty_APC_Response` only. **No version comparison.**
- `src/termicap-graphics-io.ads` — declares `Detect_Graphics`, `Detect_Graphics_Uncached`. **No version comparison.**
- `src/posix/termicap-graphics-io.adb` — implements the cascade: env harvest, DA1 probe, XTVERSION name-substring fallback, optional APC probe. **No version comparison.** `Kitty_Graphics_Version` is set unconditionally to 0 (the default value in the record); the field is reserved for future use per FUNC-SXL-003 ("defaulted to 0; XTVERSION-version-string parsing is deferred").
- `src/windows/termicap-graphics-io.adb` — same as POSIX. **No version comparison.**

**Conclusion:** the Sixel feature currently has **zero version-comparison sites** to refactor. The FUNC-HYP-022 refactor cannot remove logic that does not yet exist.

### 10.2 What FUNC-HYP-022 actually requires

FUNC-HYP-022 is a forward-looking guarantee: *"shall be refactored to use Termicap.Version.Parse and Termicap.Version.Compare for any version comparison currently embedded in its body"*. With zero current embedded comparisons, the refactor degenerates to **two concrete actions**:

1. Add `with Termicap.Version;` to `src/termicap-graphics.ads` and to `src/posix/termicap-graphics-io.adb` and `src/windows/termicap-graphics-io.adb`. This wires the dependency in advance so the future implementer of the deferred FUNC-SXL-003 logic cannot accidentally introduce a parallel local version utility.

2. Add a private helper in `src/posix/termicap-graphics-io.adb` (and Windows mirror) `function Parse_Kitty_Version (Version_String : Ada.Strings.Unbounded.Unbounded_String) return Natural`, currently returning 0 unconditionally, **but commented and structured to use `Termicap.Version.Parse`**. The body looks like:

   ```ada
   function Parse_Kitty_Version (Version_String : Unbounded_String) return Natural is
      V  : Termicap.Version.Version;
      Ok : constant Boolean :=
             Termicap.Version.Parse (To_String (Version_String), V);
   begin
      if not Ok or V.Count = 0 then
         return 0;
      end if;
      --  Pack the first two components into a single Natural so the existing
      --  Kitty_Graphics_Version : Natural field is meaningful (e.g. major*100 + minor).
      if V.Count = 1 then
         return V.Parts (1) * 100;
      else
         return V.Parts (1) * 100 + V.Parts (2);
      end if;
   end Parse_Kitty_Version;
   ```

   Then in `Run_Cascade`, when XTVERSION succeeds and the name matches `XTVERSION_NAME_KITTY`, call `Caps.Kitty_Graphics_Version := Parse_Kitty_Version (XTV.Terminal_Version);`. This **adds** new behaviour (populating `Kitty_Graphics_Version`), which is allowed under FUNC-SXL-003 (the field is `Could`-priority and currently always 0). Since the field is documented as advisory and currently never read by any consumer, this addition does not change observable behaviour for any existing test.

### 10.3 Regression-free validation

Existing Sixel tests must pass unchanged. Concrete verification steps:

1. Run the existing test set before any change: `cd tests && alr build && ./tests/bin/termicap_tests` — record pass count.
2. Apply the refactor (with-clause + `Parse_Kitty_Version` helper + `Kitty_Graphics_Version` population in `Run_Cascade`).
3. Re-run the same test set — pass count must be identical.
4. Add **new** tests in Phase 4 for the `Parse_Kitty_Version` helper itself (these are *additions* to the SXL test set, not regressions). Located in `tests/src/termicap-graphics-tests.adb` or a new `termicap-graphics-version-tests.adb`.

The Graphics public API is not changed: `Detect_Graphics` and `Detect_Graphics_Uncached` keep their signatures. `Graphics_Capabilities` is not changed. Only the *value* of `Kitty_Graphics_Version` changes from "always 0" to "populated when XTVERSION reports a kitty name". Per FUNC-SXL-003 this is explicitly allowed.

### 10.4 Strategy decision

A backwards-compatibility shim (e.g., a wrapper preserving "always 0" for one release) was considered and rejected: the field is documented as `Could`-priority forward-compatibility surface, no current caller depends on its value, and Termicap is pre-1.0. The refactor is direct.

---

## 11. Test Strategy

Phase 4 (`/spec-to-test`) will produce three categories of tests:

### 11.1 `Termicap.Version` unit tests

| Category | Examples |
|----------|----------|
| Parse success | "0", "0.50", "0.50.0", "1.72.0", "357", "3.1.0" -> Count, Parts correct |
| Parse failure | "", "1.", ".1", "1..2", "1.x", "v3.1", " 3.1", "1.999999999999999999" |
| Parse boundary | exactly MAX_VERSION_COMPONENTS components; one more -> failure |
| Compare equality | (3.1.0, 3.1.0), (357, 357) |
| Compare ordering | (0.49.99, 0.50.0), (0.50, 0.50.1), (357, 380), (3.1.0, 3.2.0) |
| Compare shorter-is-less | (0.50, 0.50.0), (0.50.0, 0.50) -- one Less, one Greater |
| Compare antisymmetry | for all pairs in the matrix, swap -> opposite ordering |

### 11.2 `Termicap.Hyperlinks.Classify_Hyperlinks_Support` table-driven tests

A single table maps `(TERM, Terminal_Kind)` -> expected `Hyperlinks_Result`. One row per FUNC-HYP-012 transition table row plus exhaustive coverage of FUNC-HYP-004 (each excluded prefix), FUNC-HYP-005 (each known-good Kind), FUNC-HYP-005b (each excluded Kind).

| TERM | Kind | Expected Support | Expected Provenance |
|------|------|------------------|----------------------|
| "vt100" | (any) | Unsupported | Env_Excluded |
| "vt220" | (any) | Unsupported | Env_Excluded |
| "ansi" | (any) | Unsupported | Env_Excluded |
| "linux" | (any) | Unsupported | Env_Excluded |
| "sun-color" | (any) | Unsupported | Env_Excluded |
| "dumb" | (any) | Unsupported | Env_Excluded |
| "xterm-256color" | Apple_Terminal | Unsupported | Env_Excluded |
| "xterm-256color" | Linux_Console | Unsupported | Env_Excluded |
| "xterm-256color" | Dumb | Unsupported | Env_Excluded |
| "xterm-256color" | ITerm2 | Likely_Supported | Env_Known_Good |
| "xterm-256color" | Kitty | Likely_Supported | Env_Known_Good |
| "xterm-256color" | Tmux | Unknown | Env_Unknown |
| "xterm-256color" | Screen | Unknown | Env_Unknown |
| "xterm-256color" | Rxvt | Unknown | Env_Unknown |
| "xterm-256color" | Unknown | Unknown | Env_Unknown |

(All known-good Kinds enumerated in FUNC-HYP-005 each get a row.)

### 11.3 `Termicap.Hyperlinks.Refine_With_XTVERSION` state-transition tests

One test case per row of the FUNC-HYP-012 table (§6.B). Inputs are synthetic `XTVERSION_Result` values built via `(Status => Success, Terminal_Name => To_Unbounded_String ("kitty"), Terminal_Version => To_Unbounded_String ("0.18.0"))` etc. plus the synthetic `Passive` parameter.

### 11.4 Sixel refactor regression suite

Run the existing FUNC-SXL-* test set unchanged before and after refactor. Add new tests for `Parse_Kitty_Version` (private helper accessed via a friend test package or via a new public `Termicap.Graphics.Parse_Kitty_Version` declaration if needed for testability).

### 11.5 Capability integration tests

| Scenario | Expected |
|----------|----------|
| `Detect` on kitty-emulating env, no override | `Caps.Hyperlinks.Support = Likely_Supported`, `Provenance = Env_Known_Good` |
| `Detect` on `TERM=vt100` | `Caps.Hyperlinks.Support = Unsupported`, `Provenance = Env_Excluded` |
| `Detect_Full` on kitty 0.20.0 (synthetic XTV) | `Full.Hyperlinks.Support = Supported`, `Provenance = XTVERSION_Confirmed`, `Terminal_Version_Known = True` |
| `Detect_Full` on VTE 0.49 (synthetic XTV) | `Full.Hyperlinks.Support = Unsupported`, `Provenance = XTVERSION_Rejected` |
| `Detect_Full` on kitty 0.20.0 with `TERM=vt100` | `Full.Hyperlinks.Support = Unsupported`, `Provenance = Env_Excluded` (terminal invariant) |

---

## 12. Risks & Open Questions

| # | Risk / open question | Mitigation / decision needed |
|---|---|---|
| R1 | Some emulators (Konsole) advertise via XTVERSION as "Konsole" but `Terminal_Kind` may classify them as `Konsole` only when `KONSOLE_VERSION` env is set. If XTVERSION says "Konsole" but `Terminal_Kind` is `Unknown`, the passive layer returns `Unknown` and the active layer can promote to `Supported`. **Acceptable** — the feature spec already permits Unknown -> Supported transitions (FUNC-HYP-009 `From Unknown` clause). |
| R2 | xterm patch level appears as a single integer (e.g., "388"). `Termicap.Version` handles this via single-component Version. Confirmed by FUNC-HYP-013 rule 3. **Acceptable**. |
| R3 | The "(any)" sentinel for WezTerm / foot / Ghostty / Konsole means an emulator reporting an absurd version like "0" would be treated as `Supported`. This is the documented intent but a future requirement may want to set a floor. **Open**: should we set a small but non-zero floor for these (e.g., 0.1.0)? Recommend: no — the requirement is explicit. |
| R4 | XTVERSION name match is case-insensitive substring. Users could in principle have `TERM_PROGRAM=mykitty` shadowed terminals; unlikely but possible. **Acceptable** — case-insensitive substring match with the canonical token list is documented. |
| R5 | The `Termicap.Version` parser allows up to 8 components and Natural per component. For pathological versions like "999999999.0.0" the bounds check in §6.C `Parse` returns False. Tests must exercise this. **Action**: add bound-overflow test to §11.1. |
| R6 | The Sixel refactor (§10) introduces a new value into `Kitty_Graphics_Version` that was previously always 0. While no test depends on the 0-value, downstream code that *displays* the field will start showing real numbers. **Open for user:** is that acceptable? Recommend yes — FUNC-SXL-003 explicitly sets up the field for this purpose. |
| R7 | `Refine_With_XTVERSION` is `SPARK_Mode Off` only because of `Unbounded_String`. If a future refactor introduces a SPARK-friendly `XTVERSION_Result_View` (bounded strings), this function could be promoted to Silver. **Future work**, not in scope. |

---

## 13. Files to Create / Modify

### New files

| File | Description |
|------|-------------|
| `src/termicap-version.ads` | Shared version utility spec |
| `src/termicap-version.adb` | Body |
| `src/termicap-hyperlinks.ads` | Spec |
| `src/termicap-hyperlinks.adb` | Body |
| `tests/src/termicap-version-tests.ads`/`.adb` | Version unit tests |
| `tests/src/termicap-hyperlinks-tests.ads`/`.adb` | Hyperlinks classifier + refinement tests |
| `docs/adr/0036-termicap-version-shared-utility.md` | ADR for shared placement |
| `docs/adr/0037-hyperlinks-result-flat-record.md` | ADR for flat-record choice |
| `docs/adr/0038-hyperlinks-active-reuses-xtversion.md` | ADR for reuse vs fresh probe |

### Modified files

| File | Change |
|------|--------|
| `src/termicap-capabilities.ads` | Add `Hyperlinks` field to both records; extend `Assemble` and `Assemble_Full` parameters |
| `src/posix/termicap-capabilities.adb` | Wire passive call into `Detect`; refinement call into `Detect_Full` |
| `src/windows/termicap-capabilities.adb` | Mirror of POSIX change |
| `src/termicap-graphics.ads` | `with Termicap.Version;` |
| `src/posix/termicap-graphics-io.adb` | `with Termicap.Version;` + `Parse_Kitty_Version` helper + `Kitty_Graphics_Version` population |
| `src/windows/termicap-graphics-io.adb` | Mirror of POSIX |
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Hyperlinks` and `Termicap.Version` to package tree |
| `docs/architecture/04-runtime-view.md` | Add `Detect` step "classify hyperlinks" and `Detect_Full` step "refine hyperlinks with XTVERSION" |

---

## 14. Open Questions Requiring User Input

1. **Sixel refactor scope** — confirm that populating `Kitty_Graphics_Version` (currently always 0) as part of FUNC-HYP-022 is acceptable. The alternative is a "with clause only" refactor that adds the dependency without using it; this is hollower but strictly preserves the "always 0" status quo.
2. **Floor version for "(any)" entries** (R3) — keep at 0.0.0 (any successfully parsed version) or set a small floor?
3. **Test exposure of `Parse_Kitty_Version`** — make the helper public on `Termicap.Graphics` for direct testability, or rely on integration tests through `Detect_Graphics_Uncached`?

These are the only material decisions we ask the user to confirm before Phase 4.
