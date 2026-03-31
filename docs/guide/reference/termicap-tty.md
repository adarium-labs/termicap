# API Reference: `Termicap.TTY`

Package providing per-stream TTY (terminal teletype) detection using POSIX `isatty()`.

**File:** `src/termicap-tty.ads`
**SPARK_Mode:** On (spec), Off (body)
**License:** Apache-2.0

---

## Overview

`Termicap.TTY` detects whether standard I/O streams are connected to an interactive terminal. It provides a type-safe `Stream_Kind` enumeration over raw file descriptor numbers, and maps any detection error to `False` (safe default).

The package spec is SPARK-annotated for type safety. The body has `SPARK_Mode => Off` because it binds to the C library function `isatty()` via `pragma Import`. Downstream detection functions should capture the TTY status once and pass it as a plain `Boolean` parameter into SPARK-provable code.

`Termicap.TTY` has **no dependency** on `Termicap.Environment` — they are independent foundational building blocks.

---

## Types

### `Stream_Kind`

```ada
type Stream_Kind is (Stdin, Stdout, Stderr);
```

Identifies a standard I/O stream. The positional values match the POSIX file descriptor convention:

| Value | File Descriptor |
|-------|----------------|
| `Stdin` | 0 |
| `Stdout` | 1 |
| `Stderr` | 2 |

The fd mapping is an internal implementation detail — callers never need to know the descriptor numbers.

**Requirement:** FUNC-TTY-001

---

### `TTY_Status`

```ada
type TTY_Status is record
   Stdin  : Boolean;
   Stdout : Boolean;
   Stderr : Boolean;
end record;
```

TTY status for all three standard streams. Returned by `Query_All` for bulk queries.

**Requirement:** FUNC-TTY-006

---

## Functions

### `Is_TTY`

```ada
function Is_TTY (Stream : Stream_Kind) return Boolean;
```

Check whether a standard stream is connected to an interactive terminal.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Stream` | in | The stream to query. |

**Returns:** `True` if the stream is connected to an interactive terminal. `False` otherwise, including when the stream handle is invalid or the query fails for any reason.

**Safety:** This function is safe to call at any time. It does not modify terminal state, and returns `False` rather than raising an exception on any error (FUNC-TTY-004).

**Implementation:** Calls POSIX `isatty(fd)` where `fd` is the file descriptor corresponding to `Stream`. Returns `True` only if `isatty()` returns exactly `1`.

```ada
--  Check if stdout is interactive before using colors
if Is_TTY (Stdout) then
   --  Safe to use ANSI escape codes
   Put_Line (ESC & "[32mSuccess" & ESC & "[0m");
else
   --  Plain text output (piped or redirected)
   Put_Line ("Success");
end if;
```

**Requirements:** FUNC-TTY-002, FUNC-TTY-003, FUNC-TTY-004

---

### `Query_All`

```ada
function Query_All return TTY_Status;
```

Query TTY status for all three streams at once.

**Returns:** A `TTY_Status` record containing the TTY status of Stdin, Stdout, and Stderr.

Equivalent to calling `Is_TTY` for each stream individually, but expresses the intent of querying all streams at once.

```ada
declare
   Status : constant TTY_Status := Query_All;
begin
   if Status.Stdout then
      --  stdout is a terminal
   end if;
   if not Status.Stdin then
      --  stdin is piped — read from pipe/file
   end if;
end;
```

**Requirement:** FUNC-TTY-006

---

## Usage Patterns

### Pattern 1: TTY gate for color output

```ada
with Termicap.TTY; use Termicap.TTY;

--  Only use colors when stdout is interactive
if Is_TTY (Stdout) then
   Enable_Colors;
end if;
```

### Pattern 2: Passing TTY status to SPARK-provable detection

```ada
--  In application init (Ada-only region):
Is_Interactive : constant Boolean := Termicap.TTY.Is_TTY (Stdout);

--  In SPARK-provable detection function:
function Detect_Color_Level
   (Env            : Termicap.Environment.Environment;
    Is_Interactive : Boolean) return Color_Level
   with Global => null;
```

This preserves the SPARK boundary: `Is_TTY` is called once outside the provable zone, and the result flows as a plain `Boolean` into the detection chain.

### Pattern 3: Per-stream behavior

```ada
declare
   Status : constant TTY_Status := Query_All;
begin
   --  stdout may be piped while stderr remains a terminal
   if Status.Stdout then
      --  Interactive output: use progress bars, colors
   else
      --  Piped output: plain text, machine-readable
   end if;

   if not Status.Stdin then
      --  Reading from pipe/file, not interactive input
   end if;
end;
```

---

## Requirements Traceability

| Requirement | API Element | SPARK |
|-------------|-------------|-------|
| FUNC-TTY-001 | `Stream_Kind` enumeration, `TTY_Status` record | Silver (spec) |
| FUNC-TTY-002 | `Is_TTY` function | Spec: Silver, Body: Off |
| FUNC-TTY-003 | `C_Isatty` pragma Import, `FD_MAP` array (internal) | Off (body only) |
| FUNC-TTY-004 | `Is_TTY` returns `False` on error (`C_Isatty /= 1`) | Off (body only) |
| FUNC-TTY-005 | Spec: `SPARK_Mode`, Body: `SPARK_Mode => Off` | Silver / Off |
| FUNC-TTY-006 | `TTY_Status` record, `Query_All` function | Spec: Silver, Body: Off |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy and SPARK boundary diagram
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — TTY detection flow, bulk query flow, downstream integration
- **ADR-0003** (`docs/adr/0003-tty-detection-package-structure.md`) — package structure and `TTY_Status` type decision
- **Tech Spec F2** (`docs/tech-specs/f2-tty-detection.md`) — full design rationale
