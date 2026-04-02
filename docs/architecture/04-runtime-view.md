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

## Scenario 8: Color Level Detection Flow

Full end-to-end scenario showing how a client calls `Detect_Color_Level`. The environment snapshot and TTY status are obtained separately (Scenarios 1 and 5) and then passed into the pure SPARK function.

```
Application Init (Ada-only region)
  │
  │  Env    : Environment;
  │  Is_TTY : Boolean;
  │
  │  Capture_Current (Env);             -- Scenario 1 (SPARK_Mode => Off)
  │  Is_TTY := Termicap.TTY.Is_TTY (Stdout);  -- Scenario 5 (SPARK_Mode => Off)
  │
  ▼
Termicap.Color.Detect_Color_Level (Env, Is_TTY)   [SPARK Silver, Global => null]
  │
  │  Step 1: Contains (Env, "FORCE_COLOR")?
  │    Yes → Classify value → set Floor, Force_Set := True (or return None)
  │    No  → continue
  │
  │  Step 2: not Force_Set → Parse_Clicolor_Force (Env)
  │    CLICOLOR_FORCE present and ≠ "0" → Floor := Basic_16, Force_Set := True
  │
  │  Step 3: not Force_Set and Contains (Env, "NO_COLOR") → return None
  │
  │  Step 4: Equal_Case_Insensitive (Value (Env, "TERM"), "dumb")
  │    True → return Floor   (None unless steps 1–2 set it)
  │
  │  Step 5: Detect_CI_Color (Env)
  │    GITHUB_ACTIONS="true" / GITEA_ACTIONS / CIRCLECI → Heuristic := True_Color
  │    TRAVIS / APPVEYOR / GITLAB_CI / BUILDKITE / DRONE → Heuristic := Basic_16
  │    CI present (generic) → Heuristic := Basic_16
  │
  │  Step 6: not Is_TTY and Floor = None and Heuristic = None → return None
  │
  │  Step 7: Detect_Colorterm (Env)
  │    COLORTERM = "truecolor"/"24bit":
  │      if TERM starts with "screen" and TERM_PROGRAM ≠ "tmux"
  │        → cap at Extended_256 (multiplexer cannot pass TrueColor)
  │      else → True_Color
  │    COLORTERM present (other value) → Basic_16
  │    → Heuristic := Color_Level'Max (Heuristic, result)
  │
  │  Step 8: Detect_Term_Program (Env)
  │    TERM_PROGRAM = "iTerm.app":
  │      TERM_PROGRAM_VERSION starts with '3' or higher → True_Color
  │      otherwise → Extended_256
  │    TERM_PROGRAM = "Apple_Terminal" / "vscode" → Extended_256
  │    → Heuristic := Color_Level'Max (Heuristic, result)
  │
  │  Step 9: Detect_Term_Pattern (Env)
  │    TERM ends with "-256color" or "-256" → Extended_256
  │    TERM contains xterm/screen/vt100/vt220/rxvt/color/ansi/cygwin/linux → Basic_16
  │    → Heuristic := Color_Level'Max (Heuristic, result)
  │
  │  Step 10: Has_Clicolor (Env)
  │    CLICOLOR present and ≠ "0" → Heuristic := Color_Level'Max (Heuristic, Basic_16)
  │
  │  Step 11: return Color_Level'Max (Floor, Heuristic)
  │
  └──► Color_Level result (None / Basic_16 / Extended_256 / True_Color)
```

**Key properties:**

- `Detect_Color_Level` is a pure function: no OS calls, no global state. GNATprove verifies `Global => null` on the spec.
- The `Floor` variable accumulates force overrides (steps 1–2). The `Heuristic` variable accumulates evidence-based detections (steps 5, 7–10). The final result is `Color_Level'Max (Floor, Heuristic)`, ensuring a force override can never be undercut by a heuristic.
- All `Contains` and `Value` calls delegate to `Termicap.Environment` (Scenarios 2 and the query flow), which are themselves `Global => null`.
- The multiplexer cap (step 7) requires both a `TERM` prefix check (`screen`) and a `TERM_PROGRAM` value check (`tmux`), demonstrating multi-variable coordination within a single pure function.
- Integration test pattern (no OS, no TTY):

