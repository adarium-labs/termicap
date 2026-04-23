# KITTY-KB: Kitty Keyboard Protocol Detection

**Feature:** Keyboard input protocol detection (Win32 / Kitty / XTerm modifyOtherKeys / Legacy)
**Requirements:** FUNC-KKB-001 through FUNC-KKB-019
**Parent Requirement:** OSC-INFRA (REQ-OSC), DA1 (REQ-DA1), CYGWIN (REQ-CYG)
**Status:** Proposed
**Date:** 2026-04-23

---

## A. Summary

At process startup, applications that route keyboard input through Termicap need to know which of the four keyboard input protocols the controlling terminal supports: **Win32 Console** (Windows, native console), **Kitty Keyboard Protocol** (`CSI ? u`), **XTerm modifyOtherKeys** (`CSI ? 4 m`), or **Legacy** (classic VT/ANSI encoding).

This feature adds a new package `Termicap.Keyboard` (SPARK On spec, SPARK Off body with locally-annotated pure parsers) and its platform-specific I/O child `Termicap.Keyboard.IO`. The public entry point `Detect_Keyboard_Protocol` returns a `Keyboard_Capability` record and implements the cascade **Win32 > guards > Kitty-probe > XTerm-probe > Legacy**, reusing `Termicap.OSC.Sentinel_Query` for both escape-sequence probes with DA1 as boundary sentinel and a **1000 ms timeout per probe** (FUNC-KKB-013). The Kitty and XTerm response recognisers are pure SPARK Silver-provable functions. The result is cached in a package-level protected object for the process lifetime (FUNC-KKB-017). Integration into `Terminal_Capabilities` (FUNC-KKB-019) is intentionally deferred to a follow-up milestone; the standalone `Detect_Keyboard_Protocol` function is the primary API.

---

## B. Scope & Requirements

Each approved FUNC-KKB requirement is satisfied by a specific design element.

| UID | Priority | Summary | Non-trivial interpretation |
|-----|----------|---------|----------------------------|
| FUNC-KKB-001 | Must | `Keyboard_Protocol` enumeration with five values (`Unknown`, `Legacy`, `XTerm_CSI`, `Kitty`, `Win32`) | No |
| FUNC-KKB-002 | Must | `Kitty_Flags` record with five Boolean fields (bits 0..4) | No |
| FUNC-KKB-003 | Must | `Keyboard_Capability` record (`Protocol`, `Flags`, `Probed`); canonical "no result" is `(Unknown, all False, Probed=False)` | No |
| FUNC-KKB-004 | Must | Kitty query `ESC [ ? u` (3 bytes) + DA1 sentinel; response pattern `ESC [ ? <digits>* u`; bare `CSI ? u` is valid (flags = 0) | No |
| FUNC-KKB-005 | Must | Pure `Parse_Kitty_Flags (Flags_Int : Natural) return Kitty_Flags`; bits >= 32 ignored | No |
| FUNC-KKB-006 | Must | Pure `Parse_Kitty_Response (Buffer, Length) return Parse_Result`; `<digits>*` may be empty | No |
| FUNC-KKB-007 | Must | XTerm query `ESC [ ? 4 m` (5 bytes) + DA1 sentinel; response `ESC [ ? 4 ; <value> m` | No |
| FUNC-KKB-008 | Must | Pure `Parse_XTerm_Keyboard_Response (Buffer, Length) return Boolean`; requires at least one digit | No |
| FUNC-KKB-009 | Must | Cascade Win32 > TTY guard > foreground guard > Kitty probe > XTerm probe > Legacy | No |
| FUNC-KKB-010 | Must | Windows Console gate: short-circuit on `GetConsoleMode (STD_INPUT_HANDLE) = TRUE`; fall through on Cygwin/MSYS PTY | **Yes** — see note below |
| FUNC-KKB-011 | Must | Non-TTY guard (Is_TTY) and background-process guard (Is_Foreground_Process) both yield `Unknown, Probed = False` | No |
| FUNC-KKB-012 | Must | Probe I/O exclusively through `Termicap.OSC.Open/Sentinel_Query/Finalize`; no direct `tcgetattr`/`tcsetattr`/`read`/`write` | No |
| FUNC-KKB-013 | Must | Timeout 1000 ms per probe (not combined); per-probe reset | No |
| FUNC-KKB-014 | Must | No-exception contract for `Detect_Keyboard_Protocol` across all failure modes | No |
| FUNC-KKB-015 | Must | Termios restore on every exit path — guaranteed by `Probe_Session` RAII | No |
| FUNC-KKB-016 | Should | Partial / garbled response handling: parsers return negative; `Sentinel_Query` drains to DA1 regardless | No |
| FUNC-KKB-017 | Must | One-probe-per-process cache; lazy elaboration; not invalidated by SIGWINCH | No |
| FUNC-KKB-018 | Must | Package structure `Termicap.Keyboard` (SPARK On spec) + `Termicap.Keyboard.IO` child (SPARK Off); platform split under `src/posix/` and `src/windows/` | **Yes** — see note below |
| FUNC-KKB-019 | Should | Extend `Terminal_Capabilities` with `Keyboard : Keyboard_Capability` field | **Yes** — deferred; see §K |

### Non-trivial interpretations

**FUNC-KKB-010 Windows gate — single-body implementation, platform-specific child.** The requirement mandates a GetConsoleMode check on Windows only; on POSIX the gate is skipped. Rather than embed a conditional compilation path in a shared body, we use the project's established platform-dispatch pattern (ADR-0018): `Termicap.Keyboard.IO` has **two bodies**, `src/posix/termicap-keyboard-io.adb` and `src/windows/termicap-keyboard-io.adb`. The GPR source-dir list selects exactly one. The shared spec `src/termicap-keyboard-io.ads` declares `Detect_Keyboard_Protocol` once. This keeps the Win32 FFI out of the POSIX object file entirely (no linker leak of `Win32.Wincon` symbols on Linux/macOS).

**FUNC-KKB-018 Parser placement.** The spec declares the three parsers `Parse_Kitty_Flags`, `Parse_Kitty_Response`, `Parse_XTerm_Keyboard_Response` with `SPARK_Mode => On` and `Global => null`. Their bodies live **in the same body file** `src/termicap-keyboard.adb` with per-subprogram `pragma SPARK_Mode (On);` annotations (mixed SPARK pattern, per ADR-0013 and the pattern already used in `Termicap.Win32_Cygwin` for `Is_Cygwin_Pipe_Name`). The I/O orchestration (`Detect_Keyboard_Protocol`) is declared in the child spec `Termicap.Keyboard.IO` to avoid putting `SPARK_Mode => Off` into an otherwise-SPARK-On parent spec.

**FUNC-KKB-019 deferral — see §K.** The Should-priority integration into `Terminal_Capabilities` is explicitly deferred to a later milestone. Rationale: the field addition is backward-compatible in Ada, but the decision about **when** `Capabilities.Detect` triggers the probe (and at what cost — +1 s worst-case latency per cold-start `Get`) deserves its own ADR and should be made only after the standalone `Detect_Keyboard_Protocol` function has stabilised. The design in this spec is forward-compatible: extending `Terminal_Capabilities` later requires only adding a field and a call site in `Capabilities.Detect`; no parser or I/O change is required.

---

## C. Framework Survey

### tcell (Go) — the authoritative reference

`reference-frameworks/tcell/tscreen.go` (lines 124–129) declares the four canonical query strings used by the industry:

```go
queryKittyKbd     = "\x1b[?u"       // Kitty keyboard query
enableKittyKbd    = "\x1b[=1u"      // push-mode enable
queryXTermKbd     = "\x1b[?4m"      // XTerm modifyOtherKeys query
enableXTermKbd    = "\x1b[>4;2m"    // level-2 enable
```

