# API Reference: `Termicap.Terminfo` and `Termicap.Terminfo.IO`

Package pair providing SPARK Silver-provable terminfo binary parsing and a POSIX file I/O boundary for terminfo database lookup. Together they implement the complete terminfo search-path resolution, file read, and binary parse pipeline.

**Files:**
- `src/termicap-terminfo.ads`, `src/termicap-terminfo.adb`
- `src/termicap-terminfo-io.ads`, `src/termicap-terminfo-io.adb`

**SPARK_Mode:** `Termicap.Terminfo` — On (spec and body, Silver level); `Termicap.Terminfo.IO` — Off (spec and body)
**License:** Apache-2.0

---

## Overview

The TERMINFO feature reads the compiled terminfo database entry for the active terminal (`$TERM`) and extracts the capabilities relevant to color detection: the `colors` numeric capability, the `setaf` and `setab` string capabilities (ANSI SGR foreground/background), and the extended `RGB` and `Tc` truecolor flags.

`Termicap.Terminfo` contains all SPARK-provable building blocks: discrete types, bounded string types, named constants for all magic numbers and capability indices, ghost predicates that bundle header structural invariants, and the full pure parsing pipeline from magic-number detection through truecolor flag extraction. All parsing functions carry `Global => null` (or explicit structural preconditions) and are verifiable at SPARK Silver level.

`Termicap.Terminfo.IO` contains the I/O boundary: `Read_File` opens a single file path and reads its bytes, while `Parse_Terminfo` orchestrates the full search-path resolution and delegates binary parsing to `Parse_Buffer` in the parent package. Both have `SPARK_Mode => Off` because they perform POSIX `open`/`read`/`close` system calls and build path strings dynamically.

Two ncurses terminfo binary format variants are supported:
- **`Legacy_16bit`** (magic `0x011A`): numeric fields are 16-bit signed little-endian integers.
- **`Extended_32bit`** (magic `0x021E`): numeric fields are 32-bit signed little-endian integers. Introduced in ncurses 6.1 (2018).

**Key distinction from active-probing packages:** `Termicap.Terminfo.IO` does not use a `Probe_Session` or open a TTY device. The terminfo database is a static filesystem artifact and can be read in non-TTY contexts.

The typical call patterns are:

- **Single call (recommended):** `Parse_Terminfo (Env)` — accepts an `Environment` snapshot, returns a `Terminfo_Result` directly.
- **Buffer-only (testing or custom I/O):** load a `Byte_Array` by any means, call `Parse_Buffer (Buffer, Size)`.
- **Step-by-step:** call `Detect_Format`, `Parse_Header`, individual capability extractors (`Get_Boolean`, `Get_Numeric`, `Get_String`), `Parse_Extended_Header`, and `Extract_Truecolor_Flags` in sequence.

---

## Package `Termicap.Terminfo`

### Types

#### `Terminfo_Format`

```ada
type Terminfo_Format is (Legacy_16bit, Extended_32bit, Unknown);
```

Identifies the binary format variant detected from the magic number.

| Literal | Magic | Description |
|---------|-------|-------------|
| `Legacy_16bit` | `0x011A` | Numeric fields are 2-byte signed little-endian integers. |
| `Extended_32bit` | `0x021E` | Numeric fields are 4-byte signed little-endian integers. ncurses 6.1+. |
| `Unknown` | any other | First two bytes do not match a recognised magic value. |

**Requirements:** FUNC-TIF-007

---

#### `Boolean_Cap_Value`

```ada
type Boolean_Cap_Value is (Absent, Cancelled, True_Value, False_Value);
```

Four-valued result for standard boolean capability extraction. Maps the ncurses byte conventions:

| Literal | Byte | Meaning |
|---------|------|---------|
| `True_Value` | `0x01` | Capability is present and set. |
| `False_Value` | `0x00` | Capability is present but cleared. |
| `Cancelled` | `0xFF` | Explicitly cancelled (`ABSENT_BOOLEAN`). |
| `Absent` | `0xFE` or any other | Absent (`CANCELLED_BOOLEAN`) or unrecognised byte. |

**Requirements:** FUNC-TIF-009

---

#### `Read_Error`

```ada
type Read_Error is (Read_OK, Read_Not_Found, Read_IO_Error, Read_Too_Large);
```

Status codes for the `Read_File` file-loading operation. Declared in the SPARK On parent package so that SPARK callers can reference the type in contracts; `Read_File` itself lives in `Termicap.Terminfo.IO`.

