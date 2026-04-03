# Discriminated Record for Downsampled_Color Return Type

* Status: accepted
* Deciders: Termicap contributors
* Date: 2026-04-03

## Context and Problem Statement

The Color Downsampling feature (FUNC-DSP-001 through FUNC-DSP-012) introduces a general `Downsample` function that accepts a color at any fidelity level and a target `Color_Level`, returning the downsampled result. The result may be an RGB value (TrueColor identity), a 256-color palette index, a 16-color ANSI index, or no-color. How should this polymorphic return value be represented in Ada while remaining SPARK Gold provable?

## Decision Drivers

* **SPARK Gold compatibility:** The entire `Termicap.Downsampling` package must be provable at SPARK Gold level -- no dispatching calls, no dynamic allocation, no class-wide types, no FFI.
* **Postcondition expressibility:** The idempotency property (FUNC-DSP-009) and monotonicity property (FUNC-DSP-010) must be expressible as SPARK postconditions on the `Downsample` function.
* **`Color_Level_Of` classification:** FUNC-DSP-010 requires a `Color_Level_Of` function that returns the effective color level of any downsampled result. This must be trivially implementable.
* **Caller ergonomics:** Callers should be able to dispatch on the result level using idiomatic Ada constructs (case statements).
* **No dynamic allocation:** The return type must have a known maximum size at compile time.

## Considered Options

* **Option A:** Discriminated record with `Color_Level` discriminant
* **Option B:** Overloaded functions returning specific types (no unified return type)
* **Option C:** Tagged type hierarchy with abstract root

## Decision Outcome

Chosen option: "Option A: Discriminated record with Color_Level discriminant", because it is the only option that satisfies all five decision drivers simultaneously. It provides a single unified return type expressible in SPARK Gold, enables natural postconditions for both idempotency and monotonicity, and allows trivial implementation of `Color_Level_Of` as `return D.Level`.

### Positive Consequences

* Postconditions for idempotency and monotonicity are directly expressible on a single function signature.
* `Color_Level_Of` is a trivial one-line function (`return D.Level`), provable without lemmas.
* Callers use `case D.Level is ...` for dispatch, which is idiomatic Ada and exhaustiveness-checked by the compiler.
* Fixed maximum size: the largest variant (True_Color) contains three `Color_Component` fields (3 bytes) plus discriminant overhead. No heap allocation is ever needed.
* The `None` variant carries no data, cleanly modeling the absence of color as distinct from index 0 (Black).

### Negative Consequences

* The discriminated record requires a default discriminant value (Ada rule for unconstrained objects), which means callers can declare `D : Downsampled_Color` without specifying a level. The default is `None`, which is the safest choice.
* The record size is the maximum of all variants, not the size of the active variant. For this type the overhead is negligible (3 bytes for the `RGB` variant vs. 1 byte for the index variants).

## Pros and Cons of the Options

### Option A: Discriminated record with Color_Level discriminant

```ada
type Downsampled_Color (Level : Color_Level := None) is record
   case Level is
      when True_Color   => RGB_Value : RGB;
      when Extended_256  => Index_256 : Color_Index_256;
      when Basic_16      => Index_16  : Color_Index_16;
      when None          => null;
   end case;
end record;
```

* Good, because it is fully SPARK Gold compatible (no dispatching, no heap, no class-wide types)
* Good, because `Color_Level_Of` is trivially `return D.Level`
* Good, because postconditions can reference `D.Level`, `D.RGB_Value`, `D.Index_256`, `D.Index_16` directly
* Good, because callers get exhaustiveness-checked case statements on the discriminant
* Good, because the `None` variant carries no data, cleanly modeling color absence
* Bad, because all variants occupy the space of the largest variant (negligible for this type)

### Option B: Overloaded functions returning specific types

Each conversion function returns its natural type. The general `Downsample` function does not exist as a single function; instead, callers must choose the right overload at compile time.

* Good, because each function has a precise return type with no runtime discrimination needed
* Good, because fully SPARK Gold compatible
* Bad, because there is no unified return type, so the general dispatch table (FUNC-DSP-008) cannot be expressed as a single function
* Bad, because the idempotency postcondition (FUNC-DSP-009) cannot be expressed on a single function -- it must be duplicated across multiple overloads
* Bad, because the monotonicity postcondition (FUNC-DSP-010) references `Color_Level_Of`, which has no single input type to operate on
* Bad, because callers who hold a `Color_Level` detected at runtime cannot dispatch to the right overload without writing their own case statement

### Option C: Tagged type hierarchy

```ada
type Abstract_Color is abstract tagged null record;
type True_Color_Value is new Abstract_Color with record Value : RGB; end record;
-- etc.
```

* Good, because it models the IS-A relationship naturally
* Good, because class-wide postconditions can express idempotency
* Bad, because SPARK does not support dispatching calls at Gold level -- tagged types with dynamic dispatch require SPARK_Mode => Off or Silver-level concessions
* Bad, because class-wide types may require heap allocation for indefinite objects
* Bad, because `Color_Level_Of` requires a dispatching call, which SPARK cannot verify at Gold level
* Bad, because it is the most complex option for a type with only four fixed variants

## Links

* Requirements: FUNC-DSP-007 (strip-to-None representation), FUNC-DSP-008 (general dispatch), FUNC-DSP-009 (idempotency), FUNC-DSP-010 (monotonicity)
* Tech Spec: `docs/tech-specs/color-downsampling.md` (Section 3.5: Downsampled_Color)
