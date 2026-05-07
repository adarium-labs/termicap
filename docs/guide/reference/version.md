# API Reference: `Termicap.Version`

Shared dotted-numeric version utility for parsing and comparing terminal version strings (e.g. `"0.50.0"`, `"3.1.0"`, `"357"`). Used by `Termicap.Hyperlinks` (XTVERSION refinement) and `Termicap.Graphics` (kitty version gating per FUNC-HYP-022).

**Files:**
- [`src/termicap-version.ads`](../../src/termicap-version.ads)
- `src/termicap-version.adb`

**SPARK_Mode:** `Termicap.Version` — On (spec); Off at body level (postcondition discharge deferred; bodies correct by construction)
**License:** Apache-2.0

---

## Overview

A bounded, allocation-free representation of a dotted-numeric version. Designed as a SPARK Silver-friendly building block to centralise version arithmetic across the library (ADR-0036).

Properties:
- Up to **8 components** (`MAX_VERSION_COMPONENTS`) — sufficient for every version in the known-good database (the longest observed is `1.72.0`).
- Fixed-size storage (no heap allocation, no unbounded containers).
- Total: `Parse` never raises; on failure it returns `ZERO_VERSION` with `Success = False`.
- Comparator is total and obeys the *prefix rule*: `"0.50" < "0.50.0"` (FUNC-HYP-013 comparison rule 2).

Used by:
- [`Termicap.Hyperlinks`](hyperlinks.md) — minimum-version lookup in the known-good emulator table.
- [`Termicap.Graphics`](sixel-graphics.md) via `Parse_Kitty_Version` — kitty version gating (FUNC-SXL-003 / FUNC-HYP-022).

---

## Constants

### `MAX_VERSION_COMPONENTS`

```ada
MAX_VERSION_COMPONENTS : constant := 8;
```

Upper bound on the number of dot-separated components accepted by `Parse`. Bounds all loops for SPARK Silver provability and keeps the `Version` record stack-allocatable.

### `ZERO_VERSION`

```ada
ZERO_VERSION : constant Version := (Count => 0, Parts => [others => 0]);
```

Canonical zero / uninitialised version value. Used as:
- The initial value of `Result` in `Parse` on failure.
- The "any version" floor for emulators that support hyperlinks in any released build (e.g. WezTerm, foot, Ghostty, Konsole in the `Termicap.Hyperlinks` known-good table).

---

## Types

### `Component_Index`

```ada
subtype Component_Index is Positive range 1 .. MAX_VERSION_COMPONENTS;
```

Index subtype for `Component_Array`.

### `Component_Array`

```ada
type Component_Array is array (Component_Index) of Natural;
```

Fixed-size array holding the parsed components at indices `1 .. Count`; elements beyond `Count` are zero and are not considered by `Compare`.

### `Version`

```ada
type Version is record
   Count : Natural         := 0;
   Parts : Component_Array := [others => 0];
end record;
```

Bounded, allocation-free representation of a dotted-numeric version.

- `Count` holds the number of valid components (0 when the version is uninitialised or `ZERO_VERSION`).
- `Parts (1 .. Count)` holds the component values.

### `Version_Ordering`

```ada
type Version_Ordering is (Less_Than, Equal, Greater_Than);
```

Three-way comparison result returned by `Compare`.

---

## Subprograms

### `Parse`

```ada
procedure Parse
  (S       : String;
   Result  : out Version;
   Success : out Boolean)
with
  SPARK_Mode => On,
  Global     => null;
```

Parse a dotted-numeric version string. Declared as a procedure (rather than a `Boolean` function with an `out` parameter) because SPARK 2014 prohibits `out` parameters in functions [E0015].

**Accepts** strings of the form `"N"`, `"N.N"`, `"N.N.N"`, …, where each `N` is a sequence of one or more ASCII decimal digits and the component count is `1 .. MAX_VERSION_COMPONENTS`.

**Rejects** (returns `Success = False`, `Result = ZERO_VERSION`):
- Empty string
- Leading dot (`".1"`)
- Trailing dot (`"1."`)
- Consecutive dots (`"1..2"`)
- Non-digit characters other than `'.'` (e.g. `"1.a"`, `"v1.2"`, `"1.2-rc1"`, `" 1.2"`, `"1 2"`, `"-1"`, `"+1"`)
- More than `MAX_VERSION_COMPONENTS` parts
- Numeric overflow (a component value exceeding `Natural'Last`)