| Literal | Meaning |
|---------|---------|
| `Read_OK` | File read successfully; `Size` bytes placed in `Buffer`. |
| `Read_Not_Found` | File does not exist or cannot be opened. |
| `Read_IO_Error` | File found but an I/O error occurred during reading. |
| `Read_Too_Large` | File size exceeds `MAX_TERMINFO_FILE_SIZE` (32 KiB). |

**Requirements:** FUNC-TIF-006

---

#### `Terminfo_Error`

```ada
type Terminfo_Error is
  (Error_No_Term,
   Error_File_Not_Found,
   Error_IO_Failure,
   Error_Invalid_Magic,
   Error_Header_Corrupt,
   Error_File_Too_Large,
   Error_Encoding);
```

Error codes for the overall terminfo parse operation. Each literal maps to a distinct failure mode in the pipeline.

| Literal | Meaning |
|---------|---------|
| `Error_No_Term` | `TERM` environment variable is not set or is empty. |
| `Error_File_Not_Found` | No terminfo file found for `TERM` in any searched directory. |
| `Error_IO_Failure` | Terminfo file found but could not be read. |
| `Error_Invalid_Magic` | First two bytes do not match a recognised magic number. |
| `Error_Header_Corrupt` | Header field sizes are inconsistent or cause out-of-bounds access. |
| `Error_File_Too_Large` | File size exceeds `MAX_TERMINFO_FILE_SIZE`. |
| `Error_Encoding` | A string capability contains bytes outside the expected range. |

**Requirements:** FUNC-TIF-002

---

#### `Capability_String`

```ada
type Capability_String is record
   Data   : String (1 .. MAX_CAPABILITY_STRING_LENGTH) := [others => ' '];
   Length : Capability_String_Index := 0;
end record;
```

Bounded string holding an extracted terminfo string capability value. `Data (1 .. Length)` contains the significant characters; bytes beyond `Length` are initialised to spaces and carry no meaning. Bounded strings are required for SPARK provability — unbounded strings involve heap allocation.

`MAX_CAPABILITY_STRING_LENGTH` is `64`. `Capability_String_Index` is `Natural range 0 .. 64`.

**Requirements:** FUNC-TIF-001

---

#### `Term_Name_String`

```ada
type Term_Name_String is record
   Data   : String (1 .. MAX_TERM_NAME_LENGTH) := [others => ' '];
   Length : Natural range 0 .. MAX_TERM_NAME_LENGTH := 0;
end record;
```

Bounded string holding the primary terminal name extracted from the names section of the terminfo binary (the text before the first `|` separator, NUL-terminated). `MAX_TERM_NAME_LENGTH` is `64`.

**Requirements:** FUNC-TIF-001

---

#### `Terminfo_Snapshot`

```ada
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
```

Immutable record of the terminfo capabilities relevant to color detection. Plain Ada record (not tagged, not limited, not controlled) to ensure value-copy semantics. Default-constructed value represents "no capabilities detected".

| Field | Default | Description |
|-------|---------|-------------|
| `Colors` | `ABSENT_NUMERIC` (−1) | Value of the `colors` numeric capability. `ABSENT_NUMERIC` when absent; `CANCELLED_NUMERIC` (−2) when cancelled. |
| `Has_Setaf` | `False` | `True` when `setaf` is present and non-empty. |
| `Has_Setab` | `False` | `True` when `setab` is present and non-empty. |
| `Setaf` | empty | Raw value of `setaf`; empty when `Has_Setaf = False`. |
| `Setab` | empty | Raw value of `setab`; empty when `Has_Setab = False`. |
| `Has_RGB_Flag` | `False` | `True` when the extended `RGB` truecolor flag is present and set. |
| `Has_Tc_Flag` | `False` | `True` when the extended `Tc` truecolor flag is present and set. |
| `Term_Name` | empty | Primary terminal name from the names section. |

**Requirements:** FUNC-TIF-001, FUNC-TIF-016

---

#### `Terminfo_Result`

```ada
type Terminfo_Result (Success : Boolean := False) is record
   case Success is
      when True =>
         Snapshot : Terminfo_Snapshot;
      when False =>
         Error : Terminfo_Error;
   end case;
end record;
```

Discriminated result type wrapping either a `Terminfo_Snapshot` or a `Terminfo_Error` code. The discriminant `Success` forces callers to test the variant before accessing `Snapshot` or `Error`. Default discriminant `False` ensures default-initialised values represent failure.

