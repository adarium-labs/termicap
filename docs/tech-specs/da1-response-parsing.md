# Technical Specification: DA1 Primary Device Attributes Response Parsing

**Feature:** DA1 (Primary Device Attributes) Response Parsing
**Requirements:** `docs/requirements/functional/da1.sdoc` (FUNC-DA1-001 through FUNC-DA1-015)
**Date:** 2026-04-06

---

## 1. Overview

The DA1 feature delivers semantic interpretation of Primary Device Attributes responses. When a terminal receives the CSI c query (ESC [ c), it responds with ESC [ ? Ps ; Ps ; ... c, where the first Ps value encodes the VT conformance level (VT200=62, VT300=63, VT400=64, VT500=65) and subsequent Ps values advertise specific hardware capabilities (Sixel graphics=4, ANSI colour=22, rectangular editing=28, etc.).

This feature builds on top of the existing DA1 parsing infrastructure in `Termicap.OSC.Parsing` (which already provides `Parse_DA1_Response`, `Contains_DA1_Response`, and the `DA1_Params` record type) by adding:

- **Capability type system** -- `DA1_Capability` enumeration, `VT_Level` enumeration, `Capability_Flags` array, and `DA1_Capabilities` record (FUNC-DA1-001 through FUNC-DA1-003)
- **Interpretation functions** -- `Interpret_DA1`, `Has_Capability`, `VT_Level_Of` as pure SPARK Silver functions (FUNC-DA1-004 through FUNC-DA1-006)
- **Query constant** -- `DA1_QUERY` byte-array constant for the CSI c sequence (FUNC-DA1-007)
- **I/O procedure** -- `Query_DA1` using a timeout-only read loop (FUNC-DA1-008)
- **Convenience function** -- `Detect_DA1` combining I/O, parsing, and interpretation (FUNC-DA1-009)
- **Integration** -- `DA1_Capabilities` field in `Terminal_Capabilities` (FUNC-DA1-015)

This is a Layer 6 identification method per the global synthesis taxonomy (`reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` lines 398--414), providing hardware-level capability advertisements directly from the terminal emulator.

**Dependencies on existing features:**

- `Termicap.OSC.Parsing` -- `DA1_Params`, `DA1_Value_Array`, `Parse_DA1_Response`, `Contains_DA1_Response`, `Wrap_For_Passthrough`, `Passthrough_Mode` (Tier 3, SPARK Silver)
- `Termicap.OSC` -- `Probe_Session`, `Timed_Read`, `Write_Query`, `Byte`, `Byte_Array`, `Response_Buffer`, `MAX_RESPONSE_SIZE` (Tier 3, SPARK Off)
- `Termicap.Terminal_Id` -- `Terminal_Identity`, `Detect_Terminal_Identity` for multiplexer detection (Tier 2)
- `Termicap.Environment` / `Termicap.Environment.Capture` -- environment snapshot for terminal identity detection (Tier 1)
- `Termicap.Capabilities` -- `Terminal_Capabilities` record to extend (Tier 4)

---

## 2. Framework Survey

### notcurses (C)

notcurses provides the most comprehensive DA1 handling among the reference frameworks.

1. **Query constant:** `#define PRIDEVATTR "\x1b[c"` in `src/lib/termdesc.c`. Sent as the last item in a batched identification query string (`DIRECTIVES`), interleaved with XTVERSION, DA2, DA3, and XTGETTCAP. All known terminals respond to DA1, so it serves as both a capability query and a universal "end of queries" sentinel.

2. **Response parsing:** In `src/lib/in.c`, the `da1_attrs_cb` function handles the DA1 response via the automaton input parser:
   ```c
   unsigned val = amata_next_numeric(&ictx->amata, "\x1b[?", ';');
   char* attrlist = amata_next_kleene(&ictx->amata, "", 'c');
   ```
   The first numeric parameter is the conformance class. The attribute list is then scanned character-by-character, accumulating decimal digits and dispatching on semicolons:
   - `curattr == 4` -> Sixel graphics (sets `foundsixel = 1`, defaults colour registers to 256)
   - `curattr == 28` -> rectangular editing (`rectangular_edits = true`)

3. **Sixel cross-validation:** If DA1 does not advertise Sixel (Ps=4), notcurses calls `scrub_sixel_responses` to discard any XTSMGRAPHICS geometry responses, preventing false Sixel activation. This is a defence-in-depth pattern.

4. **Terminal-specific DA1 callbacks:** notcurses has separate callbacks for different DA1 response formats:
   - `da1_cb` -- generic DA1 without attribute parsing (scrubs Sixel)
   - `da1_vt102_cb` -- VT102-style DA1 (CSI ? 6 c, no semicolons)
   - `da1_syncterm_cb` -- SyncTERM-specific handling
   - `da1_attrs_cb` -- full attribute parsing with Sixel and rectangular editing extraction

5. **Comment on universality:** "All known terminals respond to DA1" (`termdesc.c` line 339). This makes DA1 the most reliable active query.

### tcell (Go)

tcell parses DA1 responses in `input.go`:

1. **eventPrimaryAttributes struct:** A struct with named Boolean fields for each recognised Ps value:
   ```go
   type eventPrimaryAttributes struct {
       Class     int   // Terminal class (first Ps value)
       ReGIS     bool  // DA 3
       Sixel     bool  // DA 4
       National  bool  // DA 9
       Color     bool  // DA 22
       Greek     bool  // DA 23
       Turkish   bool  // DA 24
       Latin2    bool  // DA 42
       Clipboard bool  // DA 52
   }
   ```
   
2. **Ps value dispatch:** A switch statement maps each Ps value to its corresponding Boolean field. Unrecognised values are silently ignored.

3. **Comment on sentinel role:** "eventPrimaryAttributes is for primary device attributes -- this should be the last event returned during initial handshaking" (`input.go` line 1169). This confirms DA1's dual role as both capability query and handshake terminator.

4. **Extended attribute set:** tcell recognises more Ps values than the Termicap enumeration (National=9, SerboCroation=12, Greek=23, Turkish=24, Latin2=42, Clipboard=52). These are character-set and protocol extensions with limited relevance for modern capability detection; Termicap's curated subset (FUNC-DA1-001) omits them deliberately.

### crossterm (Rust)

crossterm recognises DA1 responses in `src/event/sys/unix/parse.rs`:

1. **Stub parser:** `parse_csi_primary_device_attributes` asserts the ESC [ ? prefix and 'c' suffix but does not parse individual Ps values:
   ```rust
   // This is a stub for parsing the primary device attributes.
   // This response is not exposed in the crossterm API so we don't
   // need to parse the individual attributes yet.
   Ok(Some(InternalEvent::PrimaryDeviceAttributes))
   ```

2. **Sentinel use:** crossterm uses DA1 as a sentinel for other queries (keyboard enhancement flags, Kitty protocol detection), similar to Termicap's Sentinel_Query pattern.

### Key differences for Termicap

| Aspect | notcurses (C) | tcell (Go) | crossterm (Rust) | Termicap (Ada) |
|--------|--------------|------------|------------------|----------------|
| Query form | `\x1b[c` (batched) | `\x1b[c` | `\x1b[c` | `\x1b[c` (standalone) |
| Read loop | Automaton-based | Event loop | Event loop | Timeout-only (ADR-0017) |
| Ps extraction | Manual digit accumulation | Switch on parsed ints | Stub (not parsed) | Reuse `Parse_DA1_Response` |
| Ps values tracked | 4, 28 | 3, 4, 9, 12, 22, 23, 24, 42, 52 | None | 2, 3, 4, 6, 8, 18, 22, 28 |
| VT level decoding | Implicit (callback selection) | `Class` int field | Not extracted | `VT_Level` enumeration |
| Sixel cross-validation | Yes (scrub_sixel_responses) | No | No | Not in v1 (future) |
| SPARK provability | N/A | N/A | N/A | Silver for interpretation |
| Result type | C struct fields | Go struct | Opaque event | `DA1_Capabilities` record |

### Patterns borrowed

| Pattern | Source | Adaptation |
|---------|--------|------------|
| Boolean flags indexed by capability | tcell `eventPrimaryAttributes` | `Capability_Flags` array indexed by `DA1_Capability` enum |
| Unrecognised Ps values silently ignored | notcurses `da1_attrs_cb`, tcell switch | Same in `Interpret_DA1` step 4 |
| DA1 as universal handshake terminator | notcurses "all known terminals respond to DA1", tcell "last event returned" | Informs timeout-only approach (ADR-0017) |
| Conformance class as first parameter | DEC VT documentation, notcurses `val` | `VT_Level_Of` function (FUNC-DA1-006) |

---

## 3. Package Architecture

### Package tree

```
Termicap                                  (existing root namespace)
├── Termicap.DA1                          [SPARK_Mode => On]  -- types, constants, interpretation
│   └── Termicap.DA1.IO                  [SPARK_Mode => Off] -- Query_DA1, Detect_DA1
```

### SPARK boundary rationale

| Package | SPARK_Mode | Reason |
|---------|------------|--------|
| `Termicap.DA1` | On | Pure types (`DA1_Capability`, `VT_Level`, `DA1_Capabilities`, `Capability_Flags`), the `DA1_QUERY` constant, and three pure interpretation functions (`Interpret_DA1`, `Has_Capability`, `VT_Level_Of`). No FFI, no controlled types, no global state. All functions carry Silver-level contracts with `Global => null`. Depends on `Termicap.OSC.Parsing` for `DA1_Params` and `DA1_Value_Array` types, which are declared in a SPARK On package. |
| `Termicap.DA1.IO` | Off | Calls `Termicap.OSC.Probe_Session` (controlled type), `Write_Query`, `Timed_Read`, and `Contains_DA1_Response`. Accesses `Termicap.Terminal_Id` for multiplexer detection. Performs terminal I/O. |

### SPARK dependency note

`Termicap.DA1` (SPARK On) depends on `Termicap.OSC.Parsing` (SPARK On) for the `DA1_Params` and `DA1_Value_Array` types. This is a clean SPARK-to-SPARK dependency. Unlike `Termicap.XTVERSION` and `Termicap.Color.BG_Query`, which re-declare compatible `Byte`/`Byte_Array` types to avoid depending on the SPARK Off `Termicap.OSC` package, `Termicap.DA1` does not need its own `Byte`/`Byte_Array` because its pure functions operate on `DA1_Params` records rather than raw byte buffers. The byte-level parsing is already handled by `Parse_DA1_Response` in `Termicap.OSC.Parsing`.

### No new C source file

All terminal I/O is performed through the existing `Termicap.OSC.Probe_Session`, `Write_Query`, and `Timed_Read` infrastructure. The DA1 feature adds no new system calls, no new C wrappers, and no new FFI bindings.

### File layout

| File | Purpose |
|------|---------|
| `src/termicap-da1.ads` | `DA1_Capability`, `VT_Level`, `Capability_Flags`, `DA1_Capabilities`, `DA1_QUERY` constant, `Interpret_DA1`, `Has_Capability`, `VT_Level_Of` function specs |
| `src/termicap-da1.adb` | `Interpret_DA1` function body |
| `src/termicap-da1-io.ads` | `Query_DA1` procedure spec, `Detect_DA1` function spec |
| `src/termicap-da1-io.adb` | `Query_DA1` body: probe session + timeout-only read loop; `Detect_DA1` body |

---

## 4. Type Design

All types in this section are declared in `Termicap.DA1` (SPARK_Mode => On).

### DA1_Capability (FUNC-DA1-001)

```ada
type DA1_Capability is
  (Printer,             --  Ps = 2:  Printer port
   ReGIS_Graphics,      --  Ps = 3:  ReGIS graphics
   Sixel_Graphics,      --  Ps = 4:  Sixel graphics
   Selective_Erase,     --  Ps = 6:  Selective erase
   User_Defined_Keys,   --  Ps = 8:  User-defined keys (UDK)
   Windowing,           --  Ps = 18: Windowing capability
   ANSI_Color,          --  Ps = 22: ANSI colour (VT525)
   Rectangular_Editing);  --  Ps = 28: Rectangular editing
```

Curated subset of xterm DA1 Ps values with practical relevance for terminal capability detection. Follows Mixed_Case naming per Ada enumeration convention. Callers needing raw parameter inspection can use `DA1_Params.Values` directly via `Parse_DA1_Response` (FUNC-OSC-010).

### VT_Level (FUNC-DA1-002)

```ada
type VT_Level is
  (Unknown,   --  No DA1 response, or first Ps unrecognised
   VT100,     --  Ps = 1 (reserved; no modern terminal sends this)
   VT200,     --  Ps = 62
   VT300,     --  Ps = 63
   VT400,     --  Ps = 64
   VT500);    --  Ps = 65
```

Ordering places `Unknown` first so that default-initialized records have `Unknown` as their `VT_Level`. The `VT100` literal is reserved for completeness but never assigned by `Interpret_DA1`.

### Capability_Flags (FUNC-DA1-003)

```ada
type Capability_Flags is
  array (DA1_Capability) of Boolean;
```

Boolean array indexed by `DA1_Capability`. Provides O(1) access to any individual capability flag. Default aggregate `[others => False]` ensures future enumeration additions default to False.

### DA1_Capabilities (FUNC-DA1-003)

```ada
type DA1_Capabilities is record
   Supported : Boolean          := False;
   Level     : VT_Level         := Unknown;
   Flags     : Capability_Flags := [others => False];
end record;
```

Plain (non-discriminated) record. `Supported` acts as a semantic guard: when False, `Level` is `Unknown` and all `Flags` are False. This is enforced by convention and by the `Interpret_DA1` postcondition, not by a discriminant, to avoid the syntactic overhead of variant components where none are needed.

### DA1_QUERY (FUNC-DA1-007)

```ada
DA1_QUERY : constant Byte_Array :=
  [16#1B#,   --  ESC
   16#5B#,   --  [   (CSI introducer)
   16#63#];  --  c   (Primary Device Attributes)
```

Three-byte constant encoding ESC [ c. Defined in the SPARK On package so it can be referenced by both the I/O layer and test code. Note: this is the same byte sequence used as the DA1 sentinel in `Sentinel_Query`, but semantically distinct -- here it is the primary query, not a boundary marker (see FUNC-DA1-007 comment).

The `Byte_Array` type used here is the one from `Termicap.OSC.Parsing` (inherited from `Termicap.OSC`). Since `Termicap.DA1` needs to reference `DA1_Params` from `Termicap.OSC.Parsing` (which is SPARK On), the `Byte_Array` type is already transitively available.

---

## 5. Algorithm: Interpret_DA1 (FUNC-DA1-004)

**Input:** `Params : DA1_Params` -- parsed DA1 response from `Parse_DA1_Response`.
**Output:** `DA1_Capabilities` -- structured interpretation with VT level and capability flags.

```
1. If Params.Count = 0:
      return DA1_Capabilities'(Supported => False,
                                Level     => Unknown,
                                Flags     => [others => False])

2. Set Supported := True

3. Decode first parameter as VT conformance level:
      Level := (case Params.Values(1) is
                   when 62 => VT200,
                   when 63 => VT300,
                   when 64 => VT400,
                   when 65 => VT500,
                   when others => Unknown)

4. Initialize Flags := [others => False]

5. For I in 2 .. Params.Count:
      V := Params.Values(I)
      case V is
         when  2 => Flags(Printer)             := True
         when  3 => Flags(ReGIS_Graphics)      := True
         when  4 => Flags(Sixel_Graphics)      := True
         when  6 => Flags(Selective_Erase)      := True
         when  8 => Flags(User_Defined_Keys)   := True
         when 18 => Flags(Windowing)            := True
         when 22 => Flags(ANSI_Color)           := True
         when 28 => Flags(Rectangular_Editing)  := True
         when others => null  -- silently ignored

6. return DA1_Capabilities'(Supported => True,
                             Level     => Level,
                             Flags     => Flags)
```

**Loop bound:** The for loop iterates at most `MAX_DA1_PARAMS - 1` times (15 iterations). `Params.Count <= MAX_DA1_PARAMS` is guaranteed by the postcondition of `Parse_DA1_Response` (FUNC-OSC-010). The SPARK prover can discharge all index obligations at Silver level.

**Unknown Ps values:** Step 5 silently ignores unrecognised Ps values. This is intentional for forward compatibility: terminals may advertise vendor-specific or future-standard capabilities. notcurses and tcell both follow this pattern.

### Has_Capability (FUNC-DA1-005)

```ada
function Has_Capability
  (Caps : DA1_Capabilities; Cap : DA1_Capability) return Boolean is
  (Caps.Supported and then Caps.Flags (Cap));
```

Expression function. Short-circuit evaluation ensures False when `Supported` is False. Postcondition is trivially discharged by the SPARK prover.

### VT_Level_Of (FUNC-DA1-006)

```ada
function VT_Level_Of
  (Caps : DA1_Capabilities) return VT_Level is
  (Caps.Level);
```

Expression function. Postcondition `(if not Caps.Supported then Result = Unknown)` is provable because `Interpret_DA1` guarantees that `not Supported` implies `Level = Unknown`.

---

## 6. Algorithm: Query_DA1 (FUNC-DA1-008)

**Input:** `Timeout_Ms : Natural`.
**Output:** `Response : Byte_Array`, `Resp_Length : Natural`, `Timed_Out : Boolean`.

**Critical design decision:** Query_DA1 cannot use `Sentinel_Query` because the DA1 response IS the data being sought. Appending a second CSI c would produce two overlapping DA1 responses, making boundary detection ambiguous. See ADR-0017 for the full decision record.

```
 1. -- Determine multiplexer passthrough
    Env := Capture environment snapshot
    Identity := Detect_Terminal_Identity (Env)
    Passthrough :=
       (if Identity.Is_Multiplexer and then Identity.Kind = Tmux
        then Tmux_Passthrough
        elsif Identity.Is_Multiplexer and then Identity.Kind = Screen
        then Screen_Passthrough
        elsif Identity.Is_Multiplexer
        then Tmux_Passthrough   -- safe default for unknown multiplexers
        else No_Passthrough)

 2. Query_Bytes := Wrap_For_Passthrough (DA1_QUERY, Passthrough)

 3. -- Open probe session
    declare
       Session : Probe_Session;
       Status  : Session_Status;
    begin
       Open (Session, Status);
       if Status /= Session_OK then
          -- Covers: Session_Not_Foreground (FUNC-DA1-010),
          --         Session_No_Terminal     (FUNC-DA1-011),
          --         Session_Save_Failed, Session_Raw_Failed,
          --         Session_Already_Active
          Timed_Out := True;
          Resp_Length := 0;
          Response := [others => 0];
          return;
       end if;

 4.    -- Write DA1 query to terminal
       Write_Query (Session, Query_Bytes, Written, Write_OK);
       if not Write_OK then
          Timed_Out := True;
          Resp_Length := 0;
          Response := [others => 0];
          return;
       end if;

 5.    -- Timeout-only read loop
       Accumulated := 0;
       Start_Time := Clock;  -- monotonic timestamp
       loop
          Remaining_Ms := Timeout_Ms - Elapsed_Ms (Start_Time);
          exit when Remaining_Ms <= 0;

          Timed_Read
            (FD         => Session.FD,
             Buffer     => Chunk_Buffer,
             Bytes_Read => Chunk_Len,
             Timeout_Ms => Remaining_Ms,
             Timed_Out  => Read_Timed_Out);

          -- Append chunk to accumulation buffer
          for I in 1 .. Chunk_Len loop
             exit when Accumulated >= MAX_RESPONSE_SIZE;
             Accumulated := Accumulated + 1;
             Accum_Buffer(Accumulated) := Chunk_Buffer(I);
          end loop;

          -- Check for complete DA1 response
          if Contains_DA1_Response (Accum_Buffer, Accumulated) then
             -- DA1 response detected
             Resp_Length := Accumulated;
             Response(1 .. Accumulated) := Accum_Buffer(1 .. Accumulated);
             Timed_Out := False;
             return;  -- Session closes via Finalize
          end if;

          exit when Read_Timed_Out;
          exit when Accumulated >= MAX_RESPONSE_SIZE;
       end loop;

 6.    -- Timeout: no complete DA1 response detected
       Timed_Out := True;
       Resp_Length := 0;

 7.    -- Session closes automatically via Finalize (RAII)
    end;
```

**Key differences from Sentinel_Query:**

| Aspect | Sentinel_Query | Query_DA1 |
|--------|---------------|-----------|
| Query sent | User query + DA1 sentinel | DA1 query only |
| Exit condition | `Contains_DA1_Response` (sentinel) | `Contains_DA1_Response` (the actual response) |
| Response extraction | Pre-sentinel bytes only | All accumulated bytes |
| Retry support | Optional (Retry parameter) | None (single attempt) |

**Safety guards inherited from Probe_Session:**
- Foreground process group check (FUNC-DA1-010): `Open` returns `Session_Not_Foreground`
- Not-a-TTY guard (FUNC-DA1-011): `Open` returns `Session_No_Terminal`
- Multiplexer passthrough (FUNC-DA1-012): wrapping applied in step 2

**Buffer overflow protection:** The loop exits if `Accumulated >= MAX_RESPONSE_SIZE` (4096 bytes). This is far larger than any known DA1 response (~15 bytes for a typical VT200+Sixel response).

### Timing implementation note

The elapsed-time calculation requires a monotonic clock. The I/O package (SPARK Off) can use `Ada.Real_Time.Clock` or the `select()` timeout mechanism already used by `Timed_Read`. The implementation may simplify the timing by passing decreasing `Timeout_Ms` values to successive `Timed_Read` calls, using `Timed_Read`'s built-in select() timeout as the wall-clock governor.

---

## 7. Algorithm: Detect_DA1 (FUNC-DA1-009)

**Input:** `Timeout_Ms : Natural := 100`.
**Output:** `DA1_Capabilities`.

```
1. Declare Response : Response_Buffer
   Declare Resp_Length : Natural
   Declare Timed_Out : Boolean

2. Query_DA1
     (Timeout_Ms  => Timeout_Ms,
      Response    => Response,
      Resp_Length => Resp_Length,
      Timed_Out   => Timed_Out)

3. If Timed_Out then
      return DA1_Capabilities'(Supported => False,
                                Level     => Unknown,
                                Flags     => [others => False])

4. Params := Parse_DA1_Response (Response, Resp_Length)

5. return Interpret_DA1 (Params)
```

Default `Timeout_Ms` is 100, consistent with `Query_And_Identify` (FUNC-XTV-013). This function is in `Termicap.DA1.IO` (SPARK Off).

---

## 8. Integration with Terminal_Capabilities (FUNC-DA1-015)

### Terminal_Capabilities record extension

The `Terminal_Capabilities` record in `src/termicap-capabilities.ads` is extended with a DA1 field:

```ada
type Terminal_Capabilities is record
   TTY_Stdin              : Boolean;
   TTY_Stdout             : Boolean;
   TTY_Stderr             : Boolean;
   Color                  : Termicap.Color.Color_Level;
   Size                   : Termicap.Dimensions.Terminal_Size;
   Unicode                : Termicap.Unicode.Unicode_Level;
   Identity               : Termicap.Terminal_Id.Terminal_Identity;
   Downsampling_Available : Boolean;
   DA1                    : Termicap.DA1.DA1_Capabilities;  --  NEW
end record;
```

### Assemble function extension

The `Assemble` function gains a `DA1` parameter:

```ada
function Assemble
  (TTY_Stdin  : Boolean;
   TTY_Stdout : Boolean;
   TTY_Stderr : Boolean;
   Color      : Termicap.Color.Color_Level;
   Size       : Termicap.Dimensions.Terminal_Size;
   Unicode    : Termicap.Unicode.Unicode_Level;
   Identity   : Termicap.Terminal_Id.Terminal_Identity;
   DA1        : Termicap.DA1.DA1_Capabilities)
   return Terminal_Capabilities
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    Assemble'Result.Downsampling_Available
    = (Assemble'Result.Color >= Termicap.Color.Extended_256);
```

The `Downsampling_Available` postcondition is unchanged; the DA1 field does not affect its derivation.

### Detect function extension

The `Detect` function in `src/termicap-capabilities.adb` adds a DA1 detection step after the existing sub-detectors:

```
-- Existing steps 1-6: Env, Id, TTY, Color, Size, Unicode

-- Step 7: Detect DA1 capabilities (active probe)
DA1_Caps := Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => 100);

-- Step 8: Assemble with DA1 field
return Assemble (..., DA1 => DA1_Caps);
```

DA1 detection is placed after all passive detectors because it requires opening a `Probe_Session` (terminal I/O). If the session cannot be opened (non-interactive context), `Detect_DA1` returns `DA1_Capabilities` with `Supported = False`, which is set in the record without affecting other fields.

### Ordering consideration

The DA1 query requires an open `Probe_Session`. The existing detection sequence in `Capabilities.Detect` runs all passive detectors first (environment capture, terminal identity, TTY status, colour level, dimensions, Unicode). The DA1 query is the first active probe added to the `Detect` function. If XTVERSION were also added in the future, the two active probes should share a single `Probe_Session` to avoid the overhead of two open/raw-mode/close cycles. For v1, `Detect_DA1` manages its own session internally.

---

## 9. SPARK Contracts and Provability

### SPARK Silver targets

| Package | Subprogram | Proof level | Key obligations |
|---------|-----------|-------------|-----------------|
| `Termicap.DA1` | `Interpret_DA1` | Silver | Loop bound by `MAX_DA1_PARAMS`, array index within `Values(1..Count)`, postcondition: Count=0 implies not Supported |
| `Termicap.DA1` | `Has_Capability` | Silver | Expression function: trivial rewrite of postcondition |
| `Termicap.DA1` | `VT_Level_Of` | Silver | Expression function: trivial; `not Supported => Level = Unknown` provable from Interpret_DA1 construction |

All functions carry `Global => null` contracts. No dynamic allocation, no OS calls, and no unbounded loops appear in the package body. All loops are bounded by `Params.Count <= MAX_DA1_PARAMS` (16).

### Interpret_DA1 contract (FUNC-DA1-004)

```ada
function Interpret_DA1
  (Params : Termicap.OSC.Parsing.DA1_Params) return DA1_Capabilities
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    (if Params.Count = 0
     then not Interpret_DA1'Result.Supported
            and then Interpret_DA1'Result.Level = Unknown)
    and then
    (if Params.Count > 0
     then Interpret_DA1'Result.Supported);
```

The postcondition has two clauses:
1. `Count = 0` implies `Supported = False` and `Level = Unknown` -- follows from step 1 of the algorithm.
2. `Count > 0` implies `Supported = True` -- follows from step 2.

Both are dischargeable at Silver level by GNATprove through direct inspection of the two branches.

### Has_Capability contract (FUNC-DA1-005)

```ada
function Has_Capability
  (Caps : DA1_Capabilities; Cap : DA1_Capability) return Boolean
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    Has_Capability'Result = (Caps.Supported and then Caps.Flags (Cap));
```

### VT_Level_Of contract (FUNC-DA1-006)

```ada
function VT_Level_Of
  (Caps : DA1_Capabilities) return VT_Level
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    VT_Level_Of'Result = Caps.Level
    and then (if not Caps.Supported
              then VT_Level_Of'Result = Unknown);
```

### Ada FFI boundary

| Package | Subprogram | Reason for SPARK Off |
|---------|-----------|---------------------|
| `Termicap.DA1.IO` | `Query_DA1` | Calls `Probe_Session` (controlled type), `Write_Query` (I/O), `Timed_Read` (I/O), `Contains_DA1_Response`, `Detect_Terminal_Identity` (env capture) |
| `Termicap.DA1.IO` | `Detect_DA1` | Calls `Query_DA1` (I/O), `Parse_DA1_Response`, and `Interpret_DA1` |

### Query_DA1 contract (FUNC-DA1-008)

```ada
procedure Query_DA1
  (Timeout_Ms  :     Natural;
   Response    : out Byte_Array;
   Resp_Length : out Natural;
   Timed_Out   : out Boolean)
with Pre => Response'Length >= MAX_RESPONSE_SIZE;
```

### Detect_DA1 contract (FUNC-DA1-009)

```ada
function Detect_DA1
  (Timeout_Ms : Natural := 100) return DA1_Capabilities;
```

---

## 10. Test Strategy (FUNC-DA1-014)

All tests use programmatically constructed `DA1_Params` values and do not require a live terminal. Tests are located in `tests/src/` and integrated into the existing Termicap test runner.

### Test cases

| # | Description | Input | Expected | Requirement |
|---|------------|-------|----------|-------------|
| 1 | Empty params | Count=0 | Supported=False, Level=Unknown, all Flags=False | FUNC-DA1-004, FUNC-DA1-014 |
| 2 | Single-param VT200 | Count=1, Values(1)=62 | Supported=True, Level=VT200, all Flags=False | FUNC-DA1-004, FUNC-DA1-014 |
| 3 | VT200 + Sixel | Count=2, Values=[62,4] | Level=VT200, Flags(Sixel_Graphics)=True, others False | FUNC-DA1-004, FUNC-DA1-014 |
| 4 | VT400 + multiple | Count=4, Values=[64,4,22,28] | Level=VT400, Sixel=True, ANSI_Color=True, Rect_Edit=True, Printer=False | FUNC-DA1-004, FUNC-DA1-014 |
| 5 | Unknown first param | Count=1, Values(1)=99 | Supported=True, Level=Unknown | FUNC-DA1-004, FUNC-DA1-014 |
| 6 | VT500 + unrecognised Ps | Count=3, Values=[65,100,200] | Level=VT500, all Flags=False | FUNC-DA1-004, FUNC-DA1-014 |
| 7 | Has_Capability unsupported | Supported=False | Has_Capability(_, any Cap) = False | FUNC-DA1-005, FUNC-DA1-014 |
| 8 | Has_Capability Sixel | VT200+Sixel result | Has_Capability(_, Sixel_Graphics) = True | FUNC-DA1-005, FUNC-DA1-014 |
| 9 | VT_Level_Of unsupported | Supported=False | VT_Level_Of = Unknown | FUNC-DA1-006, FUNC-DA1-014 |
| 10 | VT_Level_Of VT400 | VT400 result | VT_Level_Of = VT400 | FUNC-DA1-006, FUNC-DA1-014 |
| 11 | Max params | Count=MAX_DA1_PARAMS, all recognised values | No constraint error, all applicable flags set | FUNC-DA1-004, FUNC-DA1-014 |

### Edge cases to verify

- **Duplicate Ps values:** Values=[62, 4, 4] -- Sixel_Graphics set once, no error.
- **First param as capability value:** Values=[4] -- Level=Unknown (4 is not a valid VT class), Supported=True. The first parameter is always interpreted as the conformance class, not as a capability flag.
- **All eight capabilities present:** Values=[62, 2, 3, 4, 6, 8, 18, 22, 28] -- all eight Flags set to True.

---

## 11. Risk Assessment

### Risk 1: DA1 response not terminated by 'c'

**Risk:** Some obscure terminals might send a malformed DA1 response where the terminating byte is not 0x63 ('c').

**Mitigation:** `Contains_DA1_Response` (FUNC-OSC-006) specifically checks for the 0x63 terminator as part of the pattern `ESC [ ? <digits/semicolons> c`. Malformed responses will not be detected, and `Query_DA1` will time out. This is the correct behaviour: treating malformed data as "no response" is safer than attempting partial interpretation.

**Likelihood:** Very low. DEC defined the DA1 response format in the VT220 era, and all modern terminal emulators follow it precisely.

### Risk 2: Timeout latency in non-interactive contexts

**Risk:** When running in CI or as a daemon, `Query_DA1` will wait the full `Timeout_Ms` (100 ms default) before returning, because no terminal responds.

**Mitigation:** The not-a-TTY guard (FUNC-DA1-011) short-circuits the query when `/dev/tty` cannot be opened, returning immediately with `Timed_Out := True`. This covers the vast majority of non-interactive contexts. The timeout penalty only occurs when `/dev/tty` exists but the terminal does not respond to DA1, which is extremely rare.

### Risk 3: Multiplexer intercepting DA1

**Risk:** tmux intercepts CSI c and responds on behalf of itself, reporting tmux's own VT level rather than the outer terminal's.

**Mitigation:** Passthrough wrapping (FUNC-DA1-012) sends the DA1 query inside a DCS passthrough envelope, ensuring it reaches the outer terminal. The same mechanism is already proven to work for XTVERSION and background colour queries.

### Risk 4: Probe_Session contention with other active queries

**Risk:** If `Detect_DA1` is called while another probe session is active (e.g., during a concurrent `Query_XTVERSION`), `Probe_Session.Open` returns `Session_Already_Active` and `Query_DA1` returns `Timed_Out := True`.

**Mitigation:** The `Capabilities.Detect` function calls all active probes sequentially, so contention does not occur in the normal path. Direct callers of `Detect_DA1` should be aware of the single-session constraint documented in `Termicap.OSC` (FUNC-OSC-012).

### Risk 5: Future session sharing with XTVERSION

**Risk:** Adding DA1 to `Capabilities.Detect` alongside XTVERSION creates two sequential probe sessions (open/raw/query/restore/close twice). This doubles the terminal setup overhead.

**Mitigation:** For v1, the overhead is acceptable (two 100 ms queries, each with ~1 ms session overhead). A future optimisation could share a single session for both queries. This is documented as a non-breaking enhancement and does not affect the current API.

---

## 12. Dependency Graph

```
┌──────────────────────────────────┐
│    Termicap.DA1.IO               │  SPARK_Mode => Off
│  Query_DA1                       │  (I/O orchestration)
│  Detect_DA1                      │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│    Termicap.DA1                  │  SPARK_Mode => On
│  DA1_Capability, VT_Level,       │  (types + pure interpretation)
│  DA1_Capabilities,               │
│  Capability_Flags, DA1_QUERY,    │
│  Interpret_DA1, Has_Capability,  │
│  VT_Level_Of                     │
└──────┬───────────────────────────┘
       │
       ▼ (types: DA1_Params, DA1_Value_Array)
┌──────────────────────────────────┐
│  Termicap.OSC.Parsing            │  SPARK_Mode => On
│  DA1_Params, DA1_Value_Array,    │  (existing)
│  Parse_DA1_Response,             │
│  Contains_DA1_Response,          │
│  Wrap_For_Passthrough            │
└──────────────────────────────────┘

┌──────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│  Termicap.OSC    │   │ Termicap.Terminal_Id  │   │ Termicap.Environment │
│  Probe_Session   │   │ Terminal_Identity     │   │                      │
│  Write_Query     │   │                       │   │                      │
│  Timed_Read      │   │                       │   │                      │
└──────────────────┘   └──────────────────────┘   └──────────────────────┘
       ▲                        ▲                          ▲
       │                        │                          │
       └────────────────────────┴──────────────────────────┘
                     (used by DA1.IO)

┌──────────────────────┐
│ Termicap.Capabilities│   (extended with DA1 field)
│  Terminal_Capabilities│
│  Detect, Assemble    │
└──────────────────────┘
```

Dependency flow (arrows point from dependent to dependency):

- `Termicap.DA1.IO` depends on `Termicap.DA1`, `Termicap.OSC`, `Termicap.OSC.Parsing`, `Termicap.Terminal_Id`, `Termicap.Environment`
- `Termicap.DA1` depends on `Termicap.OSC.Parsing` (for `DA1_Params`, `DA1_Value_Array` types)
- `Termicap.Capabilities` depends on `Termicap.DA1` (for `DA1_Capabilities` type) and `Termicap.DA1.IO` (for `Detect_DA1`)

No circular dependencies exist. The SPARK boundary is clean: `Termicap.DA1` (SPARK On) depends only on `Termicap.OSC.Parsing` (SPARK On) and `Interfaces.C` (for `Byte` subtype transitively).

---

## 13. Requirement Traceability

| Requirement | Design Element | Package |
|-------------|---------------|---------|
| FUNC-DA1-001 | `DA1_Capability` enumeration (8 literals) | `Termicap.DA1` |
| FUNC-DA1-002 | `VT_Level` enumeration (6 literals, Unknown first) | `Termicap.DA1` |
| FUNC-DA1-003 | `DA1_Capabilities` record, `Capability_Flags` array type | `Termicap.DA1` |
| FUNC-DA1-004 | `Interpret_DA1` function with 2-clause postcondition | `Termicap.DA1` |
| FUNC-DA1-005 | `Has_Capability` expression function | `Termicap.DA1` |
| FUNC-DA1-006 | `VT_Level_Of` expression function | `Termicap.DA1` |
| FUNC-DA1-007 | `DA1_QUERY` constant (`[0x1B, 0x5B, 0x63]`) | `Termicap.DA1` |
| FUNC-DA1-008 | `Query_DA1` procedure with timeout-only read loop (ADR-0017) | `Termicap.DA1.IO` |
| FUNC-DA1-009 | `Detect_DA1` function with `Timeout_Ms : Natural := 100` | `Termicap.DA1.IO` |
| FUNC-DA1-010 | `Probe_Session.Open` returns `Session_Not_Foreground` -> `Timed_Out := True` | `Termicap.DA1.IO` |
| FUNC-DA1-011 | `Probe_Session.Open` returns `Session_No_Terminal` -> `Timed_Out := True` | `Termicap.DA1.IO` |
| FUNC-DA1-012 | `Wrap_For_Passthrough` with `Passthrough_Mode` derived from `Terminal_Identity` | `Termicap.DA1.IO` |
| FUNC-DA1-013 | `pragma SPARK_Mode (On)` on `Termicap.DA1`, `Global => null` on all pure functions | `Termicap.DA1` |
| FUNC-DA1-014 | 11 test cases + edge cases in `tests/src/` | Test suite |
| FUNC-DA1-015 | `DA1 : DA1_Capabilities` field in `Terminal_Capabilities`, `Detect` calls `Detect_DA1` | `Termicap.Capabilities` |

---

## 14. ADR Decisions

### ADR-0017: DA1 Query Uses Timeout-Only Read Loop (No Sentinel)

Filed as `docs/adr/0017-da1-timeout-only-read-loop.md`. This is the primary design decision unique to the DA1 feature: Query_DA1 cannot reuse the Sentinel_Query infrastructure because the DA1 response is both the query result and the sentinel used everywhere else. The timeout-only approach with Contains_DA1_Response as the exit condition is the simplest correct solution, consistent with notcurses and tcell.

### Reused decisions (no new ADR needed)

1. **SPARK boundary split: pure types/interpretation (On) + I/O child (Off)** -- follows the established pattern from `Termicap.XTVERSION` / `Termicap.XTVERSION.IO` and `Termicap.Color.BG_Query` / `Termicap.Color.BG_Query.IO`. Documented in ADR-0013 and ADR-0015.

2. **Plain record with semantic Supported guard rather than discriminated record** -- follows the pattern described in FUNC-DA1-003 comment. The DA1_Capabilities record has no variant components, so a discriminant would add syntactic overhead without adding type safety.

3. **Multiplexer passthrough selection logic** -- identical to XTVERSION (FUNC-XTV-012) and background colour (FUNC-BGC-007). No new decision required.
