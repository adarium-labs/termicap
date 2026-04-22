# CYGWIN: Cygwin / MSYS2 PTY Detection

**Feature:** Cygwin / MSYS2 Pseudo-Terminal Detection on Windows
**Requirements:** FUNC-CYG-001 through FUNC-CYG-017
**Parent Requirement:** FUNC-WIN-001, FUNC-WIN-003
**Status:** Proposed
**Date:** 2026-04-22

---

## A. Overview

### Problem statement

On Windows, `Termicap.TTY.Is_TTY` currently uses `Win32.Wincon.GetConsoleMode` as its sole TTY predicate (FUNC-WIN-003). `GetConsoleMode` succeeds for native console handles (Windows Terminal, `cmd.exe`, `powershell.exe`, `conhost.exe`) but returns `FALSE` for every Cygwin/MSYS2 PTY handle because those environments emulate a PTY with a pair of named pipes rather than a kernel console object.

The observable consequence is a false negative: programs launched under `git-bash`, `MSYS2 bash`, `Cygwin Terminal`, or `mintty` correctly hold a pipe handle to an interactive terminal, yet `Is_TTY (Stdout)` returns `False`, disabling colour output and other TTY-gated features for a significant fraction of Windows developer terminals.

### Scope

This feature is **Windows-only** and **extends** the existing Windows body of `Termicap.TTY.Is_TTY`. The POSIX and Linux bodies are unchanged. The public API of `Termicap.TTY` is unchanged: callers continue to invoke `Is_TTY (Stdout)` and receive a `Boolean` result.

The feature adds a new platform package `Termicap.Win32_Cygwin` (spec + body) dedicated to Cygwin/MSYS2 detection, modifies the existing Windows body `src/windows/termicap-tty.adb` to disjoin the new detection with `GetConsoleMode`, and extends `Termicap.Win32_Ntdll` with an `NtQueryObject` binding reused as a fallback.

The feature is a strict extension: every handle for which `GetConsoleMode` currently returns `True` continues to be classified as a TTY (and continues to have VT processing enabled); every handle for which `GetConsoleMode` fails is additionally checked against the Cygwin/MSYS2 pipe-name pattern before the function returns `False`.

### Requirements satisfied

| Requirement | Summary |
|-------------|---------|
| FUNC-CYG-001 | `GetFileType` guard — rejects non-pipe handles before expensive name queries |
| FUNC-CYG-002 | Dynamic probe for `GetFileInformationByHandleEx` at elaboration time |
| FUNC-CYG-003 | Pipe name retrieval via `GetFileInformationByHandleEx` with `FileNameInfo` class |
| FUNC-CYG-004 | Fallback pipe name retrieval via `NtQueryObject` with `ObjectNameInformation` class |
| FUNC-CYG-005 | UTF-16LE → ASCII-range Ada `String` decoder with `'?'` substitution |
| FUNC-CYG-006 | Public SPARK function `Is_Cygwin_Pipe_Name (Name : String) return Boolean` |
| FUNC-CYG-007 | Validation: `token[0]` matches one of four accepted prefixes |
| FUNC-CYG-008 | Validation: `token[1]` (session id) is non-empty |
| FUNC-CYG-009 | Validation: `token[2]` begins with lowercase `"pty"` |
| FUNC-CYG-010 | Validation: `token[3]` is exactly `"from"` or `"to"` |
| FUNC-CYG-011 | Validation: `token[4]` is exactly `"master"` (extra segments allowed) |
| FUNC-CYG-012 | Validation: minimum 5 `-`-delimited segments |
| FUNC-CYG-013 | 14 acceptance test vectors derived from go-isatty |
| FUNC-CYG-014 | `Is_Cygwin_Terminal` high-level pipeline function |
| FUNC-CYG-015 | `Is_TTY_Via_Handle` extended with Cygwin disjunction; VT processing skipped on Cygwin handles |
| FUNC-CYG-016 | No-exception contract for `Is_Cygwin_Terminal` |
| FUNC-CYG-017 | New package `Termicap.Win32_Cygwin` with SPARK_Mode boundary |

---

## B. Framework Survey

### How go-isatty solves this problem

The canonical cross-language reference for Cygwin/MSYS2 PTY detection is `mattn/go-isatty` (`isatty_windows.go`). Its `IsCygwinTerminal(fd)` implementation is deployed in thousands of Go CLIs (cobra, color, progressbar, ripgrep adapters) and serves as the de facto ground truth for the pipe-name pattern.

#### The two-path API strategy

go-isatty resolves four procedures once at package `init()` time:

```go
var (
    kernel32                         = syscall.NewLazyDLL("kernel32.dll")
    ntdll                            = syscall.NewLazyDLL("ntdll.dll")
    procGetConsoleMode               = kernel32.NewProc("GetConsoleMode")
    procGetFileInformationByHandleEx = kernel32.NewProc("GetFileInformationByHandleEx")
    procGetFileType                  = kernel32.NewProc("GetFileType")
    procNtQueryObject                = ntdll.NewProc("NtQueryObject")
)

func init() {
    if procGetFileInformationByHandleEx.Find() != nil {
        procGetFileInformationByHandleEx = nil
    }
}
```

Two observations that drive the Ada design:

1. `GetFileInformationByHandleEx` is probed for **availability** at init time; the returned pointer is nulled if the function is missing. This supports running on pre-Vista Windows or in reduced-surface compatibility layers (Wine, ReactOS).
2. `NtQueryObject` is **not** probed because `ntdll.dll` is guaranteed to be present and the export has been stable since NT 3.5. Only its successful invocation is checked at call time.

At call time, `IsCygwinTerminal(fd)` branches on availability:

```go
func IsCygwinTerminal(fd uintptr) bool {
    if procGetFileInformationByHandleEx == nil {
        name, err := getFileNameByHandle(fd)        // NtQueryObject path
        if err != nil { return false }
        return isCygwinPipeName(name)
    }

    // Cygwin/msys's pty is a pipe. Guard.
    ft, _, e := syscall.Syscall(procGetFileType.Addr(), 1, fd, 0, 0)
    if ft != fileTypePipe || e != 0 { return false }

    var buf [2 + syscall.MAX_PATH]uint16
    r, _, e := syscall.Syscall6(procGetFileInformationByHandleEx.Addr(),
        4, fd, fileNameInfo, uintptr(unsafe.Pointer(&buf)),
        uintptr(len(buf)*2), 0, 0)
    if r == 0 || e != 0 { return false }

    l := *(*uint32)(unsafe.Pointer(&buf))
    return isCygwinPipeName(string(utf16.Decode(buf[2 : 2+l/2])))
}
```

Key structural choices:

- The `GetFileType` guard is **only** performed on the primary (`GetFileInformationByHandleEx`) path. The fallback path skips it because `NtQueryObject` is safe to call on any handle (it simply returns a non-zero `NTSTATUS` for non-pipe handles, which is treated as "not Cygwin").
- Failure of `GetFileInformationByHandleEx` **does not** fall through to `NtQueryObject`. The two paths are **availability** alternatives, not runtime fallbacks; if the primary API is present but fails on a particular handle, the verdict is "not Cygwin".
- The `buf[2 : 2+l/2]` slice reflects the `FILE_NAME_INFO` layout: the first 4 bytes (`l : uint32`, sized as 2 `uint16`s) are the length-in-bytes header, followed by the UTF-16 file-name.

#### The `isCygwinPipeName` pure function

go-isatty's pipe-name validator is purely functional:

```go
func isCygwinPipeName(name string) bool {
    token := strings.Split(name, "-")
    if len(token) < 5 { return false }

    if token[0] != `\msys` &&
        token[0] != `\cygwin` &&
        token[0] != `\Device\NamedPipe\msys` &&
        token[0] != `\Device\NamedPipe\cygwin` { return false }

    if token[1] == "" { return false }
    if !strings.HasPrefix(token[2], "pty") { return false }
    if token[3] != `from` && token[3] != `to` { return false }
    if token[4] != "master" { return false }

    return true
}
```

The function splits the full name by `'-'`, then applies five independent token-level predicates. Empty tokens are treated as segments (counted toward `len(token) < 5`), rather than elided. Token 4 is the last validated segment; additional trailing segments are ignored, permitting forward compatibility with future Cygwin runtime conventions.

### Ada applicability

| go-isatty mechanism | Ada / Termicap equivalent |
|---|---|
| `syscall.NewLazyDLL` / `NewProc` / `Find()` | `Win32.Winbase.LoadLibraryA` + `Win32.Winbase.GetProcAddress` + `Win32.Winbase.FreeLibrary`, already used in `Termicap.Win32_Ntdll` for `RtlGetNtVersionNumbers` |
| `init()` availability check | Package body elaboration code in `Termicap.Win32_Cygwin` |
| `procGetFileInformationByHandleEx` (unsafe-pointer access) | Ada access-to-function type (`Get_File_Info_Fn_Ptr`) with `Convention => Stdcall`, stored as a package-level variable, populated via `Ada.Unchecked_Conversion` from `FARPROC` |
| `strings.Split` | Manual left-to-right scan over `String`; no standard `Split` in Ada 2012 |
| `strings.HasPrefix` | Slice comparison: `Name (First .. First + 2) = "pty"` |
| `unicode/utf16.Decode` | ASCII-range-only decoder over `Interfaces.C.char16_array`; `'?'` substitution for non-ASCII code units |
| `[2+MAX_PATH]uint16` stack buffer | `Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1)` in a local `File_Name_Info` record |

The strategic choice confirmed by go-isatty: keep the OS-call FFI separate from the pure pipe-name predicate. In Ada, the predicate becomes `Is_Cygwin_Pipe_Name (Name : String)` in a SPARK_Mode => On spec, while the FFI glue lives in a SPARK_Mode => Off body. This mirrors the architecture already used for `Termicap.Win32_Color.Build_To_Color_Level` (SPARK Silver) vs. `Termicap.Win32_Color.Detect_Windows_Color_Level` (SPARK_Mode => Off).

### Consensus with other frameworks

- **crossterm (Rust)**: equivalent two-path design; primary path uses `GetFileInformationByHandleEx`; no fallback (hard-depends on Vista+). Treats handle-type check as a gate in the same place we do.
- **Python colorama**: calls `GetFileType` first and classifies anything non-`FILE_TYPE_CHAR` as "not a console"; does not implement pipe-name matching — colorama's approach under-detects Cygwin PTYs and is the baseline Termicap intends to surpass.
- **supports-color (Node.js, older branches)**: when `process.stdout.isTTY` is false, invokes `NtQueryObject` via FFI to inspect the pipe name for `cygwin` / `msys` substrings — confirms the robustness of the `NtQueryObject` approach on older Windows (XP).

The four-prefix / five-token grammar is identical across all surveyed implementations.

---

## C. Package Design

### New package: `Termicap.Win32_Cygwin`

A new platform package is introduced under `src/windows/` following the established Win32 platform-package pattern (`Win32_Ntdll`, `Win32_VT`, `Win32_Color`).

| Property | Value |
|----------|-------|
| Files | `src/windows/termicap-win32_cygwin.ads`, `src/windows/termicap-win32_cygwin.adb` |
| SPARK_Mode | Spec: On; Body: Off (with `Is_Cygwin_Pipe_Name` body locally annotated `SPARK_Mode => On`) |
| Spec dependencies | *(none beyond `Termicap` root — no Win32 types in the spec)* |
| Body dependencies | `Ada.Unchecked_Conversion`, `Interfaces.C`, `System`, `Win32`, `Win32.Winbase`, `Win32.Winnt`, `Win32.Windef`, `Termicap.Win32_Ntdll` |

The **spec** declares only:

1. `Is_Cygwin_Pipe_Name (Name : String) return Boolean` — pure SPARK predicate (FUNC-CYG-006).
2. `Is_Cygwin_Terminal (Handle : Win32.Winnt.HANDLE) return Boolean` — impure high-level integration (FUNC-CYG-014).

Because FUNC-CYG-014 explicitly takes a `Win32.Winnt.HANDLE`, the spec must `with Win32.Winnt`. This is a necessary exception to the "no Win32 types in the spec" guideline in FUNC-CYG-017's ideal — the alternative (an opaque wrapper type) would complicate the call site in `Termicap.TTY` without improving SPARK coverage, since `Is_Cygwin_Terminal` is already `SPARK_Mode => Off`.

> **Scope clarification (spec with-clauses).** FUNC-CYG-017 expresses a preference that the spec declare no Win32 types directly. Because FUNC-CYG-014 requires `Is_Cygwin_Terminal` to accept a `Win32.Winnt.HANDLE`, we accept `with Win32.Winnt;` in the spec as the minimal Win32 dependency. `Is_Cygwin_Pipe_Name` remains Win32-free (takes only `String`) and is the function that carries the `SPARK_Mode => On` marker.

The **body** contains:

1. Package-level elaboration code that probes for `GetFileInformationByHandleEx` availability.
2. Package-level variables storing the function pointer and availability flag.
3. The `Is_Cygwin_Pipe_Name` body, locally marked `SPARK_Mode => On`.
4. The `Is_Cygwin_Terminal` body (impure), which sequences the FFI pipeline.
5. All supporting helpers: `Get_File_Type_Is_Pipe`, `Retrieve_Name_Via_GetFileInfo`, `Retrieve_Name_Via_NtQueryObject`, `Decode_UTF16_To_ASCII`.

### Dependency graph

```
Termicap.TTY (Windows body)
  |
  |-- Termicap.Win32_Cygwin
  |     |-- Termicap.Win32_Ntdll          (for NtQueryObject fallback)
  |     |-- Win32, Win32.Winnt,
  |     |   Win32.Winbase, Win32.Windef   (LoadLibrary, GetFileType, FARPROC)
  |     |-- Interfaces.C                   (char16_t, char16_array, DWORD ↔ unsigned_long)
  |     |-- System                         (System.Address for FARPROC conversion, buffer addressing)
  |     |-- Ada.Unchecked_Conversion
  |
  |-- Termicap.Win32_VT
  |-- Termicap.Override
```

`Termicap.Win32_Cygwin` depends on `Termicap.Win32_Ntdll` **only** to reuse an `NtQueryObject` binding that will be added to `Win32_Ntdll` by this feature (see §F). It does **not** depend on `Termicap.Win32_VT` or `Termicap.Win32_Color`.

### SPARK boundary table

| Package / subprogram | SPARK_Mode | Rationale |
|----------------------|------------|-----------|
| `Termicap.Win32_Cygwin` spec | `On` | Declares `Is_Cygwin_Pipe_Name` as SPARK Silver with `Global => null` |
| `Termicap.Win32_Cygwin` body | `Off` | Contains Win32 FFI, access-to-function types, `Unchecked_Conversion`, `System.Address` arithmetic |
| `Is_Cygwin_Pipe_Name` body | `On` (locally) | Pure `String` iteration; eligible for SPARK Silver |
| `Is_Cygwin_Terminal` body | `Off` | Calls `GetFileType`, indirect calls via function-pointer dereference |
| `Termicap.Win32_Ntdll` (extended) | `Off` | Adds `NtQueryObject` binding to the existing `SPARK_Mode => Off` package |
| `Termicap.TTY` Windows body | `Off` | Unchanged SPARK status; gains a call to `Is_Cygwin_Terminal` |