**Example:**
```ada
declare
   Result : constant Terminfo_Result :=
     Termicap.Terminfo.IO.Parse_Terminfo (Env);
begin
   if Result.Success then
      if Result.Snapshot.Has_RGB_Flag then
         --  Terminal advertises RGB truecolor via terminfo
      end if;
   elsif Result.Error = Error_File_Not_Found then
      --  Terminfo not available; use environment variable fallback
   end if;
end;
```

**Requirements:** FUNC-TIF-002

---

#### `Parsed_Header` (internal, public for SPARK visibility)

```ada
type Parsed_Header is record
   Format              : Terminfo_Format := Unknown;
   Names_Size          : Natural := 0;
   Bool_Count          : Natural := 0;
   Num_Count           : Natural := 0;
   String_Count        : Natural := 0;
   Table_Size          : Natural := 0;
   Bool_Section_Offset : Positive := 1;
   Num_Section_Offset  : Positive := 1;
   String_Table_Offset : Positive := 1;
   String_Data_Offset  : Positive := 1;
   Total_Standard_Size : Positive := 1;
end record;
```

Parsed binary header result for the standard terminfo sections. Produced by `Parse_Header`. All offset fields are 1-based buffer indices. Declared public because it appears as a parameter of the ghost predicate `Header_Is_Valid`, which is referenced in the preconditions of the public parsing functions.

Access is only safe when `Header_Is_Valid (Buffer, Header)` holds.

**Requirements:** FUNC-TIF-008

---

#### `Extended_Header` (internal, public for SPARK visibility)

```ada
type Extended_Header is record
   Ext_Bool_Count       : Natural := 0;
   Ext_Num_Count        : Natural := 0;
   Ext_String_Count     : Natural := 0;
   Ext_String_Entries   : Natural := 0;
   Ext_Table_Size       : Natural := 0;
   Ext_Start            : Positive := 1;
   Ext_Bool_Offset      : Positive := 1;
   Ext_Num_Offset       : Positive := 1;
   Ext_Str_Table_Offset : Positive := 1;
   Ext_Data_Offset      : Positive := 1;
end record;
```

Parsed extended-section header and offset cache. Produced by `Parse_Extended_Header`. Declared public for the same reason as `Parsed_Header` — it appears in the ghost predicate `Extended_Is_Valid`.

Access is only safe when `Extended_Is_Valid (Buffer, Header, Ext)` holds.

**Requirements:** FUNC-TIF-012

---

### Constants

#### Size and Bound Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_TERMINFO_FILE_SIZE` | `32_768` | Maximum accepted file size in bytes (32 KiB). Files larger than this are rejected with `Read_Too_Large` before any parsing is attempted. |
| `MAX_NAMES_SECTION_SIZE` | `512` | Maximum byte length of the names section (includes trailing NUL). |
| `MAX_BOOL_COUNT` | `64` | Maximum number of standard boolean capabilities. |
| `MAX_NUM_COUNT` | `512` | Maximum number of standard numeric capabilities. |
| `MAX_STRING_COUNT` | `512` | Maximum number of standard string capability offset entries. |
| `MAX_STRING_TABLE_SIZE` | `16_384` | Maximum byte size of the string data table. |
| `MAX_CAPABILITY_STRING_LENGTH` | `64` | Maximum character length of an extracted capability string value. |
| `MAX_TERM_NAME_LENGTH` | `64` | Maximum character length of the terminal name. |
| `MAX_PATH_LENGTH` | `512` | Maximum character length of a constructed terminfo file path. |
| `HEADER_SIZE` | `12` | Fixed byte size of the standard terminfo binary header (2 bytes magic + 5 × 2-byte fields). |

**Requirements:** FUNC-TIF-001, FUNC-TIF-002, FUNC-TIF-005, FUNC-TIF-008

---

#### Magic Number Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAGIC_LEGACY` | `16#011A#` | Magic number for the legacy 16-bit format. Little-endian bytes `0x1A 0x01`. |
| `MAGIC_EXTENDED` | `16#021E#` | Magic number for the extended 32-bit format. Little-endian bytes `0x1E 0x02`. Introduced in ncurses 6.1 (2018). |

**Requirements:** FUNC-TIF-007

---

