# Technical Specification: Background / Foreground Color Query

**Feature:** Background / Foreground Color Query (BG-COLOR)
**Requirements:** `docs/requirements/bg-color-query.sdoc` (FUNC-BGC-001 through FUNC-BGC-019)
**Date:** 2026-04-05

---

## 1. Overview

The BG-COLOR feature delivers active terminal background and foreground color detection via OSC 10/11 escape sequence queries, with a passive COLORFGBG environment variable fallback. It enables callers to determine whether a terminal has a dark or light background, which is the prerequisite for theme-aware rendering.

This feature delivers:

- **RGB color type** -- a SPARK-provable record with constrained 0..255 components for representing terminal colors
- **OSC 10/11 query construction** -- named constant byte sequences for foreground and background color queries
- **X11 rgb: response parsing** -- pure SPARK functions that parse the `rgb:RRRR/GGGG/BBBB` response format returned by terminals, including 2-digit and 4-digit hex channel normalization
- **OSC response header stripping** -- removal of the `ESC ] 11 ;` / `ESC ] 10 ;` prefix and ST/BEL terminator from raw sentinel response bytes
- **COLORFGBG fallback parsing** -- pure SPARK function parsing the semicolon-delimited `fg;bg` or `fg;extra;bg` environment variable format
- **ANSI color index to RGB mapping** -- a provable constant lookup table for the canonical xterm 16-color palette
- **Query I/O orchestration** -- procedure that opens a Probe_Session, sends the (optionally multiplexer-wrapped) OSC query via Sentinel_Query, and returns the raw response bytes
- **High-level detection cascade** -- `Detect_Background_Color` and `Detect_Foreground_Color` functions implementing the two-level cascade: OSC query first, COLORFGBG fallback second

**Dependencies on existing features:**

- `Termicap.OSC` -- probe session lifecycle, Sentinel_Query, Byte/Byte_Array types (Tier 3)
- `Termicap.OSC.Parsing` -- Wrap_For_Passthrough for multiplexer passthrough wrapping (Tier 3)
- `Termicap.Terminal_Id` -- Terminal_Identity for multiplexer detection (Tier 2)
- `Termicap.Environment` -- environment variable snapshot for COLORFGBG lookup (Tier 1)

---

## 2. Framework Survey

### termbg (Rust)

termbg implements background color detection in `src/lib.rs`:

1. **OSC query construction**: The `query_xterm` function builds multiplexer-specific query strings directly as string literals:
   - Plain xterm: `\x1b]11;?\x1b\\` (ESC ] 11 ; ? ESC \)
   - tmux: `\x1bPtmux;\x1b\x1b]11;?\x07\x1b\\` (DCS passthrough with inner BEL terminator)
   - screen: `\x1bP\x1b]11;?\x07\x1b\\` (screen DCS passthrough)

2. **Response parsing**: The `extract_rgb` function locates `"rgb:"` in the response string, then `decode_x11_color` splits on `/` and calls `decode_hex` for each channel. `decode_hex` uses Rust's `u16::from_str_radix` and left-shifts to normalize variable-length hex values to 16-bit: `ret = ret << ((4 - len) * 4)`. This means a 2-digit hex `"FF"` becomes `0xFF00` (not `0x00FF`). The final Rgb struct stores 16-bit values.

3. **COLORFGBG fallback**: `from_env_colorfgbg` splits the COLORFGBG value on `;`, takes only the second field (index 1) as the background, parses it as a decimal u8, and looks up a hardcoded rxvt color table. Notably, termbg only extracts the background index, not the foreground. The table values are 8-bit and then multiplied by 256 to produce 16-bit Rgb values.

4. **Multiplexer passthrough**: Handled inline in the query string selection (case on Terminal enum). No separate wrapping function.

5. **Sentinel pattern**: termbg does NOT use a DA1 sentinel. It relies on crossterm's event polling with timeout to detect the OSC response terminator (BEL, ST, or ESC). This makes response boundary detection fragile compared to the sentinel approach.

### termenv (Go)

termenv implements color detection in `termenv_unix.go` and parsing in `color.go`:

1. **OSC query construction**: `termStatusReport(sequence int)` formats the OSC query dynamically: `OSC + "%d;?" + ST` where sequence is 10 or 11. The query is written to the TTY via `fmt.Fprintf`.

2. **Response parsing**: `xTermColor(s string)` expects the full OSC response (24-25 bytes including ESC ] and terminator). It strips BEL, single ESC, or ESC \ terminators from the suffix, then skips the first 4 bytes and the `;rgb:` prefix. Channel parsing uses `h[0][:2]` to take only the first two hex characters of each channel (equivalent to dividing 16-bit by 256), then formats as a CSS hex color string `#RRGGBB`. The result is an `RGBColor` string, not a numeric struct.

3. **COLORFGBG fallback**: `foregroundColor()` and `backgroundColor()` in `termenv_unix.go` read `COLORFGBG`, split on `;`, and take `c[0]` for foreground (first field) and `c[len(c)-1]` for background (last field). This correctly handles the `fg;extra;bg` three-field variant. The parsed decimal integer is used as an `ANSIColor` index directly.

4. **Multiplexer passthrough**: termenv does NOT use DCS passthrough. The `termStatusReport` function explicitly rejects `screen` and `tmux` TERM prefixes with `ErrStatusReport`. This means termenv cannot detect colors through multiplexers.

5. **Sentinel pattern**: termenv uses CPR (Cursor Position Report, `CSI 6n` / response ending in `R`) as the sentinel instead of DA1. It sends the OSC query first, then `CSI 6n`, and reads responses byte-by-byte using `readNextResponse`, classifying them by the second byte (`]` = OSC, `[` = CSI). The first OSC response is kept; the CPR response is discarded.

### Key differences for Termicap

| Aspect | termbg (Rust) | termenv (Go) | Termicap (Ada) |
|--------|---------------|--------------|----------------|
| Sentinel | None (timeout-based) | CPR (`CSI 6n`) | DA1 (`CSI c`) |
| Multiplexer passthrough | Inline in query string | Not supported | Via `Wrap_For_Passthrough` |
| Color representation | 16-bit `Rgb` struct | CSS hex string | 8-bit `RGB` record |
| Hex normalization | Left-shift to 16-bit | Take first 2 chars | Take first 2 chars (high byte) |
| COLORFGBG foreground | Not extracted | First field | First field |
| COLORFGBG background | Second field only | Last field | Last field |
| COLORFGBG range | 0..255 (u8) | unchecked int | 0..15 (ANSI subset) |
| SPARK provability | N/A | N/A | Silver for all parsing |
| Result type | `Result<Rgb, Error>` | `(Color, error)` | Discriminated record |

### Patterns borrowed

| Pattern | Source | Adaptation |
|---------|--------|------------|
| `"rgb:"` prefix search in response | termbg, termenv | Pure SPARK function `Find_RGB_Prefix` with postcondition |
| Take first 2 hex digits for 4-digit channels | termenv | `Parse_Hex_Channel` with 2/4-digit normalization |
| Left-shift normalization for variable-length hex | termbg | Not used; take-high-byte approach is simpler and equivalent |
| COLORFGBG first/last field extraction | termenv | `Parse_Colorfgbg` takes first field as FG, last as BG |
| COLORFGBG as fallback after OSC failure | termbg, termenv | Same cascade: OSC first, then COLORFGBG, then error |
| Multiplexer-specific query wrapping | termbg | Reuse `Wrap_For_Passthrough` from OSC infrastructure |
| xterm 16-color ANSI palette table | termbg (rxvt table) | `ANSI_COLOR_TABLE` with canonical xterm defaults |

---

## 3. Package Design

### Package tree

```
Termicap                              (existing root namespace)
├── Termicap.Color                    (existing — color level detection)
│   ├── Termicap.Color.BG_Query       [SPARK_Mode => On]  — types, constants, pure parsing
│   │   └── Termicap.Color.BG_Query.IO [SPARK_Mode => Off] — Query_Color I/O procedure
│   └── Termicap.Color.Detection      [SPARK_Mode => Off] — Detect_Background/Foreground_Color
```

### SPARK boundary rationale

