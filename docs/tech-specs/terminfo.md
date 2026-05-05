# Technical Specification: Terminfo Database Parsing

**Feature:** TERMINFO (Terminfo Database Parsing)
**Requirements:** `docs/requirements/terminfo.sdoc` (FUNC-TIF-001 through FUNC-TIF-020)
**Date:** 2026-05-05

---

## 1. Overview

The TERMINFO feature provides in-memory parsing of compiled ncurses terminfo binary database files to extract terminal capabilities that serve as authoritative inputs to the Termicap color detection cascade. The parser locates the correct terminfo entry via the standard `$TERM` / search-path hierarchy, reads it into a bounded byte array, and extracts: the `colors` numeric capability, `setaf`/`setab` string capabilities, and the extended `RGB` and `Tc` truecolor boolean flags.

**SPARK Level:** Silver for all parsing logic (header validation, capability extraction, extended section parsing). SPARK_Mode => Off only for the thin file-read FFI operation.

**Dependencies:**
- `Termicap.Environment` -- provides the immutable environment snapshot (TERM, TERMINFO, TERMINFO_DIRS, HOME)
- `Termicap.Color` -- integration point: the Terminfo_Snapshot feeds into the color cascade
- No external crate dependency (no `Functional` crate -- see ADR-0030)

---

## 2. Framework Survey

### Rust `term` crate (`reference-frameworks/term/src/terminfo/`)

The Rust `term` crate provides the cleanest reference implementation for compiled terminfo parsing:

1. **Search path** (`searcher.rs`): Checks `$TERMINFO`, `$HOME/.terminfo`, `$TERMINFO_DIRS` (colon-separated, with empty entries expanding to default locations), then hardcoded defaults (`/etc/terminfo`, `/usr/share/terminfo`, `/usr/lib/terminfo`, `/lib/terminfo`). For each directory, tries `<dir>/<first_char>/<term>` then `<dir>/<hex_of_first_char>/<term>`.

2. **Binary parser** (`parser/compiled.rs`): Reads magic (0x011A or 0x021E), dispatches to 16-bit or 32-bit numeric readers. Reads five header fields (names_bytes, bools_bytes, numbers_count, string_offsets_count, string_table_bytes). Processes sections sequentially: names (pipe-separated, NUL-terminated), booleans (1 byte each, skip 0/0xFF), alignment padding if `(names_bytes + bools_bytes) % 2 == 1`, numerics (skip 0xFFFF), string offsets (16-bit, skip 0xFFFF/0xFFFE), string table (NUL-terminated entries).

3. **Key design choice**: Streaming read via `io::Read` trait. Each section is consumed in order. No backtracking. Error handling via `Result<TermInfo, Error>`.

### termlib (C, `reference-frameworks/termlib/ti.c`)

A minimal standalone terminfo processor:

1. **Capability indexing**: Uses static arrays of capability names (`ti_boolnames`, `ti_numnames`, `ti_strnames`) to map indices to short names. The `colors` numeric is at index 13 in `ti_numnames`, `setaf`/`setab` at indices 359/360 in `ti_strnames` -- consistent with ncurses definitions.

2. **Buffer-based parsing**: Loads the entire file into a buffer, then performs offset arithmetic. This approach simplifies bounds checking and matches the SPARK requirement.

3. **Extended section**: Parses user-defined capabilities by name string lookup in the extended string table.

### wezterm/termwiz (Rust, `reference-frameworks/wezterm/termwiz/src/render/terminfo.rs`)

Uses the `terminfo` crate for database loading. Relevant patterns:

1. **MaxColors capability**: Checks `MaxColors` numeric capability; if too large (e.g., 16777216 from xterm-direct), falls back to indexed-colour rendering for 256-colour sequences.

2. **RGB flag**: Cross-checks the `RGB` extended capability with the `MaxColors` value to determine if direct-color rendering is appropriate.

### notcurses (C)

