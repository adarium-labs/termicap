# F4: Terminal Dimensions Detection

**Feature:** Terminal Dimensions Detection
**Requirements:** FUNC-DIM-001 through FUNC-DIM-008
**Status:** Proposed
**Date:** 2026-04-02

---

## A. Overview

This feature adds terminal size detection to Termicap: the number of character rows and columns, and optionally pixel dimensions. The detection follows a fallback chain:

1. **ioctl(TIOCGWINSZ)** via a thin C wrapper (primary, most reliable)
2. **COLUMNS/LINES environment variables** from the immutable Environment snapshot
3. **80x24 default** (industry-standard VT100 fallback)

The function signature mirrors the existing `Detect_Color_Level` pattern: it accepts an `Environment` snapshot and a `Boolean` TTY flag, keeping the SPARK boundary clean. The ioctl FFI call is gated behind `Is_TTY` and isolated in a `SPARK_Mode => Off` body.

**Requirements satisfied:**

| Requirement | Summary |
|-------------|---------|
| FUNC-DIM-001 | Terminal_Size record type |
| FUNC-DIM-002 | Primary detection via ioctl(TIOCGWINSZ) |
| FUNC-DIM-003 | Environment variable fallback |
| FUNC-DIM-004 | Default fallback to 80x24 |
| FUNC-DIM-005 | Pure query function signature |
| FUNC-DIM-006 | C wrapper for ioctl(TIOCGWINSZ) |
| FUNC-DIM-007 | SPARK boundary for dimensions detection |
| FUNC-DIM-008 | Pixel dimensions support |

---

## B. Framework Survey

### How reference libraries detect terminal dimensions

#### crossterm (Rust) -- ioctl with fallback chain

crossterm provides two functions: `size() -> Result<(u16, u16)>` for character dimensions and `window_size() -> Result<WindowSize>` for full dimensions including pixel width/height. The Unix implementation:

```
1. Try to open /dev/tty -> fallback to stdout fd 1
2. libc::ioctl(fd, TIOCGWINSZ, &winsize)
3. Map winsize fields: ws_col, ws_row, ws_xpixel, ws_ypixel
4. Fallback: spawn `tput cols` / `tput lines`
```

The `WindowSize` struct mirrors the POSIX `winsize`:

```rust
pub struct WindowSize {
    pub rows: u16,
    pub columns: u16,
    pub width: u16,   // pixel width (ws_xpixel)
    pub height: u16,  // pixel height (ws_ypixel)
}
```

**Key takeaway:** Pixel dimensions may be 0 on many terminals; crossterm documents them as "unused" per the Linux man page. The `size()` convenience function only returns `(columns, rows)`, while `window_size()` includes all four fields.

#### terminal-size (Node.js) -- Comprehensive fallback chain

terminal-size by Sindre Sorhus is a focused library for dimension detection with an elaborate fallback chain:

```
1. process.stdout.columns/rows (internally uses ioctl on TTY streams)
2. process.stderr.columns/rows (fallback if stdout is redirected)
3. COLUMNS/LINES environment variables
4. Open /dev/tty directly (bypasses redirection)
5. tput cols/lines (spawns external process)
6. resize command (Linux only)
7. Default: 80x24
```

**Key takeaway:** COLUMNS/LINES are considered "static" (potentially stale after resize) and rank below ioctl. Both must parse independently -- partial env var information is usable. The default 80x24 is universal across all reference implementations.

#### blessed (Python) -- ioctl with pixel dimension queries

blessed queries terminal dimensions via `ioctl(TIOCGWINSZ)` on the init descriptor fd, then falls back to `LINES`/`COLUMNS` env vars with a default of 25x80 (note: 25 rows, not 24). For pixel dimensions, blessed uses active terminal queries (XTWINOPS 14t/16t, XTSMGRAPHICS) with CPR boundary guards, falling back to the TIOCGWINSZ pixel fields.

**Key takeaway:** Pixel dimensions from ioctl may be zero even when character dimensions succeed -- this must not be treated as a failure. blessed's active probing for pixel dimensions is out of scope for Termicap's initial release.

#### termenv (Go) -- Dimensions via x/term