| Package | SPARK_Mode | Reason |
|---------|------------|--------|
| `Termicap.Color.BG_Query` | On | Pure types, constants, and parsing functions. No FFI, no controlled types, no global state. All functions carry Silver-level contracts. |
| `Termicap.Color.BG_Query.IO` | Off | Calls `Termicap.OSC.Probe_Session` (controlled type), `Sentinel_Query`, and `Wrap_For_Passthrough`. Accesses `Termicap.Terminal_Id` for multiplexer detection. |
| `Termicap.Color.Detection` | Off | Calls `Query_Color` (I/O), reads `Termicap.Environment` for COLORFGBG. Orchestration layer with no algorithmic complexity. |

### No new C source file

All terminal I/O is performed through the existing `Termicap.OSC.Probe_Session` and `Sentinel_Query` infrastructure. The BG-COLOR feature adds no new system calls, no new C wrappers, and no new FFI bindings. The only external dependencies are on `Termicap.OSC` (for I/O), `Termicap.OSC.Parsing` (for passthrough wrapping), `Termicap.Terminal_Id` (for multiplexer detection), and `Termicap.Environment` (for COLORFGBG).

### File layout

| File | Purpose |
|------|---------|
| `src/termicap-color-bg_query.ads` | RGB type, Query_Kind, Parse_Result, Channel_Result, Channel_Slice, Strip_Result, Colorfgbg_Result, ANSI_Color_Array, constants, pure parsing function specs |
| `src/termicap-color-bg_query.adb` | Pure parsing function bodies |
| `src/termicap-color-bg_query-io.ads` | Query_Color procedure spec |
| `src/termicap-color-bg_query-io.adb` | Query_Color body: probe session + sentinel query orchestration |
| `src/termicap-color-detection.ads` | Detect_Error, Detection_Result, Detect_Background_Color, Detect_Foreground_Color specs |
| `src/termicap-color-detection.adb` | Detection cascade bodies |

---

## 4. Type Design

All types in this section are declared in `Termicap.Color.BG_Query` (SPARK_Mode => On) unless otherwise noted.

### RGB

```ada
type RGB is record
   Red   : Natural range 0 .. 255;
   Green : Natural range 0 .. 255;
   Blue  : Natural range 0 .. 255;
end record;
```

FUNC-BGC-001. Constrained to 8-bit channel values. The prover can verify that all component assignments from `Parse_Hex_Channel` results stay in range.

### Default color constants

```ada
DEFAULT_FOREGROUND : constant RGB := (Red => 170, Green => 170, Blue => 170);
DEFAULT_BACKGROUND : constant RGB := (Red => 0,   Green => 0,   Blue => 0);
```

FUNC-BGC-001. ANSI index 7 (light grey) for foreground, index 0 (black) for background.

### Query_Kind

```ada
type Query_Kind is (Background, Foreground);
```

FUNC-BGC-002. Selects between OSC 11 (Background) and OSC 10 (Foreground) queries.

### Parse_Result

```ada
type Parse_Result (Success : Boolean := False) is record
   case Success is
      when True  => Color : RGB;
      when False => null;
   end case;
end record;
```

FUNC-BGC-007. Discriminant constraint prevents access to Color when Success is False.

### Channel_Result

```ada
type Channel_Result (Success : Boolean := False) is record
   case Success is
      when True  => Value : Natural range 0 .. 255;
      when False => null;
   end case;
end record;
```

FUNC-BGC-009. Return type for `Parse_Hex_Channel`.

### Channel_Slice

```ada
type Channel_Slice is record
   Start  : Positive;
   Length : Natural range 0 .. MAX_CHANNEL_LENGTH;
end record;
```

FUNC-BGC-008. Index and length within a Byte_Array identifying a single hex channel substring. No data copy; purely positional.

```ada
MAX_CHANNEL_LENGTH : constant := 4;
```

### Strip_Result

```ada
type Strip_Result (Success : Boolean := False) is record
   case Success is
      when True =>
         Offset         : Positive;
         Payload_Length : Natural;
      when False => null;
   end case;
end record;
```

FUNC-BGC-010. Identifies the payload region within the raw response bytes after the OSC header has been removed.

### Colorfgbg_Result

