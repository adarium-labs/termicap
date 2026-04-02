# API Reference: `Termicap.Dimensions`

Package providing terminal dimensions detection with a three-step fallback chain: ioctl(TIOCGWINSZ), environment variables (COLUMNS/LINES), then the 80×24 industry-standard default.

**File:** `src/termicap-dimensions.ads`
**SPARK_Mode:** On (spec), Off (body)
**License:** Apache-2.0

---

## Overview

`Termicap.Dimensions` exposes a single function, `Get_Size`, that determines the terminal's character-cell and pixel dimensions. It accepts an immutable `Termicap.Environment.Environment` snapshot and a `Boolean` TTY flag and performs no OS calls when `Is_TTY` is `False`, making the environment-variable and default fallback paths fully testable and SPARK-contract-compatible.

The `Global => null` contract on `Get_Size` is declared in the spec and machine-verified by GNATprove. The body has `SPARK_Mode => Off` because it binds to the C wrapper `termicap_get_winsize` via `pragma Import` and uses Ada access types as out-parameters to C.

The C wrapper (`src/c/termicap_ioctl.c`) exists because `ioctl(2)` is a variadic function that Ada cannot bind directly. The wrapper provides the fixed signature `termicap_get_winsize` and unpacks `struct winsize` into four out-parameters.

---

## Constants

### `DEFAULT_COLUMNS`

```ada
DEFAULT_COLUMNS : constant Positive := 80;
```

Industry-standard default terminal width. Used when ioctl returns zero/error and `COLUMNS` is absent or invalid.

**Requirement:** FUNC-DIM-004

---

### `DEFAULT_ROWS`

```ada
DEFAULT_ROWS : constant Positive := 24;
```

Industry-standard default terminal height. Used when ioctl returns zero/error and `LINES` is absent or invalid.

**Requirement:** FUNC-DIM-004

---

## Types

### `Terminal_Size`

```ada
type Terminal_Size is record
   Rows         : Positive;
   Columns      : Positive;
   Pixel_Width  : Natural;
   Pixel_Height : Natural;
end record;
```

Terminal dimensions in character cells and pixels.

| Field | Type | Description |
|-------|------|-------------|
| `Rows` | `Positive` | Number of character-cell rows. Always ≥ 1. |
| `Columns` | `Positive` | Number of character-cell columns. Always ≥ 1. |
| `Pixel_Width` | `Natural` | Terminal width in pixels. `0` when unavailable (non-ioctl paths, or ioctl terminal that does not report pixel size). |
| `Pixel_Height` | `Natural` | Terminal height in pixels. `0` when unavailable. |

`Rows` and `Columns` are `Positive` because a terminal always has at least one row and one column. `Pixel_Width` and `Pixel_Height` are `Natural` because pixel information is optional — many terminals set `ws_xpixel`/`ws_ypixel` to zero.

**Requirements:** FUNC-DIM-001, FUNC-DIM-008

---

## Functions

### `Get_Size`

```ada
function Get_Size
   (Env    : Termicap.Environment.Environment;
    Is_TTY : Boolean) return Terminal_Size
   with Global => null;
```

Detect terminal dimensions using a three-step fallback chain.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | Immutable environment variable snapshot. Obtained via `Termicap.Environment.Capture.Capture_Current` or built programmatically with `Insert` for testing. |
| `Is_TTY` | in | Whether stdout (fd 1) is connected to an interactive terminal. Typically the result of `Termicap.TTY.Is_TTY (Stdout)`. When `False`, the ioctl path is skipped entirely. |

**Returns:** A `Terminal_Size` record. `Rows` and `Columns` are always ≥ 1. `Pixel_Width` and `Pixel_Height` are `0` on any non-ioctl path.

**SPARK contract:** `Global => null` on the spec — verified by GNATprove. The body is `SPARK_Mode => Off` due to the C FFI call.

**Requirements:** FUNC-DIM-002, FUNC-DIM-003, FUNC-DIM-004, FUNC-DIM-005

---

## Detection Fallback Chain

`Get_Size` evaluates three steps in order. Each axis (columns and rows) falls back independently.

| Priority | Step | Source | Condition |
|----------|------|--------|-----------|
| 1 | ioctl(TIOCGWINSZ) | Kernel terminal driver | `Is_TTY = True` and `termicap_get_winsize` returns 0 and both dimensions > 0 |
| 2 | `COLUMNS` / `LINES` environment variables | Process environment snapshot | ioctl was skipped or returned an error or zero dimensions; each axis evaluated independently |
| 3 | `DEFAULT_COLUMNS` (80) / `DEFAULT_ROWS` (24) | Built-in constants | Env var absent, empty, non-numeric, overflow, or `"0"` |

The ioctl call targets stdout (file descriptor 1). If `Is_TTY = False`, step 1 is skipped and the result begins at `(Rows => 24, Columns => 80, Pixel_Width => 0, Pixel_Height => 0)` before step 2 may override `Rows` and `Columns`.