---

## D. `Is_Cygwin_Pipe_Name` — Detailed Algorithm

This is the core SPARK-provable predicate. It performs token decomposition and five token-level validations over a bounded Ada `String`. The function has no side effects, calls no OS routine, and touches no package-level state.

### Signature

```ada
function Is_Cygwin_Pipe_Name (Name : String) return Boolean
  with SPARK_Mode => On,
       Global     => null,
       Pre        => True,
       Post       => True;
```

`Pre => True` / `Post => True` are placeholder contracts per FUNC-CYG-006; they may be strengthened during implementation (e.g., `Pre => Name'Length <= MAX_PIPE_NAME_LENGTH`) without invalidating the requirement.

### Constants (declared in the body)

```ada
MAX_PIPE_NAME_LENGTH : constant := 512;  -- UTF-16 code units; same as FUNC-CYG-003 buffer

--  Four accepted token[0] prefixes (FUNC-CYG-007)
CYG_PREFIX_1 : constant String := "\cygwin";
CYG_PREFIX_2 : constant String := "\msys";
CYG_PREFIX_3 : constant String := "\Device\NamedPipe\cygwin";
CYG_PREFIX_4 : constant String := "\Device\NamedPipe\msys";
```

### Token extraction strategy

Ada 2012 has **no** standard `Split` function — `Ada.Strings.Split` is an Ada 2022 addition and Termicap targets Ada 2012 (consistent with the rest of the codebase). Rather than allocating a dynamic vector of strings (which would require a SPARK-compatible container and inflate the proof surface), we iterate the string once and validate each token against the per-position rule as it is encountered.

The extraction algorithm scans left to right, tracking the start index of the **current token** and incrementing a **token index**:

```
Token_Start : Positive := Name'First;
Token_Idx   : Natural  := 0;   -- 0-based logical index (0, 1, 2, 3, 4, ...)
I           : Natural  := Name'First - 1;  -- current scan index (before start)

loop
   I := I + 1;
   if I > Name'Last or else Name (I) = '-' then
      --  Current token is Name (Token_Start .. I - 1)
      declare
         Token_End : constant Integer := I - 1;  -- may be Token_Start - 1 if empty
      begin
         case Token_Idx is
            when 0 =>
               if not Is_Valid_Prefix (Name (Token_Start .. Token_End)) then
                  return False;
               end if;
            when 1 =>
               if Token_End < Token_Start then   -- empty token
                  return False;
               end if;
            when 2 =>
               if not Starts_With_Pty (Name (Token_Start .. Token_End)) then
                  return False;
               end if;
            when 3 =>
               if not Is_From_Or_To (Name (Token_Start .. Token_End)) then
                  return False;
               end if;
            when 4 =>
               if Name (Token_Start .. Token_End) /= "master" then
                  return False;
               end if;
               --  Early success: tokens 5+ are ignored (FUNC-CYG-011)
               return True;
            when others =>
               null;  -- unreachable: we return at Token_Idx = 4
         end case;
      end;

      exit when I > Name'Last;
      Token_Idx   := Token_Idx + 1;
      Token_Start := I + 1;
   end if;
end loop;

--  Loop exited without reaching token 4 → fewer than 5 segments (FUNC-CYG-012)
return False;
```

### Per-token helpers (all `Global => null`)

```ada
function Is_Valid_Prefix (T : String) return Boolean is
  (T = CYG_PREFIX_1 or else T = CYG_PREFIX_2
   or else T = CYG_PREFIX_3 or else T = CYG_PREFIX_4);

function Starts_With_Pty (T : String) return Boolean is
  (T'Length >= 3
   and then T (T'First)     = 'p'
   and then T (T'First + 1) = 't'
   and then T (T'First + 2) = 'y');

function Is_From_Or_To (T : String) return Boolean is
  (T = "from" or else T = "to");
```

Each helper is a pure expression function with `Global => null`, composing trivially in the SPARK prover.

### Case-sensitivity

All comparisons are case-sensitive (`=` on `String`), per FUNC-CYG-007 through FUNC-CYG-011. No call to `Ada.Characters.Handling.To_Lower` or equivalent is made. This is deliberate: Cygwin and MSYS2 runtimes always emit lowercase names; accepting mixed case would widen the match and risk false positives against unrelated named pipes.

### The 14 test vectors — token decomposition

The table below makes each test vector's expected tokenisation explicit, to aid test authoring and manual review of the algorithm. Tokens are 0-indexed.

| # | Name | Tokens | Failing rule | Expected |
|---|---|---|---|---|
| 1 | `""` | [`""`] | FUNC-CYG-012 (only 1 segment) | `False` |
| 2 | `"\msys-"` | [`"\msys"`, `""`] | FUNC-CYG-012 (only 2 segments) | `False` |
| 3 | `"\cygwin-----"` | [`"\cygwin"`, `""`, `""`, `""`, `""`, `""`] | FUNC-CYG-008 (token[1] empty) | `False` |
| 4 | `"\msys-x-PTY5-pty1-from-master"` | [`"\msys"`, `"x"`, `"PTY5"`, `"pty1"`, `"from"`, `"master"`] | FUNC-CYG-009 (token[2] starts with `"PTY"` not `"pty"`) | `False` |
| 5 | `"\cygwin-x-PTY5-from-master"` | [`"\cygwin"`, `"x"`, `"PTY5"`, `"from"`, `"master"`] | FUNC-CYG-009 | `False` |
| 6 | `"\cygwin-x-pty2-from-toaster"` | [`"\cygwin"`, `"x"`, `"pty2"`, `"from"`, `"toaster"`] | FUNC-CYG-011 (token[4] /= `"master"`) | `False` |
| 7 | `"\cygwin--pty2-from-master"` | [`"\cygwin"`, `""`, `"pty2"`, `"from"`, `"master"`] | FUNC-CYG-008 (token[1] empty) | `False` |
| 8 | `"\\cygwin-x-pty2-from-master"` | [`"\\cygwin"`, `"x"`, `"pty2"`, `"from"`, `"master"`] | FUNC-CYG-007 (token[0] has double backslash) | `False` |
| 9 | `"\cygwin-x-pty2-from-master-"` | [`"\cygwin"`, `"x"`, `"pty2"`, `"from"`, `"master"`, `""`] | Extra token ignored → accepted | `True` |
| 10 | `"\cygwin-e022582115c10879-pty4-from-master"` | [`"\cygwin"`, `"e022582115c10879"`, `"pty4"`, `"from"`, `"master"`] | none | `True` |
| 11 | `"\msys-e022582115c10879-pty4-to-master"` | [`"\msys"`, `"e022582115c10879"`, `"pty4"`, `"to"`, `"master"`] | none | `True` |
| 12 | `"\Device\NamedPipe\cygwin-e022582115c10879-pty4-from-master"` | [`"\Device\NamedPipe\cygwin"`, `"e022582115c10879"`, `"pty4"`, `"from"`, `"master"`] | none | `True` |
| 13 | `"\Device\NamedPipe\msys-e022582115c10879-pty4-to-master"` | [`"\Device\NamedPipe\msys"`, `"e022582115c10879"`, `"pty4"`, `"to"`, `"master"`] | none | `True` |
| 14 | `"Device\NamedPipe\cygwin-e022582115c10879-pty4-to-master"` | [`"Device\NamedPipe\cygwin"`, `"e022582115c10879"`, `"pty4"`, `"to"`, `"master"`] | FUNC-CYG-007 (no leading `\`) | `False` |

Implementation note: because the algorithm returns early on token 4 (FUNC-CYG-011, accept branch), vector 9's sixth empty segment is never examined, matching FUNC-CYG-011's "extra segments ignored" wording.

---

## E. Primary Path — `GetFileInformationByHandleEx`

### Dynamic probe strategy

`GetFileInformationByHandleEx` is not exported by the win32ada Alire crate (confirmed by `grep -R GetFileInformationByHandleEx alire/cache/dependencies/win32ada_26.0.0_*`). It must therefore be resolved manually, using the same `LoadLibraryA` / `GetProcAddress` pattern established in `Termicap.Win32_Ntdll.Get_Build_Number`.

The probe is performed **once per process** at package body elaboration time, exactly as go-isatty's `init()` does. The result is cached in two package-level variables:

```ada
--  Package body elaboration-time state (SPARK_Mode => Off)
Has_Get_File_Info : Boolean := False;
Get_File_Info_Fn  : Get_File_Info_Fn_Ptr := null;
```

### Access-to-function type

Because `GetFileInformationByHandleEx` is a `__stdcall` function returning `BOOL`, the Ada access-to-function type must use `Convention => Stdcall`:

```ada
FILE_NAME_INFO_CLASS : constant Win32.DWORD := 2;   -- FileNameInfo

type Get_File_Info_Fn_Ptr is access function
   (hFile                : Win32.Winnt.HANDLE;
    FileInformationClass : Win32.DWORD;
    lpFileInformation    : System.Address;
    dwBufferSize         : Win32.DWORD)
   return Win32.BOOL
   with Convention => Stdcall;

function To_Get_File_Info is new Ada.Unchecked_Conversion
   (Win32.Windef.FARPROC, Get_File_Info_Fn_Ptr);
```

`Win32.Windef.FARPROC` is the return type of `Win32.Winbase.GetProcAddress` in the win32ada binding (same convention as in `Termicap.Win32_Ntdll`).

### `FILE_NAME_INFO` layout

The Windows SDK defines `FILE_NAME_INFO` (fileapi.h) as:

```c
typedef struct _FILE_NAME_INFO {
  DWORD FileNameLength;    // length in BYTES (not characters), excluding any NUL
  WCHAR FileName[1];       // variable-length UTF-16 name, NOT NUL-terminated
} FILE_NAME_INFO;
```

In Ada, with a fixed-size upper bound:

```ada
MAX_PIPE_NAME_LENGTH : constant := 512;  -- UTF-16 code units

type File_Name_Info_Record is record
   File_Name_Length : Win32.DWORD;
   File_Name        : Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1);