```ada
type Colorfgbg_Result is record
   Success    : Boolean;
   Foreground : Natural range 0 .. 15;
   Background : Natural range 0 .. 15;
end record;
```

FUNC-BGC-011. Non-discriminated record; both index fields always present but only meaningful when Success is True.

### Detect_Error (in Termicap.Color.Detection)

```ada
type Detect_Error is
   (Not_A_Terminal, Not_Foreground, Query_Timeout, Parse_Failed, No_Fallback);
```

FUNC-BGC-013. Each value identifies a specific failure in the detection cascade.

### Detection_Result (in Termicap.Color.Detection)

```ada
type Detection_Result (Success : Boolean := False) is record
   case Success is
      when True  => Color : RGB;
      when False => Error : Detect_Error;
   end case;
end record;
```

Replaces the `functional` Result type (not in the project). Uses a discriminated record following the same pattern as Parse_Result. See ADR-0016.

### ANSI_Color_Array and ANSI_COLOR_TABLE

```ada
type ANSI_Color_Array is array (Natural range 0 .. 15) of RGB;

ANSI_COLOR_TABLE : constant ANSI_Color_Array :=
   (0  => (Red =>   0, Green =>   0, Blue =>   0),   --  Black
    1  => (Red => 128, Green =>   0, Blue =>   0),   --  Dark Red
    2  => (Red =>   0, Green => 128, Blue =>   0),   --  Dark Green
    3  => (Red => 128, Green => 128, Blue =>   0),   --  Dark Yellow (Olive)
    4  => (Red =>   0, Green =>   0, Blue => 128),   --  Dark Blue
    5  => (Red => 128, Green =>   0, Blue => 128),   --  Dark Magenta
    6  => (Red =>   0, Green => 128, Blue => 128),   --  Dark Cyan
    7  => (Red => 192, Green => 192, Blue => 192),   --  Light Grey
    8  => (Red => 128, Green => 128, Blue => 128),   --  Dark Grey
    9  => (Red => 255, Green =>   0, Blue =>   0),   --  Bright Red
   10  => (Red =>   0, Green => 255, Blue =>   0),   --  Bright Green
   11  => (Red => 255, Green => 255, Blue =>   0),   --  Bright Yellow
   12  => (Red =>   0, Green =>   0, Blue => 255),   --  Bright Blue
   13  => (Red => 255, Green =>   0, Blue => 255),   --  Bright Magenta
   14  => (Red =>   0, Green => 255, Blue => 255),   --  Bright Cyan
   15  => (Red => 255, Green => 255, Blue => 255));  --  White
```

FUNC-BGC-012, FUNC-BGC-018. Named index associations, decimal literals, canonical xterm defaults.

### OSC Query Constants

```ada
OSC_BG_QUERY : constant Byte_Array :=
   (16#1B#, 16#5D#,
    Character'Pos ('1'), Character'Pos ('1'), Character'Pos (';'),
    Character'Pos ('?'),
    16#1B#, 16#5C#);

OSC_FG_QUERY : constant Byte_Array :=
   (16#1B#, 16#5D#,
    Character'Pos ('1'), Character'Pos ('0'), Character'Pos (';'),
    Character'Pos ('?'),
    16#1B#, 16#5C#);
```

FUNC-BGC-003, FUNC-BGC-004. ESC ] 1 1 ; ? ESC \ and ESC ] 1 0 ; ? ESC \ respectively.

### MAX_COLORFGBG_LENGTH

```ada
MAX_COLORFGBG_LENGTH : constant := 32;
```

FUNC-BGC-011. Upper bound on COLORFGBG string length for precondition safety.

---

## 5. Algorithm Design

### Parse_RGB_Response (FUNC-BGC-007)

**Input:** `Bytes(Bytes'First .. Bytes'First + Length - 1)` -- payload bytes after OSC header stripping.
**Output:** `Parse_Result` -- Success with RGB, or failure.