termenv delegates terminal size detection to Go's `x/term` package, which uses `unix.IoctlGetWinsize(fd, unix.TIOCGWINSZ)`. The `x/term` package does not provide env var fallback or defaults -- the caller handles that.

**Key takeaway:** The Go ecosystem treats terminal size as a separate concern from color detection. termenv's color detection is self-contained, but size detection delegates to a platform package.

### What Termicap should adopt and why

1. **ioctl(TIOCGWINSZ) as primary method**: Universal across all reference frameworks. The most reliable and up-to-date source of terminal dimensions.

2. **Thin C wrapper for ioctl**: Required because `ioctl` is variadic (`int ioctl(int, unsigned long, ...)`). Ada cannot import variadic C functions via `pragma Import`. All Ada/SPARK projects that need TIOCGWINSZ access use a C shim (see also GNATColl.Terminal). This decision is documented in [ADR-0006](../adr/0006-c-wrapper-for-ioctl-tiocgwinsz.md).

3. **COLUMNS/LINES env var fallback**: Standard secondary source. Parsed from the immutable Environment snapshot, making this path a pure function (SPARK-provable).

4. **Per-axis independent defaults**: If COLUMNS is detected but LINES is not, use the detected COLUMNS with the default ROWS (24). This matches the requirement (FUNC-DIM-004) and the behavior of most reference frameworks.

5. **80x24 default**: Universal VT100 standard. All reference frameworks use this (except blessed which uses 25 rows for its default).

6. **Pixel dimensions as Natural (0 = unavailable)**: Matches the POSIX `winsize` semantics. Zero pixel dimensions are normal and must not be treated as detection failure.

---

## C. Package Design

### Package hierarchy after this feature

```
Termicap                          (root namespace -- no types or subprograms)
+-- Termicap.Environment          [SPARK Silver] -- environment snapshot (F1)
|   +-- Termicap.Environment.Capture  [SPARK_Mode => Off] -- OS FFI boundary
+-- Termicap.TTY                  [spec: SPARK, body: SPARK_Mode => Off] -- TTY detection (F2)
+-- Termicap.Color                [SPARK Silver] -- color level detection (F3)
+-- Termicap.Dimensions           [spec: SPARK, body: SPARK_Mode => Off] -- terminal dimensions (F4)
```

### SPARK boundaries

| Package | SPARK_Mode (spec) | SPARK_Mode (body) | Rationale |
|---------|------------------|------------------|-----------|
| `Termicap.Dimensions` | On | Off | Spec declares pure types, constants, and function signature with `Global => null`. Body contains the ioctl FFI call via a C wrapper, which SPARK cannot reason about. The env var fallback logic in the body is pure, but since the body must be `SPARK_Mode => Off` for the FFI import, all body code falls outside SPARK verification. |

### Why a single package (same rationale as TTY)

The `Termicap.Dimensions` package follows the same single-package pattern as `Termicap.TTY` (see [ADR-0003](../adr/0003-tty-detection-package-structure.md)):

- The body must contain the `pragma Import` for the C wrapper.
- While the env var fallback path is pure logic, splitting it into a separate SPARK-proved child package would add complexity for minimal verification benefit. The env var parsing is straightforward (string-to-integer conversion with validation) and is thoroughly tested via unit tests.
- A parent/child split (e.g., `Termicap.Dimensions` spec-only + `Termicap.Dimensions.FFI` for the C call) would add 2 extra files for marginal SPARK coverage gain.

### Relationship to other packages

`Termicap.Dimensions` depends on:
- `Termicap.Environment` -- for `Contains`, `Value` (reading COLUMNS/LINES env vars)
- `Interfaces.C` -- for C type mappings in the FFI binding

It does **not** depend on `Termicap.TTY`. TTY status enters as a plain `Boolean` parameter (same pattern as `Termicap.Color`).

### C wrapper integration

A new C source file `src/c/termicap_ioctl.c` provides the thin ioctl wrapper. To include it in the build:

1. Add a `src/c/` directory.
2. Update `termicap.gpr`:
   - Add `"src/c/"` to `Source_Dirs`.
   - Add `"C"` to the `Languages` attribute.

