# API Reference: `Termicap.Hyperlinks`

Package providing two-tier OSC 8 hyperlink support detection: a pure SPARK Silver passive classifier and a value-to-value XTVERSION refinement function.

**Files:**
- [`src/termicap-hyperlinks.ads`](../../src/termicap-hyperlinks.ads)
- `src/termicap-hyperlinks.adb`

**SPARK_Mode:** `Termicap.Hyperlinks` — On (spec and `Classify_Hyperlinks_Support`); Off (`Refine_With_XTVERSION`)
**License:** Apache-2.0

---

## Overview

The Hyperlinks feature answers the question "can I safely emit OSC 8 hyperlink escape sequences to the controlling terminal?" at two levels of confidence:

- **Tier 1 — Passive classification** (`Classify_Hyperlinks_Support`): inspects the `TERM` environment variable and `Terminal_Identity.Kind`. Pure SPARK Silver function with `Global => null`; runs in `Termicap.Capabilities.Detect` as Step 8, before any active probe.
- **Tier 2 — XTVERSION refinement** (`Refine_With_XTVERSION`): promotes `Likely_Supported` to `Supported` (or demotes to `Unsupported`) using a known-good version table and the `XTVERSION_Result` already collected by `Termicap.Capabilities.Detect_Full` Step 9. No new probe session is opened (ADR-0038).

The passive classification applies three steps in normative order:

1. **TERM legacy-prefix exclusion** (FUNC-HYP-004): terminals whose `TERM` starts with `"vt"` or `"sun"`, or equals `"ansi"`, `"linux"`, or `"dumb"` → `Unsupported`.
2. **Terminal_Kind hard exclusion** (FUNC-HYP-005b): `Apple_Terminal`, `Dumb`, `Linux_Console` → `Unsupported`.
3. **Terminal_Kind known-good list** (FUNC-HYP-005): 14 emulators including Alacritty, Foot, Ghostty, ITerm2, Kitty, VSCode, WezTerm, Windows_Terminal → `Likely_Supported`. All others → `Unknown`.

The XTVERSION refinement consults a body-private known-good version table (12 emulators with minimum versions or "any" minimum). See tech spec §7 and the algorithm section below for the full table and state-transition rules.

This is a single mixed-SPARK package with no `.IO` child package (ADR-0038). No platform-specific body files are required (FUNC-HYP-017).

---

## Package `Termicap.Hyperlinks`

### Types

#### `Hyperlinks_Support`

```ada
type Hyperlinks_Support is (Unsupported, Likely_Supported, Supported, Unknown);
```

Four-value classification of OSC 8 hyperlink support.

| Value | Meaning |
|-------|---------|
| `Unsupported` | The terminal is known not to support OSC 8, or sending OSC 8 sequences would render as visible garbage. Callers **must not** emit OSC 8. |
| `Likely_Supported` | The terminal is likely to support OSC 8 based on passive heuristics (known-good `Terminal_Kind` or no legacy-TERM exclusion fired). Callers **may** emit OSC 8 safely; at worst the terminal silently ignores the sequence. |
| `Supported` | The terminal is known to support OSC 8 at the confirmed minimum version (XTVERSION-gated). Callers **should** emit OSC 8. |
| `Unknown` | No evidence either way. The terminal was not on the known-good list and no XTVERSION refinement was available. Callers may treat this as `Likely_Supported` for output purposes. |

**Note:** The positional ordering (`Unsupported < Likely_Supported < Supported < Unknown`) is **not** semantic for `Unknown`. `Unknown` is placed last only to keep the three confirmed states contiguous. Callers comparing with `>=` must handle `Unknown` explicitly.

**Requirements:** FUNC-HYP-001

---

#### `Hyperlinks_Provenance`

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

Seven-value linear provenance chain for `Hyperlinks_Result`. Records the detection step that last updated `Support`.

| Value | Meaning |
|-------|---------|
| `Default` | Not yet classified; initial / uninitialised state. |
| `Env_Excluded` | Legacy TERM prefix exclusion (FUNC-HYP-004) or `Terminal_Kind` hard exclusion (FUNC-HYP-005b) fired; `Support = Unsupported`. |
| `Env_Known_Good` | `Terminal_Kind` was on the known-good list (FUNC-HYP-005); `Support = Likely_Supported`. |
| `Env_Unknown` | `Terminal_Kind` was not on any list; fallback; `Support = Unknown`. |
| `XTVERSION_Confirmed` | XTVERSION lookup found a matching entry and the reported version met or exceeded the minimum; `Support` promoted to `Supported`. |
| `XTVERSION_Rejected` | XTVERSION lookup found a matching entry but the reported version was below the minimum; `Support` demoted to `Unsupported` (FUNC-HYP-010). |
| `XTVERSION_Unresolved` | XTVERSION result was not `Success`, or the terminal name was not found in the known-good table; `Support` unchanged from passive result. |