Relies heavily on terminfo for capability detection. Tracks palette size and RGB flag independently rather than using a single level enum. Uses the `colors` numeric as the primary authority for colour depth, with `RGB`/`Tc` as secondary truecolor indicators.

### Design Lessons from Reference Frameworks

| Aspect | Consensus Pattern | Termicap Approach |
|--------|------------------|-------------------|
| File loading | Load entire file into buffer | Same: bounded byte array, stack-allocatable |
| Format detection | Magic number check first | Same: Detect_Format pure function |
| Numeric byte order | Always little-endian, regardless of host | Same: explicit byte reconstruction |
| Extended section | Optional, not an error if absent | Same: absent = Has_RGB_Flag = False |
| Error reporting | Return error rather than crash | Same: discriminated result type |

---

## 3. Package Structure

```
Termicap.Terminfo              [SPARK Silver (spec + body)] -- types, constants, pure parsing functions
Termicap.Terminfo.IO           [SPARK_Mode => Off]          -- Read_File FFI, Parse_Terminfo entry point
```

### `Termicap.Terminfo`

**File:** `src/termicap-terminfo.ads`, `src/termicap-terminfo.adb`
**SPARK_Mode:** On (spec and body)
**Dependencies:** None (leaf package, operates on raw byte arrays)

Contains:
- All public types (Terminfo_Snapshot, Terminfo_Format, Parsed_Header, Extended_Header, Boolean_Cap_Value, Terminfo_Error, Terminfo_Result)
- All named constants (MAX_*, ABSENT_NUMERIC, CANCELLED_NUMERIC, COLORS_INDEX, SETAF_INDEX, SETAB_INDEX)
- All pure parsing functions (Detect_Format, Parse_Header, Get_Boolean, Get_Numeric, Get_String, Parse_Extended_Header, Extract_Truecolor_Flags)
- Ghost functions (Header_Is_Valid, Extended_Is_Valid)

### `Termicap.Terminfo.IO`

**File:** `src/termicap-terminfo-io.ads`, `src/termicap-terminfo-io.adb`
**SPARK_Mode:** Off (body); On (spec, for callable contracts)
**Dependencies:** `Termicap.Environment`, `Termicap.Terminfo`

Contains:
- `Read_File` procedure (POSIX open/read/close FFI)
- `Parse_Terminfo` entry function (search path resolution + file read + parse orchestration)
- `Read_Error` type (declared in the spec so callers can reference it)

This split follows the established pattern from `Termicap.OSC` / `Termicap.OSC.Parsing`: pure logic in the SPARK parent, impure I/O in a child package with SPARK_Mode => Off.

---

## 4. Type Definitions

### Core Types (in `Termicap.Terminfo`)

```ada
--  Terminfo binary format variant
type Terminfo_Format is (Legacy_16bit, Extended_32bit, Unknown);

--  Boolean capability result
type Boolean_Cap_Value is (Absent, Cancelled, True_Value, False_Value);

--  Read operation status (SPARK-visible)
type Read_Error is (Read_OK, Read_Not_Found, Read_IO_Error, Read_Too_Large);

--  Error codes for the overall parse operation
type Terminfo_Error is
  (Error_No_Term,
   Error_File_Not_Found,
   Error_IO_Failure,
   Error_Invalid_Magic,
   Error_Header_Corrupt,
   Error_File_Too_Large,
   Error_Encoding);

--  Byte types (compatible with Interfaces.C.unsigned_char)
subtype Byte is Interfaces.C.unsigned_char;
type Byte_Array is array (Positive range <>) of Byte;

--  Bounded string for capability values
MAX_CAPABILITY_STRING_LENGTH : constant := 64;
subtype Capability_String_Index is Natural range 0 .. MAX_CAPABILITY_STRING_LENGTH;
type Capability_String is record
   Data   : String (1 .. MAX_CAPABILITY_STRING_LENGTH) := [others => ' '];
   Length : Capability_String_Index := 0;
end record;

--  Bounded string for terminal name
MAX_TERM_NAME_LENGTH : constant := 64;
type Term_Name_String is record
   Data   : String (1 .. MAX_TERM_NAME_LENGTH) := [others => ' '];
   Length : Natural range 0 .. MAX_TERM_NAME_LENGTH := 0;
end record;

--  The immutable snapshot
type Terminfo_Snapshot is record
   Colors       : Integer := ABSENT_NUMERIC;
   Has_Setaf    : Boolean := False;
   Has_Setab    : Boolean := False;
   Setaf        : Capability_String;
   Setab        : Capability_String;
   Has_RGB_Flag : Boolean := False;
   Has_Tc_Flag  : Boolean := False;
   Term_Name    : Term_Name_String;
end record;

--  Discriminated result type
type Terminfo_Result (Success : Boolean := False) is record
   case Success is
      when True  => Snapshot : Terminfo_Snapshot;
      when False => Error    : Terminfo_Error;
   end case;
end record;
```