#### Numeric Sentinel Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `ABSENT_NUMERIC` | `−1` | Capability is not present. Matches ncurses `ABSENT_NUMERIC`. |
| `CANCELLED_NUMERIC` | `−2` | Capability has been explicitly cancelled. Matches ncurses `CANCELLED_NUMERIC`. |

**Requirements:** FUNC-TIF-010

---

#### Capability Index Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `COLORS_INDEX` | `13` | Standard ncurses index of the `colors` numeric capability. Stable across all ncurses versions since 5.x. |
| `SETAF_INDEX` | `359` | Standard ncurses index of the `setaf` (set_a_foreground) string capability. |
| `SETAB_INDEX` | `360` | Standard ncurses index of the `setab` (set_a_background) string capability. |

**Requirements:** FUNC-TIF-010, FUNC-TIF-011

---

### Ghost Predicates

#### `Header_Is_Valid`

```ada
function Header_Is_Valid
  (Buffer : Byte_Array; Header : Parsed_Header) return Boolean
with Ghost;
```

Ghost predicate encapsulating all structural invariants established by `Parse_Header`. Asserting `Header_Is_Valid (Buffer, Header)` in a precondition gives GNATprove the complete set of bounds facts needed to discharge array-index checks in `Get_Boolean`, `Get_Numeric`, `Get_String`, and `Parse_Extended_Header` without requiring those contracts to enumerate every individual field constraint.

When `Header_Is_Valid` holds, the following facts are known:
- `Header.Format /= Unknown`
- `1 <= Header.Names_Size <= MAX_NAMES_SECTION_SIZE`
- `Header.Bool_Count <= MAX_BOOL_COUNT`
- `Header.Num_Count <= MAX_NUM_COUNT`
- `Header.String_Count <= MAX_STRING_COUNT`
- `Header.Table_Size <= MAX_STRING_TABLE_SIZE`
- `Header.Bool_Section_Offset >= 1`
- `Header.Total_Standard_Size <= Buffer'Length`

**Requirements:** FUNC-TIF-018

---

#### `Extended_Is_Valid`

```ada
function Extended_Is_Valid
  (Buffer : Byte_Array; Header : Parsed_Header; Ext : Extended_Header)
   return Boolean
with Ghost;
```

Ghost predicate encapsulating extended section structural invariants. Implies `Header_Is_Valid` so that callers only need to assert `Extended_Is_Valid` to obtain all bounds facts for both the standard and extended sections. Required in the precondition of `Extract_Truecolor_Flags`.

**Requirements:** FUNC-TIF-018

---

### Functions and Procedures

#### `Detect_Format`

```ada
function Detect_Format
  (Buffer : Byte_Array; Size : Natural) return Terminfo_Format
with
  Pre  => Size >= 2 and then Size <= Buffer'Length,
  Post => Detect_Format'Result in Legacy_16bit | Extended_32bit | Unknown;
```

Inspect the first two bytes of a buffer to detect the format variant. Reads `Buffer (1)` and `Buffer (2)` as a little-endian 16-bit unsigned integer and compares against `MAGIC_LEGACY` and `MAGIC_EXTENDED`. Any other value yields `Unknown`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Byte array containing the loaded terminfo file data. |
| `Size` | in | Number of valid bytes in `Buffer`; must satisfy `2 <= Size <= Buffer'Length`. |

**Returns:** `Legacy_16bit`, `Extended_32bit`, or `Unknown`.

**Requirements:** FUNC-TIF-007

---

#### `Parse_Header`

```ada
procedure Parse_Header
  (Buffer  : Byte_Array;
   Size    : Natural;
   Format  : Terminfo_Format;
   Header  : out Parsed_Header;
   Success : out Boolean)
with
  Pre  =>
    Size >= HEADER_SIZE
    and then Size <= Buffer'Length
    and then Format /= Unknown,
  Post => (if Success then Header_Is_Valid (Buffer, Header));
```

Parse the fixed 12-byte header and compute all section offsets. Reads the five 16-bit little-endian fields at byte offsets 2..11, validates all `MAX_*` bounds, computes section offsets including the alignment padding after the boolean section, and validates that the total consumed size does not exceed `Size`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Byte array containing the loaded terminfo file. |
| `Size` | in | Number of valid bytes in `Buffer`. |
| `Format` | in | The detected format variant; must not be `Unknown`. |
| `Header` | out | Receives the parsed header on success; unspecified on failure. |
| `Success` | out | `True` on success; `False` when any validation check fails. |