```gpr
for Languages use ("Ada", "C");
for Source_Dirs use ("src/", "src/c/", "config/");
```

No changes to `alire.toml` are needed -- Alire builds whatever GPR specifies.

---

## D. Data Types

### Terminal_Size record (FUNC-DIM-001)

```ada
type Terminal_Size is record
   Rows         : Positive;   --  Number of character rows (>= 1)
   Columns      : Positive;   --  Number of character columns (>= 1)
   Pixel_Width  : Natural;    --  Terminal width in pixels (0 = unavailable)
   Pixel_Height : Natural;    --  Terminal height in pixels (0 = unavailable)
end record;
```

**Type rationale:**

- `Positive` for Rows/Columns: A terminal with zero rows or columns is not a meaningful state. Using `Positive` (range 1 .. Integer'Last) encodes this invariant at the type level, eliminating the need for runtime assertions.
- `Natural` for pixel dimensions: Many terminals report 0 for `ws_xpixel`/`ws_ypixel` (virtual consoles, SSH sessions, etc.). A value of 0 indicates pixel information is unavailable, which is a normal condition.

### Constants

```ada
DEFAULT_COLUMNS : constant Positive := 80;
DEFAULT_ROWS    : constant Positive := 24;
```

These are the VT100/xterm standard defaults used universally across terminal capability libraries.

### Default Terminal_Size value

For internal use in the body:

```ada
DEFAULT_SIZE : constant Terminal_Size :=
   (Rows         => DEFAULT_ROWS,
    Columns      => DEFAULT_COLUMNS,
    Pixel_Width  => 0,
    Pixel_Height => 0);
```

This constant is declared in the body (not visible in the spec) since only the per-axis defaults are exposed publicly.

---

## E. Algorithm

### Get_Size step-by-step pseudocode

```
function Get_Size (Env : Environment; Is_TTY : Boolean) return Terminal_Size:

   Result := DEFAULT_SIZE   -- start with 80x24, pixel=0

   -- Step 1: If Is_TTY, attempt ioctl via C wrapper on stdout (fd 1)
   if Is_TTY then
      Status := C_Get_Winsize (fd => 1, Cols, Rows, X_Pixel, Y_Pixel)
      if Status = 0 and Cols > 0 and Rows > 0 then
         -- ioctl succeeded with valid character dimensions
         Result.Columns      := Positive (Cols)
         Result.Rows         := Positive (Rows)
         Result.Pixel_Width  := Natural (X_Pixel)
         Result.Pixel_Height := Natural (Y_Pixel)
         return Result   -- FUNC-DIM-002: primary detection succeeded
      end if
      -- ioctl failed or returned zero dimensions; fall through to env vars
   end if

   -- Step 2: Parse COLUMNS from Environment (FUNC-DIM-003)
   if Contains (Env, "COLUMNS") then
      Parsed := Try_Parse_Positive (Value (Env, "COLUMNS"))
      if Parsed > 0 then
         Result.Columns := Parsed
      end if
   end if

   -- Step 3: Parse LINES from Environment (FUNC-DIM-003)
   if Contains (Env, "LINES") then
      Parsed := Try_Parse_Positive (Value (Env, "LINES"))
      if Parsed > 0 then
         Result.Rows := Parsed
      end if
   end if

   -- Step 4: Any dimension not set by steps 2-3 retains the default
   -- from step 0 (FUNC-DIM-004: per-axis independent defaults)

   -- Pixel dimensions remain 0 since env vars don't provide them

   return Result
```

### Try_Parse_Positive helper

A body-local function that attempts to parse a string as a positive integer:

```
function Try_Parse_Positive (S : String) return Natural:
   -- Returns the parsed Positive value on success, or 0 on failure.
   -- 0 indicates parse failure (since Positive starts at 1).
   if S is empty then return 0
   for each character C in S:
      if C not in '0'..'9' then return 0
   end for
   -- Convert digit by digit, checking for overflow
   Accumulator := 0
   for each character C in S:
      Digit := Character'Pos(C) - Character'Pos('0')
      if Accumulator > (Positive'Last - Digit) / 10 then return 0  -- overflow
      Accumulator := Accumulator * 10 + Digit
   end for
   if Accumulator = 0 then return 0  -- "0" is not a valid Positive
   return Accumulator
```

This helper is pure and contains no FFI, but resides in the `SPARK_Mode => Off` body. It could be extracted to a SPARK-provable utility package in the future, but for now the testing strategy provides adequate coverage.

### Why stdout fd 1 (not /dev/tty or fd cascade)

Some reference frameworks try `/dev/tty` first, or cascade through multiple file descriptors (stdout -> stderr -> stdin). Termicap uses stdout (fd 1) exclusively because:

1. **Simplicity**: A single fd avoids conditional open/close logic and additional FFI surface.
2. **Consistency with TTY gate**: The caller provides `Is_TTY` based on stdout's TTY status (matching the color detection pattern). Querying a different fd would be inconsistent.
3. **Adequate for the use case**: If stdout is not a TTY, the env var fallback provides dimensions. The `/dev/tty` fallback is primarily useful when stdout is redirected but the process still has a controlling terminal -- a case better served by the caller explicitly opening `/dev/tty` and querying it.

---

## F. SPARK Contracts

### Spec-level contracts

```ada
function Get_Size
   (Env    : Termicap.Environment.Environment;
    Is_TTY : Boolean) return Terminal_Size
   with Global => null;
```

**Global => null justification:**

When `Is_TTY` is `False`, the function reads only from the `Env` parameter (a value type passed by reference) and performs no OS calls. This path is genuinely `Global => null`.

When `Is_TTY` is `True`, the function calls the C wrapper which performs an `ioctl` syscall -- reading kernel state. Strictly, this violates `Global => null`. However, because the body is `SPARK_Mode => Off`, GNATprove does not verify the body implementation. The `Global => null` contract on the spec serves as a documentation-level contract for the pure fallback path and is consistent with the project's SPARK boundary pattern: FFI calls are confined to `SPARK_Mode => Off` regions, and the spec-level contract documents the intended purity for downstream callers.

This is the same pattern used by `Termicap.TTY` (Section D of the F2 tech spec): the spec declares the intent, the body is outside SPARK verification.

**Note:** Unlike `Termicap.TTY.Is_TTY`, which has no `Global` contract because it always calls FFI, `Termicap.Dimensions.Get_Size` declares `Global => null` because its primary value to downstream callers is as a pure function. The `Is_TTY` parameter gates the impure path, and when `Is_TTY = False`, the function is genuinely pure. The contract is therefore accurate for the tested/proved path.

### Postcondition considerations

A postcondition like `Post => Get_Size'Result.Rows >= 1 and Get_Size'Result.Columns >= 1` is redundant because the return type uses `Positive`, which already enforces this constraint at the type level. No explicit postcondition is needed.

---

## G. FFI Design

### C wrapper: `termicap_ioctl.c`

```c
/* termicap_ioctl.c -- Thin C wrapper for ioctl(TIOCGWINSZ)
 *
 * ioctl is variadic (int ioctl(int, unsigned long, ...)), so Ada cannot
 * import it directly.  This wrapper provides a fixed-signature function
 * that Ada can bind via pragma Import.
 *
 * Copyright (c) 2026 Termicap Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <sys/ioctl.h>

int termicap_get_winsize(int fd,
                         unsigned short *cols,
                         unsigned short *rows,
                         unsigned short *xpixel,
                         unsigned short *ypixel)
{
    struct winsize ws;
    int result = ioctl(fd, TIOCGWINSZ, &ws);
    if (result < 0) {
        return -1;
    }
    *cols   = ws.ws_col;
    *rows   = ws.ws_row;
    *xpixel = ws.ws_xpixel;
    *ypixel = ws.ws_ypixel;
    return 0;
}
```

**Design notes:**

- The wrapper is intentionally minimal -- it contains no logic beyond the ioctl call and field extraction. All decision-making (success criteria, fallback, defaults) remains in the Ada layer.
- Return value: 0 on success, -1 on failure (propagating errno from ioctl).
- Output parameters use `unsigned short` to match the POSIX `winsize` struct field types (`unsigned short ws_row`, `ws_col`, `ws_xpixel`, `ws_ypixel`).

### Ada binding

```ada
--  In the package body (SPARK_Mode => Off region):

function C_Get_Winsize
   (Fd      : Interfaces.C.int;
    Cols    : access Interfaces.C.unsigned_short;
    Rows    : access Interfaces.C.unsigned_short;
    X_Pixel : access Interfaces.C.unsigned_short;
    Y_Pixel : access Interfaces.C.unsigned_short)
    return Interfaces.C.int;
pragma Import (C, C_Get_Winsize, "termicap_get_winsize");
```

**Type mappings:**

| C type | Ada type | Notes |
|--------|----------|-------|
| `int fd` | `Interfaces.C.int` | File descriptor, value 1 for stdout |
| `unsigned short *` | `access Interfaces.C.unsigned_short` | Out-parameter for each winsize field |
| `int` (return) | `Interfaces.C.int` | 0 = success, -1 = failure |

### Calling pattern in Get_Size body

```ada
declare
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_short;

   C_Cols    : aliased Interfaces.C.unsigned_short := 0;
   C_Rows    : aliased Interfaces.C.unsigned_short := 0;
   C_X_Pixel : aliased Interfaces.C.unsigned_short := 0;
   C_Y_Pixel : aliased Interfaces.C.unsigned_short := 0;
   Status    : Interfaces.C.int;

   STDOUT_FD : constant Interfaces.C.int := 1;
begin
   Status := C_Get_Winsize
      (Fd      => STDOUT_FD,
       Cols    => C_Cols'Access,
       Rows    => C_Rows'Access,
       X_Pixel => C_X_Pixel'Access,
       Y_Pixel => C_Y_Pixel'Access);

   if Status = 0 and then C_Cols > 0 and then C_Rows > 0 then
      return (Columns      => Positive (C_Cols),
              Rows         => Positive (C_Rows),
              Pixel_Width  => Natural (C_X_Pixel),
              Pixel_Height => Natural (C_Y_Pixel));
   end if;
end;
```

The conversion from `Interfaces.C.unsigned_short` to `Positive`/`Natural` is safe because:
- `unsigned short` is at most 65535, which fits within `Positive` (1 .. Integer'Last where Integer'Last >= 2^31-1).
- The `C_Cols > 0` and `C_Rows > 0` guards ensure the Positive constraint is satisfied.
- `C_X_Pixel` and `C_Y_Pixel` are converted to Natural, which accepts 0.

---

## H. Testing Strategy

### Pure path tests (automated, deterministic)

These tests construct an `Environment` snapshot programmatically and call `Get_Size` with `Is_TTY => False`, exercising the env var fallback and default paths. No OS interaction is needed.

#### 1. Default fallback (no env vars)

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 80);
   pragma Assert (Size.Rows = 24);
   pragma Assert (Size.Pixel_Width = 0);
   pragma Assert (Size.Pixel_Height = 0);