```ada
declare
   Env : Environment := EMPTY_ENVIRONMENT;
   Level : Color_Level;
begin
   Insert (Env, "COLORTERM", "truecolor");
   Level := Detect_Color_Level (Env, Is_TTY => True);
   pragma Assert (Level = True_Color);

   --  NO_COLOR overrides even truecolor claim
   Insert (Env, "NO_COLOR", "");
   Level := Detect_Color_Level (Env, Is_TTY => True);
   pragma Assert (Level = None);
end;
```

## Scenario 9: Terminal Dimensions Detection — TTY Path (ioctl)

Executed when stdout is connected to an interactive terminal. This is the primary path that delivers accurate live dimensions including optional pixel sizes.

```
Application Init (Ada-only region)
  │
  │  Env    : Environment;
  │  Is_TTY : Boolean;
  │
  │  Capture_Current (Env);                        -- Scenario 1 (SPARK_Mode => Off)
  │  Is_TTY := Termicap.TTY.Is_TTY (Stdout);       -- Scenario 5 (SPARK_Mode => Off)
  │
  ▼
Termicap.Dimensions.Get_Size (Env, Is_TTY => True)  [spec: SPARK, body: SPARK_Mode => Off]
  │
  │  Is_TTY = True → attempt ioctl path:
  │
  │  C_Get_Winsize (Fd => 1, Cols, Rows, X_Pixel, Y_Pixel)
  │    │                                           [pragma Import (C, ..., "termicap_get_winsize")]
  │    ▼
  │  termicap_get_winsize (fd=1)                   [src/c/termicap_ioctl.c]
  │    │  ioctl (1, TIOCGWINSZ, &ws)
  │    │  if result < 0: return -1
  │    │  *cols   = ws.ws_col
  │    │  *rows   = ws.ws_row
  │    │  *xpixel = ws.ws_xpixel
  │    │  *ypixel = ws.ws_ypixel
  │    └──► return 0
  │
  │  Status = 0 and C_Cols > 0 and C_Rows > 0?
  │    Yes →
  │      return (Columns      => Positive (C_Cols),
  │              Rows         => Positive (C_Rows),
  │              Pixel_Width  => Natural (C_X_Pixel),
  │              Pixel_Height => Natural (C_Y_Pixel))
  │
  └──► Terminal_Size with live dimensions and pixel info
```

**Key properties:**

- `termicap_get_winsize` is a fixed-signature C wrapper required because `ioctl(2)` is variadic and cannot be bound directly from Ada via `pragma Import` (ADR-0006).
- The C wrapper returns `-1` on any error; Ada maps a non-zero status or zero dimensions to "ioctl failed", falling through to Scenario 10.
- `Pixel_Width` and `Pixel_Height` may themselves be zero even on a successful ioctl call — some terminal emulators do not populate `ws_xpixel`/`ws_ypixel`.

## Scenario 10: Terminal Dimensions Detection — Environment Variable Fallback

Executed when `Is_TTY = False` (piped/redirected output) or when the ioctl call fails.

