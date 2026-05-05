# Custom Discriminated Record for Terminfo_Result (Over Functional.Result)

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-05-05

## Context and Problem Statement

The TERMINFO feature (FUNC-TIF-002) requires a result type that wraps either a `Terminfo_Snapshot` on success or a `Terminfo_Error` enumeration on failure. Two approaches are available: (1) use the `Functional` crate's generic `Result` type already available as a dependency, or (2) define a custom discriminated record specific to the terminfo domain.

The choice affects SPARK provability, API ergonomics, and compile-time type safety.

## Decision Drivers

* **SPARK Silver provability.** The result type must work under `SPARK_Mode => On` with full GNATprove discharge of discriminant checks.
* **Domain-specific error semantics.** The `Terminfo_Error` enumeration is a fixed, closed set of seven error codes specific to the terminfo parsing domain. Callers need pattern-matching on these specific codes.
* **Simplicity.** The `Terminfo_Snapshot` record contains bounded strings (fixed-size arrays); embedding it in a generic wrapper adds constraint complexity.
* **Zero additional dependencies for the SPARK package.** The pure parsing package (`Termicap.Terminfo`) should be a leaf with no crate dependencies to minimise proof obligations.
* **Consistency with existing Termicap patterns.** Other Termicap packages already use custom discriminated records (e.g., `Mode_Query_Result` in `Termicap.DECRPM.IO`, `Batch_Query_Result` in the same package).

## Considered Options

* **Option A**: Custom discriminated record `Terminfo_Result` with Boolean discriminant.
* **Option B**: Instantiate `Functional.Result` generic with `Terminfo_Snapshot` and `Terminfo_Error`.
* **Option C**: Separate out-parameters (`Snapshot : out Terminfo_Snapshot; Error : out Terminfo_Error; Success : out Boolean`).

## Decision Outcome

Chosen option: **Option A (custom discriminated record)**, because it provides the cleanest SPARK proof experience, avoids introducing a crate dependency into a leaf SPARK package, and matches the established Termicap pattern for domain-specific result types.

### Positive Consequences

* **Self-contained SPARK proof.** GNATprove sees the full type definition in the same compilation unit; no cross-crate proof context needed.
* **Exhaustive pattern matching.** Callers use `case Result.Success is when True => ...; when False => ...;` which is statically checked by the compiler.
* **Domain documentation.** The type definition in the spec explicitly documents the error variants alongside the success payload, improving readability.
* **No crate dependency.** `Termicap.Terminfo` has zero `with` clauses for external crates, making it trivially portable and fast to compile.

### Negative Consequences

* **Slight code duplication.** The discriminated-record pattern is repeated across packages (DECRPM, Terminfo, etc.) rather than being factored into a generic. This is acceptable given the different payload types and error enumerations.
* **Not composable with Functional.Result combinators.** If the project later adopts monadic chaining from the Functional crate, terminfo results would need manual adaptation. This is unlikely given the SPARK constraints.

## Pros and Cons of the Options

### Option A: Custom discriminated record (chosen)

```ada
type Terminfo_Result (Success : Boolean := False) is record
   case Success is
      when True  => Snapshot : Terminfo_Snapshot;
      when False => Error    : Terminfo_Error;
   end case;
end record;
```

* Good, because SPARK-provable without external dependencies.
* Good, because the error type is domain-specific and closed.
* Good, because matches existing patterns in Termicap (DECRPM, Mouse, Keyboard).
* Good, because GNATprove can fully discharge discriminant checks locally.
* Bad, because repeats the success/failure discriminant pattern manually.

### Option B: Functional.Result generic instantiation

```ada
package Terminfo_Results is new Functional.Result
  (Value_Type => Terminfo_Snapshot,
   Error_Type => Terminfo_Error);
```

* Good, because reuses an existing abstraction.
* Good, because provides map/bind combinators for monadic chaining.
* Bad, because introduces a crate dependency into a SPARK leaf package.
* Bad, because the generic instantiation adds proof obligations that cross compilation unit boundaries.
* Bad, because `Functional.Result` may use features (tagged types, dynamic dispatch) incompatible with SPARK Silver.
* Bad, because the Terminfo_Snapshot contains bounded strings (fixed-size arrays), which may complicate the generic constraint.

### Option C: Separate out-parameters

```ada
procedure Parse_Terminfo
  (Env     :     Environment;
   Result  : out Terminfo_Snapshot;
   Error   : out Terminfo_Error;
   Success : out Boolean);
```

* Good, because simple and explicit.
* Good, because trivially SPARK-provable.
* Bad, because the caller can ignore `Success` and read an uninitialised `Result`.
* Bad, because it is a procedure (not a function), breaking the functional style of the detection API.
* Bad, because the triple out-parameter pattern is verbose and error-prone.

## Links

* Requirements: FUNC-TIF-002 (Terminfo_Result Error Enumeration)
* Related: `Termicap.DECRPM.IO` -- `Mode_Query_Result` discriminated record (precedent)
* Related: `Termicap.Keyboard` -- `Parse_Result` discriminated record (precedent)
* Tech Spec: `docs/tech-specs/terminfo.md` section 4
