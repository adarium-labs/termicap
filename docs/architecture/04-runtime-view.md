# arc42 §6: Runtime View

Runtime behavior of the Termicap library — detection flows, FFI boundaries, and testability patterns.

## Scenario 1: Environment Capture Flow

Executed once at program startup (or whenever a fresh snapshot is needed).

```
Caller (application / detection init)
  │
  │  Capture_Current (Env : out Environment)
  ▼
Termicap.Environment.Capture          [SPARK_Mode => Off]
  │
  │  Env := EMPTY_ENVIRONMENT;
  │  Ada.Environment_Variables.Iterate (Process_Variable'Access)
  │
  │  For each (Name, Value) in OS process environment:
  │    │
  │    │  Insert (Env, Name, Value)
  │    ▼
  │  Termicap.Environment              [SPARK Silver]
  │    │  Key normalized to lowercase
  │    │  Stored in Env_Maps (SPARK.Containers.Formal.Unbounded_Hashed_Maps)
  │    └──► Entry added to Env.Map
  │
  └──► Env is now an immutable snapshot of the full process environment
```

**Key properties:**

- `Capture_Current` is the only point where OS calls occur.
- After `Capture_Current` returns, the caller holds a value-typed `Environment` snapshot. Subsequent OS changes to the process environment have no effect on it.
- The `Insert` call inside `Capture_Current` crosses back into SPARK-provable code, but this is safe because `SPARK_Mode => Off` packages may call into `SPARK_Mode => On` packages freely.

## Scenario 2: Environment Query Flow

Executed during capability detection — may be called many times per snapshot.

```
Detection Logic (e.g., Termicap.Standards)
  │
  │  Contains (Env, "NO_COLOR")    -- or Value / Value_Matches
  ▼
Termicap.Environment                [SPARK Silver, Global => null]
  │
  │  Key := To_Lower ("NO_COLOR")   -- normalize to "no_color"
  │  Result := Env_Maps.Contains (Env.Map, Key)
  │
  └──► Boolean result returned to caller
```

**Key properties:**

- No OS interaction. The `Global => null` contract is machine-verified by GNATprove.
- Key normalization happens at query time as well as at insertion time; both paths lower-case the key before the hash map operation.
- `Value` returns `""` for absent keys (safe default per FUNC-ENV-003). Callers that need to distinguish absence from empty must call `Contains` first.

### NO_COLOR compliance query pattern

```ada
--  Correct: distinguishes absence from empty value
if Contains (Env, "NO_COLOR") then
   --  NO_COLOR is set (present), even if Env.Value ("NO_COLOR") = ""
   Disable_Color;
end if;

--  Incorrect: treats absent the same as empty
if Value (Env, "NO_COLOR") /= "" then  --  wrong for NO_COLOR spec
   Disable_Color;
end if;
```

## Scenario 3: Testability Pattern (No OS Interaction)

Unit tests construct deterministic snapshots using `EMPTY_ENVIRONMENT` and `Insert`. No OS environment is read or modified.

```
Test body
  │
  │  Env : Environment := EMPTY_ENVIRONMENT;
  │
  │  Insert (Env, "NO_COLOR", "")
  │  Insert (Env, "TERM",     "xterm-256color")
  │  Insert (Env, "COLORTERM", "truecolor")
  │
  ▼
Termicap.Environment                [SPARK Silver]
  │  Each Insert normalizes key to lowercase and stores in Env.Map
  └──► Env is now a deterministic, OS-independent snapshot
  │
  │  Detection logic under test receives Env as parameter
  ▼
Unit assertions
  │  Contains (Env, "NO_COLOR")        -- True
  │  Value (Env, "TERM")               -- "xterm-256color"
  │  Value_Matches (Env, "COLORTERM",  -- True
  │    ["truecolor", "24bit"])
  └──► All results are deterministic; tests are parallelizable
```

**Key properties:**

- No mocking framework required.
- No process environment mutation.
- Tests are fully parallelizable and reproduce identically across machines.
- `Termicap.Environment.Capture` is not involved in any unit test.

## Scenario 4: Multi-Candidate Matching Flow

Used during TERM / TERM_PROGRAM / COLORTERM detection where a variable may match one of several known values.