### Internal Types (in `Termicap.Terminfo` private or body)

```ada
--  Parsed header from the binary file
type Parsed_Header is record
   Format       : Terminfo_Format := Unknown;
   Names_Size   : Natural := 0;
   Bool_Count   : Natural := 0;
   Num_Count    : Natural := 0;
   String_Count : Natural := 0;
   Table_Size   : Natural := 0;
   --  Computed offsets (validated against buffer size)
   Bool_Section_Offset   : Positive := 1;
   Num_Section_Offset    : Positive := 1;
   String_Table_Offset   : Positive := 1;
   String_Data_Offset    : Positive := 1;
   Total_Standard_Size   : Positive := 1;
end record;

--  Extended section header
type Extended_Header is record
   Ext_Bool_Count      : Natural := 0;
   Ext_Num_Count       : Natural := 0;
   Ext_String_Count    : Natural := 0;
   Ext_String_Entries  : Natural := 0;
   Ext_Table_Size      : Natural := 0;
   --  Computed offsets within the buffer
   Ext_Start           : Positive := 1;
   Ext_Bool_Offset     : Positive := 1;
   Ext_Num_Offset      : Positive := 1;
   Ext_Str_Table_Offset : Positive := 1;
   Ext_Data_Offset     : Positive := 1;
end record;
```

---

## 5. Algorithm Design

### 5.1 Search Path Resolution (`Parse_Terminfo` in `Termicap.Terminfo.IO`)

```
1. Read TERM from Environment snapshot
   - If absent or empty -> return Error_No_Term

2. Build candidate directory list (bounded array, max 32 entries):
   a. If TERMINFO is set and non-empty, add it
   b. If TERMINFO_DIRS is set, split on ':' and add each (up to 16 entries)
   c. If HOME is set, add HOME & "/.terminfo"
   d. Add "/usr/share/terminfo"
   e. Add "/etc/terminfo"
   f. Add "/lib/terminfo"

3. For each candidate directory D:
   a. Construct primary path: D / TERM(1) / TERM
   b. Call Read_File(primary_path, Buffer, Size, Error)
   c. If Read_OK -> proceed to parse (step 4)
   d. If Read_Not_Found -> construct alternate path: D / hex(TERM(1)) / TERM
   e. Call Read_File(alternate_path, Buffer, Size, Error)
   f. If Read_OK -> proceed to parse (step 4)
   g. If Read_Too_Large -> continue to next candidate (non-fatal)
   h. If Read_IO_Error -> continue to next candidate (non-fatal)

4. If no file found -> return Error_File_Not_Found
```

### 5.2 Binary Parsing Pipeline (all in SPARK Silver `Termicap.Terminfo`)