end record
   with Convention => C;
```

Buffer sizing:

- `MAX_PIPE_NAME_LENGTH = 512` UTF-16 code units = **1024 bytes** (512 × `sizeof(WCHAR)`).
- Plus `File_Name_Length : DWORD` = 4 bytes.
- Total: **1028 bytes** (Ada may pad for alignment; `Convention => C` preserves the SDK layout).
- go-isatty uses `[2 + MAX_PATH]uint16` = `2 + 260` = 262 `uint16` = 524 bytes. Termicap sizes somewhat larger (512 code units ≥ `MAX_PATH`) for safety against NT-device-path-form pipe names, which are longer.

The buffer is stack-allocated in `Retrieve_Name_Via_GetFileInfo`. No heap allocation, no `new`, no `Ada.Finalization`. Passing `Buffer'Address` as `System.Address` to the access-to-function yields the same ABI as a C `FILE_NAME_INFO*` argument.

### Call sequence

```
function Retrieve_Name_Via_GetFileInfo
   (Handle : Win32.Winnt.HANDLE;
    Out_Name : out String;
    Out_Last : out Natural) return Boolean
is
   Buffer : aliased File_Name_Info_Record;
   Ok     : Win32.BOOL;
   Units  : Natural;
begin
   if Get_File_Info_Fn = null then
      return False;   -- defensive; Is_Cygwin_Terminal already checks Has_Get_File_Info
   end if;

   Ok := Get_File_Info_Fn
           (hFile                => Handle,
            FileInformationClass => FILE_NAME_INFO_CLASS,
            lpFileInformation    => Buffer'Address,
            dwBufferSize         => File_Name_Info_Record'Size / 8);

   if Ok = Win32.FALSE then
      return False;
   end if;

   --  FUNC-CYG-003: Length field is in bytes; divide by 2 for UTF-16 code units.
   --  Clamp to MAX_PIPE_NAME_LENGTH to protect against malformed responses.
   Units := Natural (Buffer.File_Name_Length) / 2;
   if Units > MAX_PIPE_NAME_LENGTH then
      Units := MAX_PIPE_NAME_LENGTH;
   end if;

   Decode_UTF16_To_ASCII
      (Input     => Buffer.File_Name,
       Unit_Count => Units,
       Output     => Out_Name,
       Last       => Out_Last);
   return True;
exception
   when others => return False;  -- FUNC-CYG-016: never propagate
end Retrieve_Name_Via_GetFileInfo;
```

Note: `File_Name_Info_Record'Size / 8` converts the Ada-level size (in bits) to bytes; this is the canonical idiom matching Win32's `dwBufferSize` semantics.

---

## F. Fallback Path — `NtQueryObject`

### Extension of `Termicap.Win32_Ntdll`

The requirements (FUNC-CYG-004) state that the `NtQueryObject` binding is **already declared** in `Termicap.Win32_Ntdll`. Inspection of `src/windows/termicap-win32_ntdll.ads` and `.adb` (see §H for the current spec) shows that **only** `Get_Build_Number` is present today. This feature therefore **extends** `Termicap.Win32_Ntdll` with a new subprogram:

```ada
--  Added to src/windows/termicap-win32_ntdll.ads
with Win32;
with Win32.Winnt;
with System;

--  @summary Retrieve the NT object name of a handle via ntdll!NtQueryObject.
--  @param Handle     The handle to query.
--  @param Buffer     A caller-allocated System.Address of at least Buffer_Size
--                    bytes. On success, populated with an OBJECT_NAME_INFORMATION
--                    record whose UNICODE_STRING header is followed by the
--                    UTF-16 name data (in-buffer pointer).
--  @param Buffer_Size Size of Buffer in bytes (caller ensures >= 1024).
--  @return True iff NtQueryObject returned NTSTATUS 0 (STATUS_SUCCESS).
--  @relation(FUNC-CYG-004): Fallback pipe-name retrieval
function Query_Object_Name
   (Handle      : Win32.Winnt.HANDLE;
    Buffer      : System.Address;
    Buffer_Size : Interfaces.Unsigned_32) return Boolean;
```

The body (`termicap-win32_ntdll.adb`) performs the same dynamic-load dance already used for `RtlGetNtVersionNumbers`, but:

- targets `ntdll.dll` (already loaded) and export name `"NtQueryObject"`;
- declares a stdcall access-to-function returning `Interfaces.C.long` (NTSTATUS);
- frees the module via `FreeLibrary` after the call, matching the existing style.

An optimisation (optional): since `Termicap.Win32_Ntdll` may be called repeatedly for both `Get_Build_Number` and `Query_Object_Name`, a future refactor could cache the `ntdll.dll` `HINSTANCE` at elaboration time. This is **out of scope** for the CYG feature; each call continues to load and free `ntdll.dll` per the existing pattern, which is cheap because the OS keeps ntdll.dll pinned in every process.

### `NtQueryObject` signature

```ada
OBJECT_NAME_INFORMATION_CLASS : constant Win32.DWORD := 1;

type Nt_Query_Object_Fn_Ptr is access function
   (Handle             : Win32.Winnt.HANDLE;
    ObjectInformationClass : Win32.DWORD;
    ObjectInformation  : System.Address;
    ObjectInformationLength : Interfaces.Unsigned_32;
    ReturnLength       : access Interfaces.Unsigned_32)
   return Interfaces.C.long   -- NTSTATUS
   with Convention => Stdcall;
```

