# Protected record with Stream_Kind-indexed array for capability cache

* Status: proposed
* Deciders: Heziode
* Date: 2026-04-03

## Context and Problem Statement

The `Get` function (FUNC-CAP-003) requires a per-stream cache with lazy initialization and thread safety. The cache must hold up to three entries (one per `Stream_Kind` value: Stdin, Stdout, Stderr). How should the cache be structured internally?

## Decision Drivers

* Thread safety: concurrent calls to `Get` for the same stream must not produce partial or duplicate initialization (FUNC-CAP-008)
* SPARK compatibility: the protected object must be confined to a `SPARK_Mode => Off` region; the design should minimize the size of that region
* Simplicity: the cache has exactly three fixed slots; the design should exploit this
* No deadlock risk: `Get` may be called during library elaboration (single-threaded) or from any task

## Considered Options

* **Option A: Protected record with `Cache_Array` indexed by `Stream_Kind`** -- single protected object, array of `(Initialized, Value)` slots
* **Option B: Three separate protected variables** -- one protected object per stream
* **Option C: Single protected object with separate Boolean flags** -- initialized flags stored outside the array

## Decision Outcome

Chosen option: **Option A (protected record with `Cache_Array`)**, because it uses a single protected object (simplest synchronization), exploits Ada's natural array indexing by enumeration, and keeps all cache state in one place.

### Positive Consequences

* Single protected object means one lock, one declaration, minimal code
* `Cache_Array` indexed by `Stream_Kind` maps directly to the three-slot requirement; adding a stream in the future (unlikely) requires only extending the enum
* The `Initialized` flag is co-located with the `Value` in a `Cache_Slot` record, making the check-and-store operation atomic within the protected object
* All `SPARK_Mode => Off` code is confined to the protected object declaration and the `Get` function body

### Negative Consequences

* A call to `Get(Stderr)` blocks if another task is inside the protected object for `Get(Stdout)` -- but this contention window is negligible (one record copy) and occurs at most once per stream
* The `Terminal_Capabilities` record includes `Unbounded_String` fields (from `Terminal_Identity`), so the protected object manages heap-allocated data indirectly; this is acceptable because Ada's protected object semantics guarantee mutual exclusion

## Pros and Cons of the Options

### Option A: Protected record with Cache_Array

* Good, because single protected object, minimal synchronization complexity
* Good, because natural array indexing by `Stream_Kind` enumeration
* Good, because `Cache_Slot` groups `Initialized` flag with value (structural clarity)
* Bad, because cross-stream contention (negligible in practice)

### Option B: Three separate protected variables

* Good, because zero cross-stream contention
* Bad, because three protected objects means three declarations, three sets of accessor subprograms
* Bad, because more code to maintain and test
* Bad, because SPARK_Mode => Off region is larger (three protected object declarations)

### Option C: Single protected object with separate Boolean flags

* Good, because single protected object
* Bad, because the initialized flags are separated from the values they guard, making it easier to introduce inconsistencies during maintenance
* Bad, because no structural advantage over Option A; the array approach is strictly cleaner

## Links

* Relates to: FUNC-CAP-003 (Get cached), FUNC-CAP-008 (thread-safe initialization)
* Informed by: `Termicap.Override` (uses a single protected object for one scalar value -- same pattern scaled to three slots)