```
1. Detect_Format(Buffer, Size) -> Format
   - If Unknown -> return Error_Invalid_Magic

2. Parse_Header(Buffer, Size, Format) -> (Header, OK)
   - Reads 5 x 16-bit LE fields at offsets 2..11
   - Validates all MAX_* bounds
   - Computes section offsets with alignment padding
   - Validates total size <= Size
   - If invalid -> return Error_Header_Corrupt

3. Get_Numeric(Buffer, Header, Format, COLORS_INDEX) -> Colors

4. Get_String(Buffer, Header, SETAF_INDEX) -> (Setaf, Has_Setaf)

5. Get_String(Buffer, Header, SETAB_INDEX) -> (Setab, Has_Setab)

6. If Total_Standard_Size + 10 <= Size:  -- room for extended header?
   Parse_Extended_Header(Buffer, Size, Header) -> (Ext, Ext_Valid)
   If Ext_Valid:
     Extract_Truecolor_Flags(Buffer, Header, Ext, Format) -> (Has_RGB, Has_Tc)
   Else:
     Has_RGB := False; Has_Tc := False

7. Construct Terminfo_Snapshot; return success
```

### 5.3 Extended Section Name Resolution

The extended section interleaves values and names in a single string table. The algorithm to find "RGB" and "Tc":

```
Given: Ext_Bool_Count booleans, Ext_Num_Count numerics, Ext_Str_Count pure-string caps

Total name entries = Ext_Bool_Count + Ext_Num_Count + Ext_Str_Count
where Ext_Str_Count = Ext_String_Count - Ext_Bool_Count - Ext_Num_Count
       (Ext_String_Entries in header includes BOTH value offsets and name offsets)

Name offsets start at: Ext_Str_Table_Offset + Ext_Str_Count * 2
  (after the string value offset entries)

For each name index I in 0 .. Total_Name_Count - 1:
  Read 16-bit offset at name_offsets_start + I * 2
  Read NUL-terminated name from Ext_Data_Offset + offset
  Compare name against "RGB" and "Tc"
  If match:
    Determine capability type by position:
      I < Ext_Bool_Count -> extended boolean at Ext_Bool_Offset + I
      I < Ext_Bool_Count + Ext_Num_Count -> extended numeric
      Otherwise -> extended string
    Extract value accordingly
```

---

## 6. Binary Format Layout

### Standard Format (ncurses term(5))

```
Offset  Size   Content
------  ----   -------
0       2      Magic number (0x011A or 0x021E), little-endian
2       2      Names_Size (bytes, includes trailing NUL)
4       2      Bool_Count (number of boolean capabilities)
6       2      Num_Count (number of numeric capabilities)
8       2      String_Count (number of string offset entries)
10      2      Table_Size (bytes in string data table)
12      N      Names section (pipe-separated names, NUL-terminated)
12+N    B      Boolean section (1 byte per capability)
        0..1   Alignment padding (if (N+B) is odd)
               Numeric section (Num_Size bytes per capability, LE)
               String offset table (2 bytes per entry, LE signed)
               String data table (NUL-terminated strings)
```

Where `Num_Size = 2` for magic 0x011A, `Num_Size = 4` for magic 0x021E.

### Extended Section (follows immediately after standard string data)

```
Offset  Size   Content
------  ----   -------
+0      0..1   Alignment padding (to reach even offset from file start)
+P      2      Ext_Bool_Count
+P+2    2      Ext_Num_Count
+P+4    2      Ext_String_Count (total string entries = values + names)
+P+6    2      Ext_String_Entries (same as Ext_String_Count in practice)
+P+8    2      Ext_Table_Size
+P+10   EB     Extended boolean values (1 byte each)
        0..1   Alignment padding (if EB is odd)
               Extended numeric values (Num_Size bytes each, LE)
               Extended string offset table (2 bytes per entry)
               Extended string data table (NUL-terminated strings)
```

### Byte Reconstruction (little-endian)