```
1. Call Find_RGB_Prefix (Bytes, Length, Prefix_End)
   If not found: return (Success => False)

2. Call Split_RGB_Channels (Bytes, Prefix_End, Length, Ch_R, Ch_G, Ch_B, Split_OK)
   If not Split_OK: return (Success => False)

3. R_Result := Parse_Hex_Channel (Bytes, Ch_R.Start, Ch_R.Length)
   If not R_Result.Success: return (Success => False)

4. G_Result := Parse_Hex_Channel (Bytes, Ch_G.Start, Ch_G.Length)
   If not G_Result.Success: return (Success => False)

5. B_Result := Parse_Hex_Channel (Bytes, Ch_B.Start, Ch_B.Length)
   If not B_Result.Success: return (Success => False)

6. return (Success => True,
           Color => (Red => R_Result.Value,
                     Green => G_Result.Value,
                     Blue  => B_Result.Value))
```

### Parse_Hex_Channel (FUNC-BGC-009)

**Input:** `Bytes(Start .. Start + Length - 1)` -- 1 to 4 hex digit bytes.
**Output:** `Channel_Result` -- Success with 0..255 value, or failure.

```
1. If Length not in 1 .. MAX_CHANNEL_LENGTH: return (Success => False)

2. Accumulator := 0
   For I in Start .. Start + Length - 1:
      Digit := Hex_Digit_Value (Bytes(I))
      If Digit = INVALID_HEX: return (Success => False)
      Accumulator := Accumulator * 16 + Digit

3. -- Normalize to 8-bit:
   case Length is
      when 1 => Value := Accumulator * 17          -- 0xF -> 0xFF
      when 2 => Value := Accumulator               -- 0xFF -> 0xFF
      when 3 => Value := Accumulator / 16           -- 0xFFF -> 0xFF
      when 4 => Value := Accumulator / 256          -- 0xFFFF -> 0xFF

4. If Value > 255: return (Success => False)   -- defensive; cannot happen for valid input

5. return (Success => True, Value => Value)
```

`Hex_Digit_Value` maps bytes `0x30..0x39` to 0..9, `0x41..0x46` to 10..15, `0x61..0x66` to 10..15, and returns `INVALID_HEX` (a sentinel Natural value, e.g., 16) for all other bytes.

### Strip_OSC_Header (FUNC-BGC-010)

**Input:** `Bytes(Bytes'First .. Bytes'First + Length - 1)` -- raw Sentinel_Query response, Kind.
**Output:** `Strip_Result` -- Success with payload offset and length, or failure.

```
1. If Length < 5: return (Success => False)   -- minimum: ESC ] 1 X ;

2. Check Bytes(1) = 0x1B and Bytes(2) = 0x5D (ESC ]):
   If not: return (Success => False)

3. Expected_Digit :=
   case Kind is
      when Background => Character'Pos ('1')   -- "11"
      when Foreground => Character'Pos ('0')   -- "10"

4. Check Bytes(3) = Character'Pos ('1') and Bytes(4) = Expected_Digit
   and Bytes(5) = Character'Pos (';'):
   If not: return (Success => False)

5. -- Payload starts at index 6 (after "ESC ] 1 X ;")
   Payload_Start := 6

6. -- Find the terminator: scan backwards for ESC \ or BEL
   Payload_End := Length
   If Length >= 2 and Bytes(Length - 1) = 0x1B and Bytes(Length) = 0x5C:
      Payload_End := Length - 2   -- exclude ESC \
   Elsif Bytes(Length) = 0x07:
      Payload_End := Length - 1   -- exclude BEL
   -- Otherwise: no terminator found, use full remaining bytes

7. Payload_Length := Payload_End - Payload_Start + 1
   If Payload_Length <= 0: return (Success => False)

8. return (Success => True,
           Offset => Payload_Start,
           Payload_Length => Payload_Length)
```

### Parse_Colorfgbg (FUNC-BGC-011)

**Input:** `Value` -- string from COLORFGBG environment variable, length <= MAX_COLORFGBG_LENGTH.
**Output:** `Colorfgbg_Result`.

```
1. Find First_Semi := index of first ';' in Value.
   If not found: return (Success => False, Foreground => 0, Background => 0)

2. Find Last_Semi := index of last ';' in Value.

3. FG_Str := Value(Value'First .. First_Semi - 1)
   BG_Str := Value(Last_Semi + 1 .. Value'Last)

4. Parse FG_Str as decimal integer -> FG_Index
   If parse fails or FG_Index not in 0..15:
      return (Success => False, Foreground => 0, Background => 0)

5. Parse BG_Str as decimal integer -> BG_Index
   If parse fails or BG_Index not in 0..15:
      return (Success => False, Foreground => 0, Background => 0)

6. return (Success => True, Foreground => FG_Index, Background => BG_Index)
```