**Requirements:** FUNC-HYP-003

---

#### `Hyperlinks_Result`

```ada
type Hyperlinks_Result is record
   Support                : Hyperlinks_Support    := Unknown;
   Provenance             : Hyperlinks_Provenance := Default;
   Terminal_Version_Known : Boolean               := False;
end record;
```

Flat result record (ADR-0037) aggregating the hyperlink detection outcome. All fields are unconditionally meaningful for every `Support` value; there is no per-variant payload.

| Field | Description |
|-------|-------------|
| `Support` | Coarse classification (see `Hyperlinks_Support`). |
| `Provenance` | Which detection step last set `Support`. |
| `Terminal_Version_Known` | `True` when the XTVERSION refinement matched a terminal name in the known-good table, even if the version was unparseable or the match led to demotion. |

**Requirements:** FUNC-HYP-002

---

### Constants

#### `DEFAULT_HYPERLINKS_RESULT`

```ada
DEFAULT_HYPERLINKS_RESULT : constant Hyperlinks_Result :=
  (Support => Unknown, Provenance => Default, Terminal_Version_Known => False);
```

Canonical default / uninitialised `Hyperlinks_Result` value. Used as the initial value for the `Hyperlinks` field in `Terminal_Capabilities` and `Full_Terminal_Capabilities`, and as the default argument to `Assemble` / `Assemble_Full`.

**Requirements:** FUNC-HYP-002

---

#### TERM Exclusion Constants (FUNC-HYP-006)

Legacy `TERM` values / prefixes identifying terminals known not to support OSC 8 (or to render it as visible text garbage). Derived from the tcell exclusion list and GLOBAL-SYNTHESIS §2.8.

| Constant | Value | Match Type | Description |
|----------|-------|-----------|-------------|
| `TERM_PREFIX_VT` | `"vt"` | Prefix | VT-family terminals (`vt100`, `vt220`, `vt52`, …) |
| `TERM_PREFIX_ANSI` | `"ansi"` | Exact | Legacy ANSI terminals |
| `TERM_LINUX` | `"linux"` | Exact | Linux virtual console |
| `TERM_PREFIX_SUN` | `"sun"` | Prefix | Sun terminals (`sun`, `sun-color`, …) |
| `TERM_DUMB` | `"dumb"` | Exact | Dumb terminals with no escape sequence capability |

---

### Functions

#### `Classify_Hyperlinks_Support`

```ada
function Classify_Hyperlinks_Support
  (Env      : Termicap.Environment.Environment;
   Identity : Termicap.Terminal_Id.Terminal_Identity)
   return Hyperlinks_Result
with SPARK_Mode => On, Global => null;
```

Classify OSC 8 hyperlink support using passive heuristics only.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | Immutable environment variable snapshot. Read for the `TERM` variable. |
| `Identity` | in | Passively identified terminal kind and metadata. |

**Returns:** `Hyperlinks_Result` with `Support`, `Provenance`, and `Terminal_Version_Known = False`.

**Algorithm (three steps in normative order, FUNC-HYP-007):**

| Step | Condition | Result |
|------|-----------|--------|
| 1 | `TERM` starts with `"vt"` or `"sun"`, or equals `"ansi"`, `"linux"`, `"dumb"` | `(Unsupported, Env_Excluded, False)` |
| 2 | `Identity.Kind` in `Apple_Terminal \| Dumb \| Linux_Console` | `(Unsupported, Env_Excluded, False)` |
| 3a | `Identity.Kind` in known-good list (14 emulators) | `(Likely_Supported, Env_Known_Good, False)` |
| 3b | All other `Terminal_Kind` values | `(Unknown, Env_Unknown, False)` |

Known-good Terminal_Kind list (step 3a): `Alacritty`, `Foot`, `Ghostty`, `ITerm2`, `JediTerm`, `Kitty`, `Konsole`, `Mintty`, `VSCode`, `VTE`, `WarpTerminal`, `WezTerm`, `Windows_Terminal`, `Xterm`.

**SPARK contract:** `SPARK_Mode => On`; `Global => null` — no OS calls, no global state, no exceptions. GNATprove verifies this at Silver level (FUNC-HYP-018).

**Requirements:** FUNC-HYP-007, FUNC-HYP-008, FUNC-HYP-018

---

#### `Refine_With_XTVERSION`

```ada
function Refine_With_XTVERSION
  (Passive : Hyperlinks_Result;
   XTV     : Termicap.XTVERSION.XTVERSION_Result) return Hyperlinks_Result
with SPARK_Mode => Off;
```