```ada
--  16-bit signed from two bytes
Value_16 : Integer := Integer (Buffer (Offset)) +
                      Integer (Buffer (Offset + 1)) * 256;
if Value_16 >= 32768 then
   Value_16 := Value_16 - 65536;  -- sign extension
end if;

--  32-bit signed from four bytes
Value_32 : Integer := Integer (Buffer (Offset)) +
                      Integer (Buffer (Offset + 1)) * 256 +
                      Integer (Buffer (Offset + 2)) * 65536 +
                      Integer (Buffer (Offset + 3)) * 16777216;
--  (with sign extension for negative values)
```

---

## 7. SPARK Contracts

### Ghost Functions

```ada
--  Encapsulates all structural invariants from Parse_Header
function Header_Is_Valid
  (Buffer : Byte_Array; Header : Parsed_Header) return Boolean
is (Header.Format /= Unknown
    and then Header.Names_Size >= 1
    and then Header.Names_Size <= MAX_NAMES_SECTION_SIZE
    and then Header.Bool_Count <= MAX_BOOL_COUNT
    and then Header.Num_Count <= MAX_NUM_COUNT
    and then Header.String_Count <= MAX_STRING_COUNT
    and then Header.Table_Size <= MAX_STRING_TABLE_SIZE
    and then Header.Bool_Section_Offset >= 1
    and then Header.Total_Standard_Size <= Buffer'Length)
with Ghost;

--  Encapsulates extended section invariants
function Extended_Is_Valid
  (Buffer : Byte_Array; Header : Parsed_Header; Ext : Extended_Header) return Boolean
is (Header_Is_Valid (Buffer, Header)
    and then Ext.Ext_Bool_Count <= 64
    and then Ext.Ext_Num_Count <= 128
    and then Ext.Ext_String_Count <= 256
    and then Ext.Ext_Table_Size <= 8192
    and then Ext.Ext_Data_Offset + Ext.Ext_Table_Size <= Buffer'Length + 1)
with Ghost;
```

### Key Pre/Post Contracts

```ada
function Detect_Format (Buffer : Byte_Array; Size : Natural) return Terminfo_Format
with Pre  => Size >= 2 and then Size <= Buffer'Length,
     Post => Detect_Format'Result in Legacy_16bit | Extended_32bit | Unknown;

procedure Parse_Header
  (Buffer  :     Byte_Array;
   Size    :     Natural;
   Format  :     Terminfo_Format;
   Header  : out Parsed_Header;
   Success : out Boolean)
with Pre  => Size >= 12 and then Size <= Buffer'Length and then Format /= Unknown,
     Post => (if Success then Header_Is_Valid (Buffer, Header));

function Get_Numeric
  (Buffer : Byte_Array;
   Header : Parsed_Header;
   Format : Terminfo_Format;
   Index  : Natural) return Integer
with Pre  => Header_Is_Valid (Buffer, Header) and then Format /= Unknown,
     Post => Get_Numeric'Result >= -2;

procedure Get_String
  (Buffer  :     Byte_Array;
   Header  :     Parsed_Header;
   Index   :     Natural;
   Result  : out Capability_String;
   Present : out Boolean)
with Pre  => Header_Is_Valid (Buffer, Header),
     Post => (if not Present then Result.Length = 0);
```

### Loop Variants

All loops over byte arrays use explicit loop variants:

```ada
--  String copy loop (Get_String)
loop
   pragma Loop_Variant (Increases => Copy_Index);
   pragma Loop_Invariant (Copy_Index >= 1 and Copy_Index <= MAX_CAPABILITY_STRING_LENGTH + 1);
   exit when Copy_Index > MAX_CAPABILITY_STRING_LENGTH;
   exit when Buffer (String_Start + Copy_Index - 1) = 0;
   Result.Data (Copy_Index) := Character'Val (Natural (Buffer (String_Start + Copy_Index - 1)));
   Copy_Index := Copy_Index + 1;
end loop;

--  Name search loop (Extract_Truecolor_Flags)
for I in 0 .. Total_Name_Count - 1 loop
   pragma Loop_Variant (Increases => I);
   pragma Loop_Invariant (I >= 0 and I < Total_Name_Count);
   --  ...compare name at offset against "RGB" / "Tc"...
end loop;
```