### `UNICODE_STRING` interpretation

The returned buffer contains an `OBJECT_NAME_INFORMATION` struct, the first 16 bytes (64-bit) or 12 bytes (32-bit) of which are a `UNICODE_STRING`:

```c
typedef struct _UNICODE_STRING {
  USHORT Length;          // byte length of Buffer (excluding any trailing NUL)
  USHORT MaximumLength;
  PWSTR  Buffer;          // points into the same allocation, past the header
} UNICODE_STRING;
```

In Ada, consumed in the `Termicap.Win32_Cygwin` body (not declared in the Win32_Ntdll spec, to keep the Win32_Ntdll surface focused on the raw FFI):

```ada
type Unicode_String is record
   Length         : Interfaces.C.unsigned_short;
   Maximum_Length : Interfaces.C.unsigned_short;
   Buffer         : System.Address;
end record
   with Convention => C;
```

The `Buffer` field points into the same stack allocation as the struct itself — reading through it is safe while the stack frame remains live, which it does for the duration of `Retrieve_Name_Via_NtQueryObject`. This matches the documented NT semantics and go-isatty's expectation.

### Buffer sizing

- Total buffer: **1024 bytes** (matches go-isatty's `[4 + MAX_PATH]uint16` = `4 + 260` `uint16` ≈ 528 bytes, rounded up generously).
- Represented in Ada as `Interfaces.C.char16_array (0 .. 511)` = 512 `char16_t` = 1024 bytes, with the first 8 / 16 bytes (depending on bitness) reinterpreted as the `UNICODE_STRING` header via `System.Address` arithmetic or an overlaying record.

Two implementation options, both acceptable:

**Option A (overlay record)** — clearest for auditors:

```ada
type Object_Name_Buffer is record
   Header  : Unicode_String;                              -- 16 bytes on x64
   Payload : Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1);
end record
   with Convention => C;
```

However, `UNICODE_STRING.Buffer` is not guaranteed by NtQueryObject to point at `Payload'Address`: the OS may lay the name anywhere after the header. The Payload field is sized as upper bound.

**Option B (raw byte buffer + address arithmetic)** — closer to go-isatty:

```ada
--  1024 bytes, 512 UTF-16 code units, indexed 0..511
Buffer : aliased Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1);
```

Reinterpret the first ceil(sizeof(UNICODE_STRING) / 2) = 8 code units as a header via `Ada.Unchecked_Conversion` or `with Import, Address => Buffer'Address`. This is the preferred technique because it avoids assumptions about where the OS places the name data.

### Call sequence

```
function Retrieve_Name_Via_NtQueryObject
   (Handle   : Win32.Winnt.HANDLE;
    Out_Name : out String;
    Out_Last : out Natural) return Boolean
is
   --  1024-byte scratch; UNICODE_STRING header is overlaid via Address.
   Buffer : aliased Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1);
   Header : Unicode_String
      with Import, Convention => C, Address => Buffer'Address;

   Units       : Natural;
   Name_Start  : Natural;
begin
   if not Termicap.Win32_Ntdll.Query_Object_Name
             (Handle      => Handle,
              Buffer      => Buffer'Address,
              Buffer_Size => Interfaces.Unsigned_32 (Buffer'Size / 8))
   then
      return False;
   end if;

   --  FUNC-CYG-004: Length is bytes; divide by 2 for UTF-16 code units.
   Units := Natural (Header.Length) / 2;
   if Units > MAX_PIPE_NAME_LENGTH then
      Units := MAX_PIPE_NAME_LENGTH;
   end if;

   --  The name data is at Header.Buffer (System.Address inside the same allocation).
   --  We access it via an overlay char16_array at that address.
   declare
      Name_Codes : Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1)
         with Import, Convention => C, Address => Header.Buffer;
   begin
      Decode_UTF16_To_ASCII
         (Input      => Name_Codes,
          Unit_Count => Units,
          Output     => Out_Name,
          Last       => Out_Last);
   end;
   return True;
exception
   when others => return False;   -- FUNC-CYG-016
end Retrieve_Name_Via_NtQueryObject;
```

---

## G. UTF-16 → ASCII `String` Decode (FUNC-CYG-005)

All legitimate Cygwin/MSYS2 pipe names are pure ASCII. A minimal decoder that extracts only ASCII-range code units is both correct and small.

### Ada representation of UTF-16 code units

`Interfaces.C.char16_t` is an Ada 2012 type defined in GNAT's `Interfaces.C` as a 16-bit modular type (equivalent to C's `char16_t` / Windows' `WCHAR`). `Interfaces.C.char16_array` is an **unconstrained array of `char16_t` indexed by `size_t`** with index origin 0. This matches C's array semantics.

### Decoder signature and body

```ada
procedure Decode_UTF16_To_ASCII
   (Input      : Interfaces.C.char16_array;
    Unit_Count : Natural;
    Output     : out String;
    Last       : out Natural)
is
   use Interfaces.C;
   Out_Idx : Natural := Output'First - 1;
   --  We fill Output (Output'First .. Output'First + Unit_Count - 1)
   --  and set Last accordingly.
begin
   Last := Output'First - 1;
   for I in 0 .. Unit_Count - 1 loop
      exit when Out_Idx + 1 > Output'Last;
      Out_Idx := Out_Idx + 1;
      declare
         Code : constant Interfaces.C.char16_t := Input (size_t (I));
      begin
         if Code >= 16#0001# and Code <= 16#007F# then
            --  Non-null ASCII: emit as Character
            Output (Out_Idx) := Character'Val (Integer (Code));
         else
            --  NUL or non-ASCII: replace with '?'
            Output (Out_Idx) := '?';
         end if;
      end;
   end loop;
   Last := Out_Idx;
exception
   when others =>
      --  Defensive: any overflow/coercion error falls back to empty-slice output.
      Last := Output'First - 1;
end Decode_UTF16_To_ASCII;
```

### Stack-allocated output buffer

The caller (`Is_Cygwin_Terminal`) supplies a stack-local `String` bounded by `MAX_PIPE_NAME_LENGTH`:

```ada
Name_Buffer : String (1 .. MAX_PIPE_NAME_LENGTH);
Name_Last   : Natural := 0;
```

After `Retrieve_Name_Via_…` returns, the actual slice `Name_Buffer (1 .. Name_Last)` is passed to `Is_Cygwin_Pipe_Name`. The trailing uninitialised region of `Name_Buffer` is **never** read by the predicate, satisfying FUNC-CYG-005 rule 5.

> **Design note.** `'?'` substitution for non-ASCII ensures that any non-ASCII code unit produces a benign mismatch against the fixed ASCII tokens (`\cygwin`, `\msys`, `pty`, `from`, `to`, `master`, `\Device\NamedPipe\…`). No dependency on `Ada.Strings.UTF_Encoding` is taken, keeping the SPARK-unsafe surface minimal.

---

## H. TTY Integration (FUNC-CYG-015)

### Exact modification to `src/windows/termicap-tty.adb`

The current `Is_TTY_Via_Handle` body (see the file as of commit `50fcb8c`) reads:

```ada
function Is_TTY_Via_Handle
  (Std_Handle_Constant : Win32.DWORD;
   Is_Output           : Boolean) return Boolean
is
   H    : Win32.Winnt.HANDLE;
   Mode : aliased Win32.DWORD := 0;
   Res  : Win32.BOOL;
begin
   H := Win32.Winbase.GetStdHandle (Std_Handle_Constant);

   if not Termicap.Win32_VT.Is_Valid_Handle (H) then
      --  CONIN$/CONOUT$ fallback (FUNC-WIN-004) — unchanged
      ...
   end if;

   Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);

   if Res /= Win32.FALSE and then Is_Output then
      --  Enable VT processing on stdout (non-fatal if it fails)
      declare
         Dummy : constant Boolean :=
            Termicap.Win32_VT.Enable_VT_Processing (H);
         pragma Unreferenced (Dummy);
      begin
         null;
      end;
   end if;

   return Res /= Win32.FALSE;
end Is_TTY_Via_Handle;
```

After this feature, the final three-line return becomes a disjunction:

```ada
   if Res /= Win32.FALSE then
      --  (a) Native Windows console: enable VT on stdout, return True.
      if Is_Output then
         declare
            Dummy : constant Boolean :=
               Termicap.Win32_VT.Enable_VT_Processing (H);
            pragma Unreferenced (Dummy);
         begin
            null;
         end;
      end if;
      return True;
   end if;

   --  (b) GetConsoleMode failed: try Cygwin/MSYS2 PTY detection
   --  (FUNC-CYG-015). VT processing is NOT enabled here — Cygwin
   --  PTY handles do not support ENABLE_VIRTUAL_TERMINAL_PROCESSING.
   return Termicap.Win32_Cygwin.Is_Cygwin_Terminal (H);
end Is_TTY_Via_Handle;
```

Additions/edits required in `src/windows/termicap-tty.adb`:

1. New `with Termicap.Win32_Cygwin;` clause.
2. Replace the final `return Res /= Win32.FALSE;` block with the disjunction above.
3. The CONIN$/CONOUT$ fallback branch (for `not Is_Valid_Handle (H)`) **also** needs to be updated: after opening CONIN$/CONOUT$, if `GetConsoleMode` on the new handle fails, additionally check `Is_Cygwin_Terminal (H)` before closing the handle and returning.

Exact fallback-branch update:

```ada
   if not Termicap.Win32_VT.Is_Valid_Handle (H) then
      if Is_Output then
         H := Termicap.Win32_VT.Open_Console_Output;
      else
         H := Termicap.Win32_VT.Open_Console_Input;
      end if;

      if not Termicap.Win32_VT.Is_Valid_Handle (H) then
         return False;
      end if;

      Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
      if Res /= Win32.FALSE then
         Termicap.Win32_VT.Close_Handle (H);
         return True;
      end if;

      --  GetConsoleMode on reopened handle failed: check Cygwin.
      declare
         Cygwin : constant Boolean :=
            Termicap.Win32_Cygwin.Is_Cygwin_Terminal (H);
      begin
         Termicap.Win32_VT.Close_Handle (H);
         return Cygwin;
      end;
   end if;
```

### No VT enable for Cygwin handles

Per FUNC-CYG-015, `Enable_VT_Processing` is **never** called on a Cygwin PTY handle:

- Cygwin and MSYS2 runtimes interpret escape sequences inside their own PTY emulation layer; the underlying named pipe has no console mode.
- `SetConsoleMode` on a pipe handle returns `ERROR_INVALID_HANDLE` (6), requiring otherwise unnecessary error handling.
- The control flow above enforces this: `Enable_VT_Processing` is called only in the `Res /= Win32.FALSE` branch; the Cygwin branch skips it entirely.

### Short-circuit ordering

`GetConsoleMode` is still called **first**. Native console handles (the common case on Windows Terminal, `cmd.exe`, `powershell.exe`) pay **zero** additional cost: `Is_TTY_Via_Handle` returns `True` at the `Res /= Win32.FALSE` branch without invoking any of the Cygwin detection code. Only when `GetConsoleMode` fails — the minority case — does the handle pipeline flow to `Is_Cygwin_Terminal`.

---

## I. Elaboration-Time Probe

### Ada package-body elaboration

In Ada, statements that appear between `begin` and the final `end X;` of a package body execute **once** during the program's elaboration phase, before the main subprogram begins. `Termicap.Win32_Cygwin`'s body uses this hook to probe `GetFileInformationByHandleEx` availability.

### Package-level state

```ada
package body Termicap.Win32_Cygwin
   with SPARK_Mode => Off
is
   ...

   --  Elaboration-time state (FUNC-CYG-002, FUNC-CYG-017).
   --  Populated by the probe block at the bottom of the body; read
   --  by Is_Cygwin_Terminal at call time.
   Has_Get_File_Info : Boolean := False;
   Get_File_Info_Fn  : Get_File_Info_Fn_Ptr := null;

   ...

begin
   --  Package body elaboration: runs once at program startup.
   Probe_Get_File_Info;
end Termicap.Win32_Cygwin;
```

### The probe procedure

```ada
procedure Probe_Get_File_Info is
   Lib_Name  : constant String := "kernel32.dll" & ASCII.NUL;
   Proc_Name : constant String :=
      "GetFileInformationByHandleEx" & ASCII.NUL;

   H_Module : Win32.Windef.HINSTANCE;
   Proc_Ptr : Win32.Windef.FARPROC;
   Unused   : Win32.BOOL;
   pragma Unreferenced (Unused);
begin
   H_Module := Win32.Winbase.LoadLibraryA (Win32.Addr (Lib_Name));
   if H_Module = System.Null_Address then
      Has_Get_File_Info := False;
      Get_File_Info_Fn  := null;
      return;
   end if;

   Proc_Ptr := Win32.Winbase.GetProcAddress
                 (H_Module, Win32.Addr (Proc_Name));

   if Proc_Ptr = null then
      Unused := Win32.Winbase.FreeLibrary (H_Module);
      Has_Get_File_Info := False;
      Get_File_Info_Fn  := null;
      return;
   end if;

   Get_File_Info_Fn  := To_Get_File_Info (Proc_Ptr);
   Has_Get_File_Info := True;

   --  Per FUNC-CYG-002 step 5: free the module handle.
   --  The OS maintains a reference count on kernel32 for the process
   --  lifetime, so the function pointer remains valid after FreeLibrary.
   Unused := Win32.Winbase.FreeLibrary (H_Module);
exception
   when others =>
      --  Defensive: any elaboration error disables the primary path.
      Has_Get_File_Info := False;
      Get_File_Info_Fn  := null;
end Probe_Get_File_Info;
```

### Why `FreeLibrary` is safe here

`kernel32.dll` is loaded by the Windows loader into every process image before `main`/elaboration runs. `LoadLibraryA` simply increments the module's reference count; `FreeLibrary` decrements it. The module remains mapped into the process address space for the process's lifetime, so the `FARPROC` returned by `GetProcAddress` remains callable. This matches the idiom already used in `Termicap.Win32_Ntdll.Get_Build_Number` and go-isatty's `LazyDLL.NewProc` caching.

### Once-per-process guarantee

Package body elaboration is executed **exactly once** per process by the Ada runtime. No mutex is required because elaboration precedes concurrent-task startup. After elaboration, `Has_Get_File_Info` and `Get_File_Info_Fn` are **read-only** from the perspective of `Is_Cygwin_Terminal`, satisfying FUNC-CYG-002 step 4 (probe performed at most once).

---

## J. `Is_Cygwin_Terminal` Pipeline (FUNC-CYG-014)

### Full implementation outline

```ada
function Is_Cygwin_Terminal (Handle : Win32.Winnt.HANDLE) return Boolean is
   Name    : String (1 .. MAX_PIPE_NAME_LENGTH);
   Last    : Natural := 0;
   Got     : Boolean;
begin
   --  Defensive guard: invalid or null handle cannot be a Cygwin PTY.
   if Handle = Win32.Winbase.INVALID_HANDLE_VALUE
      or else Handle = System.Null_Address
   then
      return False;
   end if;

   --  Step 1: FUNC-CYG-001 GetFileType guard.
   if Win32.Winbase.GetFileType (Handle) /= Win32.Winbase.FILE_TYPE_PIPE then
      return False;
   end if;

   --  Step 2: retrieve the pipe name via the available API.
   if Has_Get_File_Info then
      Got := Retrieve_Name_Via_GetFileInfo   --  FUNC-CYG-003
                (Handle => Handle, Out_Name => Name, Out_Last => Last);
   else
      Got := Retrieve_Name_Via_NtQueryObject --  FUNC-CYG-004
                (Handle => Handle, Out_Name => Name, Out_Last => Last);
   end if;

   if not Got or else Last < Name'First then
      return False;
   end if;

   --  Step 3: hand off to the pure SPARK predicate.
   return Is_Cygwin_Pipe_Name (Name (Name'First .. Last));
exception
   when others =>
      --  FUNC-CYG-016: absolute no-exception contract.
      return False;
end Is_Cygwin_Terminal;
```

### No-exception guarantee (FUNC-CYG-016)

Defence-in-depth is applied at three levels:

1. Each FFI helper (`Retrieve_Name_Via_*`, `Decode_UTF16_To_ASCII`, `Probe_Get_File_Info`) has its own `when others => return False;` / reset-state handler.
2. `Is_Cygwin_Terminal` wraps the entire pipeline in a top-level `when others => return False;`.
3. `Is_Cygwin_Pipe_Name` is SPARK Silver and **proved** not to raise, but the surrounding `when others` protects callers if the SPARK proof ever gaps.

The `INVALID_HANDLE_VALUE` and null-handle checks at the top of `Is_Cygwin_Terminal` satisfy the "called with INVALID_HANDLE_VALUE or a null handle" clause in FUNC-CYG-016 without relying on `GetFileType`'s behaviour on invalid handles (which sets `GetLastError` but the Ada code does not inspect it).

---

## K. SPARK Boundary Details

### Subprogram-level SPARK_Mode table

| Subprogram | Location | SPARK_Mode | Notes |
|------------|----------|-----------|-------|
| `Is_Cygwin_Pipe_Name` (spec) | `termicap-win32_cygwin.ads` | On | Declared with `Global => null`, `Pre => True`, `Post => True` |
| `Is_Cygwin_Pipe_Name` (body) | `termicap-win32_cygwin.adb` | On (locally) | Pure string iteration; proves at Silver |
| `Is_Cygwin_Terminal` (spec) | `termicap-win32_cygwin.ads` | On | Spec-level declaration only; body is Off |
| `Is_Cygwin_Terminal` (body) | `termicap-win32_cygwin.adb` | Off | FFI, function-pointer deref |
| `Probe_Get_File_Info` | `termicap-win32_cygwin.adb` | Off | Elaboration-only helper |
| `Retrieve_Name_Via_GetFileInfo` | `termicap-win32_cygwin.adb` | Off | Calls FFI via function pointer |
| `Retrieve_Name_Via_NtQueryObject` | `termicap-win32_cygwin.adb` | Off | Calls `Termicap.Win32_Ntdll.Query_Object_Name` |
| `Decode_UTF16_To_ASCII` | `termicap-win32_cygwin.adb` | Off | Uses `Interfaces.C.char16_array` (tolerated in Off only) |
| `Get_File_Info_Fn_Ptr` access type | body | Off | Access-to-subprogram is outside SPARK 2014 subset |

Rationale for placing `Get_File_Info_Fn_Ptr` in the body: Ada access-to-subprogram types are explicitly excluded from SPARK (they are not statically analysable for `Global`/`Depends` by the prover). Declaring the type in the spec would forbid `SPARK_Mode => On` at the package level, conflicting with FUNC-CYG-017.

### `Is_Cygwin_Pipe_Name` provability plan

To prove the function at SPARK Silver (absence of run-time errors, respect of `Global => null`), the implementation must include explicit loop invariants that the prover can pattern-match. The main scan loop needs three invariants:

```ada
pragma Loop_Invariant (I >= Name'First - 1 and I <= Name'Last + 1);
pragma Loop_Invariant (Token_Start >= Name'First);
pragma Loop_Invariant (Token_Start <= I + 1);
pragma Loop_Invariant (Token_Idx <= 5);  -- upper bound; we return at 4
```

The first invariant bounds the scan index; the second and third bound the token-start index relative to the scan; the fourth caps the token index. With these invariants, every `Name (Token_Start .. I - 1)` slice is well-formed (empty or non-empty but within bounds), and no index or range check can fail.

Prefix-match helpers (`Is_Valid_Prefix`, `Starts_With_Pty`, `Is_From_Or_To`) are expression functions whose preconditions are implicit: `Starts_With_Pty` explicitly guards `T'Length >= 3` before indexing, so no separate `Pre` contract is needed.

### GNATprove command

The feature is verified by the same project-level invocation already used for `Termicap.Win32_Color`:

```bash
alr exec -- gnatprove -P termicap.gpr --level=2 --mode=all
```

Expected outcome: Silver for `Is_Cygwin_Pipe_Name` and its three helpers. Gold is not attempted (requires functional postconditions that are not worth the effort for a boolean validator).

---

## L. Files Created / Modified

### New files

| File | Purpose |
|------|---------|
| `src/windows/termicap-win32_cygwin.ads` | Spec: `Is_Cygwin_Pipe_Name` (SPARK), `Is_Cygwin_Terminal` |
| `src/windows/termicap-win32_cygwin.adb` | Body: FFI pipeline, elaboration probe, pure predicate body |
| `tests/src/windows/test_win32_cygwin.ads` | Test suite spec — registers 14 `Is_Cygwin_Pipe_Name` vectors |
| `tests/src/windows/test_win32_cygwin.adb` | Test suite body — each vector as a named test case |
| `examples/cygwin_pty_demo/src/cygwin_pty_demo.adb` | Demo program printing `Is_TTY` per stream + handle kind |
| `examples/cygwin_pty_demo/alire.toml` | Alire crate file for the demo |
| `examples/cygwin_pty_demo/cygwin_pty_demo.gpr` | GPR for the demo |

### Modified files

| File | Change |
|------|--------|
| `src/windows/termicap-tty.adb` | Add `with Termicap.Win32_Cygwin;`; replace final two-line return of `Is_TTY_Via_Handle` with disjunction (both the primary and the CONIN$/CONOUT$ fallback branches); §H shows the exact edits |
| `src/windows/termicap-win32_ntdll.ads` | Add `function Query_Object_Name` declaration; add `with Win32.Winnt;` and `with System;` if not already present |
| `src/windows/termicap-win32_ntdll.adb` | Add body for `Query_Object_Name` mirroring the `Get_Build_Number` dynamic-load pattern but targeting `NtQueryObject` in `ntdll.dll` |
| `tests/src/windows/termicap_tests.adb` | Register the new `test_win32_cygwin` harness |
| `examples/termicap_examples.gpr` | Include `cygwin_pty_demo` in the examples project list |
| `docs/architecture/03-building-blocks.md` | Add a new `Termicap.Win32_Cygwin` subsection (same level as `Termicap.Win32_Color`); updated automatically by `/doc-update` after implementation |
| `docs/architecture/04-runtime-view.md` | Append Scenario 25 "Windows TTY detection with Cygwin disjunction"; updated by `/doc-update` |

### Files explicitly **not** modified

- `src/windows/termicap-win32_vt.{ads,adb}` — unchanged; Cygwin detection does not need VT helpers.
- `src/windows/termicap-win32_color.{ads,adb}` — unchanged; colour detection is orthogonal.
- `src/windows/termicap-capabilities.adb` — unchanged; `Is_TTY` continues to return the correct `Boolean`; `Win32_Color.Detect_Windows_Color_Level` will then pick up the right colour level through the existing `Color_Level'Max` logic (a Cygwin PTY supports TrueColor via mintty; this is reflected already via `COLORTERM=truecolor`, which Cygwin sets).
- `src/windows/termicap-dimensions.adb` — unchanged; dimensions on Cygwin PTYs continue to use the `COLUMNS`/`LINES` env-var fallback (ioctl isn't reachable through Win32 API on a pipe handle; this is a known limitation documented in the dimensions tech spec).
- `termicap.gpr`, `alire.toml` — no new dependencies.

---

## M. Test Plan

### Unit tests — `Is_Cygwin_Pipe_Name` (14 vectors, FUNC-CYG-013)

The test package `Test_Win32_Cygwin` contains one test per vector in §D's table, named `Test_Is_Cygwin_Pipe_Name_<N>_<short_description>`. Each test calls `Is_Cygwin_Pipe_Name` with the exact input and asserts `=` against the expected Boolean. The tests run on **all platforms** because the predicate is pure and has no Windows dependency.

### Unit test — dispatch

`Test_Is_Cygwin_Terminal_Invalid_Handle`: passes `INVALID_HANDLE_VALUE` and asserts `False`. Runs on Windows only (linker depends on win32ada); implementation confined by an `alr`-level platform guard in the test body.

### Integration tests (Windows-only, manual or CI-with-Cygwin)

| Test | Mechanism | CI-safe |
|------|-----------|---------|
| `Is_TTY (Stdout) = True` under `git-bash` | Manual run on developer machine | No |
| `Is_TTY (Stdout) = False` when stdout redirected to a file | Existing pattern | Yes |
| `Is_TTY (Stdout) = True` under Windows Terminal (native console) — regression | Existing CI path | Yes |

### Example program

`examples/cygwin_pty_demo/` prints one line per stream (`Stdin`, `Stdout`, `Stderr`) with columns `Is_TTY`, `GetConsoleMode_Result`, `Is_Cygwin_Terminal_Result`, and `Handle_Kind` (console / pipe / file / invalid). Under `git-bash`, the expected output is `Is_TTY = True, GetConsoleMode_Result = False, Is_Cygwin_Terminal_Result = True` for `Stdout`.

---

## N. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `GetFileInformationByHandleEx` returns a pipe name that does not match the Cygwin grammar for a genuine Cygwin PTY (future Cygwin version changes naming) | Low | Medium | `Is_TTY` degrades to `False`, same as pre-feature behaviour; forward-compatibility via FUNC-CYG-011's "extra segments ignored" rule |
| A non-Cygwin application creates a named pipe whose name coincidentally matches the grammar | Very low | Low | False positive results in a single misclassified stream; VT processing is **not** enabled on Cygwin handles, so no terminal state is corrupted |
| `NtQueryObject` disappears from a future Windows version (very unlikely) | Very low | Medium | Same graceful degradation: `Retrieve_Name_Via_NtQueryObject` returns `False`, `Is_Cygwin_Terminal` returns `False` |
| Stack overflow from 1024-byte buffer allocation | Very low | High | 1 KiB × 2 (one for each path, but they are in separate call sites) is trivial; the Ada runtime stack is typically 1 MiB+ |
| `LoadLibraryA`/`FreeLibrary` race during elaboration under multithreaded early-startup | Very low | Low | Package body elaboration is serialised by the Ada runtime; no tasks exist yet |
| `Unchecked_Conversion` of `FARPROC` to `Get_File_Info_Fn_Ptr` has size mismatch on 32-bit vs 64-bit | Low | High | Both types are pointer-sized; GNAT's `FARPROC` definition in win32ada is already used successfully by `Termicap.Win32_Ntdll` |
| SPARK proof of `Is_Cygwin_Pipe_Name` requires non-trivial loop invariants that fail to discharge | Medium | Medium | Fallback to SPARK Bronze (absence of runtime errors only); Silver is preferred but not mandated by the requirement (`Post => True` is the contract) |

---

## O. Requirements Traceability

| Requirement | Design element | Section |
|-------------|---------------|---------|
| FUNC-CYG-001 | `GetFileType` guard at step 1 of `Is_Cygwin_Terminal` | J |
| FUNC-CYG-002 | `Probe_Get_File_Info` elaboration procedure + package-level state | I |
| FUNC-CYG-003 | `Retrieve_Name_Via_GetFileInfo` + `File_Name_Info_Record` + `Get_File_Info_Fn_Ptr` | E |
| FUNC-CYG-004 | `Retrieve_Name_Via_NtQueryObject` + `Termicap.Win32_Ntdll.Query_Object_Name` extension + `Unicode_String` overlay | F |
| FUNC-CYG-005 | `Decode_UTF16_To_ASCII` procedure; stack-allocated `String (1 .. MAX_PIPE_NAME_LENGTH)` | G |
| FUNC-CYG-006 | `Is_Cygwin_Pipe_Name` signature with `SPARK_Mode => On, Global => null` | D |
| FUNC-CYG-007 | `Is_Valid_Prefix` helper + four-constant table | D |
| FUNC-CYG-008 | Token-1 empty check in the scan loop (`Token_End < Token_Start`) | D |
| FUNC-CYG-009 | `Starts_With_Pty` helper | D |
| FUNC-CYG-010 | `Is_From_Or_To` helper | D |
| FUNC-CYG-011 | `Name (Token_Start .. Token_End) = "master"` + early `return True` at `Token_Idx = 4` | D |
| FUNC-CYG-012 | Scan loop exits without reaching `Token_Idx = 4` ⇒ `return False` | D |
| FUNC-CYG-013 | Test package `Test_Win32_Cygwin` with 14 vectors | M |
| FUNC-CYG-014 | `Is_Cygwin_Terminal` pipeline function | J |
| FUNC-CYG-015 | `Is_TTY_Via_Handle` disjunction edit; no `Enable_VT_Processing` on Cygwin branch | H |
| FUNC-CYG-016 | Triple-defence exception handling in helpers, `Is_Cygwin_Terminal`, and invalid-handle guard | J |
| FUNC-CYG-017 | `Termicap.Win32_Cygwin` package with SPARK_Mode boundary and file layout | C |

---

## P. Related Documents

- **Tech Spec WIN32** (`docs/tech-specs/windows-console.md`) — Windows Console API integration, establishes the `Termicap.Win32_*` package pattern
- **Tech Spec F2** (`docs/tech-specs/f2-tty-detection.md`) — POSIX TTY detection via `isatty(3)` and the `Termicap.TTY` package design
- **Tech Spec F9** (`docs/tech-specs/override.md`) — Override short-circuit, which is checked **before** `Is_TTY_Via_Handle` in the Windows body
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`) — GPR source-dir platform dispatch, selects the Windows body automatically
- **ADR-0019** (`docs/adr/0019-win32ada-as-ffi-layer.md`) — Primary Win32 FFI strategy, justifies the dynamic-load fallback for APIs win32ada does not provide
- **ADR-0020** (`docs/adr/0020-cygwin-pty-detection-strategy.md`) — This feature's ADR: two-path API strategy for pipe-name retrieval
- **Requirements** (`docs/requirements/cygwin-pty.sdoc`) — FUNC-CYG-001 through FUNC-CYG-017
- **Reference** (`reference-frameworks/go-isatty/isatty_windows.go`) — canonical implementation
- **Analysis** (`reference-frameworks/analysis/go-isatty-analysis.md`) — cross-language discussion of TTY + Cygwin detection
