# FORCE_COLOR value parsing via string comparison, not integer conversion

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-02

## Context and Problem Statement

FUNC-CLR-004 requires parsing the FORCE_COLOR environment variable to determine a color level floor. The value can be "0", "1", "2", "3", "true", "false", "" (empty), or any other string. How should the string-to-`Color_Level` mapping be implemented while maintaining SPARK Silver provability?

## Decision Drivers

* SPARK Silver provability -- no runtime exceptions, no proof failures
* Correctness -- the mapping must exactly match FUNC-CLR-004
* Simplicity -- the implementation should be easy to audit
* No dependency on integer parsing -- `Integer'Value` raises `Constraint_Error` on invalid input, which is incompatible with SPARK's no-exception guarantee

## Considered Options

* **Option A**: Parse FORCE_COLOR as an integer using `Integer'Value` with exception handling
* **Option B**: Parse FORCE_COLOR using character-level digit extraction (manual integer parsing)
* **Option C**: Direct string comparison using `Equal_Case_Insensitive` with if-elsif chain

## Decision Outcome

Chosen option: **Option C** (direct string comparison), because it is the simplest approach that satisfies all decision drivers and exactly matches the small, finite set of recognized FORCE_COLOR values.

### Positive Consequences

* Fully SPARK-provable -- no exceptions, no integer conversion, no range checks needed.
* The if-elsif chain reads as a direct transcription of the FUNC-CLR-004 value table.
* Uses `Equal_Case_Insensitive` from `Termicap.Environment`, which is already proven and tested.
* The catch-all `else` clause handles unknown values by returning `Basic_16`, matching the requirement ("Any other non-empty value not listed above shall be treated as Basic_16").

### Negative Consequences

* If FORCE_COLOR ever needs to support additional numeric values (e.g., "4"), a new elsif branch must be added. This is unlikely given that the 4-level color model is an industry standard with no indication of extension.
* Slightly more verbose than a numeric approach for the 0-3 mapping.

## Pros and Cons of the Options

### Option A: Integer'Value with exception handling

```ada
Level := Integer'Value (Val);  -- raises Constraint_Error if not a number
```

* Good, because concise for numeric parsing
* Bad, because `Integer'Value` raises `Constraint_Error` on non-numeric input ("true", "false", "")
* Bad, because exception handling is not allowed in SPARK mode
* Bad, because even with SPARK_Mode => Off for this section, it breaks the goal of full SPARK provability for the Color package

### Option B: Manual digit extraction

Extract single characters and convert to integer manually:

```ada
if Val'Length = 1 and then Val (Val'First) in '0' .. '3' then
   Level := Character'Pos (Val (Val'First)) - Character'Pos ('0');
```

* Good, because SPARK-provable (character comparison, no exceptions)
* Good, because handles the numeric case efficiently
* Bad, because still needs separate branches for "true", "false", "" -- ending up as complex as Option C
* Bad, because introduces integer arithmetic that must be range-checked
* Bad, because the intermediate integer must be mapped back to `Color_Level` via a case statement, adding another layer

### Option C: Direct string comparison (chosen)

```ada
if Equal_Case_Insensitive (Val, "0") or Equal_Case_Insensitive (Val, "false") then
   return None;
elsif Equal_Case_Insensitive (Val, "3") then
   return True_Color;
elsif Equal_Case_Insensitive (Val, "2") then
   return Extended_256;
elsif Equal_Case_Insensitive (Val, "1") or
      Equal_Case_Insensitive (Val, "true") or Val'Length = 0 then
   return Basic_16;
else
   return Basic_16;
end if;
```

* Good, because fully SPARK-provable with no exceptions or integer arithmetic
* Good, because reads as a direct transcription of the FUNC-CLR-004 mapping table
* Good, because reuses existing `Equal_Case_Insensitive` utility
* Good, because the catch-all else naturally implements "any other value -> Basic_16"
* Bad, because slightly more verbose than a numeric approach (6 comparisons vs. 1 integer parse)

## Links

* [Tech Spec F3](../tech-specs/f3-color-level-detection.md) -- Full technical specification
* [FUNC-CLR-004](../requirements/02-functional.sdoc) -- FORCE_COLOR override requirement
* [ADR-0004](0004-color-detection-decomposed-helpers.md) -- Related: decomposed helpers decision