### Query_Color (FUNC-BGC-006, in Termicap.Color.BG_Query.IO)

**Input:** Kind, Timeout_Ms.
**Output:** Response buffer, Resp_Length, Timed_Out.

```
1. Query_Bytes := Query_Sequence (Kind)
   -- Returns OSC_BG_QUERY or OSC_FG_QUERY

2. -- Determine multiplexer wrapping from terminal identity
   Env := Capture environment snapshot
   Identity := Detect_Terminal_Identity (Env)
   Passthrough :=
      (if Identity.Kind in Multiplexer_Kind and then Identity.Kind = Tmux
       then Tmux_Passthrough
       elsif Identity.Kind in Multiplexer_Kind and then Identity.Kind = Screen
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
         Timed_Out := True;
         Resp_Length := 0;
         return;
      end if;

5.    Sentinel_Query
        (Session     => Session,
         Query       => Wrapped_Query,
         Response    => Response,
         Resp_Length => Resp_Length,
         Timeout_Ms  => Timeout_Ms,
         Timed_Out   => Timed_Out);

6.    -- Session closes automatically via Finalize
   end;
```

### Detect_Background_Color / Detect_Foreground_Color (FUNC-BGC-013, FUNC-BGC-014)

Both functions share the same algorithm, differing only in the Kind parameter. Shown for Background:

```
1. -- Clamp timeout
   Effective_Timeout := Natural'Min (Timeout_Ms, 30_000)

2. If Effective_Timeout = 0 then
      -- Skip OSC query, go directly to fallback
      goto COLORFGBG_Fallback

3. -- Attempt OSC query
   Query_Color (Kind       => Background,
                Timeout_Ms => Effective_Timeout,
                Response   => Resp_Buffer,
                Resp_Length => Resp_Len,
                Timed_Out  => Timed_Out)

4. If not Timed_Out and Resp_Len > 0 then
      Strip := Strip_OSC_Header (Resp_Buffer, Resp_Len, Background)
      If Strip.Success then
         Parse := Parse_RGB_Response
                    (Resp_Buffer (Strip.Offset ..
                                  Strip.Offset + Strip.Payload_Length - 1),
                     Strip.Payload_Length)
         If Parse.Success then
            return (Success => True, Color => Parse.Color)
         end if
      end if

5. <<COLORFGBG_Fallback>>
   Env := Capture environment snapshot
   COLORFGBG_Val := Value (Env, "COLORFGBG")
   If COLORFGBG_Val'Length > 0 and COLORFGBG_Val'Length <= MAX_COLORFGBG_LENGTH then
      CFGBG := Parse_Colorfgbg (COLORFGBG_Val)
      If CFGBG.Success then
         return (Success => True,
                 Color   => ANSI_COLOR_TABLE (CFGBG.Background))
      end if

6. return (Success => False, Error => No_Fallback)
```

For Detect_Foreground_Color, step 3 uses `Kind => Foreground`, step 4 uses `Strip_OSC_Header (..., Foreground)`, and step 5 uses `CFGBG.Foreground` instead of `CFGBG.Background`.

---

## 6. SPARK Contracts

All functions below are in `Termicap.Color.BG_Query` (SPARK_Mode => On).

### Query_Sequence (FUNC-BGC-005)

```ada
function Query_Sequence (Kind : Query_Kind) return Byte_Array
  with Post => Query_Sequence'Result'Length > 0;
```

### Parse_RGB_Response (FUNC-BGC-007)

```ada
function Parse_RGB_Response
   (Bytes  : Byte_Array;
    Length : Natural)
    return Parse_Result
  with Pre  => Length <= Bytes'Length,
       Post => (if Parse_RGB_Response'Result.Success
                then Parse_RGB_Response'Result.Color.Red   in 0 .. 255
                     and Parse_RGB_Response'Result.Color.Green in 0 .. 255
                     and Parse_RGB_Response'Result.Color.Blue  in 0 .. 255);
```