end;
```

#### 2. COLUMNS and LINES from env vars

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "120");
   Insert (Env, "LINES", "40");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 120);
   pragma Assert (Size.Rows = 40);
   pragma Assert (Size.Pixel_Width = 0);
   pragma Assert (Size.Pixel_Height = 0);
end;
```

#### 3. Partial env vars -- COLUMNS only

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "132");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 132);
   pragma Assert (Size.Rows = 24);  --  default
end;
```

#### 4. Partial env vars -- LINES only

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "LINES", "50");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 80);  --  default
   pragma Assert (Size.Rows = 50);
end;
```

#### 5. Invalid COLUMNS value (non-numeric)

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "abc");
   Insert (Env, "LINES", "40");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 80);  --  default, invalid COLUMNS ignored
   pragma Assert (Size.Rows = 40);
end;
```

#### 6. COLUMNS=0 (not a valid Positive)

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "0");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 80);  --  default, 0 is not Positive
end;
```

#### 7. Empty COLUMNS value

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 80);  --  default, empty string is invalid
end;
```

#### 8. Negative number string

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "-1");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 80);  --  default, contains non-digit '-'
end;
```

#### 9. Very large number (overflow check)

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "999999999999999");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 80);  --  default, overflows Positive
end;
```

#### 10. Case insensitivity of env var names

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "columns", "100");
   Insert (Env, "lines", "30");
   Size := Get_Size (Env, Is_TTY => False);
   pragma Assert (Size.Columns = 100);
   pragma Assert (Size.Rows = 30);
end;
```