The postcondition guarantees that `Header_Is_Valid (Buffer, Header)` holds whenever `Success = True` — this is machine-verified by GNATprove.

**Requirements:** FUNC-TIF-008

---

#### `Get_Boolean`

```ada
function Get_Boolean
  (Buffer : Byte_Array; Header : Parsed_Header; Index : Natural)
   return Boolean_Cap_Value
with
  Pre =>
    Header_Is_Valid (Buffer, Header)
    and then Header.Bool_Section_Offset + Header.Bool_Count
             <= Buffer'Length;
```

Extract a single standard boolean capability by its ncurses index. If `Index >= Header.Bool_Count`, returns `Absent`. Otherwise reads the byte at `Header.Bool_Section_Offset + Index` and maps it to `Boolean_Cap_Value` per the ncurses conventions.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Loaded terminfo file byte array. |
| `Header` | in | Validated `Parsed_Header` (`Header_Is_Valid` must hold). |
| `Index` | in | Standard ncurses boolean capability index (0-based). |

**Returns:** The `Boolean_Cap_Value` for the capability.

**Requirements:** FUNC-TIF-009

---

#### `Get_Numeric`

```ada
function Get_Numeric
  (Buffer : Byte_Array;
   Header : Parsed_Header;
   Format : Terminfo_Format;
   Index  : Natural) return Integer
with
  Pre  => Header_Is_Valid (Buffer, Header) and then Format /= Unknown,
  Post => Get_Numeric'Result >= CANCELLED_NUMERIC;
```

Extract a single standard numeric capability by its ncurses index. If `Index >= Header.Num_Count`, returns `ABSENT_NUMERIC`. Otherwise reads 2 bytes (`Legacy_16bit`) or 4 bytes (`Extended_32bit`) as a little-endian signed integer. Sentinel values `ABSENT_NUMERIC` (−1) and `CANCELLED_NUMERIC` (−2) are returned unmodified.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Loaded terminfo file byte array. |
| `Header` | in | Validated `Parsed_Header`. |
| `Format` | in | The detected format variant; must not be `Unknown`. |
| `Index` | in | Standard ncurses numeric capability index (0-based). |

**Returns:** The integer value, or `ABSENT_NUMERIC` when out of range. Postcondition: result `>= CANCELLED_NUMERIC` (machine-verified).

**Requirements:** FUNC-TIF-010

---

#### `Get_String`

```ada
procedure Get_String
  (Buffer  : Byte_Array;
   Header  : Parsed_Header;
   Index   : Natural;
   Result  : out Capability_String;
   Present : out Boolean)
with
  Pre  => Header_Is_Valid (Buffer, Header),
  Post => (if not Present then Result.Length = 0);
```

Extract a single standard string capability by its ncurses index. If `Index >= Header.String_Count`, sets `Present := False` and `Result.Length := 0`. Otherwise reads the 16-bit signed offset at `Header.String_Table_Offset + Index * 2`; if the offset is −1 or −2 (absent/cancelled), sets `Present := False`. Otherwise copies bytes from `Header.String_Data_Offset + offset` until NUL or `MAX_CAPABILITY_STRING_LENGTH` bytes are copied.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Loaded terminfo file byte array. |
| `Header` | in | Validated `Parsed_Header`. |
| `Index` | in | Standard ncurses string capability index (0-based). |
| `Result` | out | Receives the capability string on success; `Length = 0` otherwise. |
| `Present` | out | `True` when the capability was found and non-empty. |

**Requirements:** FUNC-TIF-011

---

#### `Parse_Extended_Header`

```ada
procedure Parse_Extended_Header
  (Buffer  : Byte_Array;
   Size    : Natural;
   Header  : Parsed_Header;
   Ext     : out Extended_Header;
   Success : out Boolean)
with
  Pre  => Header_Is_Valid (Buffer, Header) and then Size <= Buffer'Length,
  Post => (if Success then Extended_Is_Valid (Buffer, Header, Ext));
```

Parse the extended capabilities section header and compute offsets. Checks whether there are at least 10 bytes beyond `Header.Total_Standard_Size` in `Buffer`. If not, sets `Success := False` (extended section absent — not an error). If present, reads the five 16-bit little-endian fields, validates bounds, computes offsets including alignment padding, and verifies all offsets remain within `Buffer`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Loaded terminfo file byte array. |
| `Size` | in | Number of valid bytes in `Buffer`. |
| `Header` | in | A validated `Parsed_Header`. |
| `Ext` | out | Receives the parsed extended header on success; unspecified on failure. |
| `Success` | out | `True` when an extended section was found and validated. |

