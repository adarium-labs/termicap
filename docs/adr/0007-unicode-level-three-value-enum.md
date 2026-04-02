# Unicode_Level as a three-value enumeration rather than Boolean

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-02

## Context and Problem Statement

Unicode support detection needs to communicate its result to callers. The simplest representation is a Boolean (`Is_Unicode_Supported`), which is what the most popular reference library (is-unicode-supported) uses. However, Termicap's requirements (FUNC-UNI-001) specify a three-value enumeration with `None`, `Basic`, and `Extended` levels. What is the right representation, and why is a Boolean insufficient?

## Decision Drivers

* **Future extensibility** -- the reference analysis (section 2.10 of `00-GLOBAL-SYNTHESIS.md`) identifies `wcwidth()` probing as a method that can distinguish BMP-only support from full supplementary-plane support. A Boolean cannot represent this distinction.
* **API consistency** -- `Termicap.Color` already uses a four-value ordered enumeration (`Color_Level`). Using a Boolean for Unicode while Color uses an enum would create an inconsistent API surface.
* **Comparison semantics** -- callers should be able to write `if Unicode >= Basic` to check whether any Unicode is available, and `if Unicode >= Extended` to check for emoji/supplementary-plane support. Ada's enumeration ordering provides this naturally.
* **Floor operations** -- the detection cascade uses `Unicode_Level'Max(Floor, ...)` to ensure higher-priority signals are never undercut, exactly as `Color_Level'Max` works in color detection. A Boolean does not support `'Max` in this graduated sense.

## Considered Options

* **Option A**: `Boolean` (`Is_Unicode_Supported`)
* **Option B**: Three-value enumeration (`None`, `Basic`, `Extended`)
* **Option C**: Integer level (0, 1, 2) mirroring `FORCE_COLOR`

## Decision Outcome

Chosen option: **Option B** (three-value enumeration), because it is the only option that satisfies all decision drivers: it preserves design space for `wcwidth()` probing, maintains API consistency with `Color_Level`, supports natural ordering comparisons, and enables `'Max`-based floor operations in the detection cascade.

For v1 of the library, the detection algorithm returns only `None` or `Basic`. `Extended` is reserved for a future version that adds `wcwidth()` probing via a separate FFI boundary package. This means v1 callers can treat the result as effectively Boolean (`/= None`), but the type is ready for graduation without a breaking API change.

### Positive Consequences

* API is forward-compatible with `wcwidth()` probing -- no breaking change when `Extended` detection is added.
* Consistent shape with `Color_Level`: both are ordered enumerations with a `None` sentinel, both support `'Max` for floor operations, both are used as fields in the planned `Terminal_Capabilities` record.
* Callers who only care about yes/no can write `Unicode /= None` or `Unicode >= Basic`.
* The `Extended` value documents the design intent in the type system itself, making it visible to anyone reading the spec.

### Negative Consequences

* Slightly more complex than a Boolean for callers who only need yes/no. Mitigation: the comparison `Unicode >= Basic` is barely more verbose than `Is_Unicode`.
* `Extended` is unused in v1, which may cause confusion. Mitigation: the spec comment and requirement (FUNC-UNI-001) document that it is reserved for future use.
* One additional enumeration literal to handle in case statements. Mitigation: for v1, any code path that produces `Extended` is unreachable; tests will verify that only `None` and `Basic` are returned.

## Pros and Cons of the Options

### Option A: Boolean

```ada
function Is_Unicode_Supported (Env : Environment) return Boolean;
```

* Good, because simplest possible return type.
* Good, because matches is-unicode-supported's Boolean interface.
* Bad, because cannot represent BMP-only vs. full-Unicode distinction when `wcwidth()` probing is added.
* Bad, because a future API change from `Boolean` to an enum would break all callers.
* Bad, because inconsistent with `Color_Level` (enum) -- callers learn two different patterns for the same library.
* Bad, because no `'Max` support for floor operations in the cascade.

### Option B: Three-value enumeration (chosen)

```ada
type Unicode_Level is (None, Basic, Extended);
```

* Good, because forward-compatible with `wcwidth()` probing.
* Good, because consistent with `Color_Level` API shape.
* Good, because Ada's enumeration ordering gives natural `>=`, `'Max` semantics.
* Good, because the type documents the capability taxonomy in code.
* Bad, because `Extended` is unused in v1 (reserved).
* Bad, because marginally more verbose than Boolean for simple yes/no checks.

### Option C: Integer level (0, 1, 2)

```ada
subtype Unicode_Level is Natural range 0 .. 2;
```

* Good, because compact and supports arithmetic comparisons.
* Good, because extensible (could add level 3, 4, etc.).
* Bad, because magic numbers -- `0`, `1`, `2` carry no self-documenting meaning.
* Bad, because SPARK range checks are needed to prevent out-of-range values.
* Bad, because inconsistent with `Color_Level` (which is an enumeration, not a subtype of Natural).
* Bad, because arithmetic on capability levels is semantically meaningless -- you never want `Basic + Basic = Extended`.

## Links

* [Tech Spec F5](../tech-specs/unicode-support.md) -- Unicode Support Detection technical specification
* [FUNC-UNI-001](../requirements/unicode-support.sdoc) -- Unicode_Level enumeration type requirement
* [Global Synthesis](../../reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md) -- Section 2.10: Unicode/Wide Char Support