---

## 8. Integration

### Color Cascade Integration Point (FUNC-TIF-017)

The `Terminfo_Snapshot` is consumed by `Termicap.Color.Detect_Color_Level` as a passive advisory source. The integration is implemented in `Termicap.Capabilities` (the aggregation layer), which calls `Parse_Terminfo` once and passes the result to the color cascade.

```
Termicap.Capabilities.Detect:
  1. Capture environment snapshot
  2. Detect TTY
  3. Call Parse_Terminfo(Env) -> Terminfo_Result
  4. Call Detect_Color_Level(Env, Is_TTY, Terminfo_Source)
     where Terminfo_Source is derived from Terminfo_Result
```

The color cascade applies terminfo data at a specific priority level (after FORCE_COLOR, COLORTERM, TERM suffix matching; before active OSC probing):

```ada
--  In the cascade logic:
if Terminfo_Source.Colors >= 16_777_216 then
   Level := Color_Level'Max (Level, True_Color);
elsif Terminfo_Source.Has_RGB_Flag or Terminfo_Source.Has_Tc_Flag then
   Level := Color_Level'Max (Level, True_Color);
elsif Terminfo_Source.Colors >= 256 then
   Level := Color_Level'Max (Level, Extended_256);
elsif Terminfo_Source.Colors >= 8 then
   Level := Color_Level'Max (Level, Basic_16);
end if;
```

The `Color_Level'Max` idiom ensures terminfo can only raise the detected level, never lower it (advisory semantics).

### Dependency Graph Addition

```
Termicap.Terminfo          [leaf -- no Termicap dependencies]
Termicap.Terminfo.IO       [depends on Termicap.Environment, Termicap.Terminfo]
Termicap.Capabilities      [depends on Termicap.Terminfo.IO (new)]
```

---

## 9. Error Handling

### Error Flow Diagram

```
Parse_Terminfo
  ├── TERM absent/empty ─────────────────────────────> Error_No_Term
  ├── Search loop: all paths exhausted ──────────────> Error_File_Not_Found
  ├── Read_File returns Read_Too_Large ──────────────> (continue search)
  ├── Read_File returns Read_IO_Error ───────────────> (continue search)
  ├── Detect_Format returns Unknown ─────────────────> Error_Invalid_Magic
  ├── Parse_Header fails validation ─────────────────> Error_Header_Corrupt
  └── Parse succeeds ───────────────────────────────── Success (Terminfo_Snapshot)
```

### Design Principles

1. **No exceptions propagate.** The FFI `Read_File` catches all I/O exceptions internally and converts them to `Read_Error` values. All SPARK On code is exception-free by construction (proven by GNATprove).

2. **First-found-file semantics.** Once a terminfo file is located and opened successfully, the parser commits to it. Corruption errors (Invalid_Magic, Header_Corrupt) are returned immediately -- no fallback to lower-priority directories. This prevents silent data corruption.

3. **Extended section tolerance.** If the extended section is absent, malformed, or has unexpected structure, the parser sets Has_RGB_Flag and Has_Tc_Flag to False and returns success. Extended section issues are never fatal.

4. **Callers test discriminant.** The `Terminfo_Result` discriminated record forces callers to test `Success` before accessing `Snapshot`. SPARK contracts prevent accessing the wrong variant.

---

## 10. Test Strategy

### Unit Tests (pure parsing functions)

1. **Known-good binary files**: Include compiled terminfo binaries for common terminals in `tests/data/terminfo/`:
   - `xterm-256color` -- Legacy format, colors=256, setaf/setab present, no extended section
   - `tmux-256color` -- Extended section with `Tc` boolean flag
   - `xterm-direct` -- Extended-numeric format (0x021E), colors=16777216, `RGB` flag