tcell's cascade (documented in §2.7 of `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md`) is **Win32 > Kitty > XTerm > Legacy**, exactly matching FUNC-KKB-009. The DA1 sentinel (`CSI c`) is appended after each keyboard query; if the DA1 response arrives first, the queried protocol is absent. This is the pattern Termicap's `Sentinel_Query` was designed for, and this feature reuses it unchanged.

tcell does **not** structure the Kitty flags as a named record — it stores the raw integer. Termicap extracts named Booleans (FUNC-KKB-002) for self-documenting APIs and SPARK-provable bitmasking.

### crossterm (Rust) — query-then-filter pattern

`reference-frameworks/crossterm/src/terminal/sys/unix.rs` lines 213–267 (`query_keyboard_enhancement_flags_raw`):

```rust
// ESC [ ? u        Query progressive keyboard enhancement flags (kitty protocol).
// ESC [ c          Query primary device attributes.
const QUERY: &[u8] = b"\x1B[?u\x1B[c";
```

crossterm's implementation pairs `CSI ? u` with `CSI c` in a **single write** and then filters the event queue for `KeyboardEnhancementFlags` or `PrimaryDeviceAttributes`, whichever arrives first. The 2000 ms timeout is longer than Termicap's 1000 ms; Termicap's choice is aligned with the project-wide `Sentinel_Query` convention (`FUNC-OSC-004` comment). crossterm returns `None` on timeout (no Kitty support detected) — equivalent to Termicap's "cascade to next step".

crossterm does **not** query XTerm modifyOtherKeys. It relies on Kitty-or-nothing. Termicap's three-level probe (Kitty → XTerm → Legacy) provides finer granularity, following tcell and notcurses.

### notcurses (C)

`reference-frameworks/notcurses/src/lib/termdesc.c` lines 386–400 implement a similar detection. Notcurses pushes Kitty flags at startup (`CSI = <flags> u`) and waits for the DA1 response to confirm whether the terminal acknowledged the push. This is functionally equivalent but conflates detection with activation; Termicap keeps them separate (detection only).

### termenv (Go) — no keyboard detection

`reference-frameworks/termenv` focuses on color, size, and hyperlinks. It does **not** implement keyboard protocol detection. The lone `"xterm-kitty"` match in `termenv_unix.go` line 59 is a TERM-string heuristic for color level; it is not a protocol probe. No lessons to port from termenv here.

### supports-color (Rust) — no keyboard detection

Focuses on color; not relevant.

### Cross-language consensus

| Framework | Kitty probe | XTerm probe | Order | Timeout |
|-----------|-------------|-------------|-------|---------|
| tcell | `CSI ? u` + DA1 | `CSI ? 4 m` + DA1 | Win32 > Kitty > XTerm > Legacy | not documented |
| crossterm | `CSI ? u` + DA1 | skipped | Kitty or nothing | 2000 ms |
| notcurses | push + DA1 roundtrip | skipped | Kitty or nothing | tied to screen init |
| Termicap (this feature) | `CSI ? u` + DA1 | `CSI ? 4 m` + DA1 | Win32 > Kitty > XTerm > Legacy | 1000 ms per probe |

The query byte sequences in FUNC-KKB-004 and FUNC-KKB-007 exactly match tcell's `queryKittyKbd` and `queryXTermKbd`. No ambiguity.

---

## D. Architecture & Package Structure

### Package hierarchy

```
Termicap.Keyboard                      (src/termicap-keyboard.ads: SPARK_Mode => On)
  |   Types:      Keyboard_Protocol, Kitty_Flags, Keyboard_Capability,
  |               Parse_Result
  |   Constants:  CSI_KITTY_QUERY, CSI_XTERM_KBD_QUERY
  |   Parsers:    Parse_Kitty_Flags, Parse_Kitty_Response,
  |               Parse_XTerm_Keyboard_Response    (all SPARK_Mode => On)
  |
  |-- Termicap.Keyboard.IO             (src/termicap-keyboard-io.ads: SPARK_Mode => Off)
  |     Public:   Detect_Keyboard_Protocol : function return Keyboard_Capability
  |     Private:  cached_value : protected object (FUNC-KKB-017)
  |
  |     POSIX body:  src/posix/termicap-keyboard-io.adb
  |         No Win32 gate; starts cascade at TTY guard (step 2).
  |
  |     Windows body: src/windows/termicap-keyboard-io.adb
  |         Includes Win32 gate (step 1 of FUNC-KKB-009).
  |         Falls through to POSIX-like probe path on Cygwin/MSYS PTY.
```

### Dependency graph

```
Termicap.Keyboard.IO (POSIX body)
  |-- Termicap.Keyboard         (types, parsers)
  |-- Termicap.OSC              (Probe_Session, Sentinel_Query)
  |-- Termicap.OSC.Parsing      (DA1_Response_Start  — optional, see §H)
  |-- Termicap.TTY              (Is_TTY, Stream_Kind)

Termicap.Keyboard.IO (Windows body)
  |-- Termicap.Keyboard
  |-- Termicap.OSC
  |-- Termicap.TTY
  |-- Win32
  |-- Win32.Winbase             (GetStdHandle, STD_INPUT_HANDLE)
  |-- Win32.Wincon              (GetConsoleMode)
  |-- Win32.Winnt               (HANDLE)
  |-- Termicap.Win32_Cygwin     (Is_Cygwin_Terminal) — optional, see §H
```

### Why split `Termicap.Keyboard` from `Termicap.Keyboard.IO`?

Two reasons:

1. **SPARK mode hygiene.** `Termicap.Keyboard` spec declares the three pure parsers with `SPARK_Mode => On` and `Global => null`. If `Detect_Keyboard_Protocol` lived in the same spec, the spec would need `SPARK_Mode => Off` (because its body calls `Termicap.OSC`, which is `SPARK_Mode => Off`) — which would silently weaken every contract in the package spec to "unverified". This is the same split we applied for `Termicap.XTVERSION` / `Termicap.XTVERSION.IO` and `Termicap.DA1` / `Termicap.DA1.IO`.

2. **Platform dispatch.** The Win32 gate (FUNC-KKB-010) is Windows-only. Using one shared spec plus two per-platform bodies lets the project-standard GPR source-dir mechanism (ADR-0018) drop the Win32 dependencies on POSIX builds without IF-DEFs.

### SPARK boundary table

| Package / subprogram | SPARK_Mode | Rationale |
|----------------------|------------|-----------|
| `Termicap.Keyboard` spec | On | Declares pure types, query constants, three parsers as SPARK Silver |
| `Termicap.Keyboard` body | Off (package level) | Parser bodies are locally annotated `SPARK_Mode => On`; no other code |
| `Parse_Kitty_Flags` body | On (locally) | Pure bit-masking over `Natural`; Silver-provable |
| `Parse_Kitty_Response` body | On (locally) | Pure iteration over `Byte_Array`; Silver-provable |
| `Parse_XTerm_Keyboard_Response` body | On (locally) | Pure iteration over `Byte_Array`; Silver-provable |
| `Termicap.Keyboard.IO` spec | Off | Declares cache-aware I/O function; depends on `Termicap.OSC` |
| `Termicap.Keyboard.IO` body (POSIX) | Off | Opens `Probe_Session`, calls `Sentinel_Query` |
| `Termicap.Keyboard.IO` body (Windows) | Off | Same, plus Win32 gate |

---

## E. Types — detailed declarations

The following declarations are in prose (matching the tech-spec conventions); they become the exact Ada declarations during implementation.

### `Keyboard_Protocol` enumeration (FUNC-KKB-001)

```ada
--  @relation(FUNC-KKB-001)
type Keyboard_Protocol is
  (Unknown,    --  Detection not performed or not possible
   Legacy,     --  Probed successfully; no enhanced protocol
   XTerm_CSI,  --  XTerm modifyOtherKeys acknowledged
   Kitty,      --  Kitty Keyboard Protocol acknowledged
   Win32);     --  Windows Console API keyboard (platform-gated, not probed)
```