**Requirements:** FUNC-TIF-012

---

#### `Extract_Truecolor_Flags`

```ada
procedure Extract_Truecolor_Flags
  (Buffer  : Byte_Array;
   Header  : Parsed_Header;
   Ext     : Extended_Header;
   Format  : Terminfo_Format;
   Has_RGB : out Boolean;
   Has_Tc  : out Boolean)
with
  Pre =>
    Header_Is_Valid (Buffer, Header)
    and then Extended_Is_Valid (Buffer, Header, Ext)
    and then Format /= Unknown;
```

Search extended capabilities for the `RGB` and `Tc` truecolor flags. Iterates over all extended capability name entries (bounded by `Ext.Ext_String_Count`), comparing each NUL-terminated name against `"RGB"` and `"Tc"` (case-sensitive). For each match, determines the capability type by position (boolean, numeric, or string) and extracts the value.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Loaded terminfo file byte array. |
| `Header` | in | Validated `Parsed_Header`. |
| `Ext` | in | Validated `Extended_Header`. |
| `Format` | in | The detected format variant; must not be `Unknown`. |
| `Has_RGB` | out | `True` when the `RGB` truecolor flag is present and set. |
| `Has_Tc` | out | `True` when the `Tc` truecolor flag is present and set. |

**Truecolor flag matching rules:**
- `RGB` as boolean `True_Value` or numeric `>= 1` → `Has_RGB := True`.
- `Tc` as boolean `True_Value` or non-empty string → `Has_Tc := True`.

The search loop is bounded by `Ext.Ext_String_Count` and carries a `Loop_Variant` annotation for SPARK proof.

**Requirements:** FUNC-TIF-013, FUNC-TIF-014

---

#### `Parse_Buffer`

```ada
function Parse_Buffer
  (Buffer : Byte_Array; Size : Natural) return Terminfo_Result
with Pre => Size >= 2 and then Size <= Buffer'Length;
```

Parse a loaded terminfo byte buffer and return a `Terminfo_Result`. Convenience aggregation that executes the complete binary parsing pipeline in sequence:

1. `Detect_Format` — validate magic bytes; return `Error_Invalid_Magic` on `Unknown`.
2. `Parse_Header` — validate header fields and compute offsets; return `Error_Header_Corrupt` on failure.
3. `Get_Numeric` — extract `colors` at `COLORS_INDEX`.
4. `Get_String` — extract `setaf` at `SETAF_INDEX`.
5. `Get_String` — extract `setab` at `SETAB_INDEX`.
6. Extract term name from the names section.
7. `Parse_Extended_Header` — attempt extended section (non-fatal on absence).
8. `Extract_Truecolor_Flags` — extract `RGB` and `Tc` flags (if extended present).
9. Construct and return `Terminfo_Result (Success => True, Snapshot => ...)`.

On any fatal parsing error, returns the appropriate error variant of `Terminfo_Result`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Loaded terminfo file byte array. |
| `Size` | in | Number of valid bytes in `Buffer`. |

**Returns:** `Terminfo_Result` carrying either the populated snapshot or an error code.

**Requirements:** FUNC-TIF-007 through FUNC-TIF-014

---

## Package `Termicap.Terminfo.IO`

### Overview

`Termicap.Terminfo.IO` is the I/O boundary for the TERMINFO feature. Both spec and body carry `pragma SPARK_Mode (Off)` because the package performs POSIX `open`/`read`/`close` system calls and constructs path strings dynamically — both outside the SPARK 2014 language subset.

Unlike the I/O children of active-probing packages (`Termicap.DA1.IO`, `Termicap.XTVERSION.IO`, etc.), `Termicap.Terminfo.IO` does not manage a `Probe_Session` or open a TTY device. The terminfo database is a static filesystem artifact and can be read in any context, including when stdout is not a terminal.

**Search directory order (FUNC-TIF-004):**
1. `$TERMINFO` (if set and non-empty)
2. Each colon-separated entry in `$TERMINFO_DIRS` (if set and non-empty)
3. `$HOME/.terminfo` (if `HOME` is set)
4. `/usr/share/terminfo`
5. `/etc/terminfo`
6. `/lib/terminfo`

