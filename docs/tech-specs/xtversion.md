# Technical Specification: Terminal Identification (Active: XTVERSION)

**Feature:** Terminal Identification (Active: XTVERSION)
**Requirements:** `docs/requirements/functional/xtversion.sdoc` (FUNC-XTV-001 through FUNC-XTV-017)
**Date:** 2026-04-06

---

## 1. Overview

The XTVERSION feature delivers active terminal identification via the `CSI > q` escape sequence query, which elicits a `DCS >| <name> <version> ST` response from terminals that implement the xterm XTVERSION extension. This is a Layer 5 identification method (per the global synthesis taxonomy), sitting above the passive environment-variable layers (1--4) and providing authoritative terminal name and version data directly from the terminal emulator itself.

This feature delivers:

- **XTVERSION query constant** -- a named byte-array constant encoding the `ESC [ > q` escape sequence
- **DCS response recognition** -- a pure SPARK function that identifies a valid `DCS >| <payload> ST` envelope in a byte buffer
- **Payload extraction** -- a pure SPARK function that returns the (offset, length) slice of the payload region within a recognised DCS response
- **Name/version tokenisation** -- a pure SPARK function that splits the payload into a terminal name and version string, handling both `name(version)` (xterm, mlterm, foot) and `name version` (tmux, WezTerm, kitty) formats
- **Top-level parse function** -- a pure SPARK function that orchestrates recognition, extraction, and tokenisation into a discriminated `XTVERSION_Result`
- **I/O query procedure** -- an Ada FFI boundary procedure that sends the (optionally multiplexer-wrapped) query via `Probe_Session` and `Sentinel_Query` with DA1 sentinel bounding
- **Convenience function** -- `Query_And_Identify` combining I/O and parsing into a single call with a default 100 ms timeout

**Dependencies on existing features:**

- `Termicap.OSC` -- probe session lifecycle, Sentinel_Query, Byte/Byte_Array types (Tier 3)
- `Termicap.OSC.Parsing` -- Wrap_For_Passthrough for multiplexer passthrough wrapping (Tier 3)
- `Termicap.Terminal_Id` -- Terminal_Identity for multiplexer detection (Tier 2)
- `Termicap.Environment` -- environment variable snapshot for terminal identity detection (Tier 1)

---

## 2. Framework Survey

### tcell (Go)

tcell implements XTVERSION response handling in `vt/emulate.go`:

1. **Response generation (emulator side):** `processExtendedAttributes` responds to XTVERSION queries by emitting `DCS >| <name> <version> ST`:
   ```go
   em.SendRaw(fmt.Appendf(nil, "\x1bP>|%s %s\x1b\\", em.name, em.vers))
   ```
   This confirms the canonical DCS response format: `ESC P > | name SP version ESC \`.

2. **Payload format:** tcell uses the space-separated format (`name version`), consistent with Format A in FUNC-XTV-005.

### WezTerm / termwiz (Rust)

termwiz implements XTVERSION parsing in `termwiz/src/caps/probed.rs`:

1. **XtVersion type:** A newtype wrapper `XtVersion(String)` around the raw payload string.

2. **name_and_version() parser:** Handles both format variants in order:
   - If the string ends with `)`, find `(` and split: `name[0..paren]`, `version[paren+1..len-1]` (Format B)
   - Otherwise, find first space and split: `name[0..space]`, `version[space+1..]` (Format A)
   - Returns `None` if neither delimiter is found.
   
   Test cases confirm: `"WezTerm something"` -> `("WezTerm", "something")`, `"xterm(something)"` -> `("xterm", "something")`, `"something-else"` -> `None`.

3. **Query construction:** Uses `CSI::Device(Box::new(Device::RequestTerminalNameAndVersion))` which encodes to `CSI > q`. The DA1 sentinel (`RequestPrimaryDeviceAttributes`) is sent immediately after.

4. **Multiplexer passthrough:** tmux wrapping uses `ESC P tmux ; ESC <query> ESC \`, matching the Termicap passthrough syntax. A 100 ms sleep is inserted between the tmux-wrapped query and the DA1 sentinel to allow tmux to forward the DCS sequence to the outer terminal.

### notcurses (C)

notcurses implements XTVERSION in `src/lib/termdesc.c` and `src/lib/in.c`:

1. **Query constant:** `#define XTVERSION "\x1b[>0q"` -- uses the `CSI > 0 q` form (with explicit parameter 0). This is functionally equivalent to `CSI > q`.

2. **Response pattern matching:** In `in.c`, the DCS automaton matches `P>|\S` (where `\S` is a string capture) and dispatches to `xtversion_cb`.

3. **xtversion_cb parser:** Extracts the payload string after `ESC P > |`, then iterates over a table of known terminal prefixes:
   ```c
   { .prefix = "xterm(", .suffix = ')', .term = TERMINAL_XTERM },
   { .prefix = "tmux ", .suffix = 0, .term = TERMINAL_TMUX },
   { .prefix = "WezTerm ", .suffix = 0, .term = TERMINAL_WEZTERM },
   { .prefix = "foot(", .suffix = ')', .term = TERMINAL_FOOT },
   { .prefix = "kitty(", .suffix = ')', .term = TERMINAL_KITTY },
   { .prefix = "mlterm(", .suffix = ')', .term = TERMINAL_MLTERM },
   { .prefix = "contour ", .suffix = 0, .term = TERMINAL_CONTOUR },
   { .prefix = "mintty ", .suffix = 0, .term = TERMINAL_MINTTY },
   ```
   The `extract_xtversion` helper strips the suffix character (if any) from the version string and stores it via `strndup`.

4. **Batched queries:** notcurses sends XTVERSION as part of a batched identification query string (`IDQUERIES`), interleaving it with DA2, DA3, and XTGETTCAP. This is a future optimisation opportunity for Termicap but not in scope for v1.

### Key differences for Termicap

| Aspect | tcell (Go) | WezTerm (Rust) | notcurses (C) | Termicap (Ada) |
|--------|------------|-----------------|---------------|----------------|
| Query form | `CSI > q` | `CSI > q` | `CSI > 0 q` | `CSI > q` (4 bytes) |
| Sentinel | N/A (emulator) | DA1 | DA1 (batched) | DA1 (single query) |
| Payload parsing | Space-separated only | Both formats | Prefix table lookup | Both formats (generic) |
| Name/version split | N/A | Generic 2-format | Per-terminal table | Generic 2-format |
| SPARK provability | N/A | N/A | N/A | Silver for all parsing |
| Result type | N/A | `Result<XtVersion>` | C enum + strdup | Discriminated record |

### Patterns borrowed

| Pattern | Source | Adaptation |
|---------|--------|------------|
| Two-format name/version split: `name(version)` and `name version` | WezTerm `name_and_version()` | Pure SPARK function `Split_XTV_Payload` |
| Check `)` first, then fall back to space | WezTerm | Same priority order in FUNC-XTV-005 |
| DA1 sentinel after XTVERSION query | WezTerm `xt_version_impl`, notcurses `IDQUERIES` | Reuse existing `Sentinel_Query` infrastructure |
| DCS `>|` prefix as unambiguous discriminator | notcurses `P>|\S` pattern | `Contains_XTVERSION_Response` checks 4-byte prefix |
| Known-terminal prefix table | notcurses `xtversion_cb` | Not adopted: Termicap returns raw name/version strings and lets the caller or `Terminal_Identity` reconcile |
| tmux DCS passthrough + 100 ms delay | WezTerm | Passthrough via `Wrap_For_Passthrough`; no extra delay (DA1 sentinel handles timing) |

---

## 3. Package Design

### Package tree

```
Termicap                                  (existing root namespace)
├── Termicap.XTVERSION                    [SPARK_Mode => On]  -- types, constants, pure parsing
│   └── Termicap.XTVERSION.IO            [SPARK_Mode => Off] -- Query_XTVERSION, Query_And_Identify
```

### SPARK boundary rationale

| Package | SPARK_Mode | Reason |
|---------|------------|--------|
| `Termicap.XTVERSION` | On | Pure types, constants, and parsing functions. No FFI, no controlled types, no global state. All functions carry Silver-level contracts. Uses `Ada.Strings.Unbounded` (SPARK-compatible in GNAT for value operations). Re-declares `Byte`/`Byte_Array` using `Interfaces.C.unsigned_char` for SPARK compatibility, same pattern as `Termicap.Color.BG_Query`. |
| `Termicap.XTVERSION.IO` | Off | Calls `Termicap.OSC.Probe_Session` (controlled type), `Sentinel_Query`, and `Wrap_For_Passthrough`. Accesses `Termicap.Terminal_Id` for multiplexer detection. Performs terminal I/O. |

### No new C source file

All terminal I/O is performed through the existing `Termicap.OSC.Probe_Session` and `Sentinel_Query` infrastructure. The XTVERSION feature adds no new system calls, no new C wrappers, and no new FFI bindings.

### File layout

| File | Purpose |
|------|---------|
| `src/termicap-xtversion.ads` | XTVERSION_Status, XTVERSION_Result, Token_Pair, Payload_Slice, CSI_XTVERSION_QUERY constant, pure parsing function specs |
| `src/termicap-xtversion.adb` | Pure parsing function bodies |
| `src/termicap-xtversion-io.ads` | Query_XTVERSION procedure spec, Query_And_Identify function spec |
| `src/termicap-xtversion-io.adb` | Query_XTVERSION body: probe session + sentinel query orchestration; Query_And_Identify body |

---

## 4. Type Design

All types in this section are declared in `Termicap.XTVERSION` (SPARK_Mode => On) unless otherwise noted.

### Byte types (SPARK-compatible re-declaration)

```ada
subtype Byte is Interfaces.C.unsigned_char;

type Byte_Array is array (Positive range <>) of Byte;
```

Same pattern as `Termicap.Color.BG_Query`: defines SPARK-compatible byte types independently of `Termicap.OSC` (which is SPARK Off). The underlying type `Interfaces.C.unsigned_char` is identical, so the I/O child package can convert between the two without a copy.

### XTVERSION_Status

```ada
type XTVERSION_Status is (Success, Timeout, Parse_Error);
```

FUNC-XTV-001. Three-way discriminant: Success (valid name + version extracted), Timeout (terminal did not respond), Parse_Error (response received but not a valid DCS XTVERSION envelope).

### XTVERSION_Result

```ada
type XTVERSION_Result (Status : XTVERSION_Status := Timeout) is record
   case Status is
      when Success =>
         Terminal_Name    : Ada.Strings.Unbounded.Unbounded_String;
         Terminal_Version : Ada.Strings.Unbounded.Unbounded_String;
      when Timeout | Parse_Error =>
         null;
   end case;
end record;
```

FUNC-XTV-001. Discriminated record preventing access to Terminal_Name and Terminal_Version without checking Status = Success. Default discriminant is Timeout (the most common non-success case). Uses `Unbounded_String` because terminal names and versions are variable-length (e.g., WezTerm date-hash versions exceed 30 characters).

### Token_Pair

```ada
type Token_Pair is record
   Name    : Ada.Strings.Unbounded.Unbounded_String;
   Version : Ada.Strings.Unbounded.Unbounded_String;
end record;
```

FUNC-XTV-005. Intermediate type returned by `Split_XTV_Payload`. Both fields may be empty; the caller (`Parse_XTVERSION_Response`) checks for a non-empty Name before constructing a Success result.

### Payload_Slice

```ada
type Payload_Slice is record
   Offset : Positive;
   Length : Natural;
end record;
```

FUNC-XTV-004. Zero-copy positional reference into the byte buffer. Same design pattern as `Channel_Slice` in `Termicap.Color.BG_Query`.

### CSI_XTVERSION_QUERY

```ada
CSI_XTVERSION_QUERY : constant Byte_Array :=
   [16#1B#, 16#5B#,                       --  ESC [   (CSI introducer)
    Character'Pos ('>'),                   --  >
    Character'Pos ('q')];                  --  q
```

FUNC-XTV-002. Four-byte constant encoding `ESC [ > q`. Defined in the SPARK On package so it can be referenced by both I/O and test code.

### MAX_RESPONSE_SIZE

```ada
MAX_RESPONSE_SIZE : constant := 4_096;
```

Matches `Termicap.OSC.MAX_RESPONSE_SIZE`. Used in preconditions to bound the parsing functions.

---

## 5. Algorithm Design

### Contains_XTVERSION_Response (FUNC-XTV-003)

**Input:** `Bytes(Bytes'First .. Bytes'First + Length - 1)` -- raw response buffer from Sentinel_Query.
**Output:** `Boolean` -- True if a valid DCS XTVERSION response envelope is present.

```
1. If Length < 7: return False
   -- Minimum valid response: ESC P > | X ST = 7 bytes
   --   ESC P (2) + > | (2) + payload (1) + ESC \ (2) = 7
   --   or ESC P (2) + > | (2) + payload (1) + BEL (1) = 6
   -- Use 6 as the actual minimum.

   If Length < 6: return False

2. Check 4-byte prefix:
   Bytes(First)     = 0x1B (ESC)
   Bytes(First + 1) = 0x50 (P)     -- DCS introducer
   Bytes(First + 2) = 0x3E (>)
   Bytes(First + 3) = 0x7C (|)
   If any mismatch: return False

3. Scan for ST terminator (ESC \ = 0x1B 0x5C) or BEL (0x07)
   starting from Bytes(First + 5):
   -- First + 4 is the first payload byte; we need at least one
   -- payload byte before the terminator.

   For I in First + 5 .. First + Length - 1:
      If Bytes(I) = 0x07:          -- BEL terminator
         return True
      If I >= First + 6
         and then Bytes(I - 1) = 0x1B
         and then Bytes(I) = 0x5C:  -- ESC \ terminator
         return True

4. return False   -- no terminator found
```

The scan is bounded by `Length <= MAX_RESPONSE_SIZE`, so no unbounded loop.

### Extract_XTV_Payload (FUNC-XTV-004)

**Input:** `Bytes(Bytes'First .. Bytes'First + Length - 1)` -- buffer confirmed to contain a valid XTVERSION response.
**Output:** `Payload_Slice` -- (Offset, Length) of the payload region.

**Precondition:** `Contains_XTVERSION_Response (Bytes, Length) = True`.

```
1. Payload_Start := Bytes'First + 4
   -- Payload begins immediately after ESC P > |

2. Scan backwards from Bytes'First + Length - 1 to find terminator:
   Last := Bytes'First + Length - 1

   If Bytes(Last) = 0x07:
      Payload_End := Last - 1       -- BEL: exclude 1 byte

   Elsif Last >= Bytes'First + 1
      and then Bytes(Last - 1) = 0x1B
      and then Bytes(Last) = 0x5C:
      Payload_End := Last - 2       -- ESC \: exclude 2 bytes

   Else:
      -- Precondition guarantees a terminator exists;
      -- this branch is unreachable.
      Payload_End := Last

3. return (Offset => Payload_Start,
           Length => Payload_End - Payload_Start + 1)
```

**Postcondition guarantees:** `Result.Length > 0`, `Result.Offset >= Bytes'First + 4`, and the slice is within bounds.

### Split_XTV_Payload (FUNC-XTV-005)

**Input:** `Bytes(Offset .. Offset + Length - 1)` -- payload bytes.
**Output:** `Token_Pair` -- Name and Version as Unbounded_Strings.

```
1. Scan for '(' (0x28) in the payload range:
   For I in Offset .. Offset + Length - 1:
      If Bytes(I) = 0x28:
         -- Format B: name(version)
         Name_Bytes  := Bytes(Offset .. I - 1)
         -- Find closing ')' (0x29)
         Version_End := I + 1
         For J in I + 1 .. Offset + Length - 1:
            If Bytes(J) = 0x29:
               Version_End := J - 1
               exit
         Name    := Trim(To_String(Name_Bytes))
         Version := Trim(To_String(Bytes(I + 1 .. Version_End)))
         return (Name, Version)

2. If no '(' found, scan for space (0x20):
   For I in Offset .. Offset + Length - 1:
      If Bytes(I) = 0x20:
         -- Format A: name version
         Name    := Trim(To_String(Bytes(Offset .. I - 1)))
         Version := Trim(To_String(Bytes(I + 1 .. Offset + Length - 1)))
         return (Name, Version)

3. If neither delimiter found:
   -- Name-only: entire payload is the name, version is empty
   Name    := Trim(To_String(Bytes(Offset .. Offset + Length - 1)))
   Version := To_Unbounded_String ("")
   return (Name, Version)
```

`Trim` removes leading/trailing ASCII space (0x20) bytes from each token. `To_String` converts a `Byte_Array` slice to an Ada `String` by mapping each byte via `Character'Val`.

### Parse_XTVERSION_Response (FUNC-XTV-006)

**Input:** `Bytes(Bytes'First .. Bytes'First + Length - 1)` -- raw response buffer.
**Output:** `XTVERSION_Result`.

```
1. If Length = 0:
      return (Status => Parse_Error)

2. If not Contains_XTVERSION_Response (Bytes, Length):
      return (Status => Parse_Error)

3. Slice := Extract_XTV_Payload (Bytes, Length)

4. Tokens := Split_XTV_Payload (Bytes, Slice.Offset, Slice.Length)

5. If Ada.Strings.Unbounded.Length (Tokens.Name) = 0:
      return (Status => Parse_Error)

6. return (Status           => Success,
           Terminal_Name    => Tokens.Name,
           Terminal_Version => Tokens.Version)
```

**Postcondition:** When `Status = Success`, `Length(Terminal_Name) > 0`.

---

## 6. I/O Design

### Query_XTVERSION (FUNC-XTV-008, FUNC-XTV-009)

**Input:** Timeout_Ms.
**Output:** Response buffer, Resp_Length, Timed_Out.

This procedure mirrors `Query_Color` in `Termicap.Color.BG_Query.IO` exactly.

```
1. Query_Bytes := CSI_XTVERSION_QUERY
   -- ESC [ > q (4 bytes)

2. -- Determine multiplexer wrapping from terminal identity
   Env := Capture environment snapshot
   Identity := Detect_Terminal_Identity (Env)
   Passthrough :=
      (if Identity.Kind = Tmux
       then Tmux_Passthrough
       elsif Identity.Kind = Screen
       then Screen_Passthrough
       else No_Passthrough)

3. Wrapped_Query := Wrap_For_Passthrough (Query_Bytes, Passthrough)

4. -- Open probe session
   declare
      Session : Probe_Session;
      Status  : Session_Status;
   begin
      Open (Session, Status);
      if Status /= Session_OK then
         -- Covers: Session_Not_Foreground (FUNC-XTV-010),
         --         Session_No_Terminal     (FUNC-XTV-011),
         --         Session_Save_Failed, Session_Raw_Failed,
         --         Session_Already_Active
         Timed_Out := True;
         Resp_Length := 0;
         Response := [others => 0];
         return;
      end if;

5.    Sentinel_Query
        (Session     => Session,
         Query       => Wrapped_Query,
         Response    => OSC_Response,
         Resp_Length => OSC_Length,
         Timeout_Ms  => Timeout_Ms,
         Timed_Out   => OSC_Timeout,
         Retry       => False);   -- No retry per FUNC-XTV-009

6.    -- Session closes automatically via Finalize (RAII)
   end;

7. -- Copy OSC response bytes into caller's buffer
   Resp_Length := OSC_Length;
   Timed_Out := OSC_Timeout;
   for I in 1 .. OSC_Length loop
      Response (I) := Byte (OSC_Response (I));
   end loop;
```

**Safety guards inherited from Probe_Session:**
- Foreground process group check (FUNC-XTV-010): `Open` returns `Session_Not_Foreground`
- Not-a-TTY guard (FUNC-XTV-011): `Open` returns `Session_No_Terminal`
- Multiplexer passthrough (FUNC-XTV-012): wrapping applied in step 3

### Query_And_Identify (FUNC-XTV-013)

```
1. Query_XTVERSION
      (Timeout_Ms  => Timeout_Ms,
       Response    => Resp_Buffer,
       Resp_Length => Resp_Len,
       Timed_Out   => Timed_Out)

2. If Timed_Out then
      return (Status => Timeout)

3. Result := Parse_XTVERSION_Response (Resp_Buffer, Resp_Len)

4. return Result
```

Default `Timeout_Ms` is 100 (FUNC-XTV-013). This function is in `Termicap.XTVERSION.IO` (SPARK Off).

---

## 7. Integration Points

### Relationship to Terminal_Identity (FUNC-XTV-014)

The XTVERSION result is designed to augment -- not replace -- passive terminal identification. The two identification paths remain orthogonal:

1. **Passive identification:** `Termicap.Terminal_Id.Detect_Terminal_Identity` reads environment variables and returns a `Terminal_Identity` record with `Kind`, `Program_Name`, `Program_Version`, `Term_Value`, and `Is_Multiplexer`.

2. **Active identification:** `Termicap.XTVERSION.IO.Query_And_Identify` sends `CSI > q` and returns an `XTVERSION_Result` with `Terminal_Name` and `Terminal_Version`.

Callers (including the future `Termicap.Capabilities` integration) combine these results according to the precedence rule in FUNC-XTV-014: when both are available and inconsistent, the XTVERSION result takes precedence because it is a direct response from the terminal. The reconciliation logic is not in scope for v1 of the XTVERSION package; it will live in the caller layer.

### Dependency on Termicap.OSC

`Termicap.XTVERSION` (SPARK On) does **not** depend on `Termicap.OSC` (SPARK Off). It re-declares compatible `Byte`/`Byte_Array` types, following the same pattern as `Termicap.Color.BG_Query`. Only the child package `Termicap.XTVERSION.IO` depends on `Termicap.OSC` for `Probe_Session`, `Sentinel_Query`, and `Response_Buffer`.

### Dependency on Termicap.Terminal_Id

Only `Termicap.XTVERSION.IO` depends on `Termicap.Terminal_Id` for multiplexer detection. The parent parsing package has no dependency on terminal identity.

---

## 8. Error Handling

### Error propagation strategy

All parsing functions return discriminated records. No exceptions are raised anywhere in the XTVERSION feature. This follows the Termicap convention established in `Termicap.Color.BG_Query` and documented in ADR-0016.

### XTVERSION_Status mapping

| Condition | XTVERSION_Status | Source |
|-----------|-----------------|--------|
| Terminal responded with valid DCS XTVERSION, name non-empty | `Success` | `Parse_XTVERSION_Response` |
| Sentinel_Query timed out (DA1 not detected) | `Timeout` | `Query_And_Identify` |
| Probe_Session Open failed (not foreground, no TTY, etc.) | `Timeout` | `Query_XTVERSION` (maps session failure to timeout) |
| Response received but not a valid DCS `>|` envelope | `Parse_Error` | `Parse_XTVERSION_Response` |
| DCS `>|` envelope present but no ST/BEL terminator within buffer | `Parse_Error` | `Contains_XTVERSION_Response` returns False |
| Valid envelope but empty payload (ESC P > \| ESC \\) | `Parse_Error` | `Contains_XTVERSION_Response` requires >= 1 payload byte |
| Valid envelope and payload but tokenised Name is empty | `Parse_Error` | `Parse_XTVERSION_Response` step 5 |

### Timeout is not an error (FUNC-XTV-015)

A timeout is the expected outcome for terminals that do not implement XTVERSION. This includes the Linux virtual console, GNU Screen, and many older terminal emulators. Callers should treat timeout as a normal code path and fall back to passive identification (`Termicap.Terminal_Id`) without logging or reporting.

### Parse_Error cases (FUNC-XTV-016)

All malformed-input cases produce `Parse_Error` without raising an exception:
- Response begins with `ESC P` but lacks the `>|` discriminator
- Response has `ESC P > |` but no ST terminator
- Valid DCS envelope but payload is empty or whitespace-only
- Response is not a DCS sequence at all (e.g., stale OSC bytes in the buffer)

---

## 9. SPARK Boundary

### SPARK Silver targets

| Package | Subprogram | Proof level |
|---------|-----------|-------------|
| `Termicap.XTVERSION` | `Contains_XTVERSION_Response` | Silver (bounded scan, byte comparisons) |
| `Termicap.XTVERSION` | `Extract_XTV_Payload` | Silver (precondition from Contains, arithmetic on bounded indices) |
| `Termicap.XTVERSION` | `Split_XTV_Payload` | Silver (bounded scan within payload slice) |
| `Termicap.XTVERSION` | `Parse_XTVERSION_Response` | Silver (composition of above three; postcondition chained from Split) |

All functions carry `Global => null` contracts. No dynamic allocation, no OS calls, and no unbounded loops appear in the package body. All loops are bounded by `Length <= MAX_RESPONSE_SIZE` (4096).

### Ada FFI boundary

| Package | Subprogram | Reason for SPARK Off |
|---------|-----------|---------------------|
| `Termicap.XTVERSION.IO` | `Query_XTVERSION` | Calls `Probe_Session` (controlled type), `Sentinel_Query` (I/O), `Detect_Terminal_Identity` (env capture) |
| `Termicap.XTVERSION.IO` | `Query_And_Identify` | Calls `Query_XTVERSION` (I/O) and `Parse_XTVERSION_Response` |

---

## 10. SPARK Contracts

### Contains_XTVERSION_Response (FUNC-XTV-003)

```ada
function Contains_XTVERSION_Response
   (Bytes : Byte_Array; Length : Natural) return Boolean
with
   Global => null,
   Pre    => Length <= Bytes'Length;
```

### Extract_XTV_Payload (FUNC-XTV-004)

```ada
function Extract_XTV_Payload
   (Bytes : Byte_Array; Length : Natural) return Payload_Slice
with
   Global => null,
   Pre    => Length <= Bytes'Length
               and then Contains_XTVERSION_Response (Bytes, Length),
   Post   => Extract_XTV_Payload'Result.Length > 0
               and then Extract_XTV_Payload'Result.Offset >= Bytes'First + 4
               and then Extract_XTV_Payload'Result.Offset
                          + Extract_XTV_Payload'Result.Length - 1
                        < Bytes'First + Length;
```

### Split_XTV_Payload (FUNC-XTV-005)

```ada
function Split_XTV_Payload
   (Bytes  : Byte_Array;
    Offset : Positive;
    Length : Natural) return Token_Pair
with
   Global => null,
   Pre    => Length > 0
               and then Offset >= Bytes'First
               and then Offset + Length - 1 <= Bytes'Last;
```

### Parse_XTVERSION_Response (FUNC-XTV-006)

```ada
function Parse_XTVERSION_Response
   (Bytes  : Byte_Array;
    Length : Natural) return XTVERSION_Result
with
   Global => null,
   Pre    => Length <= Bytes'Length
               and then Length <= MAX_RESPONSE_SIZE,
   Post   =>
      (if Parse_XTVERSION_Response'Result.Status = Success
       then Ada.Strings.Unbounded.Length
              (Parse_XTVERSION_Response'Result.Terminal_Name) > 0);
```

### Query_XTVERSION (FUNC-XTV-008)

```ada
procedure Query_XTVERSION
   (Timeout_Ms  :     Natural;
    Response    : out Byte_Array;
    Resp_Length : out Natural;
    Timed_Out   : out Boolean)
with Pre => Response'Length >= MAX_RESPONSE_SIZE;
```

### Query_And_Identify (FUNC-XTV-013)

```ada
function Query_And_Identify
   (Timeout_Ms : Natural := 100) return XTVERSION_Result;
```

---

## 11. Dependency Graph

```
┌──────────────────────────────────┐
│    Termicap.XTVERSION.IO         │  SPARK_Mode => Off
│  Query_XTVERSION                 │  (I/O orchestration)
│  Query_And_Identify              │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│    Termicap.XTVERSION            │  SPARK_Mode => On
│  XTVERSION_Status, Result,       │  (types + pure parsing)
│  Token_Pair, Payload_Slice,      │
│  CSI_XTVERSION_QUERY,            │
│  Contains_XTVERSION_Response,    │
│  Extract_XTV_Payload,            │
│  Split_XTV_Payload,              │
│  Parse_XTVERSION_Response        │
└──────────────────────────────────┘
       ▲
       │ (types: Byte, Byte_Array)
       │
┌──────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│  Termicap.OSC    │   │ Termicap.OSC.Parsing │   │ Termicap.Terminal_Id │
│  Probe_Session   │   │ Wrap_For_Passthrough │   │ Terminal_Identity    │
│  Sentinel_Query  │   │ Passthrough_Mode     │   │ Multiplexer_Kind    │
└──────────────────┘   └──────────────────────┘   └──────────────────────┘
       ▲                        ▲                          ▲
       │                        │                          │
       └────────────────────────┴──────────────────────────┘
                     (used by XTVERSION.IO)

┌──────────────────────┐
│ Termicap.Environment │   (used by XTVERSION.IO for env capture)
└──────────────────────┘
```

Dependency flow (arrows point from dependent to dependency):

- `Termicap.XTVERSION.IO` depends on `Termicap.XTVERSION`, `Termicap.OSC`, `Termicap.OSC.Parsing`, `Termicap.Terminal_Id`, `Termicap.Environment`
- `Termicap.XTVERSION` depends only on `Interfaces.C` (for Byte subtype) and `Ada.Strings.Unbounded` (for Token_Pair, XTVERSION_Result)

No circular dependencies exist. The SPARK boundary is clean: `Termicap.XTVERSION` (SPARK On) does not depend on any SPARK Off package.

---

## 12. Requirement Traceability

| Requirement | Design Element | Package |
|-------------|---------------|---------|
| FUNC-XTV-001 | `XTVERSION_Status`, `XTVERSION_Result` discriminated record | `Termicap.XTVERSION` |
| FUNC-XTV-002 | `CSI_XTVERSION_QUERY` constant (`[0x1B, 0x5B, 0x3E, 0x71]`) | `Termicap.XTVERSION` |
| FUNC-XTV-003 | `Contains_XTVERSION_Response` function | `Termicap.XTVERSION` |
| FUNC-XTV-004 | `Extract_XTV_Payload` function, `Payload_Slice` type | `Termicap.XTVERSION` |
| FUNC-XTV-005 | `Split_XTV_Payload` function, `Token_Pair` type | `Termicap.XTVERSION` |
| FUNC-XTV-006 | `Parse_XTVERSION_Response` function | `Termicap.XTVERSION` |
| FUNC-XTV-007 | `pragma SPARK_Mode (On)` on `Termicap.XTVERSION`, `Global => null` on all subprograms | `Termicap.XTVERSION` |
| FUNC-XTV-008 | `Query_XTVERSION` procedure | `Termicap.XTVERSION.IO` |
| FUNC-XTV-009 | `Sentinel_Query` call with `Retry => False`, DA1 sentinel | `Termicap.XTVERSION.IO` |
| FUNC-XTV-010 | `Probe_Session.Open` returns `Session_Not_Foreground` -> `Timed_Out := True` | `Termicap.XTVERSION.IO` |
| FUNC-XTV-011 | `Probe_Session.Open` returns `Session_No_Terminal` -> `Timed_Out := True` | `Termicap.XTVERSION.IO` |
| FUNC-XTV-012 | `Wrap_For_Passthrough` with `Passthrough_Mode` derived from `Terminal_Identity.Kind` | `Termicap.XTVERSION.IO` |
| FUNC-XTV-013 | `Query_And_Identify` function with `Timeout_Ms : Natural := 100` | `Termicap.XTVERSION.IO` |
| FUNC-XTV-014 | Caller-side reconciliation (not in XTVERSION packages); documented in Integration Points | Caller / `Termicap.Capabilities` |
| FUNC-XTV-015 | `Timed_Out = True` -> `XTVERSION_Result (Status => Timeout)` in `Query_And_Identify` | `Termicap.XTVERSION.IO` |
| FUNC-XTV-016 | All malformed-input paths return `Parse_Error` without exception in `Parse_XTVERSION_Response` | `Termicap.XTVERSION` |
| FUNC-XTV-017 | All parsing functions accept `Byte_Array` input; 9 test cases specified in requirements | `tests/src/` (test suite) |

---

## 13. ADR Decisions

No new ADRs are filed for this feature. The key design decisions reuse patterns already established and documented:

1. **Discriminated record for result types** -- reuses the pattern from ADR-0016 (BG-COLOR). The `XTVERSION_Result` uses a three-way `XTVERSION_Status` discriminant (Success / Timeout / Parse_Error) rather than a Boolean, but the underlying mechanism is identical.

2. **Byte/Byte_Array re-declaration for SPARK boundary** -- reuses the pattern from `Termicap.Color.BG_Query`, which is documented in the BG-COLOR tech spec. No new ADR needed.

3. **Package split: pure parsing (SPARK On) + I/O child (SPARK Off)** -- follows the established pattern from `Termicap.Color.BG_Query` / `Termicap.Color.BG_Query.IO`, documented in ADR-0015 (probe session limited controlled) and the OSC query infrastructure tech spec.

4. **Sentinel_Query with DA1 boundary marker** -- reuses the existing infrastructure from `Termicap.OSC` without modification, as documented in the OSC query infrastructure tech spec.