Ordering rationale: `Unknown` first so default-initialised `Keyboard_Protocol` variables are safely `Unknown`. `Legacy` before the enhanced variants matches increasing expressive power.

### `Kitty_Flags` record (FUNC-KKB-002)

```ada
--  @relation(FUNC-KKB-002)
type Kitty_Flags is record
   Disambiguate_Escape_Codes : Boolean := False;  --  bit 0, value 1
   Report_Event_Types        : Boolean := False;  --  bit 1, value 2
   Report_Alternate_Keys     : Boolean := False;  --  bit 2, value 4
   Report_All_Keys_As_Escape : Boolean := False;  --  bit 3, value 8
   Report_Associated_Text    : Boolean := False;  --  bit 4, value 16
end record;

NO_KITTY_FLAGS : constant Kitty_Flags := (others => False);
```

Default initialisation to all-False so that any `Kitty_Flags` declared without an aggregate is safe. `NO_KITTY_FLAGS` is a named constant for the common "not Kitty" case used in the `Legacy` and `XTerm_CSI` branches of `Keyboard_Capability`.

### `Keyboard_Capability` record (FUNC-KKB-003)

```ada
--  @relation(FUNC-KKB-003)
type Keyboard_Capability is record
   Protocol : Keyboard_Protocol := Unknown;
   Flags    : Kitty_Flags       := NO_KITTY_FLAGS;
   Probed   : Boolean           := False;
end record;

NO_KEYBOARD_CAPABILITY : constant Keyboard_Capability :=
  (Protocol => Unknown, Flags => NO_KITTY_FLAGS, Probed => False);
```

**"Unknown" / "not probed" representation — ADR-worthy (see §N).** A plain record with all-False/Unknown defaults was chosen over discriminated variant (`case Protocol is when Kitty => Flags : Kitty_Flags; when others => null;`) and over Option-wrapping (`Maybe (Keyboard_Capability)`). Rationale: SPARK-simplicity and API ergonomics. Callers inspect `Flags` only when `Protocol = Kitty`; for all other values the record invariant is `Flags = NO_KITTY_FLAGS`, enforceable by the constructor helper `Make_Capability` in the body (not a type invariant, which would complicate SPARK proofs). The explicit `Probed` field is the direct discriminant between "probed and found no enhanced protocol" (Legacy) and "could not probe" (Unknown) per FUNC-KKB-003's commentary.

### `Parse_Result` record (FUNC-KKB-006)

```ada
--  @relation(FUNC-KKB-006)
type Parse_Result is record
   Valid     : Boolean := False;
   Flags_Int : Natural := 0;
end record;
```

Used only as the return type of `Parse_Kitty_Response`. Invariant (not enforced via aspect): `not Valid implies Flags_Int = 0`.

### SPARK contracts on parsers

```ada
function Parse_Kitty_Flags (Flags_Int : Natural) return Kitty_Flags
  with SPARK_Mode => On,
       Global     => null,
       Pre        => True,
       Post       => True;

function Parse_Kitty_Response
  (Buffer : Byte_Array; Length : Natural) return Parse_Result
  with SPARK_Mode => On,
       Global     => null,
       Pre        => Length <= Buffer'Length,
       Post       => (if not Parse_Kitty_Response'Result.Valid
                      then Parse_Kitty_Response'Result.Flags_Int = 0);

function Parse_XTerm_Keyboard_Response
  (Buffer : Byte_Array; Length : Natural) return Boolean
  with SPARK_Mode => On,
       Global     => null,
       Pre        => Length <= Buffer'Length,
       Post       => True;
```

`Byte` and `Byte_Array` are re-declared in `Termicap.Keyboard` as subtypes of `Interfaces.C.unsigned_char` and `array (Positive range <>) of Byte`, matching the representation-compatible convention already used by `Termicap.DA1` and `Termicap.XTVERSION` so that `Termicap.Keyboard.IO` can convert between these and `Termicap.OSC.Byte_Array` without a SPARK-mode violation and without a copy when using explicit loops.

### Query byte constants

```ada
--  @relation(FUNC-KKB-004)
CSI_KITTY_QUERY : constant Byte_Array :=
  [16#1B#, 16#5B#, 16#3F#, 16#75#];  --  ESC [ ? u

--  @relation(FUNC-KKB-007)
CSI_XTERM_KBD_QUERY : constant Byte_Array :=
  [16#1B#, 16#5B#, 16#3F#, 16#34#, 16#6D#];  --  ESC [ ? 4 m

KITTY_PROBE_TIMEOUT_MS : constant Natural := 1000;   --  FUNC-KKB-013
XTERM_KBD_PROBE_TIMEOUT_MS : constant Natural := 1000; --  FUNC-KKB-013
```

Both constants are in the SPARK On spec so the I/O child can reference them without crossing a SPARK_Mode boundary, matching the `CSI_XTVERSION_QUERY` / `DA1_QUERY` pattern.

---

## F. Detection Algorithm

### Full cascade (FUNC-KKB-009)

```
function Detect_Keyboard_Protocol return Keyboard_Capability is

   -- Step 1: WIN32 GATE (Windows body only; FUNC-KKB-010)
   #if Platform = Windows then
      H := GetStdHandle (STD_INPUT_HANDLE);
      Mode := 0;
      if H is valid and GetConsoleMode (H, Mode'Access) /= FALSE then
         --  Native Windows Console: no escape probe useful.
         return (Win32, NO_KITTY_FLAGS, Probed => False);
      end if;
      --  GetConsoleMode failed: either Cygwin/MSYS PTY, pipe, or file.
      --  Fall through to POSIX-like cascade (Sentinel_Query works on PTY).
   #end if;

   -- Step 2: TTY GUARD (FUNC-KKB-011)
   if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdin) then
      return (Unknown, NO_KITTY_FLAGS, Probed => False);
   end if;

   -- Step 3: OPEN PROBE_SESSION
   --  Probe_Session.Open performs the foreground check (FUNC-OSC-007),
   --  acquires /dev/tty (FUNC-OSC-001), saves termios, enters raw mode
   --  (FUNC-OSC-002/003), drains stale input (FUNC-OSC-011).
   --  Session is Limited_Controlled: Finalize restores termios and closes
   --  fd on every scope exit, satisfying FUNC-KKB-015 by construction.
   Session.Open (Status);
   if Status /= Session_OK then
      return (Unknown, NO_KITTY_FLAGS, Probed => False);
   end if;

   -- Step 4: KITTY PROBE (FUNC-KKB-004)
   Session.Sentinel_Query
     (Query       => CSI_KITTY_QUERY,
      Response    => Raw,
      Resp_Length => Raw_Len,
      Timeout_Ms  => KITTY_PROBE_TIMEOUT_MS,
      Timed_Out   => Timed_Out,
      Retry       => False);

   if not Timed_Out and Raw_Len > 0 then
      Kitty_Parse := Parse_Kitty_Response (Raw, Raw_Len);
      if Kitty_Parse.Valid then
         return (Kitty,
                 Parse_Kitty_Flags (Kitty_Parse.Flags_Int),
                 Probed => True);
      end if;
   end if;

   -- Step 5: XTERM PROBE (FUNC-KKB-007)
   Session.Sentinel_Query
     (Query       => CSI_XTERM_KBD_QUERY,
      Response    => Raw,
      Resp_Length => Raw_Len,
      Timeout_Ms  => XTERM_KBD_PROBE_TIMEOUT_MS,
      Timed_Out   => Timed_Out,
      Retry       => False);

   if not Timed_Out and Raw_Len > 0 then
      if Parse_XTerm_Keyboard_Response (Raw, Raw_Len) then
         return (XTerm_CSI, NO_KITTY_FLAGS, Probed => True);
      end if;
   end if;

   -- Step 6: LEGACY (both probes negative; FUNC-KKB-009 step 6)
   return (Legacy, NO_KITTY_FLAGS, Probed => True);

exception
   when others =>
      --  FUNC-KKB-014: no-exception contract.
      return (Unknown, NO_KITTY_FLAGS, Probed => False);
end Detect_Keyboard_Protocol;
```