**Path construction (FUNC-TIF-005):** for each directory `D` and terminal name `T`:
- **Primary path:** `D / T(1) / T` (first character of `T` used as subdirectory name)
- **Alternate path:** `D / HH / T` (two-character lowercase hex encoding of the ASCII value of `T`'s first character)

Primary is tried first, then alternate. Any candidate path that would exceed `MAX_PATH_LENGTH` (512 characters) is skipped without error.

---

### Procedures and Functions

#### `Read_File`

```ada
procedure Read_File
  (Path   : String;
   Buffer : out Byte_Array;
   Size   : out Natural;
   Error  : out Read_Error);
```

Open a file at `Path`, read its entire content into `Buffer`, and report the number of bytes read and the outcome.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Path` | in | Full filesystem path to the terminfo binary file. |
| `Buffer` | out | Receives the raw file bytes on success; unspecified on error. |
| `Size` | out | Number of bytes written into `Buffer`; `0` on error. |
| `Error` | out | Outcome code from the `Read_Error` enumeration. |

**Execution steps:**
1. Open the file at `Path` in read-only mode.
2. If the file does not exist or cannot be opened, set `Error := Read_Not_Found` and return.
3. Read up to `MAX_TERMINFO_FILE_SIZE` bytes into `Buffer`.
4. If the file content exceeds `MAX_TERMINFO_FILE_SIZE` bytes, set `Error := Read_Too_Large`, close the file, and return.
5. On a successful read, set `Size` to the number of bytes read and `Error := Read_OK`.
6. On any I/O error during reading, set `Error := Read_IO_Error`, `Size := 0`, and close the file.
7. The file descriptor is always closed before returning, regardless of outcome.

Never raises an exception on any code path.

**Requirements:** FUNC-TIF-006

---

#### `Parse_Terminfo`

```ada
function Parse_Terminfo
  (Env : Termicap.Environment.Environment) return Terminfo_Result;
```

Execute the full terminfo search-path resolution and binary parsing pipeline, returning a `Terminfo_Result`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | An immutable environment snapshot (from `Termicap.Environment`). |

**Returns:** `Terminfo_Result` containing either a populated `Terminfo_Snapshot` or one of the `Terminfo_Error` codes.

**Execution steps:**
1. Read `TERM` from `Env` (FUNC-TIF-003). If absent or empty, return `(Success => False, Error => Error_No_Term)`.
2. Build the ordered candidate directory list (FUNC-TIF-004): `$TERMINFO`, entries from `$TERMINFO_DIRS`, `$HOME/.terminfo`, `/usr/share/terminfo`, `/etc/terminfo`, `/lib/terminfo`.
3. For each candidate directory, construct the primary path `T(1)/T` then the alternate path `HH/T` (FUNC-TIF-005) and call `Read_File`.
   - `Read_Not_Found`: continue to the next candidate.
   - `Read_IO_Error` or `Read_Too_Large`: continue to the next candidate (non-fatal per-path I/O errors do not abort the search, FUNC-TIF-020).
   - `Read_OK`: commit to this file and proceed to step 4.
4. If no file was found after all candidates, return `(Success => False, Error => Error_File_Not_Found)`.
5. Call `Parse_Buffer (Buffer, Size)` from `Termicap.Terminfo`. On parse failure, return the error immediately (no fallback to a lower-priority candidate).
6. On parse success, return the populated `Terminfo_Result`.

Never raises an Ada exception under any input condition (FUNC-TIF-019). Callers that receive `Error_File_Not_Found` should treat the condition as informational — many systems do not have terminfo installed, and `Error_File_Not_Found` is not a sign of a broken installation (FUNC-TIF-020).

**Requirements:** FUNC-TIF-003, FUNC-TIF-004, FUNC-TIF-005, FUNC-TIF-015, FUNC-TIF-019, FUNC-TIF-020

---

## Usage Examples

### Read terminfo capabilities for the current terminal

```ada
with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Terminfo;
with Termicap.Terminfo.IO;

procedure Check_Terminfo is
   Env    : Termicap.Environment.Environment;
   Result : Termicap.Terminfo.Terminfo_Result;
begin
   Termicap.Environment.Capture.Capture_Current (Env);
   Result := Termicap.Terminfo.IO.Parse_Terminfo (Env);

   if Result.Success then
      if Result.Snapshot.Colors >= 256 then
         --  Terminal claims 256-color support via terminfo
      end if;
      if Result.Snapshot.Has_RGB_Flag or else Result.Snapshot.Has_Tc_Flag then
         --  Terminal advertises truecolor via extended terminfo flag
      end if;
   elsif Result.Error = Termicap.Terminfo.Error_File_Not_Found then
      --  No terminfo available; fall back to environment variable detection
      null;
   end if;
end Check_Terminfo;
```

### Parse a synthetic buffer in tests

```ada
with Termicap.Terminfo;
use  Termicap.Terminfo;

procedure Test_Parse_Buffer is
   --  Minimal valid Legacy_16bit terminfo binary (header only, no capabilities)
   Buffer : constant Byte_Array :=
     [16#1A#, 16#01#,   --  magic: MAGIC_LEGACY
      12, 0,            --  names_size: 12 bytes
      0, 0,             --  bool_count: 0
      0, 0,             --  num_count: 0
      0, 0,             --  string_count: 0
      0, 0,             --  table_size: 0
      --  Names section (12 bytes, NUL-terminated)
      others => 0];
   Result : constant Terminfo_Result :=
     Parse_Buffer (Buffer, Buffer'Length);
begin
   pragma Assert (Result.Success);
   pragma Assert (Result.Snapshot.Colors = ABSENT_NUMERIC);
end Test_Parse_Buffer;
```

### Check for truecolor via terminfo (integration pattern)

```ada
with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Terminfo;
with Termicap.Terminfo.IO;

function Terminfo_Supports_Truecolor return Boolean is
   Env    : Termicap.Environment.Environment;
   Result : Termicap.Terminfo.Terminfo_Result;
begin
   Termicap.Environment.Capture.Capture_Current (Env);
   Result := Termicap.Terminfo.IO.Parse_Terminfo (Env);
   return Result.Success
     and then (Result.Snapshot.Has_RGB_Flag
               or else Result.Snapshot.Has_Tc_Flag);
end Terminfo_Supports_Truecolor;
```

---

## Design Notes

### SPARK strategy: ghost predicates as invariant bundles

The terminfo binary parsing pipeline involves dozens of inter-related bounds facts (section sizes, offsets, total sizes). Rather than repeating every fact in the precondition of each downstream function, `Termicap.Terminfo` expresses them as two ghost predicates: `Header_Is_Valid` and `Extended_Is_Valid`. A function that requires `Header_Is_Valid (Buffer, Header)` in its precondition gives GNATprove the complete set of facts without enumerating them individually. This approach reduces precondition verbosity and makes it easy to extend the invariant set without modifying every downstream contract.

### Bounded strings instead of `Ada.Strings.Unbounded`

All string values extracted from the terminfo binary are stored in bounded record types (`Capability_String`, `Term_Name_String`). This is required for SPARK provability — unbounded strings (`Ada.Strings.Unbounded.Unbounded_String`) involve heap allocation, which is outside the SPARK 2014 subset. The maximum lengths (64 characters) are sufficient for all known terminfo capability string values and terminal names.

### File-not-found is non-fatal

`Error_File_Not_Found` is not an error in the conventional sense. Many minimal or container environments do not have a terminfo database installed; in those cases, the calling code should proceed with environment variable detection rather than reporting an error to the user. The design follows FUNC-TIF-020 in treating `Error_File_Not_Found` as an advisory informational result.

### No platform dispatch

Unlike the active-probing I/O packages (`Termicap.Keyboard.IO`, `Termicap.Mouse.IO`, `Termicap.Graphics.IO`), `Termicap.Terminfo.IO` has a single body with no GPR `Source_Dirs` platform dispatch. The terminfo database is a POSIX filesystem structure; on Windows, the search simply finds no files and returns `Error_File_Not_Found`. No Windows-specific handling is required.

---

## Related

- **`Termicap.Environment`** (`docs/guide/reference/termicap-environment.md`): `Environment` snapshot type passed to `Parse_Terminfo`
- **Building Blocks** (`docs/architecture/03-building-blocks.md`): `Termicap.Terminfo` / `Termicap.Terminfo.IO` package descriptions and SPARK boundary
- **Runtime View Scenario 29** (`docs/architecture/04-runtime-view.md`): Step-by-step sequence for `Parse_Terminfo`
- **Tech Spec TERMINFO** (`docs/tech-specs/terminfo.md`): Full design rationale — binary format variants, ghost predicate SPARK strategy, search-path resolution, path construction algorithm, truecolor flag extraction
- **Requirements** (`docs/requirements/functional/terminfo.sdoc`): FUNC-TIF-001 through FUNC-TIF-020