Refine the passive hyperlink classification using the XTVERSION result.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Passive` | in | The `Hyperlinks_Result` from `Classify_Hyperlinks_Support`. |
| `XTV` | in | The `XTVERSION_Result` from `Detect_Full` Step 9 (ADR-0038). |

**Returns:** Refined `Hyperlinks_Result`.

**Algorithm — state-transition table (FUNC-HYP-012, exhaustive):**

| Condition | Result |
|-----------|--------|
| `Passive.Support = Unsupported` and `Provenance = Env_Excluded` | Return `Passive` unchanged ("Unsupported is terminal" invariant) |
| `XTV.Status /= Success` | `(Passive.Support, XTVERSION_Unresolved, Passive.Terminal_Version_Known)` |
| Terminal name not found in table | `(Passive.Support, XTVERSION_Unresolved, False)` |
| Terminal name found, "any" minimum (`Treat_Any`) | `(Supported, XTVERSION_Confirmed, True)` — promotes even when the reported version is unparseable |
| Terminal name found, strict entry, version ≥ minimum | `(Supported, XTVERSION_Confirmed, True)` |
| Terminal name found, strict entry, version < minimum | `(Unsupported, XTVERSION_Rejected, True)` |
| Terminal name found, strict entry, version unparseable | `(Passive.Support, Env_Known_Good, True)` |

**Exception safety:** An outer `when others => return Passive` handler guarantees no exception propagation (defence in depth; the body performs no I/O and `Termicap.Version.Compare` is total).

**Known-good version table (body-private, 13 entries):**

| Terminal name token (case-insensitive) | Minimum version | "Any" |
|----------------------------------------|-----------------|-------|
| iTerm2 | 3.1.0 | No |
| kitty | 0.19.0 | No |
| WezTerm | — | Yes |
| VTE | 0.50.0 | No |
| foot | — | Yes |
| Alacritty | 0.11.0 | No |
| mintty | 3.4.0 | No |
| xterm | 357 | No |
| Windows_Terminal | 1.4.0 | No |
| VSCode | 1.72.0 | No |
| Ghostty | — | Yes |
| Konsole | — | Yes |
| Warp | — | Yes |

The promotion logic checks the `Treat_Any` flag **before** parsing the reported version string, so `Treat_Any` entries (foot, WezTerm, Ghostty, Konsole, Warp) promote to `Supported / XTVERSION_Confirmed` on a name match alone — even when the XTVERSION-reported version is unparseable. This matters in practice for Warp, whose version string format (e.g. `v0.2026.04.29.08.57.stable_01`) does not parse as a dotted-numeric version under `Termicap.Version.Parse`.

**SPARK contract:** `SPARK_Mode => Off` — signature references `XTVERSION_Result` which contains `Ada.Strings.Unbounded.Unbounded_String`.

**Requirements:** FUNC-HYP-009, FUNC-HYP-010, FUNC-HYP-011, FUNC-HYP-012

---

## Usage Examples

### Tier 1: Passive classification only (no terminal I/O)

```ada
with Termicap.Environment.Capture;
with Termicap.Terminal_Id;
with Termicap.Hyperlinks;

declare
   Env      : Termicap.Environment.Environment;
   Identity : Termicap.Terminal_Id.Terminal_Identity;
   Result   : Termicap.Hyperlinks.Hyperlinks_Result;
begin
   Termicap.Environment.Capture.Capture_Current (Env);
   Identity := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);
   Result   := Termicap.Hyperlinks.Classify_Hyperlinks_Support (Env, Identity);

   case Result.Support is
      when Termicap.Hyperlinks.Unsupported =>
         null;  --  do not emit OSC 8
      when Termicap.Hyperlinks.Likely_Supported |
           Termicap.Hyperlinks.Supported =>
         Emit_OSC8_Hyperlink (URL => "https://example.com", Text => "click here");
      when Termicap.Hyperlinks.Unknown =>
         null;  --  conservative: treat as Likely_Supported or skip
   end case;
end;
```

### Tier 1 + Tier 2: Full classification via `Termicap.Capabilities.Get_Full`

```ada
with Termicap.Capabilities;
with Termicap.Hyperlinks;

declare
   Caps : constant Termicap.Capabilities.Full_Terminal_Capabilities :=
            Termicap.Capabilities.Get_Full;
begin
   --  .Hyperlinks is the XTVERSION-refined result (or passive if XTVERSION failed)
   if Caps.Hyperlinks.Support >= Termicap.Hyperlinks.Likely_Supported
     and then Caps.Hyperlinks.Support /= Termicap.Hyperlinks.Unknown
   then
      Emit_OSC8_Hyperlink (URL => "https://example.com", Text => "click here");
   end if;
end;
```

### Pure testing (no OS interaction)

```ada
with Termicap.Environment;
with Termicap.Terminal_Id;
with Termicap.Hyperlinks;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