**Postconditions:**
- On success: `Result.Count` in `1 .. MAX_VERSION_COMPONENTS`.
- On failure: `Result.Count = 0`.

### `Compare`

```ada
function Compare (Left, Right : Version) return Version_Ordering
with
  SPARK_Mode => On,
  Global     => null;
```

Lexicographic component-wise comparison.

**Rules:**
1. **Component scan** — Compare components left to right; on the first differing component, return `Less_Than` / `Greater_Than`.
2. **Prefix rule** — When all compared components are equal and one version has fewer components than the other, the shorter version is `Less_Than` the longer (e.g. `"0.50" < "0.50.0"`).
3. **Equal lengths, all equal** → `Equal`.
4. **Both `ZERO_VERSION`** (Count = 0) → `Equal`.

**Postcondition** asserts commutativity:
- `Compare (Left, Right) = Equal` ↔ `Compare (Right, Left) = Equal`
- `Compare (Left, Right) = Less_Than` ↔ `Compare (Right, Left) = Greater_Than`

### `Make`

```ada
function Make
  (Major     : Natural;
   Minor     : Natural := 0;
   Patch     : Natural := 0;
   Has_Minor : Boolean := True;
   Has_Patch : Boolean := True) return Version
with
  SPARK_Mode => On,
  Global     => null;
```

Convenience constructor for test code and known-good table entries that avoids string parsing.

- Pass only `Major` with `Has_Minor => False` to yield a single-component version (Count = 1).
- Pass `Major` and `Minor` with `Has_Patch => False` to yield Count = 2.
- Default flags yield Count = 3.

When `Has_Minor` is `False`, `Minor` and `Patch` are ignored even if non-zero.

**Postcondition:** `1 <= Result.Count <= 3` and `Result.Parts (1) = Major`.

---

## Examples

### Parse and compare

```ada
with Ada.Text_IO; use Ada.Text_IO;
with Termicap.Version;

procedure Demo is
   V1, V2 : Termicap.Version.Version;
   Ok1, Ok2 : Boolean;
   use type Termicap.Version.Version_Ordering;
begin
   Termicap.Version.Parse ("0.50",   V1, Ok1);  --  Ok1 = True, V1.Count = 2
   Termicap.Version.Parse ("0.50.0", V2, Ok2);  --  Ok2 = True, V2.Count = 3

   if Termicap.Version.Compare (V1, V2) = Termicap.Version.Less_Than then
      Put_Line ("0.50 < 0.50.0  (prefix rule)");
   end if;
end Demo;
```

### Construct without parsing

```ada
declare
   --  iTerm2 minimum-version floor for the OSC 8 known-good table.
   ITerm2_Min : constant Termicap.Version.Version :=
                  Termicap.Version.Make (3, 1, 0);

   --  xterm uses a single-component patch number ("357").
   Xterm_Min  : constant Termicap.Version.Version :=
                  Termicap.Version.Make (Major     => 357,
                                         Has_Minor => False,
                                         Has_Patch => False);

   --  "Any version" floor for WezTerm / foot / Ghostty / Konsole.
   Any        : constant Termicap.Version.Version :=
                  Termicap.Version.ZERO_VERSION;
begin
   null;
end;
```

---

## Requirements coverage

- FUNC-HYP-013 — Version type, `Parse`, `Compare`, `Make`, `Version_Ordering`
- FUNC-HYP-022 — Sixel refactor uses `Termicap.Version.Parse` (via `Termicap.Graphics.Parse_Kitty_Version`)

## Related

- [ADR-0036 — Termicap.Version as a top-level shared utility](../../adr/0036-termicap-version-shared-utility.md)
- [ADR-0037 — Hyperlinks_Result flat record](../../adr/0037-hyperlinks-result-flat-record.md)
- [ADR-0038 — Active hyperlink refinement reuses XTVERSION](../../adr/0038-hyperlinks-active-reuses-xtversion.md)
- [`Termicap.Hyperlinks`](hyperlinks.md) — primary client of `Compare`
- [`Termicap.Graphics`](sixel-graphics.md) — `Parse_Kitty_Version` delegates to `Parse`