Pixel dimensions are populated only from step 1. Steps 2 and 3 always produce `Pixel_Width => 0, Pixel_Height => 0`.

**Requirements:** FUNC-DIM-002, FUNC-DIM-003, FUNC-DIM-004, FUNC-DIM-006

---

## Environment Variables Reference

| Variable | Effect |
|----------|--------|
| `COLUMNS` | Step 2: sets `Columns` if value parses as a `Positive` integer (≥ 1, no overflow). |
| `LINES` | Step 2: sets `Rows` if value parses as a `Positive` integer (≥ 1, no overflow). |

Parsing rules: leading/trailing whitespace is **not** accepted (the entire string must be digits). The value `"0"` is rejected (`Positive` requires ≥ 1). Overflow (value > `Positive'Last`) is rejected.

---

## Usage Examples

### Standard production use

```ada
with Termicap.Dimensions;              use Termicap.Dimensions;
with Termicap.Environment;             use Termicap.Environment;
with Termicap.Environment.Capture;     use Termicap.Environment.Capture;
with Termicap.TTY;                     use Termicap.TTY;

procedure Main is
   Env  : Environment;
   Size : Terminal_Size;
begin
   Capture_Current (Env);
   Size := Get_Size (Env, Is_TTY => Is_TTY (Stdout));

   Ada.Text_IO.Put_Line
      ("Terminal:" & Size.Columns'Image & " cols x" & Size.Rows'Image & " rows");
end Main;
```

### Deterministic unit test — default fallback (no OS interaction)

```ada
Env  : Environment := EMPTY_ENVIRONMENT;
Size : Terminal_Size;

--  No env vars set, not a TTY → full defaults
Size := Get_Size (Env, Is_TTY => False);
pragma Assert (Size.Columns      = DEFAULT_COLUMNS);   --  80
pragma Assert (Size.Rows         = DEFAULT_ROWS);      --  24
pragma Assert (Size.Pixel_Width  = 0);
pragma Assert (Size.Pixel_Height = 0);
```

### Deterministic unit test — environment variable override

```ada
Env  : Environment := EMPTY_ENVIRONMENT;
Size : Terminal_Size;

Insert (Env, "COLUMNS", "132");
Insert (Env, "LINES",   "50");

Size := Get_Size (Env, Is_TTY => False);
pragma Assert (Size.Columns = 132);
pragma Assert (Size.Rows    = 50);
pragma Assert (Size.Pixel_Width  = 0);   --  env path never provides pixels
pragma Assert (Size.Pixel_Height = 0);
```

### Invalid env var — ignored, falls back to default

```ada
Env  : Environment := EMPTY_ENVIRONMENT;
Size : Terminal_Size;

Insert (Env, "COLUMNS", "not_a_number");
Insert (Env, "LINES",   "0");            --  "0" is not a valid Positive

Size := Get_Size (Env, Is_TTY => False);
pragma Assert (Size.Columns = DEFAULT_COLUMNS);   --  80
pragma Assert (Size.Rows    = DEFAULT_ROWS);      --  24
```

### Per-axis independence

```ada
Env  : Environment := EMPTY_ENVIRONMENT;
Size : Terminal_Size;

--  Only COLUMNS set — LINES falls back to default
Insert (Env, "COLUMNS", "220");

Size := Get_Size (Env, Is_TTY => False);
pragma Assert (Size.Columns = 220);
pragma Assert (Size.Rows    = DEFAULT_ROWS);   --  24
```

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-DIM-001 | `Terminal_Size` record type | Silver (spec) |
| FUNC-DIM-002 | ioctl(TIOCGWINSZ) path in `Get_Size` | Off (body) |
| FUNC-DIM-003 | `COLUMNS`/`LINES` env var fallback in `Get_Size` | Off (body) |
| FUNC-DIM-004 | `DEFAULT_COLUMNS`/`DEFAULT_ROWS` constants; final fallback | Silver (constants in spec) |
| FUNC-DIM-005 | `Get_Size` signature with `Global => null` | Silver (spec) |
| FUNC-DIM-006 | `C_Get_Winsize` pragma Import; `termicap_ioctl.c` wrapper | Off (body + C) |
| FUNC-DIM-007 | Spec: `SPARK_Mode`; Body: `SPARK_Mode => Off` | Silver (spec) / Off (body) |
| FUNC-DIM-008 | `Pixel_Width`/`Pixel_Height` fields in `Terminal_Size` | Silver (spec) |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, fallback chain description, SPARK boundary diagram
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenarios 9–11: ioctl path, env var fallback, testability pattern
- **ADR-0006** (`docs/adr/0006-c-wrapper-for-ioctl-tiocgwinsz.md`) — rationale for the thin C wrapper over ioctl
- **Tech Spec F4** (`docs/tech-specs/terminal-dimensions.md`) — full design rationale
- **[Termicap.Environment](termicap-environment.md)** — environment snapshot type used as input
- **[Termicap.TTY](termicap-tty.md)** — `Is_TTY` call that supplies the `Is_TTY` parameter