declare
   Env      : Termicap.Environment.Environment :=
                Termicap.Environment.EMPTY_ENVIRONMENT;
   Identity : Termicap.Terminal_Id.Terminal_Identity;
   Passive  : Termicap.Hyperlinks.Hyperlinks_Result;
   XTV      : constant Termicap.XTVERSION.XTVERSION_Result :=
                (Status           => Termicap.XTVERSION.Success,
                 Terminal_Name    => To_Unbounded_String ("kitty"),
                 Terminal_Version => To_Unbounded_String ("0.25.0"));
   Refined  : Termicap.Hyperlinks.Hyperlinks_Result;
begin
   Termicap.Environment.Insert (Env, "TERM", "xterm-kitty");
   Identity := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);

   Passive := Termicap.Hyperlinks.Classify_Hyperlinks_Support (Env, Identity);
   pragma Assert (Passive.Support    = Termicap.Hyperlinks.Likely_Supported);
   pragma Assert (Passive.Provenance = Termicap.Hyperlinks.Env_Known_Good);

   Refined := Termicap.Hyperlinks.Refine_With_XTVERSION (Passive, XTV);
   pragma Assert (Refined.Support               = Termicap.Hyperlinks.Supported);
   pragma Assert (Refined.Provenance            = Termicap.Hyperlinks.XTVERSION_Confirmed);
   pragma Assert (Refined.Terminal_Version_Known = True);
end;
```

---

## SPARK Notes

`Termicap.Hyperlinks` uses a split-SPARK strategy:

| Subprogram | SPARK Level | Key proof obligation |
|------------|------------|---------------------|
| `Classify_Hyperlinks_Support` | Silver | `Global => null`; termination of finite 3-step cascade; loop-free body |
| `Refine_With_XTVERSION` | Off | No proof; outer exception handler provides defence-in-depth |

The `SPARK_Mode => Off` annotation on `Refine_With_XTVERSION` is required because `XTVERSION_Result` contains `Ada.Strings.Unbounded.Unbounded_String`, which is a controlled type outside the SPARK 2014 subset. The Tier 1 provable function remains accessible to SPARK callers without a mode boundary violation.

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-HYP-001 | `Hyperlinks_Support` enumeration | Silver |
| FUNC-HYP-002 | `Hyperlinks_Result` record, `DEFAULT_HYPERLINKS_RESULT` | Silver |
| FUNC-HYP-003 | `Hyperlinks_Provenance` enumeration | Silver |
| FUNC-HYP-004 | TERM legacy-prefix exclusion (step 1 in `Classify_Hyperlinks_Support`) | Silver |
| FUNC-HYP-005 | Known-good Terminal_Kind list (step 3a) | Silver |
| FUNC-HYP-005b | Terminal_Kind hard exclusion (step 2) | Silver |
| FUNC-HYP-006 | `TERM_PREFIX_*` / `TERM_*` named constants | Silver |
| FUNC-HYP-007 | `Classify_Hyperlinks_Support` signature | Silver |
| FUNC-HYP-008 | `Global => null` on passive function | Silver |
| FUNC-HYP-009 | XTVERSION promotion path in `Refine_With_XTVERSION` | Off |
| FUNC-HYP-010 | XTVERSION demotion path | Off |
| FUNC-HYP-011 | `Refine_With_XTVERSION` signature | Off |
| FUNC-HYP-012 | Complete state-transition table | Off |
| FUNC-HYP-016 | Package structure — single mixed-SPARK package | Silver |
| FUNC-HYP-017 | No platform-specific body files | Silver |
| FUNC-HYP-018 | SPARK Silver provability of `Classify_Hyperlinks_Support` | Silver |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — `Termicap.Hyperlinks` and `Termicap.Version` building block descriptions; `Termicap.Capabilities` dependencies update
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 33: Hyperlink Classification (passive + XTVERSION refinement), testability pattern, SPARK notes
- **[Termicap.Version](version.md)** — shared dotted-numeric version utility used by `Refine_With_XTVERSION`
- **[Termicap.XTVERSION](xtversion.md)** — `XTVERSION_Result` type and `Query_And_Identify` convenience function consumed by `Refine_With_XTVERSION`
- **[Termicap.Capabilities](termicap-capabilities.md)** — `Terminal_Capabilities.Hyperlinks` field (FUNC-HYP-014); `Assemble` `Hyperlinks` parameter; `Detect_Full` XTVERSION reuse (ADR-0038)
- **Tech Spec HYPERLINK** (`docs/tech-specs/hyperlink.md`) — design rationale, framework survey, TERM exclusion list derivation, known-good table sources
- **ADR-0036** (`docs/adr/0036-termicap-version-shared-utility.md`) — shared version utility
- **ADR-0037** (`docs/adr/0037-hyperlinks-result-flat-record.md`) — flat result record
- **ADR-0038** (`docs/adr/0038-hyperlinks-active-reuses-xtversion.md`) — XTVERSION reuse
