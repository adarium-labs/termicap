# Five-literal flat enum for Override_Mode

* Status: proposed
* Deciders: Heziode
* Date: 2026-04-03

## Context and Problem Statement

The global override feature (FUNC-OVR-001) needs a type to represent the user's `--color` flag choice. The type must distinguish "no override" from four forced color levels. How should this state be modelled?

## Decision Drivers

* SPARK exhaustive case analysis must work without additional invariants
* The type should make illegal states unrepresentable
* CLI flag strings (`never`, `always`, `auto`, `true`, `1`, `2`, `3`, `256`, `16m`) must map cleanly
* The mapping from override mode to `Color_Level` must be total and obvious

## Considered Options

* **Option A: Five-literal flat enum** -- `(Auto, Force_None, Force_Basic, Force_256, Force_True_Color)`
* **Option B: Boolean + Color_Level pair** -- `record Is_Active : Boolean; Level : Color_Level end record`
* **Option C: Three-literal enum** -- `(Auto, Force_On, Force_Off)` with a separate level parameter

## Decision Outcome

Chosen option: **Option A (five-literal flat enum)**, because it eliminates illegal state combinations at the type level and enables SPARK exhaustive case analysis with no runtime invariant checks.

### Positive Consequences

* Ada case statements on five literals are exhaustive; SPARK discharges completeness automatically
* No invalid state: the pair `(Is_Active => True, Level => None)` cannot be expressed
* Direct mapping to CLI flag convention: `--color=never` -> `Force_None`, `--color=always` -> `Force_True_Color`, etc.
* Matches the `FORCE_COLOR` environment variable convention (1=Basic, 2=256, 3=TrueColor)
* Simple protected object: stores a single scalar, no composite record

### Negative Consequences

* If a sixth color level is ever added, the enum must be extended (unlikely; the four-level model is universal)
* Applications that only need on/off override must still choose among four force levels (mitigated by `Parse_Color_Flag` which maps `"always"` to `Force_True_Color`)

## Pros and Cons of the Options

### Option A: Five-literal flat enum

* Good, because SPARK case analysis is trivial
* Good, because no illegal states exist
* Good, because maps 1:1 to `FORCE_COLOR` values and `Color_Level`
* Bad, because slightly more literals than the minimum for a Boolean override

### Option B: Boolean + Color_Level pair

* Good, because separates "is override active?" from "what level?"
* Bad, because `(Is_Active => False, Level => True_Color)` is a legal but meaningless state
* Bad, because SPARK would require an invariant (`not Is_Active or Level /= None`) to eliminate this
* Bad, because the mapping function needs a branch for the inactive case plus a branch for None

### Option C: Three-literal enum

* Good, because simpler for on/off use cases
* Bad, because `Force_On` conflates four different color levels
* Bad, because a separate `Forced_Level` parameter is needed, introducing a two-variable state
* Bad, because SPARK analysis of the combined state requires reasoning about two variables simultaneously

## Links

* Relates to: FUNC-OVR-001 (Override_Mode enumeration type)
* Informed by: owo-colors (Rust, 2-bit Boolean override), chalk (JS, 0-3 integer level), termenv (Go, Profile enum)