### Find_RGB_Prefix (FUNC-BGC-008)

```ada
function Find_RGB_Prefix
   (Bytes  : Byte_Array;
    Length : Natural;
    Offset : out Natural)
    return Boolean
  with Pre  => Length <= Bytes'Length,
       Post => (if Find_RGB_Prefix'Result
                then Offset < Length and Offset >= Bytes'First + 4);
```

### Split_RGB_Channels (FUNC-BGC-008)

```ada
procedure Split_RGB_Channels
   (Bytes                : Byte_Array;
    Start                : Natural;
    Length               : Natural;
    Ch_R, Ch_G, Ch_B    : out Channel_Slice;
    Success              : out Boolean)
  with Pre  => Start >= Bytes'First
               and then Start + Length - 1 <= Bytes'Last
               and then Length > 0,
       Post => (if Success
                then Ch_R.Length in 1 .. MAX_CHANNEL_LENGTH
                     and Ch_G.Length in 1 .. MAX_CHANNEL_LENGTH
                     and Ch_B.Length in 1 .. MAX_CHANNEL_LENGTH
                     and Ch_R.Start >= Bytes'First
                     and Ch_B.Start + Ch_B.Length - 1 <= Bytes'Last);
```

### Parse_Hex_Channel (FUNC-BGC-009)

```ada
function Parse_Hex_Channel
   (Bytes  : Byte_Array;
    Start  : Natural;
    Length : Natural)
    return Channel_Result
  with Pre  => Length in 1 .. MAX_CHANNEL_LENGTH
               and then Start >= Bytes'First
               and then Start + Length - 1 <= Bytes'Last,
       Post => (if Parse_Hex_Channel'Result.Success
                then Parse_Hex_Channel'Result.Value in 0 .. 255);
```

### Strip_OSC_Header (FUNC-BGC-010)

```ada
function Strip_OSC_Header
   (Bytes  : Byte_Array;
    Length : Natural;
    Kind   : Query_Kind)
    return Strip_Result
  with Pre  => Length <= Bytes'Length,
       Post => (if Strip_OSC_Header'Result.Success
                then Strip_OSC_Header'Result.Offset >= Bytes'First + 5
                     and Strip_OSC_Header'Result.Payload_Length > 0
                     and Strip_OSC_Header'Result.Offset +
                         Strip_OSC_Header'Result.Payload_Length - 1
                         <= Bytes'First + Length - 1);
```

### Parse_Colorfgbg (FUNC-BGC-011)

```ada
function Parse_Colorfgbg
   (Value : String)
    return Colorfgbg_Result
  with Pre  => Value'Length <= MAX_COLORFGBG_LENGTH,
       Post => (if Parse_Colorfgbg'Result.Success
                then Parse_Colorfgbg'Result.Foreground in 0 .. 15
                     and Parse_Colorfgbg'Result.Background in 0 .. 15);
```

### Ansi_To_RGB (FUNC-BGC-012)

```ada
function Ansi_To_RGB (Index : Natural range 0 .. 15) return RGB
  with Post => Ansi_To_RGB'Result.Red   in 0 .. 255
               and Ansi_To_RGB'Result.Green in 0 .. 255
               and Ansi_To_RGB'Result.Blue  in 0 .. 255;
```

### Provability summary

| Subprogram | Contract | Proof level |
|-----------|----------|-------------|
| `Query_Sequence` | `Post => Result'Length > 0` | Silver (trivial: two branches both return non-empty constants) |
| `Parse_RGB_Response` | `Post => Color components in 0..255` | Silver (chained from Parse_Hex_Channel postconditions) |
| `Find_RGB_Prefix` | `Post => Offset >= First+4` | Silver (prefix is 4+ bytes; offset set after prefix) |
| `Split_RGB_Channels` | `Post => channel lengths in 1..4, indices in bounds` | Silver (loop bound + slash-counting analysis) |
| `Parse_Hex_Channel` | `Post => Value in 0..255` | Silver (hex digit max = 15; normalization arithmetic bounded) |
| `Strip_OSC_Header` | `Post => Offset >= First+5, payload in bounds` | Silver (header is 5 bytes; terminator scan bounded) |
| `Parse_Colorfgbg` | `Post => indices in 0..15` | Silver (explicit range check before returning Success) |
| `Ansi_To_RGB` | `Post => components in 0..255` | Silver (constant array; every element in range) |