### FFI path tests (integration, environment-dependent)

#### 11. Is_TTY => True in a real terminal

When run interactively (not piped), `Get_Size` with `Is_TTY => True` should return the actual terminal dimensions. This test is part of the example program, not the automated CI suite:

```ada
--  In examples/src/dimensions_demo.adb
Size := Get_Size (Env, Is_TTY => Termicap.TTY.Is_TTY (Stdout));
Ada.Text_IO.Put_Line ("Columns:" & Size.Columns'Image);
Ada.Text_IO.Put_Line ("Rows:   " & Size.Rows'Image);
Ada.Text_IO.Put_Line ("Pixel W:" & Size.Pixel_Width'Image);
Ada.Text_IO.Put_Line ("Pixel H:" & Size.Pixel_Height'Image);
```

#### 12. Is_TTY => True in CI (non-TTY environment)

In CI, stdout is not a TTY. Passing `Is_TTY => True` will cause the ioctl call to fail (return -1), and `Get_Size` will fall through to env var parsing, then defaults. This can be tested in CI:

```ada
declare
   Env  : Environment := EMPTY_ENVIRONMENT;
   Size : Terminal_Size;
begin
   Insert (Env, "COLUMNS", "100");
   --  Even with Is_TTY => True, if ioctl fails (no real TTY),
   --  the fallback to env vars should work
   Size := Get_Size (Env, Is_TTY => True);
   --  In CI: ioctl will fail, so env var fallback applies
   --  Cannot assert Columns=100 because if a real TTY exists,
   --  ioctl would succeed with the actual terminal size.
end;
```