### Decision tree

```
                    Start
                      |
         [Windows?] -- yes --> GetConsoleMode(STDIN) ?
                      |                  |
                     no                 True  ----> Win32, Probed=False
                      |                  |
                      v                 False (Cygwin/pipe/file)
                Is_TTY(Stdin) ?               \
                      |                       v
                     no --> Unknown      [continue POSIX cascade]
                      |
                     yes
                      |
                Probe_Session.Open succeeds ?
                      |
                     no --> Unknown, Probed=False
                      |
                     yes  (foreground guard passed inside Open)
                      |
                Kitty Sentinel_Query (1000 ms)
                      |
          pre-sentinel matches CSI ? <n> u ?
                      |                |
                     yes              no (incl. timeout)
                      |                |
                  Kitty,               v
                 Probed=True     XTerm Sentinel_Query (1000 ms)
                                       |
                        pre-sentinel matches CSI ? 4 ; <n> m ?
                                 |           |
                                yes          no (incl. timeout)
                                 |           |
                             XTerm_CSI,      v
                             Probed=True   Legacy,
                                           Probed=True
```

### Foreground guard placement

FUNC-KKB-011 step 3 enumerates the foreground check as a separate cascade step. In the implementation, the foreground check happens **inside** `Probe_Session.Open` (per `Termicap.OSC.Open`'s documented sequence, `FUNC-OSC-007`). If the process is backgrounded, `Open` returns `Session_Not_Foreground` which the cascade above handles in step 3 (`Status /= Session_OK`). This is the same composition already used by `Termicap.XTVERSION.IO.Query_XTVERSION` and `Termicap.DA1.IO.Query_DA1`. The observable cascade ordering matches FUNC-KKB-011 exactly: **no probe runs** unless `Is_TTY` is True and the process is foreground.

### Windows Cygwin fall-through

On Windows, if `GetConsoleMode (STD_INPUT_HANDLE)` returns FALSE, stdin is either a Cygwin/MSYS PTY, an anonymous pipe, or a file. For Cygwin PTYs, the POSIX-like path works: Cygwin's `mintty` emulates PTY semantics, interprets `CSI ? u` / `CSI ? 4 m` correctly, and responds. For pipes and files, `Termicap.TTY.Is_TTY` returns False (step 2) and the cascade exits with `Unknown`. No ambiguity.

Implementation note: the Windows body will `with Termicap.Win32_Cygwin` only if a finer classification is needed for telemetry. For the detection cascade itself, `Termicap.TTY.Is_TTY (Stdin)` already incorporates the Cygwin check (per FUNC-CYG-015), so a separate `Is_Cygwin_Terminal` call is redundant here. The Windows body will **not** import `Termicap.Win32_Cygwin`; it relies on `Is_TTY` returning True for Cygwin PTY handles.

---

## G. Parser design (SPARK Silver)

### `Parse_Kitty_Flags` (FUNC-KKB-005)

| Property | Value |
|----------|-------|
| Signature | `function Parse_Kitty_Flags (Flags_Int : Natural) return Kitty_Flags` |
| SPARK target | Silver (absence of runtime errors, `Global => null`) |
| Input | Any `Natural` |
| Output | `Kitty_Flags` record |
| Pre | `True` (placeholder) |
| Post | `True` (placeholder; may be strengthened to `Parse_Kitty_Flags (0) = NO_KITTY_FLAGS`) |

Body: five independent `(Flags_Int / 2**N) mod 2 = 1` tests, one per bit. Uses `Natural`-level arithmetic only, avoiding `Interfaces.Unsigned_8` to keep SPARK arithmetic reasoning simple. The division-by-power-of-two approach is provably total on `Natural` (no `Constraint_Error`), unlike hypothetical `Interfaces.Shift_Right` which requires `SPARK_Mode` exclusions. Bits 5+ are ignored by construction (the function examines only bits 0..4).

### `Parse_Kitty_Response` (FUNC-KKB-006)

| Property | Value |
|----------|-------|
| Signature | `function Parse_Kitty_Response (Buffer : Byte_Array; Length : Natural) return Parse_Result` |
| SPARK target | Silver |
| Input | `Byte_Array`, `Length <= Buffer'Length` |
| Output | `Parse_Result` (`Valid` + `Flags_Int`) |
| Pre | `Length <= Buffer'Length` |
| Post | `not Valid implies Flags_Int = 0` |

Body algorithm:
1. If `Length < 4` (minimum: `ESC [ ? u` is 4 bytes), return `(Valid => False, Flags_Int => 0)`.
2. Check bytes 1..3 of `Buffer (Buffer'First .. Buffer'First + 2)` are `ESC`, `[`, `?`. If not, `(False, 0)`.
3. Check `Buffer (Buffer'First + Length - 1) = Character'Pos ('u')`. If not, `(False, 0)`.
4. Parse decimal digits in `Buffer (Buffer'First + 3 .. Buffer'First + Length - 2)`:
   - If this range is empty (`Length = 4`, i.e., bare `CSI ? u`), `Flags_Int := 0`, `Valid := True`.
   - Else accumulate digits into `Flags_Int`. Non-digit byte anywhere in range: `(False, 0)`.
   - Guard against overflow: if accumulator would exceed `Natural'Last / 10`, clamp and mark invalid (defensive; 2 ** 31 overflow on a 10-digit response is astronomically unlikely but must not raise `Constraint_Error`).
5. Return `(Valid => True, Flags_Int => <accumulated>)`.

Loop invariant for digit accumulation:
```ada
pragma Loop_Invariant (Flags_Int <= Natural'Last / 10 - 9);
pragma Loop_Invariant (I in Buffer'First + 3 .. Buffer'First + Length - 2);
```
The first invariant keeps `Flags_Int * 10 + 9` safely within `Natural`. The second bounds the scan index.

**Malformed input rejection (FUNC-KKB-016).** Any byte outside the expected pattern produces `(False, 0)`, which the cascade treats as a Kitty miss and continues. Interleaved bytes (partial escape sequences, stray bracketed-paste introducers) that happen to start with `ESC [ ?` but do not terminate with `u` in the `Buffer (1 .. Length)` range are rejected because the terminator check at step 3 fails.

### `Parse_XTerm_Keyboard_Response` (FUNC-KKB-008)

| Property | Value |
|----------|-------|
| Signature | `function Parse_XTerm_Keyboard_Response (Buffer : Byte_Array; Length : Natural) return Boolean` |
| SPARK target | Silver |
| Input | `Byte_Array`, `Length <= Buffer'Length` |
| Output | `Boolean` (no numeric extraction per FUNC-KKB-007) |
| Pre | `Length <= Buffer'Length` |
| Post | `True` |

Body algorithm:
1. Minimum length: `ESC [ ? 4 ; <one digit> m` = 7 bytes. If `Length < 7`, return False.
2. Check `Buffer (Buffer'First .. Buffer'First + 4)` is `ESC [ ? 4 ;` (5 bytes).
3. Check `Buffer (Buffer'First + Length - 1) = Character'Pos ('m')`.
4. Scan `Buffer (Buffer'First + 5 .. Buffer'First + Length - 2)`:
   - Must be non-empty (at least one digit).
   - Every byte must be in `Character'Pos ('0') .. Character'Pos ('9')`.
5. Return True iff all checks pass.

The function does not accumulate the value (FUNC-KKB-007 notes that the `<value>` is the current mode setting 1/2/...; the cascade does not need it).

**Empty digits rejection** (FUNC-KKB-008 explicit): a bare `ESC [ ? 4 ; m` (6 bytes) fails step 1's length check; a pathological `ESC [ ? 4 ; m` of length 7 with a non-digit between `;` and `m` fails step 4.

### Provability notes

All three parsers are branch-heavy but loop-shallow; the Kitty digit-accumulation is the only loop, and its invariants above are pattern-matchable by GNATprove. Expected outcome: Silver (absence of runtime errors, `Global => null` proved) on all three. Gold-level functional postconditions are not pursued — the parsers are tested by unit vectors (§L) rather than proved functionally correct. This matches the precedent set by `Parse_Kitty_Response`'s counterpart `Contains_XTVERSION_Response` (also Silver, `Post => True`).

---

## H. I/O Orchestration

### Use of `Termicap.OSC.Probe_Session` and `Sentinel_Query`

The entire I/O path in `Detect_Keyboard_Protocol` is built on the existing `Termicap.OSC` primitives, satisfying FUNC-KKB-012:

| OSC primitive | Used by | Requirement |
|---------------|---------|-------------|
| `Probe_Session` (declare block) | Whole cascade | FUNC-KKB-012 step 1–6, FUNC-KKB-015 |
| `Open` | Step 3 | FUNC-OSC-001, FUNC-OSC-002, FUNC-OSC-003, FUNC-OSC-007 |
| `Sentinel_Query` | Steps 4, 5 | FUNC-KKB-004, FUNC-KKB-007, FUNC-OSC-006 |
| `Finalize` (implicit via RAII) | All exit paths | FUNC-KKB-015 |

The `Probe_Session` is declared inside `Detect_Keyboard_Protocol`; Ada's `Limited_Controlled` semantics guarantee `Finalize` runs on scope exit, whether through normal return, propagated exception, or unhandled condition. This gives us FUNC-KKB-015's "termios restore on every exit path" for free — no explicit try/finally needed, and no chance of a bug leaving the terminal in raw mode.

### Termios save/restore ownership

Owned by `Termicap.OSC.Probe_Session`, **not** by `Termicap.Keyboard.IO`. The `Keyboard.IO` body does not call `tcgetattr`, `tcsetattr`, `select`, `read`, or `write` directly. The one exception is the Windows gate, which uses `Win32.Wincon.GetConsoleMode` as a predicate (not as I/O); that call is free of termios state. This satisfies FUNC-KKB-012 step 6 precisely.

### Timeout (FUNC-KKB-013)

`KITTY_PROBE_TIMEOUT_MS = XTERM_KBD_PROBE_TIMEOUT_MS = 1000`. Each `Sentinel_Query` receives its own `Timeout_Ms` parameter and resets its internal deadline. Worst-case wall clock for a full cascade (Kitty times out, XTerm times out): **2 seconds** (plus negligible open/restore overhead). Best case (Kitty responds immediately): tens of milliseconds. This latency budget is intentional and consistent with the OSC-INFRA convention documented in `FUNC-OSC-004`.

Future optimisation (out of scope): the 1000 ms default could be tightened on local PTYs and lengthened on SSH sessions, per FUNC-KKB-013's "minimum 100 ms" clause. Not attempted in this feature; a future ADR may revisit.

### EINTR / EAGAIN handling (FUNC-KKB-014)

`Termicap.OSC.Timed_Read` (which `Sentinel_Query` drives) already handles EINTR by returning `Bytes_Read = 0` and `Timed_Out = False`, causing the accumulation loop in `Sentinel_Query` to retry up to the timeout. This behaviour is inherited, not reimplemented. If a signal arrives during the probe, the probe retries; if signals keep arriving until the 1000 ms deadline, the probe times out and the cascade continues to the next step. No exception propagates.

### Partial-read / garbled-response path (FUNC-KKB-016)

`Sentinel_Query` always accumulates bytes until the DA1 response pattern is detected (or the timeout fires). Pre-sentinel bytes that do not match the Kitty or XTerm response patterns are simply rejected by the respective parser (both return negative), and the cascade continues to the next step. Because `Sentinel_Query` keeps reading until DA1, a partial Kitty response (e.g., `ESC [ ? 1` with no terminator) does not stall the probe — the DA1 sentinel still arrives and terminates the read loop. This property is load-bearing for the cascade's correctness; it is a direct property of `Sentinel_Query`, not a new behaviour introduced by this feature.

### No-exception contract surface (FUNC-KKB-014)

Failure modes enumerated in FUNC-KKB-014 and where they are caught:

| Failure mode | Catch location |
|--------------|----------------|
| `/dev/tty` unopenable | `Probe_Session.Open` returns `Session_No_Terminal` → cascade exits with `Unknown` |
| `tcgetattr` fails | `Open` returns `Session_Save_Failed` → `Unknown` |
| `tcsetattr` raw-mode fails | `Open` returns `Session_Raw_Failed` → `Unknown` |
| `Write_Query` fails | `Sentinel_Query` sets `Timed_Out := True` → treated as negative, cascade continues |
| `Sentinel_Query` timeout | `Timed_Out := True` → cascade continues or falls through to Legacy |
| Garbled response | Parser returns `Valid := False` / `False` → cascade continues |
| EINTR / EAGAIN | `Timed_Read` loop retries internally |
| Termios restore fails | `Probe_Session.Close`'s internal `OK` flag is silently ignored per `FUNC-OSC-002`; exit continues |
| `GetConsoleMode` raises (Windows) | Top-level `when others => return (Unknown, NO_KITTY_FLAGS, False)` |
| Null / invalid fd (Windows bad stdin handle) | `GetConsoleMode` returns FALSE, gate does not fire, cascade falls through to step 2 which reads `Is_TTY (Stdin)` |

The outer `when others` handler at the bottom of `Detect_Keyboard_Protocol` is the final safety net. It never logs. It returns `(Unknown, NO_KITTY_FLAGS, Probed => False)` — the canonical "could not determine" value. No exception propagates to the caller, consistent with the no-exception convention already enforced across `Termicap.Win32_Cygwin.Is_Cygwin_Terminal`, `Termicap.DA1.IO.Detect_DA1`, and `Termicap.XTVERSION.IO.Query_And_Identify`.

---

## I. Caching (FUNC-KKB-017)

### Cache shape

A single-slot protected object in the `Termicap.Keyboard.IO` body (identical pattern to the two-value protected object in `Termicap.Override` and structurally similar to `Termicap.Capabilities`'s three-slot protected object):

```ada
type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Keyboard_Capability;
end record;

protected Cache is
   function Get_Cached return Cache_Slot;
   procedure Set_Cached (Caps : Keyboard_Capability);
private
   Slot : Cache_Slot;
end Cache;
```

`Detect_Keyboard_Protocol` reads the cache first; on initialised, returns the cached `Value`. On uninitialised, runs the full cascade, calls `Cache.Set_Cached (Result)`, and returns. Race between two concurrent first callers is safe: both run the cascade, both write to the cache, last-writer wins. Both results are semantically equivalent (the terminal does not change mid-cascade), so no correctness issue. This lazy pattern matches `Termicap.Capabilities.Get` exactly.

### Lazy initialisation (FUNC-KKB-017 explicit requirement)

The protected object's `Slot` is default-initialised by Ada elaboration to `(Initialized => False, Value => NO_KEYBOARD_CAPABILITY)`. **No probe runs at elaboration time.** The first call to `Detect_Keyboard_Protocol` triggers the cascade.

### Cache-bypass variant (FUNC-KKB-017 Should clause)

A second public function, `Probe_Keyboard_Protocol`, is added to the `Termicap.Keyboard.IO` spec:

```ada
--  @relation(FUNC-KKB-017 Should clause): cache-bypass detection
function Probe_Keyboard_Protocol return Keyboard_Capability;
```

`Probe_Keyboard_Protocol` runs the full cascade every time, **does not read or write the cache**, and is intended for test harnesses and edge cases where the terminal may have changed (e.g., `tmux attach` to a different outer terminal). This is analogous to `Termicap.Capabilities.Detect` vs. `Termicap.Capabilities.Get` (FUNC-CAP-004 vs. FUNC-CAP-003).

### SIGWINCH

Not relevant. The cache is not invalidated on SIGWINCH, explicitly required by FUNC-KKB-017's final sentence. No signal handler is installed by this feature.

### Thread-safety posture

Protected object grants mutex per call; the `Get_Cached` / `Set_Cached` pair is non-blocking in the common cached-hit case (`Get_Cached` is a function, read-only). Elaboration of the protected object precedes concurrent task startup. No deadlock risk: the probe cascade itself does not call back into `Termicap.Keyboard.*` from within a protected operation (the cascade runs entirely between the cache read and the cache write, not inside either).

---

## J. Platform-Specific Details

### POSIX body (`src/posix/termicap-keyboard-io.adb`)

Implements the cascade starting at step 2 (TTY guard). No Win32 withs. Approximate LOC: 120 including comments and the protected body.

### Windows body (`src/windows/termicap-keyboard-io.adb`)

Implements the Win32 gate (step 1) before the POSIX-like cascade. Approximate LOC: 160 including comments and the Win32 gate.

The Win32 gate uses `Win32.Winbase.GetStdHandle (STD_INPUT_HANDLE)` and `Win32.Wincon.GetConsoleMode`. If the handle is invalid (`INVALID_HANDLE_VALUE` or null), the gate treats it as "not a console" and falls through. This matches the defensive pattern in `Termicap.Win32_Cygwin.Is_Cygwin_Terminal`'s entry guard.

VT processing is **not** enabled here. The Windows body of `Termicap.TTY` handles `Enable_VT_Processing` when stdout is a TTY; keyboard detection does not touch output VT state. This is an important separation — the Kitty/XTerm probes write to `/dev/tty` (or the Windows equivalent via the `Probe_Session`), not to stdout, and do not alter the terminal's VT mode.

### Platform behaviour summary

| Platform | Step 1 Win32 gate | Step 2 TTY guard | Step 3 Probe_Session | Probe path | Returns |
|----------|-------------------|------------------|----------------------|------------|---------|
| Linux (interactive) | skipped | passes | opens | runs Kitty/XTerm probes | `Kitty` / `XTerm_CSI` / `Legacy` |
| Linux (piped stdin) | skipped | fails | — | — | `Unknown` |
| Linux (background job) | skipped | passes | `Session_Not_Foreground` | — | `Unknown` |
| macOS (interactive) | skipped | passes | opens | runs probes | `Kitty` / `XTerm_CSI` / `Legacy` |
| BSD (interactive) | skipped | passes | opens | runs probes | `Kitty` / `XTerm_CSI` / `Legacy` |
| Windows Terminal / conhost | fires | — | — | — | `Win32` |
| Windows + git-bash (Cygwin PTY) | does not fire | passes (via Cygwin branch of `Is_TTY`) | opens | runs probes | `Kitty` / `XTerm_CSI` / `Legacy` |
| Windows (stdin redirected) | does not fire (pipe/file) | fails | — | — | `Unknown` |

---

## K. Integration with `Terminal_Capabilities` (FUNC-KKB-019) — deferred

### Decision: defer

FUNC-KKB-019 is priority **Should** and introduces a non-trivial latency cost on `Terminal_Capabilities.Get`/`Detect` (up to +2 s worst-case if both probes time out). The decision about eager-vs-lazy probing from within `Capabilities.Detect` is load-bearing for existing callers and deserves its own ADR.

This spec **defers** the integration. Rationale:

1. The standalone `Detect_Keyboard_Protocol` function is the primary API; it is usable immediately without the integration.
2. `Terminal_Capabilities` is Approved and stable; adding a field requires a coordinated update to its test suite, the capability-record tech spec (§J of `docs/tech-specs/capability-record.md`), and the architecture doc — all of which should be done once the eager-vs-lazy question is resolved.
3. FUNC-KKB-019's status is "Draft/Should" per its own commentary; deferring is explicitly contemplated.

### Migration path (when integration is picked up)

1. Add field `Keyboard : Termicap.Keyboard.Keyboard_Capability := NO_KEYBOARD_CAPABILITY` to `Terminal_Capabilities` (record extension, backward-compatible in Ada).
2. Call `Termicap.Keyboard.IO.Detect_Keyboard_Protocol` from `Termicap.Capabilities.Detect`'s step sequence (currently steps 1–7, keyboard would be a new step 8).
3. Write an ADR on eager vs. lazy: **eager** (probe on every `Detect` call) is simple but slow; **lazy** (populate only on explicit opt-in via a separate `Detect_With_Keyboard` or a parameter) preserves the current `Detect` latency.
4. Extend `Termicap.Capabilities.Assemble`'s signature to accept the new field and update its SPARK postcondition.

Nothing in this feature's design precludes the integration. The `Keyboard_Capability` type is designed to be embeddable as a `Terminal_Capabilities` field.

---

## L. Testing strategy

### Unit tests — pure parsers

All three parsers are testable without any OS interaction, using synthetic `Byte_Array` inputs. Test package location: `tests/src/test_keyboard_parsers.adb`.

#### `Parse_Kitty_Flags` vectors (FUNC-KKB-005)

| Input | Expected |
|-------|----------|
| 0 | all False |
| 1 | Disambiguate_Escape_Codes = True, rest False |
| 2 | Report_Event_Types = True, rest False |
| 4 | Report_Alternate_Keys = True, rest False |
| 8 | Report_All_Keys_As_Escape = True, rest False |
| 16 | Report_Associated_Text = True, rest False |
| 31 | all five bits True |
| 32 | all False (bit 5 ignored) |
| 63 | bits 0..4 True, bit 5 ignored → all five bits True |
| Natural'Last | bits 0..4 per pattern of Natural'Last; high bits ignored |

Target: 10 vectors, >95% line coverage of `Parse_Kitty_Flags`.

#### `Parse_Kitty_Response` vectors (FUNC-KKB-006)

| Input bytes | Length | Expected |
|-------------|--------|----------|
| `ESC [ ? u` | 4 | Valid=True, Flags_Int=0 |
| `ESC [ ? 1 u` | 5 | Valid=True, Flags_Int=1 |
| `ESC [ ? 31 u` | 6 | Valid=True, Flags_Int=31 |
| `ESC [ ? 1 0 0 u` | 7 | Valid=True, Flags_Int=100 |
| empty buffer | 0 | Valid=False, Flags_Int=0 |
| `ESC [ ?` (truncated) | 3 | Valid=False |
| `ESC [ ? 1` (no terminator) | 4 | Valid=False |
| `ESC [ ? x u` (non-digit) | 5 | Valid=False |
| `ESC [ ! u` (wrong introducer) | 4 | Valid=False |
| `ESC P ? u` (wrong CSI byte) | 4 | Valid=False |
| `ESC [ ? 1 m` (wrong terminator) | 5 | Valid=False |
| mouse event prefix `ESC [ M ...` | 6 | Valid=False |

Target: 12 vectors, covering valid, empty-flags, truncated, garbled, wrong-introducer, wrong-terminator, interleaved-garbage.

#### `Parse_XTerm_Keyboard_Response` vectors (FUNC-KKB-008)

| Input bytes | Length | Expected |
|-------------|--------|----------|
| `ESC [ ? 4 ; 1 m` | 7 | True |
| `ESC [ ? 4 ; 2 m` | 7 | True |
| `ESC [ ? 4 ; 2 4 m` | 8 | True |
| `ESC [ ? 4 ; m` (no digits) | 6 | False |
| `ESC [ ? 4 m` (no semicolon) | 5 | False |
| `ESC [ ? 4 ; x m` (non-digit) | 7 | False |
| `ESC [ ? 4 ; 1` (no terminator) | 6 | False |
| empty | 0 | False |

Target: 8 vectors.

### Harness / integration tests — FFI path

These require a live terminal and are CI-gated / manual. Test programs live in `examples/` and under `tests/integration/`.

| Test | Mechanism | CI-safe |
|------|-----------|---------|
| Non-TTY stdin → `Unknown` | Run test binary with stdin redirected from `/dev/null` | Yes |
| Background job → `Unknown` | Run via `shell & wait`; inspect output | Yes (POSIX CI) |
| Native Kitty terminal → `Protocol = Kitty` | Manual on Kitty; capture `Flags` | No |
| xterm with modifyOtherKeys → `Protocol = XTerm_CSI` | Manual on xterm | No |
| Windows Terminal (native console) → `Protocol = Win32` | Manual on Windows CI | No |
| git-bash (Cygwin PTY) → Legacy or XTerm_CSI | Manual on Windows dev machine | No |

### Example program

`examples/keyboard_protocol_demo/` prints the result of `Detect_Keyboard_Protocol` along with the individual flag bits when `Protocol = Kitty`. Useful for developer verification on any terminal.

### Coverage target

Project-wide target: >95% line coverage (CLAUDE.md). The three parsers must reach 100% line coverage via the unit vectors above; `Detect_Keyboard_Protocol` itself reaches ~80% via the non-TTY / redirected paths (the probe-positive branches are not exercisable in POSIX CI without a PTY harness).

---

## M. Cross-Platform Behaviour

Summarised in the table in §J. Key invariants:

- On **POSIX** (Linux, macOS, BSD), the Win32 gate is compile-time absent; the cascade always starts at step 2.
- On **Windows native console**, the Win32 gate always fires; no escape-sequence I/O is attempted.
- On **Windows + Cygwin/MSYS PTY**, the Win32 gate does not fire, `Is_TTY (Stdin)` returns True via the Cygwin branch (FUNC-CYG-015), and the cascade probes the PTY. Cygwin's `mintty` responds correctly to both `CSI ? u` and `CSI ? 4 m` in recent versions.
- On **any platform with redirected stdin**, `Is_TTY (Stdin)` returns False and the cascade exits with `Unknown`.

The Win32 gate is compile-time guarded (platform-specific body) rather than runtime-branched. Code for the gate does not exist in the POSIX binary.

---

## N. Risks & Open Questions

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| A terminal emits a spurious `CSI ? <digits> u` sequence (mouse event or paste data coincidentally containing the pattern) before DA1 — false positive | Low | Low | `Sentinel_Query` bounds pre-sentinel bytes; parsers require exact framing; false-positive probability negligible |
| A terminal (e.g., certain tmux versions) echoes the query bytes back before DA1, confusing the parser | Medium | Low | `Parse_Kitty_Response` requires `u` terminator; echoed `ESC [ ? u` (our own query) would parse as `Valid, Flags_Int = 0`, leading to a false Kitty positive | — **open question**: should the parser reject echoed queries that lack any digits between `?` and `u`? See open question below |
| 1000 ms per probe ×2 = 2 s worst-case cold-start latency | Medium | Medium | Documented; FUNC-KKB-013 explicitly permits shorter timeouts on local PTYs; future ADR may revisit |
| A future Kitty protocol extension adds bit 5+ with meaningful semantics | Low | Low | FUNC-KKB-005 explicitly allows ignoring bits 5+; extending `Kitty_Flags` is backward-compatible (add field, default False) |
| The protected-object cache's race (two concurrent cold callers both run the cascade) wastes 2 s | Very low | Low | Accepted; the window is one cascade per process, the outcome is deterministic |
| `GetConsoleMode` hangs on an unusual handle | Very low | Medium | Top-level `when others` catches any propagated exception; `GetConsoleMode` does not itself hang (OS-enforced) |
| Detection during `tmux attach` returns stale outer-terminal capability | Medium | Low | Callers needing fresh data use `Probe_Keyboard_Protocol` (cache-bypass); consistent with `Termicap.Capabilities.Detect` semantics |

### Open questions

1. **Self-echo protection.** If the terminal (or an intermediate multiplexer configured wrong) echoes `ESC [ ? u` back before DA1, `Parse_Kitty_Response` would accept it as `Valid, Flags_Int = 0`, reporting Kitty with all flags False. This is arguably still correct (the terminal did respond to the Kitty query), but a less-charitable interpretation is that the echoed bytes are noise. **Proposed resolution:** accept bare `CSI ? u` as valid per FUNC-KKB-004's explicit allowance; callers who need certainty may cross-check with XTVERSION. Deferred to runtime experience.

2. **Multiplexer passthrough.** `Termicap.XTVERSION.IO` and `Termicap.DA1.IO` both wrap their queries for tmux/screen passthrough (`Wrap_For_Passthrough`). Should the Kitty/XTerm probes do the same? **Proposed resolution:** yes, same pattern — extend `Query_XTVERSION`-style identity detection at the top of `Detect_Keyboard_Protocol` and wrap both queries accordingly. This is a small addition (~10 LOC). Not mandated by any FUNC-KKB requirement but strongly implied by the "reuse OSC-INFRA" directive of FUNC-KKB-012. **Included in the design** — see final LOC estimate.

3. **Win32 keyboard DECRPM probe.** FUNC-KKB-001 mentions "Win32 input mode (mode 9001), detected via DECRPM" in the research citations, but the approved requirement uses `GetConsoleMode` as the Win32 gate, not a DECRPM probe. Treated as out-of-scope; `GetConsoleMode` is sufficient and avoids adding a fourth escape probe.

---

## O. Alternatives Considered

### Alternative 1: single flat `Termicap.Keyboard` package (no `.IO` child)

Put both the pure parsers and `Detect_Keyboard_Protocol` in one package, with `SPARK_Mode => On` at the package level and `SPARK_Mode => Off` locally on `Detect_Keyboard_Protocol`'s body.

**Rejected** because:
- The spec-level `SPARK_Mode => On` is a claim about every subprogram declared in the spec; `Detect_Keyboard_Protocol`'s declaration with an implicit `Off` body weakens `Global` / `Depends` reasoning across the whole spec. GNATprove would issue warnings.
- Platform dispatch requires two bodies (POSIX and Windows); a shared spec with two-body dispatch works only when the spec has at most one SPARK_Mode stance. Mixing modes at the subprogram level across two bodies is fragile.
- Follows the established Termicap convention (`Termicap.DA1` / `.IO`, `Termicap.XTVERSION` / `.IO`).

### Alternative 2: eager probe at library elaboration

Populate the cache at elaboration time via a `begin ... end;` block in the package body.

**Rejected** because FUNC-KKB-017 explicitly forbids it: "Eager probing at library elaboration time is not permitted." Also unsafe per the project's general policy: elaboration-time OS calls are a common source of startup deadlocks and cannot be cleanly recovered.

### Alternative 3: embed the probe in `Termicap.Capabilities.Detect`

Run the keyboard probe from inside the `Capabilities.Detect` sub-detector sequence (alongside Color, Dimensions, Unicode, etc.).

**Deferred, not rejected.** This is the FUNC-KKB-019 integration path. The design allows it; the decision about when and how to wire it in belongs to a follow-up ADR (see §K).

### Alternative 4: discriminated `Keyboard_Capability` variant record

```ada
type Keyboard_Capability (Protocol : Keyboard_Protocol := Unknown) is record
   Probed : Boolean := False;
   case Protocol is
      when Kitty => Flags : Kitty_Flags;
      when others => null;
   end case;
end record;
```

**Rejected** because FUNC-KKB-003 explicitly wants `Flags` unconditionally present ("The Flags field is included unconditionally (rather than in a variant record) to keep the type simple and SPARK-provable"). Matching the requirement; avoiding discriminated-record complications in SPARK.

### Alternative 5: separate Kitty-only vs. XTerm-only probe functions

Expose `Detect_Kitty_Keyboard` and `Detect_XTerm_Keyboard` as independent API entries; let the caller decide which to try.

**Rejected.** The cascade is specified in FUNC-KKB-009 as an atomic "return the highest-priority detected protocol" operation. Splitting it would require callers to implement the priority logic themselves and force a second cache layer per protocol. Simpler and less error-prone to expose only the cascade.

### Alternative 6: Kitty push-mode detection (enable + observe)

Some references (notcurses) confirm Kitty support by pushing a flag set (`CSI = 1 u`) and observing the response. This is functionally a "probe by attempting to activate" pattern.

**Rejected.** Kitty push-mode activation is a *side effect* — it changes the terminal's keyboard state until explicitly popped. Detection via `CSI ? u` (query-only) is side-effect-free and fully adequate, matching crossterm and tcell's stable query-mode path.

---

## P. Files Created / Modified

### New files

| File | Purpose | Approx LOC |
|------|---------|-----------|
| `src/termicap-keyboard.ads` | Spec: types, constants, parsers (SPARK_Mode => On) | 180 |
| `src/termicap-keyboard.adb` | Body: parser bodies (local SPARK_Mode => On) | 200 |
| `src/termicap-keyboard-io.ads` | Spec: `Detect_Keyboard_Protocol`, `Probe_Keyboard_Protocol` (SPARK_Mode => Off) | 80 |
| `src/posix/termicap-keyboard-io.adb` | POSIX body: cascade without Win32 gate | 130 |
| `src/windows/termicap-keyboard-io.adb` | Windows body: cascade with Win32 gate | 170 |
| `tests/src/test_keyboard_parsers.ads` | Test spec | 30 |
| `tests/src/test_keyboard_parsers.adb` | Test body: 30 vectors across the three parsers | 250 |
| `examples/keyboard_protocol_demo/src/keyboard_protocol_demo.adb` | Demo program | 80 |
| `examples/keyboard_protocol_demo/alire.toml` | Alire crate | 20 |
| `examples/keyboard_protocol_demo/keyboard_protocol_demo.gpr` | GPR | 15 |

Total new code: ~1150 LOC (approximately 380 spec, 770 body/test/example).

### Modified files

| File | Change |
|------|--------|
| `tests/src/termicap_tests.adb` | Register `test_keyboard_parsers` in the harness |
| `examples/termicap_examples.gpr` | Include `keyboard_protocol_demo` |
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Keyboard` and `Termicap.Keyboard.IO` subsections (handled by `/doc-update` after implementation) |
| `docs/architecture/04-runtime-view.md` | Add "Keyboard protocol detection" scenario (handled by `/doc-update`) |

### Files explicitly **not** modified in this feature

- `src/termicap-capabilities.ads` / `src/*/termicap-capabilities.adb` — FUNC-KKB-019 deferred per §K.
- `src/termicap-osc.ads` / `.adb` — no changes; all use goes through the existing `Sentinel_Query` API.
- `src/termicap-tty.ads` / `src/*/termicap-tty.adb` — no changes.
- `alire.toml`, `termicap.gpr` — no new external dependencies.

---

## Q. Requirements Traceability

| Requirement | Design element | Section |
|-------------|---------------|---------|
| FUNC-KKB-001 | `Keyboard_Protocol` enum in `Termicap.Keyboard` spec | E |
| FUNC-KKB-002 | `Kitty_Flags` record with five Boolean bit fields | E |
| FUNC-KKB-003 | `Keyboard_Capability` record + `NO_KEYBOARD_CAPABILITY` constant | E |
| FUNC-KKB-004 | `CSI_KITTY_QUERY` constant + Kitty probe step 4 | E, F |
| FUNC-KKB-005 | `Parse_Kitty_Flags` pure function (SPARK On) | G |
| FUNC-KKB-006 | `Parse_Kitty_Response` pure function (SPARK On) | G |
| FUNC-KKB-007 | `CSI_XTERM_KBD_QUERY` constant + XTerm probe step 5 | E, F |
| FUNC-KKB-008 | `Parse_XTerm_Keyboard_Response` pure function (SPARK On) | G |
| FUNC-KKB-009 | Cascade in `Detect_Keyboard_Protocol` | F |
| FUNC-KKB-010 | Win32 gate in Windows body (`GetConsoleMode`) | F, J |
| FUNC-KKB-011 | TTY guard (step 2) + foreground guard via `Probe_Session.Open` | F |
| FUNC-KKB-012 | All I/O routed through `Termicap.OSC.Probe_Session` / `Sentinel_Query` | H |
| FUNC-KKB-013 | `KITTY_PROBE_TIMEOUT_MS = XTERM_KBD_PROBE_TIMEOUT_MS = 1000`; per-probe reset | E, H |
| FUNC-KKB-014 | Per-call outer `when others` handler + OSC-level error handling | H |
| FUNC-KKB-015 | `Probe_Session` RAII guarantees termios restore | H |
| FUNC-KKB-016 | Parsers return negative on garbled input; `Sentinel_Query` drains to DA1 | G, H |
| FUNC-KKB-017 | Protected-object cache + `Probe_Keyboard_Protocol` bypass function | I |
| FUNC-KKB-018 | Package split `Termicap.Keyboard` (SPARK On) + `.IO` child; platform bodies | D |
| FUNC-KKB-019 | **Deferred** per §K; migration path documented | K |

---

## R. Related Documents

- **Tech Spec XTVERSION** (`docs/tech-specs/xtversion.md`) — Structural peer: active-probe classification with SPARK parsing + FFI I/O split
- **Tech Spec DA1** (`docs/tech-specs/da1-response-parsing.md`) — Parent feature: DA1 sentinel mechanics used by `Sentinel_Query`
- **Tech Spec OSC-INFRA** (`docs/tech-specs/osc-query-infra.md`) — `Probe_Session` and `Sentinel_Query` primitives reused here
- **Tech Spec CYGWIN** (`docs/tech-specs/cygwin-pty.md`) — Windows Cygwin detection; underpins the Cygwin fall-through on the Windows Keyboard body
- **Tech Spec Capability Record** (`docs/tech-specs/capability-record.md`) — Integration target for FUNC-KKB-019
- **ADR-0013** (`docs/adr/0013-spark-annotation-split-capabilities.md`) — Mixed SPARK_Mode pattern used for the parser bodies
- **ADR-0015** (`docs/adr/0015-probe-session-limited-controlled.md`) — Why `Probe_Session` is `Limited_Controlled` (justifies termios-restore-for-free)
- **ADR-0017** (`docs/adr/0017-da1-timeout-only-read-loop.md`) — Why DA1 query uses `Timeout_Query` not `Sentinel_Query` (contrast with this feature, which uses `Sentinel_Query`)
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`) — Platform-specific body selection via GPR source dirs
- **Requirements** (`docs/requirements/kitty-keyboard.sdoc`) — FUNC-KKB-001 through FUNC-KKB-019
- **Reference** (`reference-frameworks/tcell/tscreen.go` lines 124–129) — Canonical query constants
- **Reference** (`reference-frameworks/crossterm/src/terminal/sys/unix.rs` lines 213–267) — Kitty-probe-with-DA1-sentinel pattern in Rust
- **Analysis** (`reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` §2.7) — Cross-language keyboard input synthesis