---

## 7. Error Handling

### Error propagation strategy

All parsing functions return discriminated records with a Success discriminant. No exceptions are raised anywhere in the BG-COLOR feature. This follows the Termicap convention established in `Termicap.TTY`, `Termicap.Color`, and `Termicap.OSC`.

### Detect_Error mapping

| Condition | Detect_Error value | Source |
|-----------|-------------------|--------|
| Probe_Session Open returns Session_No_Terminal | Not_A_Terminal | Query_Color -> Detection |
| Probe_Session Open returns Session_Not_Foreground | Not_Foreground | Query_Color -> Detection |
| Sentinel_Query returns Timed_Out = True | Query_Timeout | Query_Color -> Detection |
| Strip_OSC_Header returns Success = False | Parse_Failed | Detection |
| Parse_RGB_Response returns Success = False | Parse_Failed | Detection |
| COLORFGBG not set, or Parse_Colorfgbg fails, or index out of range | No_Fallback | Detection |

Note: In the current design, Query_Color treats all session-open failures uniformly as `Timed_Out = True, Resp_Length = 0`. The Detect functions map this to the cascade fallback. The specific Detect_Error values (Not_A_Terminal, Not_Foreground) are reserved for future refinement where Query_Color could propagate the Session_Status.

### Timeout handling (FUNC-BGC-015)

- Timeout_Ms = 0: OSC query is skipped entirely; proceeds directly to COLORFGBG fallback.
- Timeout_Ms > 30_000: clamped to 30_000 to prevent accidental indefinite blocking.
- Timeout_Ms in 1..30_000: passed through unchanged to Sentinel_Query.

---

## 8. Dependency Graph

```
┌──────────────────────────────────┐
│    Termicap.Color.Detection      │  SPARK_Mode => Off
│  Detect_Background_Color         │  (high-level cascade)
│  Detect_Foreground_Color         │
└──────┬──────────┬────────────────┘
       │          │
       │          ▼
       │  ┌─────────────────────────┐
       │  │ Termicap.Color.BG_Query │  SPARK_Mode => On
       │  │  .IO                    │  (Query_Color I/O)
       │  └──────┬──────────────────┘
       │         │
       ▼         ▼
┌──────────────────────────────────┐
│    Termicap.Color.BG_Query       │  SPARK_Mode => On
│  RGB, Parse_Result, constants,   │  (types + pure parsing)
│  Parse_RGB_Response, Ansi_To_RGB │
│  Strip_OSC_Header, etc.          │
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
                     (used by BG_Query.IO)

┌──────────────────────┐
│ Termicap.Environment │   (used by Detection for COLORFGBG)
└──────────────────────┘
```

Dependency flow (arrows point from dependent to dependency):

- `Termicap.Color.Detection` depends on `Termicap.Color.BG_Query`, `Termicap.Color.BG_Query.IO`, `Termicap.Environment`
- `Termicap.Color.BG_Query.IO` depends on `Termicap.Color.BG_Query`, `Termicap.OSC`, `Termicap.OSC.Parsing`, `Termicap.Terminal_Id`, `Termicap.Environment`
- `Termicap.Color.BG_Query` depends on `Termicap.OSC` (for Byte, Byte_Array types only)

No circular dependencies exist. The SPARK boundary is clean: `BG_Query` (SPARK On) only depends on types from `Termicap.OSC` (Byte, Byte_Array), which are SPARK-compatible `Interfaces.C.unsigned_char` and array types.

---

## 9. ADR Decisions

One ADR is filed alongside this tech spec:

1. **ADR-0016**: Discriminated record instead of functional Result type for BG-COLOR result types
   - Location: `docs/adr/0016-discriminated-record-for-bg-color-results.md`
   - Decides to use Ada discriminated records (Parse_Result, Channel_Result, Detection_Result) instead of a generic Result type from the `functional` dependency, which is not present in the project