2. **Crafted binary files** for edge cases:
   - Minimum valid file (12-byte header, 1-byte names section, nothing else)
   - File with extended boolean `RGB` as numeric (value=8) instead of boolean
   - File with only `Tc` as string capability (non-empty value)
   - File with cancelled capabilities (ABSENT_NUMERIC, CANCELLED_BOOLEAN)
   - Truncated file (header claims more data than available)
   - Wrong magic number (0xDEAD)
   - Legacy format with alignment padding (odd names + bools sum)

3. **Property-based assertions**:
   - `Parse_Header` on any valid file returns offsets within `0 .. Size - 1`
   - `Get_Numeric` always returns >= -2
   - `Get_String` with `Present = False` always has `Result.Length = 0`

### Integration Tests

1. **Real system terminfo** (when available): Read `/usr/share/terminfo/x/xterm-256color` and verify `Colors = 256`, `Has_Setaf = True`.

2. **Missing terminfo**: Test with empty Environment (no TERM) -> Error_No_Term.

3. **Color cascade integration**: Verify that a Terminfo_Snapshot with `Colors = 256` results in `Color_Level >= Extended_256` from the cascade.

### SPARK Proof Targets

- `gnatprove -P termicap.gpr --level=2` on `termicap-terminfo.ads` and `termicap-terminfo.adb` with zero unproven VCs.
- All array accesses, loop bounds, and type conversions discharged.

### Test Data Source

Test binary files can be generated from known terminal descriptions using:
```bash
infocmp -x xterm-256color | tic -o tests/data/terminfo -x /dev/stdin
```

Or by including the binary files from `reference-frameworks/termlib/test/terminfo/` which already contain crafted good/bad examples (e.g., `xterm-new`, `xterm-color`, `xterm-badfile`).

---

## 11. Named Constants Summary

| Constant | Value | Purpose |
|----------|-------|---------|
| MAX_TERMINFO_FILE_SIZE | 32_768 | Maximum file size accepted (SPARK buffer bound) |
| MAX_NAMES_SECTION_SIZE | 512 | Header validation |
| MAX_BOOL_COUNT | 64 | Header validation |
| MAX_NUM_COUNT | 512 | Header validation |
| MAX_STRING_COUNT | 512 | Header validation |
| MAX_STRING_TABLE_SIZE | 16_384 | Header validation |
| MAX_CAPABILITY_STRING_LENGTH | 64 | Bounded string capacity |
| MAX_TERM_NAME_LENGTH | 64 | Terminal name capacity |
| MAX_PATH_LENGTH | 512 | Path construction bound |
| ABSENT_NUMERIC | -1 | ncurses absent sentinel |
| CANCELLED_NUMERIC | -2 | ncurses cancelled sentinel |
| COLORS_INDEX | 13 | Standard ncurses index for `colors` |
| SETAF_INDEX | 359 | Standard ncurses index for `setaf` |
| SETAB_INDEX | 360 | Standard ncurses index for `setab` |
| HEADER_SIZE | 12 | Fixed header size in bytes |
| MAGIC_LEGACY | 16#011A# | Legacy 16-bit format magic |
| MAGIC_EXTENDED | 16#021E# | Extended 32-bit format magic |

---

## 12. Platform Considerations

- **Windows**: The TERMINFO feature is POSIX-only (file paths use forward slashes, search directories are Unix paths). On Windows, `Parse_Terminfo` will return `Error_File_Not_Found` unconditionally since none of the standard paths exist. This is correct: Windows terminals do not use terminfo databases; Windows colour detection relies on `GetConsoleMode` and VT processing (handled by `Termicap.Win32_Color`).

- **macOS**: The hex-digit alternate path (`<dir>/78/xterm-256color` for the `x` prefix) is used by macOS. The primary path (`<dir>/x/xterm-256color`) is tried first, matching ncurses behaviour.

- **Endianness**: All multi-byte values are stored little-endian in the terminfo binary regardless of host. The parser always reconstructs integers from bytes explicitly -- no `Unchecked_Conversion` from byte arrays to integer types.