```
Termicap.Dimensions.Get_Size (Env, Is_TTY)   [body: SPARK_Mode => Off]
  │
  │  Result := (Rows => 24, Columns => 80, Pixel_Width => 0, Pixel_Height => 0)
  │            -- DEFAULT_ROWS, DEFAULT_COLUMNS, 0, 0
  │
  │  [ioctl skipped or failed]
  │
  │  Step 2: Parse COLUMNS env var (FUNC-DIM-003)
  │    Contains (Env, "COLUMNS")?
  │      Yes → Try_Parse_Positive (Value (Env, "COLUMNS"))
  │              > 0 → Result.Columns := Parsed
  │              = 0 → Result.Columns stays at DEFAULT_COLUMNS (80)
  │      No  → Result.Columns stays at DEFAULT_COLUMNS (80)
  │
  │  Step 3: Parse LINES env var (FUNC-DIM-003)
  │    Contains (Env, "LINES")?
  │      Yes → Try_Parse_Positive (Value (Env, "LINES"))
  │              > 0 → Result.Rows := Parsed
  │              = 0 → Result.Rows stays at DEFAULT_ROWS (24)
  │      No  → Result.Rows stays at DEFAULT_ROWS (24)
  │
  │  [Pixel_Width and Pixel_Height remain 0 — env vars carry no pixel info]
  │
  └──► Terminal_Size (columns and rows from env or defaults; pixels always 0)
```

**Key properties:**

- Each axis (columns and rows) falls back independently. A valid `COLUMNS` can coexist with a missing/invalid `LINES`, giving `(Columns => env_value, Rows => 24)`.
- `Try_Parse_Positive` rejects the empty string, non-digit characters, overflow, and the literal `"0"` — all map to a `Natural` result of `0`, causing the axis to retain its default.
- When `Is_TTY = False`, `Pixel_Width` and `Pixel_Height` are always `0` — there is no environment variable convention for pixel sizes.
- This path is fully testable with no OS interaction using `EMPTY_ENVIRONMENT` + `Insert`.

## Scenario 11: Terminal Dimensions Testability Pattern

Unit tests exercise the environment-variable and default paths without any OS calls or TTY state.

```
Test body
  │
  │  Env : Environment := EMPTY_ENVIRONMENT;
  │
  │  --  Default fallback (no env vars set, Is_TTY = False)
  │  Size := Get_Size (Env, Is_TTY => False);
  │  pragma Assert (Size.Columns = 80);
  │  pragma Assert (Size.Rows    = 24);
  │
  │  --  COLUMNS env var override
  │  Insert (Env, "COLUMNS", "132");
  │  Size := Get_Size (Env, Is_TTY => False);
  │  pragma Assert (Size.Columns = 132);
  │  pragma Assert (Size.Rows    = 24);   -- LINES not set → default
  │
  │  --  Invalid COLUMNS value → ignored, falls back to default
  │  Insert (Env, "COLUMNS", "not_a_number");
  │  Size := Get_Size (Env, Is_TTY => False);
  │  pragma Assert (Size.Columns = 80);
  │
  └──► All results deterministic; no TTY, no ioctl, no OS state
```

**Key properties:**

- `Termicap.Environment.Capture` and `Termicap.TTY` are never called in unit tests.
- The ioctl path is exercised only via integration tests or the interactive demo (`examples/dimensions_demo/`).
- Tests are fully parallelizable and reproduce identically across machines, including CI environments without a TTY.

---

## Related Documents

- **Building Blocks** (`docs/architecture/03-building-blocks.md`): Static package structure and SPARK boundary diagram
- **Tech Spec F1** (`docs/tech-specs/f1-environment-variable-abstraction.md`): Design rationale, especially Sections C (Type Design) and D (SPARK Strategy)
- **Tech Spec F2** (`docs/tech-specs/f2-tty-detection.md`): TTY detection design rationale
- **Tech Spec F3** (`docs/tech-specs/f3-color-level-detection.md`): Color level detection design rationale
- **Tech Spec F4** (`docs/tech-specs/terminal-dimensions.md`): Terminal dimensions detection design rationale
- **ADR-0006** (`docs/adr/0006-c-wrapper-for-ioctl-tiocgwinsz.md`): Rationale for the thin C wrapper over ioctl
- **Requirements** (`docs/requirements/`): FUNC-ENV-002, FUNC-ENV-004, FUNC-ENV-005, FUNC-ENV-007, FUNC-ENV-008, FUNC-TTY-001 through FUNC-TTY-006, FUNC-CLR-001 through FUNC-CLR-015, FUNC-DIM-001 through FUNC-DIM-008