```
Detection Logic
  │
  │  Value_Matches (Env, "TERM_PROGRAM", ["iTerm.app", "WezTerm", "vscode"])
  ▼
Termicap.Environment                [SPARK Silver, Global => null]
  │
  │  1. Contains (Env, "TERM_PROGRAM")?  -- if False, return False immediately
  │  2. Val := Value (Env, "TERM_PROGRAM")
  │  3. For each Candidate in Candidates:
  │       if Equal_Case_Insensitive (Val, Candidate) then return True
  │  4. return False
  │
  └──► Boolean result
```

**Key properties:**

- Short-circuits on absent key (returns `False` without iterating candidates).
- All comparisons are case-insensitive via `Equal_Case_Insensitive`.
- With Ada 2022 aggregate syntax, call sites are concise: `["iTerm.app", "WezTerm", "vscode"]`.

## Scenario 5: TTY Detection Flow

Executed at detection time to determine whether standard I/O streams are connected to an interactive terminal.

```
Caller (application / detection init)
  │
  │  Is_TTY (Stdout)
  ▼
Termicap.TTY                          [spec: SPARK, body: SPARK_Mode => Off]
  │
  │  FD_MAP (Stdout) => 1
  │  C_Isatty (1)                     -- pragma Import (C, ..., "isatty")
  │
  │  Return value:
  │    1  => True  (stream is a terminal)
  │    _  => False (pipe, file, invalid fd, or any error)
  │
  └──► Boolean result returned to caller
```

**Key properties:**

- `isatty()` is a read-only query — it never modifies terminal state.
- Any non-1 return value maps to `False`, including errors (FUNC-TTY-004).
- No exceptions can propagate from `pragma Import (C, ...)`.

## Scenario 6: Bulk TTY Query Flow

Convenience wrapper that queries all three streams in a single call.

```
Caller
  │
  │  Status : TTY_Status := Query_All;
  ▼
Termicap.TTY
  │
  │  Status.Stdin  := Is_TTY (Stdin)    -- C_Isatty (0)
  │  Status.Stdout := Is_TTY (Stdout)   -- C_Isatty (1)
  │  Status.Stderr := Is_TTY (Stderr)   -- C_Isatty (2)
  │
  └──► TTY_Status record with three Boolean fields
```

**Key properties:**

- Three `isatty()` calls, one per stream.
- Results are independent — stdout may be piped while stderr remains a terminal.

## Scenario 7: TTY Status in Downstream Detection

Downstream SPARK-provable detection functions receive TTY status as a plain `Boolean` parameter, keeping the FFI call outside the SPARK verification perimeter.

```
Application Init (Ada-only region)
  │
  │  Is_Interactive : constant Boolean := Is_TTY (Stdout);
  │  Capture_Current (Env);
  │
  ▼
Detection Logic                       [SPARK Silver, Global => null]
  │
  │  function Detect_Color_Level
  │    (Env            : Environment;
  │     Is_Interactive : Boolean) return Color_Level
  │
  │  1. if not Is_Interactive and not Force_Color then return None
  │  2. Check env vars: NO_COLOR, FORCE_COLOR, COLORTERM, TERM ...
  │
  └──► Color_Level result
```

**Key properties:**

- `Is_TTY` call happens once in an Ada-only region.
- The `Boolean` result flows into SPARK functions as a parameter.
- `Global => null` contracts are preserved on detection functions.
- This is the canonical integration pattern for `Termicap.TTY` with `Termicap.Environment`.

## Related Documents

- **Building Blocks** (`docs/architecture/03-building-blocks.md`): Static package structure and SPARK boundary diagram
- **Tech Spec F1** (`docs/tech-specs/f1-environment-variable-abstraction.md`): Design rationale, especially Sections C (Type Design) and D (SPARK Strategy)
- **Tech Spec F2** (`docs/tech-specs/f2-tty-detection.md`): TTY detection design rationale
- **Requirements** (`docs/requirements/`): FUNC-ENV-002, FUNC-ENV-004, FUNC-ENV-005, FUNC-ENV-007, FUNC-ENV-008, FUNC-TTY-001 through FUNC-TTY-006