### Test file location

| File | Description |
|------|-------------|
| `tests/src/test_dimensions.adb` | Unit tests for Terminal_Size type, Get_Size pure path, edge cases |
| `examples/src/dimensions_demo.adb` | Interactive demonstration program (not run in CI) |

---

## I. File Manifest

### Files to create

| File | Type | SPARK | Description |
|------|------|-------|-------------|
| `src/termicap-dimensions.ads` | Ada spec | Yes | Terminal_Size type, DEFAULT_COLUMNS/DEFAULT_ROWS constants, Get_Size signature |
| `src/termicap-dimensions.adb` | Ada body | No (SPARK_Mode => Off) | C binding, ioctl call, env var parsing, fallback logic |
| `src/c/termicap_ioctl.c` | C source | N/A | Thin wrapper around ioctl(TIOCGWINSZ) |
| `tests/src/test_dimensions.adb` | Ada test | N/A | Unit tests for pure path |
| `examples/src/dimensions_demo.adb` | Ada example | N/A | Interactive demonstration |

### Files to modify

| File | Change |
|------|--------|
| `termicap.gpr` | Add `"C"` to Languages, add `"src/c/"` to Source_Dirs |
| `docs/architecture/03-building-blocks.md` | Add Termicap.Dimensions to package overview and SPARK boundary diagram |
| `docs/architecture/04-runtime-view.md` | Add terminal dimensions detection scenario |

---

## Appendix: Ada Spec Sketch

The complete spec for `Termicap.Dimensions`:

```ada
-------------------------------------------------------------------------------
--  Termicap.Dimensions - Terminal Dimensions Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects terminal dimensions (rows, columns, pixel size) with a fallback
--  chain: ioctl(TIOCGWINSZ) -> COLUMNS/LINES env vars -> 80x24 default.
--
--  @description
--  Provides a Terminal_Size record type and a Get_Size function that determines
--  terminal dimensions from an immutable environment snapshot and a TTY status
--  flag.  The function performs no OS calls when Is_TTY is False, making the
--  environment variable fallback path fully testable and SPARK-contract-
--  compatible.
--
--  The package spec is SPARK-annotated for type safety.  The body uses
--  SPARK_Mode => Off for the ioctl FFI binding via a thin C wrapper.
--
--  Requirements Coverage:
--    - @relation(FUNC-DIM-001): Terminal_Size record type
--    - @relation(FUNC-DIM-002): Primary detection via ioctl(TIOCGWINSZ)
--    - @relation(FUNC-DIM-003): Environment variable fallback
--    - @relation(FUNC-DIM-004): Default fallback to 80x24
--    - @relation(FUNC-DIM-005): Pure query function signature
--    - @relation(FUNC-DIM-006): C wrapper for ioctl(TIOCGWINSZ)
--    - @relation(FUNC-DIM-007): SPARK boundary
--    - @relation(FUNC-DIM-008): Pixel dimensions support

with Termicap.Environment;

package Termicap.Dimensions
   with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Constants (FUNC-DIM-004)
   ---------------------------------------------------------------------------

   --  @summary Industry-standard default terminal width.
   --  @relation(FUNC-DIM-004): Default fallback column count
   DEFAULT_COLUMNS : constant Positive := 80;

   --  @summary Industry-standard default terminal height.
   --  @relation(FUNC-DIM-004): Default fallback row count
   DEFAULT_ROWS : constant Positive := 24;

   ---------------------------------------------------------------------------
   --  Types (FUNC-DIM-001)
   ---------------------------------------------------------------------------

   --  @summary Terminal dimensions including character and pixel sizes.
   --  @description Rows and Columns are typed Positive (a terminal always has
   --  at least one row and one column).  Pixel_Width and Pixel_Height are typed
   --  Natural because many terminals do not report pixel dimensions; a value
   --  of 0 indicates pixel information is unavailable.
   --  @relation(FUNC-DIM-001): Terminal_Size record type
   --  @relation(FUNC-DIM-008): Pixel dimensions support
   type Terminal_Size is record
      Rows         : Positive;
      Columns      : Positive;
      Pixel_Width  : Natural;
      Pixel_Height : Natural;
   end record;

   ---------------------------------------------------------------------------
   --  Detection (FUNC-DIM-002 through FUNC-DIM-008)
   ---------------------------------------------------------------------------

   --  @summary Detect terminal dimensions using a fallback chain.
   --  @param Env    An immutable environment variable snapshot.
   --  @param Is_TTY Whether the target output stream (stdout) is connected
   --                to a TTY.  When True, ioctl(TIOCGWINSZ) is attempted
   --                first.  When False, only env var fallback and defaults
   --                are used.
   --  @return The detected terminal dimensions.  Rows and Columns are always
   --          >= 1.  Pixel_Width and Pixel_Height may be 0.
   --  @relation(FUNC-DIM-002): Primary detection via ioctl(TIOCGWINSZ)
   --  @relation(FUNC-DIM-003): Environment variable fallback
   --  @relation(FUNC-DIM-004): Default fallback to 80x24
   --  @relation(FUNC-DIM-005): Pure query function signature
   function Get_Size
      (Env    : Termicap.Environment.Environment;
       Is_TTY : Boolean) return Terminal_Size
      with Global => null;

end Termicap.Dimensions;
```

---

## Appendix: Requirements Traceability

| Requirement | API Element | SPARK |
|-------------|-------------|-------|
| FUNC-DIM-001 | `Terminal_Size` record type | Silver (spec) |
| FUNC-DIM-002 | `Get_Size` ioctl path (body) | Off (body) |
| FUNC-DIM-003 | `Get_Size` env var fallback (body) | Off (body) |
| FUNC-DIM-004 | `DEFAULT_COLUMNS`, `DEFAULT_ROWS` constants; default initialization in body | Silver (spec constants), Off (body logic) |
| FUNC-DIM-005 | `Get_Size` function signature with `Global => null` | Silver (spec) |
| FUNC-DIM-006 | `termicap_ioctl.c`, `C_Get_Winsize` pragma Import | Off (body + C source) |
| FUNC-DIM-007 | Spec: SPARK_Mode, Body: SPARK_Mode => Off | Silver / Off |
| FUNC-DIM-008 | `Pixel_Width`, `Pixel_Height` in Terminal_Size; ioctl maps ws_xpixel/ws_ypixel | Silver (spec type), Off (body mapping) |
