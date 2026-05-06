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

Executed at detection time to determine whether standard I/O streams are connected to an interactive terminal. `Is_TTY` first checks the process-wide override before consulting the OS.

```
Caller (application / detection init)
  │
  │  Is_TTY (Stdout)
  ▼
Termicap.TTY                          [spec: SPARK, body: SPARK_Mode => Off]
  │
  │  Step 0: Get_Override              -- read Termicap.Override.Override_State
  │    Force_Basic | Force_256 | Force_True_Color → return True  (force TTY on)
  │    Force_None                               → return False (force TTY off)
  │    Auto                                     → fall through to isatty()
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

- When `Override_Mode /= Auto`, the entire `isatty()` call is skipped; the result is determined entirely by the override.
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

Downstream detection functions receive TTY status as a plain `Boolean` parameter, keeping the FFI call outside the SPARK verification perimeter. After the Override feature, both `Is_TTY` and `Detect_Color_Level` reference `Termicap.Override.Override_State` in their `Global` aspects.

```
Application Init (Ada-only region)
  │
  │  Is_Interactive : constant Boolean := Is_TTY (Stdout);  -- override-aware
  │  Capture_Current (Env);
  │
  ▼
Detection Logic         [SPARK Silver, Global => (Input => Override_State)]
  │
  │  function Detect_Color_Level
  │    (Env            : Environment;
  │     Is_Interactive : Boolean) return Color_Level
  │
  │  0. if Get_Override /= Auto then return mapped Color_Level immediately
  │  1. if not Is_Interactive and not Force_Color then return None
  │  2. Check env vars: NO_COLOR, FORCE_COLOR, COLORTERM, TERM ...
  │
  └──► Color_Level result
```

**Key properties:**

- `Is_TTY` call happens once in an Ada-only region. When the override is active, `Is_TTY` returns immediately without calling `isatty()`.
- The `Boolean` result flows into SPARK functions as a parameter.
- `Global => (Input => Termicap.Override.Override_State)` contracts are in effect on both `Is_TTY` and `Detect_Color_Level`. SPARK callers must include `Override_State` in their own `Global` aspects.
- This is the canonical integration pattern for `Termicap.TTY` with `Termicap.Environment` and `Termicap.Override`.

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
Termicap.Color.Detect_Color_Level (Env, Is_TTY)
  │                     [SPARK Silver, Global => (Input => Override_State)]
  │
  │  Step 0: Get_Override (reads Override_State)
  │    /= Auto → return mapped Color_Level immediately; all other steps skipped
  │    = Auto  → continue
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

- `Detect_Color_Level` performs no OS calls and reads only `Override_State`. GNATprove verifies `Global => (Input => Termicap.Override.Override_State)` on the spec (SPARK Silver).
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

## Scenario 9: Unicode Level Detection Flow

Full end-to-end scenario showing how a client calls `Detect_Unicode_Level`. Unlike color and dimensions detection, no TTY status is needed — the environment snapshot alone is sufficient.

```
Application Init (Ada-only region)
  │
  │  Env : Environment;
  │
  │  Capture_Current (Env);             -- Scenario 1 (SPARK_Mode => Off)
  │
  ▼
Termicap.Unicode.Detect_Unicode_Level (Env)   [SPARK Silver, Global => null]
  │
  │  Step 1: Locale detection (FUNC-UNI-003)
  │    LC_ALL present and contains "UTF-8" (case-insensitive)?
  │      Yes → Level := Extended
  │    LC_CTYPE present and contains "UTF-8"?
  │      Yes → Level := Extended
  │    LANG present and contains "UTF-8"?
  │      Yes → Level := Extended
  │
  │  Step 2: TERM=linux exclusion (FUNC-UNI-004)
  │    Equal_Case_Insensitive (Value (Env, "TERM"), "linux")?
  │      Yes → return None   (Linux kernel console has no Unicode rendering)
  │
  │  Step 3: CI environment awareness (FUNC-UNI-006)
  │    GITHUB_ACTIONS / GITEA_ACTIONS / CIRCLECI present?
  │      Yes → Level := Unicode_Level'Max (Level, Basic)
  │
  │  Step 4: Windows terminal heuristics (FUNC-UNI-005)
  │    WT_SESSION present → Level := Unicode_Level'Max (Level, Extended)
  │    TERM_PROGRAM = "vscode" → Level := Unicode_Level'Max (Level, Extended)
  │    TERMINAL_EMULATOR contains "JetBrains" → Level := Unicode_Level'Max (Level, Extended)
  │
  │  Step 5: Default
  │    return Level   (None if no heuristic matched)
  │
  └──► Unicode_Level result (None / Basic / Extended)
```

**Key properties:**

- `Detect_Unicode_Level` takes only `Env` — no `Is_TTY` parameter. Unicode capability is a property of the terminal emulator and locale, not of stream connectivity (FUNC-UNI-002). This makes it the only detection function callable without first invoking `Is_TTY`.
- Both the spec and the body carry `SPARK_Mode => On`, making `Termicap.Unicode` the only detection package that is fully SPARK Silver provable end-to-end (FUNC-UNI-007).
- The `TERM=linux` exclusion (step 2) takes priority over locale detection: a UTF-8 locale set by a wrapper script does not grant Unicode capability to the raw Linux kernel console.
- Integration test pattern (no OS, no TTY):

```ada
declare
   Env   : Environment := EMPTY_ENVIRONMENT;
   Level : Unicode_Level;
begin
   Insert (Env, "LANG", "en_US.UTF-8");
   Level := Detect_Unicode_Level (Env);
   pragma Assert (Level = Extended);

   --  TERM=linux overrides the UTF-8 locale
   Insert (Env, "TERM", "linux");
   Level := Detect_Unicode_Level (Env);
   pragma Assert (Level = None);
end;
```

## Scenario 10: Terminal Dimensions Detection — TTY Path (ioctl)

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
- The C wrapper returns `-1` on any error; Ada maps a non-zero status or zero dimensions to "ioctl failed", falling through to Scenario 11.
- `Pixel_Width` and `Pixel_Height` may themselves be zero even on a successful ioctl call — some terminal emulators do not populate `ws_xpixel`/`ws_ypixel`.

## Scenario 11: Terminal Dimensions Detection — Environment Variable Fallback

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

## Scenario 12: Terminal Dimensions Testability Pattern

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

## Scenario 13: Terminal Identity Detection Flow

Full end-to-end scenario showing how a client calls `Detect_Terminal_Identity`. Only the environment snapshot is required — no TTY status.

```
Application Init (Ada-only region)
  │
  │  Env : Environment;
  │
  │  Capture_Current (Env);             -- Scenario 1 (SPARK_Mode => Off)
  │
  ▼
Termicap.Terminal_Id.Detect_Terminal_Identity (Env)   [spec: SPARK, body: SPARK_Mode => Off]
  │
  │  Result := (Kind => Unknown, Is_Multiplexer => False,
  │             Program_Name | Program_Version | Term_Value => "")
  │
  │  [String fields populated unconditionally from env, regardless of Kind]
  │  Result.Program_Name    := Value (Env, "TERM_PROGRAM")
  │  Result.Program_Version := Value (Env, "TERM_PROGRAM_VERSION")
  │  Result.Term_Value      := Value (Env, "TERM")
  │
  │  Step 1: TERM_PROGRAM (priority 1 — FUNC-TID-004)
  │    Contains (Env, "TERM_PROGRAM")?
  │      "iTerm.app"      → Kind := ITerm2
  │      "Apple_Terminal" → Kind := Apple_Terminal
  │      "vscode"         → Kind := VSCode
  │      "WezTerm"        → Kind := WezTerm
  │      "WarpTerminal"   → Kind := WarpTerminal
  │      "mintty"         → Kind := Mintty
  │
  │  Step 2: TERMINAL_EMULATOR (priority 2, only if Kind = Unknown)
  │    "JetBrains-JediTerm" → Kind := JediTerm
  │
  │  Step 3: WT_SESSION presence (priority 3, only if Kind = Unknown)
  │    present → Kind := Windows_Terminal
  │
  │  Step 4: KONSOLE_VERSION presence (priority 4, only if Kind = Unknown)
  │    present → Kind := Konsole
  │
  │  Step 5: VTE_VERSION presence (priority 5, only if Kind = Unknown)
  │    present → Kind := VTE
  │
  │  Step 6: TMUX presence (priority 6, only if Kind = Unknown)
  │    present → Kind := Tmux
  │
  │  Step 7: TERM value/prefix matching (priority 7, only if Kind = Unknown)
  │    "dumb"         → Kind := Dumb
  │    "linux"        → Kind := Linux_Console
  │    prefix "tmux"  → Kind := Tmux
  │    prefix "screen"→ Kind := Screen
  │    "xterm-kitty"  → Kind := Kitty
  │    "xterm-ghostty"→ Kind := Ghostty
  │    "alacritty"    → Kind := Alacritty
  │    "wezterm"      → Kind := WezTerm
  │    prefix "rxvt"  → Kind := Rxvt
  │    "foot"/"foot-extra" → Kind := Foot
  │    prefix "xterm" → Kind := Xterm
  │
  │  Step 8: Default — Kind remains Unknown if no rule matched
  │
  │  [Derive Is_Multiplexer — FUNC-TID-006]
  │  Result.Is_Multiplexer := Result.Kind in Multiplexer_Kind
  │                        -- (i.e., Kind in Tmux | Screen)
  │
  └──► Terminal_Identity
         .Kind            -- Classified terminal or Unknown
         .Is_Multiplexer  -- True iff Kind in Tmux | Screen
         .Program_Name    -- raw TERM_PROGRAM value (or "")
         .Program_Version -- raw TERM_PROGRAM_VERSION value (or "")
         .Term_Value      -- raw TERM value (or "")
```

**Key properties:**

- `Detect_Terminal_Identity` takes only `Env` — no `Is_TTY` parameter. Terminal identity is determined entirely from environment variable strings, independent of stream connectivity (FUNC-TID-003).
- All value comparisons are case-insensitive, delegating to `Equal_Case_Insensitive` in `Termicap.Environment` or the private `Starts_With_CI` helper for prefix checks (FUNC-TID-010).
- String fields (`Program_Name`, `Program_Version`, `Term_Value`) are always populated from the snapshot regardless of whether those variables influenced the `Kind` classification. Absent variables yield the empty `Unbounded_String` (FUNC-TID-004).
- The spec carries two GNATprove-verifiable postconditions: (1) if none of the seven probe variables are present in `Env` then `Kind = Unknown` and `Is_Multiplexer = False`; (2) `Is_Multiplexer` equals `Kind in Multiplexer_Kind` in all cases (FUNC-TID-005, FUNC-TID-006).
- The body has `SPARK_Mode => Off` because `Ada.Strings.Unbounded` is a controlled type outside the SPARK subset. The spec contracts remain verifiable for all callers in the SPARK zone (ADR-0008).
- Integration test pattern (no OS, no TTY):

```ada
declare
   Env    : Environment := EMPTY_ENVIRONMENT;
   Result : Terminal_Identity;
begin
   --  tmux multiplexer via TERM
   Insert (Env, "TERM", "tmux-256color");
   Result := Detect_Terminal_Identity (Env);
   pragma Assert (Result.Kind = Tmux);
   pragma Assert (Result.Is_Multiplexer);

   --  TERM_PROGRAM takes priority over TERM
   Insert (Env, "TERM_PROGRAM", "WezTerm");
   Result := Detect_Terminal_Identity (Env);
   pragma Assert (Result.Kind = WezTerm);
   pragma Assert (not Result.Is_Multiplexer);

   --  String fields populated even when a different variable drove Kind
   pragma Assert (To_String (Result.Term_Value) = "tmux-256color");
end;
```


## Scenario 14: Color Downsampling Flow

Full end-to-end scenario showing how a caller converts a TrueColor RGB value to the color level actually supported by the terminal. Color detection (Scenario 8) and downsampling are independent steps; downsampling receives a `Color_Level` by value, not an environment snapshot.

```
Application Init (Ada-only region)
  │
  │  Env    : Environment;
  │  Is_TTY : Boolean;
  │
  │  Capture_Current (Env);                      -- Scenario 1 (SPARK_Mode => Off)
  │  Is_TTY := Termicap.TTY.Is_TTY (Stdout);     -- Scenario 5 (SPARK_Mode => Off)
  │
  ▼
Termicap.Color.Detect_Color_Level (Env, Is_TTY)  [SPARK Silver, Global => null]
  │
  │  ... 11-step cascade (Scenario 8) ...
  │
  └► Level : Color_Level   -- e.g. Basic_16 (terminal supports only 16 colors)

  │
  │  Source_Color : RGB := (Red => 220, Green => 50, Blue => 47);
  │
  ▼
Termicap.Downsampling.Downsample                 [SPARK Gold, Global => null]
  (Color => Source_Color, Target => Level)
  │
  │  Target = Basic_16 → Downsample_True_To_16 (Source_Color)
  │    │  Compute redmean weighted Euclidean distance to each of the 16
  │    │  canonical ANSI palette entries.
  │    │  Return the index of the nearest entry (tie → lower index).
  │    └► Color_Index_16 result (e.g. 1 — red)
  │
  └► Downsampled_Color'(Level => Basic_16, Index_16 => 1)

Caller dispatch on Downsampled_Color discriminant:

  case Result.Level is
     when None         => null;  --  emit no SGR escape code
     when Basic_16     => Emit_SGR_16  (Result.Index_16);
     when Extended_256 => Emit_SGR_256 (Result.Index_256);
     when True_Color   => Emit_SGR_RGB (Result.RGB_Value.Red,
                                        Result.RGB_Value.Green,
                                        Result.RGB_Value.Blue);
  end case;
```

**Key properties:**

- `Downsample` and all primitive conversion functions are pure: `Global => null`, no OS calls, no global state. GNATprove verifies this at Gold level — both spec and body carry `SPARK_Mode => On`.
- The `Downsampled_Color` discriminant is the terminal's `Color_Level`, so the caller's case statement is always exhaustive and statically checkable.
- When `Level = True_Color`, `Downsample` returns an identity result (`RGB_Value = Source_Color`), verified by the idempotency postcondition (FUNC-DSP-009).
- When `Level = None`, `Downsample` returns `(Level => None)` — no index or RGB value to extract (FUNC-DSP-007).
- The monotonicity postcondition (FUNC-DSP-010) guarantees `Color_Level_Of (result) <= Color_Level'Min (True_Color, Target)`: the output level never exceeds the requested target.
- `Color_Index_16` values may be downsampled further by passing them to the `Color_Index_256` overload of `Downsample`, since `Color_Index_16` is a subtype of `Color_Index_256` (FUNC-DSP-003).
- Integration test pattern (no OS, no TTY, no environment snapshot):

```ada
declare
   Red    : constant RGB := (Red => 220, Green => 50, Blue => 47);
   Result : Downsampled_Color;
begin
   --  Terminal supports only 16 colors
   Result := Downsample (Red, Target => Basic_16);
   pragma Assert (Result.Level = Basic_16);

   --  Terminal supports TrueColor -- identity case
   Result := Downsample (Red, Target => True_Color);
   pragma Assert (Result.Level = True_Color);
   pragma Assert (Result.RGB_Value.Red   = Red.Red);
   pragma Assert (Result.RGB_Value.Green = Red.Green);
   pragma Assert (Result.RGB_Value.Blue  = Red.Blue);

   --  No-color terminal -- strip-to-None
   Result := Downsample (Red, Target => None);
   pragma Assert (Result.Level = None);
end;
```

## Scenario 15: SIGWINCH Resize Notification Flow

End-to-end sequence showing both the polling pattern and the self-pipe (event-loop) pattern for consuming terminal resize events.

### Phase A — Installation

```
Application (Ada-only region)
  │
  │  Termicap.Sigwinch.Install (Terminal_FD => 1)
  ▼
Termicap.Sigwinch                       [SPARK_Mode => Off]
  │
  │  Protected singleton: Installed = False → proceed
  │
  │  pipe2 (read_fd, write_fd, O_NONBLOCK)   [C trampoline]
  │    └──► OS creates pipe; write end is O_NONBLOCK to avoid
  │         blocking inside the async-signal-safe handler
  │
  │  ioctl (Terminal_FD, TIOCGWINSZ, &ws)    [C trampoline]
  │    └──► Cached_Size := (Rows => ws.ws_row, Columns => ws.ws_col, ...)
  │
  │  sigaction (SIGWINCH, new_handler, &old_sa)  [C trampoline]
  │    └──► OS installs C handler; old disposition saved for Uninstall
  │
  │  Protected singleton: Installed := True, Pending := False
  │
  └──► Install returns; application may now use pipe read FD and polling API
```

### Phase B — Signal Delivery (OS / C handler, async-signal context)

```
OS kernel (terminal resize event)
  │
  │  Delivers SIGWINCH to process
  ▼
C handler (termicap_sigwinch.c)          [async-signal-safe]
  │
  │  ioctl (Terminal_FD, TIOCGWINSZ, &ws)
  │    └──► Re-queries current dimensions; result written to shared struct
  │
  │  write (write_fd, "\x00", 1)
  │    └──► Wakes any select()/poll()/epoll() waiter on read_fd
  │         (O_NONBLOCK: never blocks even if pipe buffer is full)
  │
  │  [No heap allocation, no non-reentrant functions — async-signal-safe]
  │
  └──► C handler returns; Ada protected object will absorb the update
       on the next entry call from the application
```

### Phase C — Consuming the Event

Two consumption patterns are supported and may be mixed:

**Polling pattern** (no I/O multiplexer required):

```
Application (polling loop)
  │
  │  if Termicap.Sigwinch.Has_Resize then
  ▼
Termicap.Sigwinch.Has_Resize            [protected function]
  │
  │  Protected singleton read: return Pending
  │
  └──► True if at least one SIGWINCH arrived since install or last Acknowledge

  │
  │  Size := Termicap.Sigwinch.Get_Cached_Size
  ▼
Termicap.Sigwinch.Get_Cached_Size       [protected function]
  │
  │  Protected singleton read: return Cached_Size
  │    (dimensions from last C handler ioctl call, updated atomically)
  │
  └──► Terminal_Size — no new ioctl performed

  │
  │  Termicap.Sigwinch.Acknowledge_Resize
  ▼
Termicap.Sigwinch.Acknowledge_Resize    [protected procedure]
  │
  │  Protected singleton write: Pending := False
  │  [Separate from Has_Resize to prevent loss of a concurrent SIGWINCH]
  │
  └──► Has_Resize will now return False until the next signal
```

**Self-pipe / event-loop pattern** (`select` / `poll` / `epoll`):

```
Application (event loop setup)
  │
  │  FD := Termicap.Sigwinch.Get_Pipe_Read_FD
  │    └──► Non-negative FD when installed; -1 on non-Unix or not installed
  │
  │  Register FD with select()/poll()/epoll()
  │
  ▼
Event loop (blocking on select/poll/epoll)
  │
  │  [FD becomes readable after C handler writes to pipe]
  │
  │  Drain pipe: read and discard all available bytes (loop until EAGAIN)
  │  Size := Termicap.Sigwinch.Get_Cached_Size
  │  Termicap.Sigwinch.Acknowledge_Resize
  │
  └──► Application handles resize with fresh cached dimensions
```

### Phase D — Uninstallation

```
Application
  │
  │  Termicap.Sigwinch.Uninstall
  ▼
Termicap.Sigwinch                       [SPARK_Mode => Off]
  │
  │  sigaction (SIGWINCH, &old_sa, NULL)   -- restore previous disposition
  │  close (write_fd)
  │  close (read_fd)
  │
  │  Protected singleton: Installed := False, Pending := False,
  │                        Cached_Size := DEFAULT_SIZE
  │
  └──► All resources released; FD from Get_Pipe_Read_FD is now invalid
```

**Key properties:**

- `Install` and `Uninstall` are idempotent: repeated calls without a matching pair are safe (FUNC-SWC-001).
- The C handler is entirely async-signal-safe: only `ioctl` (which is async-signal-safe) and `write` (which is async-signal-safe on Linux/macOS) are called. No heap allocation, no `malloc`, no stdio (FUNC-SWC-004).
- `Has_Resize` and `Get_Cached_Size` are non-blocking protected reads. `Acknowledge_Resize` is a protected write. All are safe to call from multiple Ada tasks concurrently (FUNC-SWC-007).
- The pipe write end is O_NONBLOCK so the C handler never stalls even if the reader has not drained the pipe between consecutive SIGWINCH signals. Multiple unread bytes in the pipe are normalised by draining the pipe before calling `Get_Cached_Size` (FUNC-SWC-004).
- On non-Unix platforms, `Install` and `Uninstall` are no-ops, `Get_Pipe_Read_FD` returns `-1`, `Has_Resize` returns `False`, and `Get_Cached_Size` returns the default size. No exceptions are raised (FUNC-SWC-008).
- Integration test pattern (interactive demo only): because `Install` performs a real `sigaction` and `ioctl`, the SIGWINCH path is exercised by the interactive example (`examples/sigwinch_demo/`) rather than automated unit tests.

## Scenario 16: Global Override — Programmatic and Scoped Flows

These scenarios cover the four main uses of `Termicap.Override`: setting a process-wide override from a CLI flag, querying/resetting it, and using a scoped guard.

### Phase A — Setting an Override from a CLI Flag

```
Application startup (Ada-only region)
  │
  │  Flag_Value : constant String := "--color=always";  -- from argv
  │
  │  Set_Override (Parse_Color_Flag ("always"))
  ▼
Termicap.Override.Parse_Color_Flag ("always")   [Global => null, SPARK Gold]
  │
  │  Case-insensitive comparison:
  │    "always" → Force_True_Color
  │
  └──► Override_Mode := Force_True_Color

Termicap.Override.Set_Override (Force_True_Color)
  │                              [Global => (In_Out => Override_State)]
  ▼
Protected object (SPARK_Mode => Off body)
  │
  │  State := Force_True_Color
  │
  └──► Override_State now holds Force_True_Color
```

**Key properties:**

- `Parse_Color_Flag` is a pure function (`Global => null`). It is total over all `String` inputs; any unrecognised string returns `Auto` so that `Set_Override (Parse_Color_Flag (unknown))` is equivalent to no override.
- `Set_Override` writes to the protected object; the body is `SPARK_Mode => Off`. The call is thread-safe.
- Initial state of the protected object is `Auto`. If `Set_Override` is never called, `Get_Override` returns `Auto` and all detection functions behave as if `Termicap.Override` were not present.

### Phase B — Override Short-Circuit in Detection Functions

After `Set_Override (Force_True_Color)` from Phase A:

```
Application
  │
  │  Level := Detect_Color_Level (Env, Is_TTY => False)
  ▼
Termicap.Color.Detect_Color_Level          [Global => (Input => Override_State)]
  │
  │  Step 0: Get_Override → Force_True_Color   (/= Auto)
  │    → return True_Color immediately
  │    (steps 1–11: env-var cascade is never reached)
  │
  └──► Color_Level = True_Color

Application
  │
  │  TTY : Boolean := Is_TTY (Stdout)
  ▼
Termicap.TTY.Is_TTY (Stdout)               [Global => (Input => Override_State)]
  │
  │  Step 0: Get_Override → Force_True_Color   (any Force_* except Force_None)
  │    → return True immediately
  │    (isatty() C call is never reached)
  │
  └──► Boolean = True
```

**Key properties:**

- The override check adds a single protected-function read before each detection call. When `Override_Mode = Auto`, control falls through to the existing detection logic unchanged.
- `Force_None` maps to `Color_Level = None` in `Detect_Color_Level` and `False` in `Is_TTY`. `Force_Basic` / `Force_256` / `Force_True_Color` map to `True` in `Is_TTY` (any color level forces the TTY gate open).

### Phase C — Reset and Restore

```
Application
  │
  │  Reset_Override
  ▼
Termicap.Override.Reset_Override           [Post => Get_Override = Auto]
  │
  │  Set_Override (Auto)
  │  Protected object: State := Auto
  │
  └──► Override_State = Auto; normal detection resumes
```

### Phase D — Scoped Override (RAII Guard)

```
Application (single task recommended)
  │
  │  declare
  │     Guard : Scoped_Override (Mode => Force_256);
  │                              -- Initialize called on declaration
  ▼
Scoped_Override.Initialize (Self.Mode = Force_256)  [SPARK_Mode => Off]
  │
  │  Self.Saved := Get_Override   -- capture current mode (e.g. Auto)
  │  Set_Override (Force_256)     -- install the new override
  │
  └──► Override_State = Force_256

  │  [block body executes with Force_256 active]
  │  Level := Detect_Color_Level (Env, Is_TTY => True);
  │    → returns Extended_256 immediately (step 0 short-circuit)
  │
  │  end;  -- scope exit: Finalize called
  ▼
Scoped_Override.Finalize              [SPARK_Mode => Off]
  │
  │  Set_Override (Self.Saved)   -- restore previously captured mode (Auto)
  │  [any exception suppressed — FUNC-OVR-008]
  │
  └──► Override_State = Auto; previous behavior restored
```

**Key properties:**

- `Scoped_Override` is `Limited_Controlled` (not `Controlled`). It cannot be copied; this prevents two objects sharing the same `Saved` value from double-restoring on finalization (FUNC-OVR-008).
- Finalization suppresses all exceptions via a `when others => null` handler. This is required by Ada rules: an exception propagated out of `Finalize` during stack unwinding causes `Program_Error` (FUNC-OVR-008).
- Scoped guards nest correctly in a single task: each `Scoped_Override` saves the mode that was active at the time of its declaration, so overlapping guards restore in LIFO order. Across tasks, the save/restore sequences interleave — use process-wide `Set_Override` / `Reset_Override` when task-local override scoping is needed.

## Scenario 17: Capability Record Assembly — Get and Detect Flows

End-to-end scenarios showing how `Termicap.Capabilities.Get` and `Termicap.Capabilities.Detect` aggregate all sub-detector results into a single `Terminal_Capabilities` record.

### Phase A — Get (Cached Path, Cache Miss)

On the first call for a given stream, `Get` delegates to `Detect` and caches the result.

```
Application
  │
  │  Caps : Terminal_Capabilities := Termicap.Capabilities.Get
  │                                  -- Stream => Stdout (default)
  ▼
Termicap.Capabilities.Get (Stream => Stdout)   [body: SPARK_Mode => Off]
  │
  │  Protected cache object: slot for Stdout not yet populated
  │    → cache miss → call Detect (Stdout)
  │
  ▼
Termicap.Capabilities.Detect (Stream => Stdout)
  │
  │  Step 1: Capture_Current (Env)              [SPARK_Mode => Off]
  │    └──► Immutable Environment snapshot of the live process environment
  │
  │  Step 2: Detect_Terminal_Identity (Env)     [spec: SPARK, body: Off]
  │    └──► Terminal_Identity (Kind, Is_Multiplexer, string fields)
  │
  │  Step 3: Status := Query_All                [SPARK_Mode => Off]
  │    └──► TTY_Status (Stdin, Stdout, Stderr — each from isatty() or override)
  │
  │  Step 4: Detect_Color_Level (Env, Status.Stdout)  [SPARK Silver]
  │    └──► Color_Level (None / Basic_16 / Extended_256 / True_Color)
  │
  │  Step 5: Get_Size (Env, Status.Stdout)      [spec: SPARK, body: Off]
  │    └──► Terminal_Size (Columns, Rows, Pixel_Width, Pixel_Height)
  │
  │  Step 6: Detect_Unicode_Level (Env)         [SPARK Silver]
  │    └──► Unicode_Level (None / Basic / Extended)
  │
  │  Step 7: Assemble (Status.Stdin, Status.Stdout, Status.Stderr,
  │                    Color, Size, Unicode, Identity)   [SPARK Silver, Global => null]
  │    └──► Terminal_Capabilities record;
  │         Downsampling_Available := Color >= Extended_256
  │         (GNATprove-verifiable postcondition)
  │
  └──► Terminal_Capabilities returned from Detect
  │
  ▼
Termicap.Capabilities.Get (cache write)
  │
  │  Protected cache object: store result in Stdout slot
  │    → subsequent Get (Stdout) calls return this copy without re-running sub-detectors
  │
  └──► Terminal_Capabilities copy returned to application
```

**Key properties:**

- The single `Capture_Current` call (step 1) ensures all sub-detectors operate on the same environment snapshot, satisfying FUNC-CAP-011.
- Sub-detectors are invoked in dependency order: identity and TTY status first (no environment dependency on each other), then color (needs TTY), size (needs TTY), and Unicode (no TTY needed) — satisfying FUNC-CAP-010.
- The `Assemble` function (step 7) is the only SPARK Silver subprogram in the body. All OS interaction is confined to steps 1–6 (FUNC-CAP-013).
- The cache is a protected object; the first-call population and all subsequent reads are thread-safe (FUNC-CAP-008).
- The returned record is a value copy — the cache is not aliased to the caller (FUNC-CAP-009).

### Phase B — Get (Cached Path, Cache Hit)

On subsequent calls for the same stream, `Get` returns the cached value immediately.

```
Application
  │
  │  Caps2 : Terminal_Capabilities := Termicap.Capabilities.Get
  │                                   -- Stream => Stdout (second call)
  ▼
Termicap.Capabilities.Get (Stream => Stdout)
  │
  │  Protected cache object: slot for Stdout is populated
  │    → cache hit → return copy without calling Detect
  │
  └──► Terminal_Capabilities copy returned to application
       (identical to first call result; no sub-detector executed)
```

**Key properties:**

- No sub-detector is invoked; no OS call is made.
- The cached value reflects the override state that was active at the time the cache slot was first populated (FUNC-CAP-006). If `Set_Override` is called after the first `Get`, the cached result is not automatically invalidated — callers that need fresh detection after an override change should use `Detect` directly.

### Phase C — Detect (Uncached, Fresh Detection)

`Detect` always performs a full detection run and never reads or writes the cache.

```
Application (e.g., after SIGWINCH or after calling Set_Override)
  │
  │  Caps : Terminal_Capabilities := Termicap.Capabilities.Detect
  │                                  -- Stream => Stdout (default)
  ▼
Termicap.Capabilities.Detect (Stream => Stdout)
  │
  │  [Identical to Phase A steps 1–7]
  │  [Cache is not consulted and not written]
  │
  └──► Fresh Terminal_Capabilities returned to application
```

**Key properties:**

- Every `Detect` call performs a complete detection run regardless of cache state, satisfying FUNC-CAP-004 and FUNC-CAP-014.
- Use `Detect` after `SIGWINCH` (to pick up new terminal dimensions) or after a `Set_Override` / `Reset_Override` call (to reflect the new override state immediately).
- `Detect` is safe to call from multiple Ada tasks concurrently — it holds no shared state of its own; all sub-detectors are either pure functions or thread-safe protected calls.

### Override Integration

When `Termicap.Override.Set_Override` has been called before `Get` or `Detect`:

- `TTY_Stdin`, `TTY_Stdout`, and `TTY_Stderr` fields reflect the override: any `Force_*` mode except `Force_None` returns `True`; `Force_None` returns `False` (FUNC-CAP-007).
- The `Color` field reflects the forced level directly from `Detect_Color_Level`'s step-0 override check (FUNC-CAP-006).
- `Downsampling_Available` is derived from `Color` by `Assemble`, so it also reflects the override indirectly.

---

## Scenario 18: OSC Probe Session — Query Lifecycle

End-to-end scenario showing how `Termicap.OSC.Probe_Session` sends an OSC query, accumulates the response using the DA1 sentinel pattern, and guarantees terminal state restoration.

### Phase A — Open: Foreground Check → /dev/tty → Raw Mode → Drain

```
Caller (active probing feature)
  │
  │  declare
  │     Session : Probe_Session;
  │     Status  : Session_Status;
  │  begin
  │     Open (Session, Status);
  ▼
Termicap.OSC.Open              [SPARK_Mode => Off]
  │
  │  Step 1: Is_Foreground_Process (any tty FD)  [FUNC-OSC-007]
  │    → ioctl(TIOCGPGRP) + getpgrp() comparison via C helper
  │    → if background: Status := Session_Not_Foreground; return
  │
  │  Step 2: Acquire single-session guard (Is_Raw flag)  [FUNC-OSC-012]
  │    → if Is_Raw = True on any existing session:
  │         Status := Session_Already_Active; return
  │
  │  Step 3: Open_Terminal  [FUNC-OSC-001]
  │    → termicap_osc_open_tty(): open("/dev/tty", O_RDWR)
  │    → if INVALID_FD: Status := Session_No_Terminal; return
  │
  │  Step 4: Save_Termios (FD, Saved_State, OK)  [FUNC-OSC-002]
  │    → termicap_osc_save_termios(): tcgetattr() → buffer
  │    → if not OK: Close_Terminal (FD);
  │               Status := Session_Save_Failed; return
  │
  │  Step 5: Set_Raw_Mode (FD, Saved_State, OK)  [FUNC-OSC-003]
  │    → termicap_osc_set_raw(): derive raw termios (clear ICANON,
  │        ECHO, ISIG, IXON, ICRNL, BRKINT; VMIN=0, VTIME=0)
  │    → tcsetattr(TCSANOW)
  │    → if not OK: Restore_Termios; Close_Terminal;
  │               Status := Session_Raw_Failed; return
  │    → Is_Raw := True
  │
  │  Step 6: Drain_Input (FD)  [FUNC-OSC-011]
  │    → non-blocking Timed_Read (Timeout_Ms = 0) loop
  │    → discard all buffered stale bytes
  │    → bounded to MAX_DRAIN_ITERATIONS; non-fatal
  │
  └──► Status := Session_OK; Session.FD valid; raw mode active
```

### Phase B — Query: Write + DA1 Sentinel → Accumulate → Detect Boundary

```
  │  Sentinel_Query (Session, Query, Response, Resp_Length,
  │                  Timeout_Ms => 250, Timed_Out, Retry => True)
  ▼
Termicap.OSC.Sentinel_Query    [SPARK_Mode => Off]
  │
  │  Attempt 1:
  │  │
  │  │  Write_Query (Session, Query, Written, Success)  [FUNC-OSC-005]
  │  │    → termicap_osc_write(): write() to Session.FD
  │  │
  │  │  Write DA1 sentinel (ESC [ c = 0x1B 0x5B 0x63)  [FUNC-OSC-006]
  │  │    → Write_Query (Session, DA1_SENTINEL, ...)
  │  │
  │  │  Accumulation loop:
  │  │  ┌──────────────────────────────────────────────────────────┐
  │  │  │  Timed_Read (Session.FD, Chunk, Bytes_Read,             │
  │  │  │              Timeout_Ms, Timed_Out)  [FUNC-OSC-004]     │
  │  │  │    → termicap_osc_select_read(): select() + read()      │
  │  │  │    → if select() timeout: Timed_Out := True; exit loop  │
  │  │  │    → append Chunk(1..Bytes_Read) to accumulation buffer │
  │  │  │    → if buffer length >= MAX_RESPONSE_SIZE: treat as    │
  │  │  │        timeout (FUNC-OSC-009)                            │
  │  │  │                                                          │
  │  │  │  Contains_DA1_Response (Buffer, Length)  [SPARK Silver] │
  │  │  │    → scan for ESC [ ? <digits/semicolons> c pattern     │
  │  │  │    → if found: DA1 boundary detected; exit loop         │
  │  │  └──────────────────────────────────────────────────────────┘
  │  │
  │  │  if Timed_Out and Retry:
  │  │    → Attempt 2 with Timeout_Ms * 2 (FUNC-OSC-013)
  │  │    → identical write + accumulation loop
  │  │
  │  │  if DA1 detected:
  │  │    DA1_Response_Start (Buffer, Length)  [SPARK Silver]
  │  │      → locate ESC byte starting the DA1 response
  │  │    Response(1..Start-1) := pre-sentinel bytes
  │  │    Resp_Length := Start - 1
  │  │    Timed_Out := False
  │  │
  └──► Response populated; Timed_Out reflects final outcome
```

### Phase C — Close: Restore Termios → Close FD (guaranteed by Finalize)

```
  │  end;  -- declare block exits: Finalize called on Session
  ▼
Termicap.OSC.Finalize / Close  [SPARK_Mode => Off, Ada.Finalization]
  │
  │  if Is_Raw:
  │  │
  │  │  Restore_Termios (FD, Saved_State, OK)  [FUNC-OSC-002]
  │  │    → termicap_osc_restore_termios(): copy buffer → tcsetattr(TCSANOW)
  │  │    → non-fatal: Close_Terminal proceeds regardless of OK
  │  │
  │  │  Close_Terminal (FD)  [FUNC-OSC-001]
  │  │    → termicap_osc_close_fd(): close(FD)
  │  │    → FD := INVALID_FD
  │  │
  │  │  Is_Raw := False  -- releases single-session guard
  │  │
  └──► Terminal fully restored; /dev/tty closed; session reusable
```

**Key properties:**

- `Finalize` is called unconditionally by the Ada runtime on scope exit, including during exception propagation. The terminal is always restored (FUNC-OSC-008).
- The `Is_Raw` boolean in `Probe_Session` doubles as the single-session guard (FUNC-OSC-012). Setting it to `True` in `Open` and back to `False` in `Finalize`/`Close` prevents concurrent sessions on different scopes.
- `Drain_Input` (step 6 of `Open`) discards stale bytes that arrived before the query, preventing them from polluting the response accumulation buffer (FUNC-OSC-011).
- `Contains_DA1_Response` and `DA1_Response_Start` are SPARK Silver functions called from the non-SPARK accumulation loop. The SPARK-provable parsing logic is isolated in `Termicap.OSC.Parsing` while the loop and I/O remain in `SPARK_Mode => Off` (FUNC-OSC-015).
- On timeout with `Retry => True`, the query and sentinel are resent and the timeout is doubled. This handles slow terminals without requiring the caller to implement retry logic (FUNC-OSC-013).

---

## Scenario 19: Background / Foreground Color Detection — Two-Level Cascade

End-to-end scenario for `Detect_Background_Color` (or `Detect_Foreground_Color`). Two phases: OSC query attempt, then COLORFGBG environment variable fallback.

### Phase A — OSC Query Path (Primary)

```
Caller
  │
  │  Result := Detect_Background_Color (Timeout_Ms => 1_000)
  ▼
Termicap.Color.Detection.Detect_Background_Color   [SPARK_Mode => Off]
  │
  │  Timeout_Ms := Natural'Min (1_000, 30_000)   -- clamp to 30 s cap
  │
  │  Step 0: Timeout_Ms = 0?
  │    Yes → skip OSC query; go to Phase B
  │    No  → continue
  │
  ▼
Termicap.Color.BG_Query.IO.Query_Color (Background, 1_000, ...)
  │                                         [SPARK_Mode => Off]
  │
  │  Capture_Current (Env)                  [SPARK_Mode => Off]
  │  Detect_Terminal_Identity (Env)         [spec: SPARK, body: Off]
  │    └──► Is_Multiplexer?
  │           Yes → Wrap_For_Passthrough    [SPARK Silver]
  │                  (tmux DCS wrapping or screen DCS wrapping)
  │
  │  declare Session : Probe_Session;       [SPARK_Mode => Off]
  │  Open (Session, Status)
  │    Status ≠ Session_OK?
  │      Session_Not_Foreground → Timed_Out := True; return
  │      Session_No_Terminal    → Timed_Out := True; return
  │      Session_Raw_Failed     → Timed_Out := True; return
  │    Status = Session_OK → continue
  │
  │  Sentinel_Query (Session, Query, Response, Resp_Length,
  │                  Timeout_Ms => 1_000, Timed_Out, Retry => True)
  │    │
  │    │  Write OSC_BG_QUERY (possibly DCS-wrapped) + DA1 sentinel
  │    │  Accumulate response bytes until DA1 detected or timeout
  │    └──► Response(1..Resp_Length) = pre-sentinel bytes; Timed_Out flag set
  │
  │  end;  -- Finalize: termios restored, /dev/tty closed
  │
  └──► Response bytes and Timed_Out returned to Detection body

  │  Timed_Out = True → go to Phase B (COLORFGBG fallback)
  │  Timed_Out = False →
  │
  ▼
Termicap.Color.BG_Query.Strip_OSC_Header   [SPARK Silver]
  │  Verifies ESC ] 1 1 ; prefix; locates payload region
  │  Success = False → go to Phase B
  │
Termicap.Color.BG_Query.Parse_RGB_Response [SPARK Silver]
  │  Find_RGB_Prefix → Split_RGB_Channels → Parse_Hex_Channel (×3)
  │  Normalises 4-digit hex to 8-bit (high-byte extraction)
  │  Success = False → go to Phase B
  │
  └──► Detection_Result'(Success => True, Color => (R, G, B))
```

### Phase B — COLORFGBG Fallback

Executed when the OSC query times out, the session fails to open, or the response cannot be parsed.

```
Termicap.Color.Detection (continuation)   [SPARK_Mode => Off]
  │
  │  Capture_Current (Env)                [SPARK_Mode => Off]
  │    └──► (or reuse captured snapshot if already available)
  │
  │  Contains (Env, "COLORFGBG")?
  │    No → return Detection_Result'(Success => False, Error => No_Fallback)
  │    Yes →
  │
  ▼
Termicap.Color.BG_Query.Parse_Colorfgbg (Value (Env, "COLORFGBG"))
  │                                          [SPARK Silver]
  │  Parses "fg;bg" or "fg;extra;bg" form
  │  Both indices must be decimal 0..15
  │  Success = False → return (Success => False, Error => No_Fallback)
  │
Termicap.Color.BG_Query.Ansi_To_RGB (Background_Index)
  │                                          [SPARK Silver, Global => null]
  │  Direct lookup in ANSI_COLOR_TABLE (16-entry constant array)
  │
  └──► Detection_Result'(Success => True, Color => ANSI_COLOR_TABLE (Index))
```

**Key properties:**

- The OSC query is guarded by a foreground-process check inside `Open`. Background processes receive `Timed_Out = True` without sending any query to the terminal (FUNC-BGC-006).
- Multiplexer passthrough wrapping (`Wrap_For_Passthrough`, SPARK Silver) is applied before `Sentinel_Query` when the terminal identity is `Tmux` or `Screen`. No new C wrappers are introduced — the existing `Termicap.OSC` infrastructure handles the wrapped query transparently (FUNC-BGC-006).
- All parsing (hex normalisation, OSC header stripping, COLORFGBG scanning) is confined to `Termicap.Color.BG_Query` (SPARK Silver, `Global => null`). The SPARK prover verifies that channel values are always in `0 .. 255` and that `Colorfgbg_Result` indices are always in `0 .. 15` (FUNC-BGC-007 through FUNC-BGC-012).
- `COLORFGBG` is parsed only after the OSC query path has been exhausted, preserving OSC accuracy for terminals that support it (FUNC-BGC-013, FUNC-BGC-014).
- When `Timeout_Ms = 0`, the caller explicitly opts out of active probing and the function becomes a pure environment-variable query — useful in contexts where terminal I/O must not occur (FUNC-BGC-015).
- Neither `Detect_Background_Color` nor `Detect_Foreground_Color` raises exceptions. All failure modes are represented by `Detection_Result'(Success => False, Error => <Detect_Error>)`.

---

## Scenario 20: Dark / Light Theme Classification and Detection

Two execution paths are defined for the DARK-LIGHT feature: a pure classification path (no I/O, SPARK Gold) and a combined detection path (I/O via the existing BG-COLOR cascade).

### Path A — Pure Classification (SPARK Gold, no I/O)

Used when the caller already holds an `RGB` value (e.g., from a prior call to `Detect_Background_Color` or from a test fixture).

```
Caller (application)
  │
  │  Classify_Theme (Color : RGB)          -- or Is_Dark / Is_Light
  ▼
Termicap.Color.Dark_Light                   [SPARK Gold]
  │
  │  Luminance (Color)
  │    Y := (299 * Color.Red
  │           + 587 * Color.Green
  │           + 114 * Color.Blue) / 1_000
  │
  │    Post: Y in 0 .. 255
  │    GNATprove: range of each term computed from field constraints;
  │               sum 0..255_000 fits Natural; no overflow possible
  │
  │  if Y < LUMINANCE_THRESHOLD (128) then
  │     return Dark
  │  else
  │     return Light
  │
  └──► Theme_Kind (Dark | Light)
```

**Key properties:**

- No OS interaction, no global state, no exceptions. `Global => null` (implicit, as no `Abstract_State` is referenced).
- Expression functions: `Luminance`, `Classify_Theme`, `Is_Dark`, and `Is_Light` are all declared as expression functions in the spec; GNATprove inlines their definitions at every call site.
- SPARK Gold: all proof obligations (overflow, range postcondition, path exhaustiveness) discharged automatically without manual lemmas.
- Boundary case: `RGB(128, 128, 128)` → `Y = 128 >= 128` → `Light`. This matches the CSS and termenv convention (boundary classified as Light, FUNC-DKL-003).

### Path B — Combined Detection (SPARK_Mode => Off)

Used when the caller needs to determine the terminal theme without having previously queried the background color. Internally invokes the full BG-COLOR cascade (Scenario 19) and then applies Path A classification.

```
Caller (application)
  │
  │  Detect_Theme (Timeout_Ms : Natural := 1_000)
  ▼
Termicap.Color.Dark_Light.Detect            [SPARK_Mode => Off]
  │
  │  Effective_Timeout := Natural'Min (Timeout_Ms, MAX_TIMEOUT_MS)
  │                                           -- MAX_TIMEOUT_MS = 30_000
  │
  │  Detect_Background_Color (Effective_Timeout)
  │    └──► (see Scenario 19 for the full OSC 11 → COLORFGBG cascade)
  │
  │  Detection result?
  │
  │  Case Success => True:
  │    Color : RGB := Result.Color
  │    │
  │    │  Classify_Theme (Color)          [SPARK Gold — Path A above]
  │    │    └──► Theme : Theme_Kind (Dark | Light)
  │    │
  │    └──► Theme_Result'(Success => True, Theme => Theme, Color => Color)
  │
  │  Case Success => False:
  │    Error : Detect_Error := Result.Error
  │    └──► Theme_Result'(Success => False, Error => Error)
  │
  └──► Theme_Result (discriminated record)
```

**Key properties:**

- `Detect_Theme` is exception-free on all paths: `Detect_Background_Color` is documented as exception-free and discriminated record construction is statically safe.
- The SPARK Off boundary is confined to `Termicap.Color.Dark_Light.Detect`. All algorithmic correctness (overflow safety in `Luminance`, range validity of `RGB` components, exhaustiveness of the classification) is proved in the Gold-level parent package.
- Including both `Theme` and `Color` in the success branch gives callers maximum flexibility: they can branch on `Dark`/`Light` using `Theme` and also log or cache the raw detected color using `Color`, without a second detection round trip.
- Failure modes are identical to `Detect_Background_Color`: `Not_A_Terminal`, `Not_Foreground`, `Query_Timeout`, `Parse_Failed`, `No_Fallback`. The `Detect_Error` type is reused directly.

---

## Scenario 21: Active Terminal Identification via XTVERSION

End-to-end scenario for `Query_And_Identify`. Shows the multiplexer-detection → passthrough-wrap decision, the probe session lifecycle, sentinel-bounded accumulation, and the SPARK Silver parse pipeline.

### Phase A — Multiplexer Check and Query Preparation

```
Caller (application)
  │
  │  Query_And_Identify (Timeout_Ms => 100)
  ▼
Termicap.XTVERSION.IO.Query_And_Identify   [SPARK_Mode => Off]
  │
  │  Query_XTVERSION (Timeout_Ms => 100, Response, Resp_Length, Timed_Out)
  ▼
Termicap.XTVERSION.IO.Query_XTVERSION      [SPARK_Mode => Off]
  │
  │  Step 1: Capture_Current (Env)          [SPARK_Mode => Off]
  │    → OS environment variables captured into immutable snapshot
  │
  │  Step 2: Detect_Terminal_Identity (Env) → Identity
  │    [Termicap.Terminal_Id — SPARK_Mode => Off body]
  │    → 8-step cascade over TERM_PROGRAM, VTE_VERSION, etc.
  │
  │  Step 3: Multiplexer passthrough selection
  │    if Identity.Is_Multiplexer then
  │      case Identity.Kind is
  │        when Tmux   → Mode := Tmux_Passthrough
  │        when Screen → Mode := Screen_Passthrough
  │        when others → Mode := Tmux_Passthrough   -- safe default
  │      end case;
  │      Effective_Query :=
  │        Wrap_For_Passthrough (CSI_XTVERSION_QUERY, Mode)
  │        [Termicap.OSC.Parsing — SPARK Silver]
  │    else
  │      Effective_Query := CSI_XTVERSION_QUERY   -- ESC [ > q
  │    end if
  │
  └──► Effective_Query ready; Env and Identity discarded
```

### Phase B — Probe Session and Sentinel Query

```
  │
  │  Open (Session, Status)               [Termicap.OSC — SPARK_Mode => Off]
  ▼
  │  Step 4: Probe_Session.Open
  │    → Foreground check (Is_Foreground_Process)  [FUNC-XTV-010]
  │    → /dev/tty open                             [FUNC-XTV-011]
  │    → Save termios, set raw mode, drain input
  │
  │  if Status /= Session_OK then
  │    → Timed_Out := True; Resp_Length := 0; return  -- no exception
  │  end if
  │
  │  Sentinel_Query                        [Termicap.OSC — SPARK_Mode => Off]
  │  (Session, Effective_Query, Response, Resp_Length,
  │   Timeout_Ms => 100, Timed_Out, Retry => False)   [FUNC-XTV-009]
  │
  │  ┌──────────────────────────────────────────────────────────────┐
  │  │  Write Effective_Query bytes to /dev/tty                    │
  │  │  Write DA1 sentinel (ESC [ c = 0x1B 0x5B 0x63)             │
  │  │                                                              │
  │  │  Accumulation loop (Timeout_Ms = 100 ms):                   │
  │  │    Timed_Read (/dev/tty) → append to Response buffer        │
  │  │    Contains_DA1_Response (Response, Length)  [SPARK Silver] │
  │  │      → scan for ESC [ ? <digits/semicolons> c pattern       │
  │  │      → if found: record pre-sentinel length; exit loop      │
  │  │    if timeout or overflow: Timed_Out := True; exit loop     │
  │  └──────────────────────────────────────────────────────────────┘
  │
  │  Probe_Session.Finalize (unconditional RAII)
  │    → Restore_Termios, close /dev/tty, release single-session guard
  │
  └──► Response(1..Resp_Length) contains pre-DA1 bytes
       Timed_Out reflects whether DA1 was received
```

### Phase C — Parse Pipeline (SPARK Silver)

```
  │
  │  Back in Query_And_Identify:
  │
  │  if Timed_Out then
  │    return XTVERSION_Result'(Status => Timeout)
  │  end if
  │
  │  Parse_XTVERSION_Response (Response, Resp_Length)
  │    [Termicap.XTVERSION — SPARK Silver]
  ▼
  │
  │  Step 5: Contains_XTVERSION_Response (Response, Resp_Length)
  │    → check prefix ESC P > | (0x1B 0x50 0x3E 0x7C)
  │    → check ST (ESC \) or BEL terminator
  │    → minimum 6 bytes (4-byte prefix + 1 payload byte + terminator)
  │    → if False: return (Status => Parse_Error)
  │
  │  Step 6: Extract_XTV_Payload (Response, Resp_Length) → Slice
  │    → Slice.Offset := index of first byte after ESC P > | prefix
  │    → Slice.Length := bytes before ST/BEL terminator
  │    → Post: Slice.Length > 0; Slice.Offset in valid range
  │
  │  Step 7: Split_XTV_Payload (Response, Slice.Offset, Slice.Length)
  │    → Pair.Name, Pair.Version
  │    Format B (parenthesised, xterm/mlterm/foot):
  │      "xterm(388)" → Name = "xterm", Version = "388"
  │      '(' found → split at '(', strip trailing ')'
  │    Format A (space-separated, tmux/WezTerm/kitty):
  │      "WezTerm 20240203" → Name = "WezTerm", Version = "20240203"
  │      ' ' found → split at first space
  │    Name-only (no delimiter):
  │      "SomeTerminal" → Name = "SomeTerminal", Version = ""
  │    All tokens trimmed of leading/trailing ASCII space (0x20)
  │
  │  Step 8: if Length (Pair.Name) > 0 then
  │    return (Status          => Success,
  │            Terminal_Name    => Pair.Name,
  │            Terminal_Version => Pair.Version)
  │    Post: Terminal_Name'Length > 0   -- machine-verified by GNATprove
  │  else
  │    return (Status => Parse_Error)
  │  end if
  │
  └──► XTVERSION_Result (Success | Timeout | Parse_Error)
```

**Key properties:**

- `Query_XTVERSION` uses `Retry => False` (no automatic retry, FUNC-XTV-009). The 100 ms default timeout balances latency against multiplexed terminal roundtrip time; callers requiring lower latency may pass a smaller value.
- `Probe_Session.Finalize` is called unconditionally by the Ada runtime. Terminal state is always restored regardless of whether the query succeeded, timed out, or the session failed to open.
- `Contains_XTVERSION_Response`, `Extract_XTV_Payload`, `Split_XTV_Payload`, and `Parse_XTVERSION_Response` are all SPARK Silver functions with `Global => null`. They have no side effects and carry machine-verified preconditions/postconditions. The SPARK-provable parsing logic is isolated in `Termicap.XTVERSION` while the session management and I/O remain in `SPARK_Mode => Off` in `Termicap.XTVERSION.IO`.
- The multiplexer passthrough step (Phase A, Step 3) reuses `Termicap.OSC.Parsing.Wrap_For_Passthrough` — the same pure SPARK Silver function used by `Termicap.Color.BG_Query.IO`. No new C wrappers or POSIX calls are introduced by the XTVERSION feature.
- `Parse_XTVERSION_Response` handles all malformed-input cases (zero-length buffer, missing DCS prefix, no ST/BEL terminator, empty name token) by returning `Status => Parse_Error` without raising an exception (FUNC-XTV-016).

---

## Scenario 22: DA1 Primary Device Attributes Query

End-to-end scenario for `Detect_DA1`. Shows the timeout-only read loop pattern (no sentinel), the probe session lifecycle, and the SPARK Silver interpretation pipeline. Contrast with Scenario 21 (XTVERSION), which uses `Sentinel_Query`; here `Timeout_Query` is used because the DA1 response is itself the sought data.

### Phase A — Multiplexer Check and Query Preparation

```
Caller (application or Termicap.Capabilities.Detect)
  │
  │  Detect_DA1 (Timeout_Ms => 100)
  ▼
Termicap.DA1.IO.Detect_DA1                         [SPARK_Mode => Off]
  │
  │  Query_DA1 (Timeout_Ms => 100, Response, Resp_Length, Timed_Out)
  ▼
Termicap.DA1.IO.Query_DA1                          [SPARK_Mode => Off]
  │
  │  Step 1: Capture_Current (Env)                 [SPARK_Mode => Off]
  │    → OS environment variables captured into immutable snapshot
  │
  │  Step 2: Detect_Terminal_Identity (Env) → Identity
  │    [Termicap.Terminal_Id — SPARK_Mode => Off body]
  │    → 8-step cascade over TERM_PROGRAM, VTE_VERSION, etc.
  │
  │  Step 3: Multiplexer passthrough selection
  │    if Identity.Is_Multiplexer then
  │      case Identity.Kind is
  │        when Tmux   → Mode := Tmux_Passthrough
  │        when Screen → Mode := Screen_Passthrough
  │        when others → Mode := Tmux_Passthrough   -- safe default
  │      end case;
  │      Effective_Query :=
  │        Wrap_For_Passthrough (DA1_QUERY, Mode)
  │        [Termicap.OSC.Parsing — SPARK Silver]
  │    else
  │      Effective_Query := DA1_QUERY              -- ESC [ c
  │    end if
  │
  └──► Effective_Query ready; Env and Identity discarded
```

### Phase B — Probe Session and Timeout-Only Read Loop

```
  │
  │  Open (Session, Status)                        [Termicap.OSC — SPARK_Mode => Off]
  ▼
  │  Step 4: Probe_Session.Open
  │    → Foreground check (Is_Foreground_Process)  [FUNC-DA1-010]
  │    → /dev/tty open                             [FUNC-DA1-011]
  │    → Save termios, set raw mode, drain input
  │
  │  if Status /= Session_OK then
  │    → Timed_Out := True; Resp_Length := 0; return  -- no exception
  │  end if
  │
  │  Timeout_Query                                 [Termicap.OSC — SPARK_Mode => Off]
  │  (Session, Effective_Query, Response, Resp_Length, Timeout_Ms, Timed_Out)
  │
  │  ┌──────────────────────────────────────────────────────────────┐
  │  │  Write Effective_Query bytes to /dev/tty                    │
  │  │  NOTE: no DA1 sentinel appended (ADR-0017)                  │
  │  │  Reason: DA1 response IS the data; a second CSI c would     │
  │  │  produce two overlapping DA1 responses, making boundary     │
  │  │  detection ambiguous.                                        │
  │  │                                                              │
  │  │  Accumulation loop (Timeout_Ms = 100 ms):                   │
  │  │    Timed_Read (/dev/tty) → append to Response buffer        │
  │  │    Contains_DA1_Response (Response, Length)  [SPARK Silver] │
  │  │      → scan for ESC [ ? <digits/semicolons> c pattern       │
  │  │      → if found: record accumulated length; exit loop       │
  │  │    if timeout or overflow: Timed_Out := True; exit loop     │
  │  └──────────────────────────────────────────────────────────────┘
  │
  │  Probe_Session.Finalize (unconditional RAII)
  │    → Restore_Termios, close /dev/tty, release single-session guard
  │
  └──► Response(1..Resp_Length) contains the full DA1 response bytes
       Timed_Out reflects whether a complete DA1 response was received
```

### Phase C — Parse and Interpret Pipeline (SPARK Silver)

```
  │
  │  Back in Detect_DA1:
  │
  │  if Timed_Out then
  │    return DA1_Capabilities'(Supported => False,
  │                             Level     => Unknown,
  │                             Flags     => [others => False])
  │  end if
  │
  │  Parse_DA1_Response (Response, Resp_Length) → Params
  │    [Termicap.OSC.Parsing — SPARK Silver]
  ▼
  │
  │  Step 5: Locate DA1_Response_Start in buffer
  │    → scan for ESC [ ? prefix (0x1B 0x5B 0x3F)
  │    → locate terminating c (0x63) byte
  │    → Post: start index within buffer bounds
  │
  │  Step 6: Extract semicolon-separated decimal parameters
  │    → Params.Values(1) = first Ps  (VT conformance level)
  │    → Params.Values(2..N) = remaining Ps (capability flags)
  │    → Params.Count = N; bounded by MAX_DA1_PARAMS = 16
  │    → Post: Count <= MAX_DA1_PARAMS
  │
  │  Interpret_DA1 (Params) → Caps
  │    [Termicap.DA1 — SPARK Silver]
  │
  │  Step 7: VT conformance level decode
  │    → Params.Values(1) = 62 → VT200
  │    → Params.Values(1) = 63 → VT300
  │    → Params.Values(1) = 64 → VT400
  │    → Params.Values(1) = 65 → VT500
  │    → others              → Unknown
  │
  │  Step 8: Capability flags scan (Params.Values(2..Count))
  │    →  4 → Flags(Sixel_Graphics)     := True
  │    → 22 → Flags(ANSI_Color)         := True
  │    → 28 → Flags(Rectangular_Editing) := True
  │    → (other recognised values mapped similarly)
  │    → unrecognised values silently ignored
  │
  │  Post (machine-verified):
  │    Count = 0  → Supported = False ∧ Level = Unknown
  │    Count > 0  → Supported = True
  │
  └──► DA1_Capabilities (Supported, Level, Flags)
```

**Key properties:**

- `Query_DA1` uses `Timeout_Query` (not `Sentinel_Query`) because the DA1 response is the primary data, not a boundary marker. Appending a second `CSI c` sentinel would interleave two DA1 responses in the buffer, making `Contains_DA1_Response` ambiguous about which `c` terminates which response (ADR-0017).
- `Probe_Session.Finalize` is called unconditionally. Terminal state is always restored regardless of whether the query succeeded, timed out, or the session failed to open.
- `Parse_DA1_Response` and `Interpret_DA1` are both SPARK Silver functions with `Global => null`. They have no side effects and carry machine-verified preconditions/postconditions. The SPARK-provable logic is isolated in `Termicap.OSC.Parsing` and `Termicap.DA1` while the session management and I/O remain in `SPARK_Mode => Off` in `Termicap.DA1.IO`.
- The multiplexer passthrough step (Phase A, Step 3) reuses `Termicap.OSC.Parsing.Wrap_For_Passthrough` — the same pure SPARK Silver function used by `Termicap.Color.BG_Query.IO` and `Termicap.XTVERSION.IO`. No new C wrappers or POSIX calls are introduced by the DA1 feature.
- `Termicap.Capabilities.Detect` calls `Detect_DA1` as part of its sub-detector sequence and places the result in the `DA1` field of the `Terminal_Capabilities` record. The default timeout of 100 ms matches `Query_And_Identify` (XTVERSION).

---

## Scenario 23: DECRPM DEC Private Mode Query

End-to-end scenario for `Detect_Mode`. Shows the sentinel-bounded read loop pattern, the probe session lifecycle, and the SPARK Silver parsing pipeline. Contrast with Scenario 22 (DA1), which uses `Timeout_Query`; here `Sentinel_Query` is used because DECRPM responses (`CSI ? Ps ; Pm $ y`) are structurally distinct from the DA1 sentinel (`ESC [ c`), so the sentinel pattern safely bounds the accumulation loop.

### Phase A — Multiplexer Check and Query Preparation

```
Caller (application)
  │
  │  Detect_Mode (Mode => MODE_BRACKETED_PASTE, Timeout_Ms => 100)
  ▼
Termicap.DECRPM.IO.Detect_Mode                     [SPARK_Mode => Off]
  │
  │  Query_Mode (Mode, Timeout_Ms, Response, Resp_Length, Timed_Out)
  ▼
Termicap.DECRPM.IO.Query_Mode                      [SPARK_Mode => Off]
  │
  │  Step 1: Capture_Current (Env)                 [SPARK_Mode => Off]
  │    → OS environment variables captured into immutable snapshot
  │
  │  Step 2: Detect_Terminal_Identity (Env) → Identity
  │    [Termicap.Terminal_Id — SPARK_Mode => Off body]
  │    → 8-step cascade over TERM_PROGRAM, VTE_VERSION, etc.
  │
  │  Step 3: Multiplexer passthrough selection
  │    if Identity.Is_Multiplexer then
  │      case Identity.Kind is
  │        when Tmux   → Mode := Tmux_Passthrough
  │        when Screen → Mode := Screen_Passthrough
  │        when others → Mode := Tmux_Passthrough   -- safe default
  │      end case;
  │      Effective_Query :=
  │        Wrap_For_Passthrough (DECRPM_Query (Mode), Passthrough_Mode)
  │        [Termicap.OSC.Parsing — SPARK Silver]
  │    else
  │      Effective_Query := DECRPM_Query (Mode)
  │        [Termicap.DECRPM — SPARK Silver]
  │        -- e.g. Mode = 2004: ESC [ ? 2 0 0 4 $ p (8 bytes)
  │    end if
  │
  └──► Effective_Query ready; Env and Identity discarded
```

### Phase B — Probe Session and Sentinel-Bounded Read Loop

```
  │
  │  Open (Session, Status)                        [Termicap.OSC — SPARK_Mode => Off]
  ▼
  │  Step 4: Probe_Session.Open
  │    → Foreground check (Is_Foreground_Process)
  │    → /dev/tty open
  │    → Save termios, set raw mode, drain input
  │
  │  if Status /= Session_OK then
  │    → Timed_Out := True; Resp_Length := 0; return  -- no exception
  │  end if
  │
  │  Sentinel_Query                                [Termicap.OSC — SPARK_Mode => Off]
  │  (Session, Effective_Query, Response, Resp_Length, Timeout_Ms,
  │   Timed_Out, Retry => False)
  │
  │  ┌──────────────────────────────────────────────────────────────┐
  │  │  Write Effective_Query bytes to /dev/tty                    │
  │  │  Write DA1 sentinel (ESC [ c) to /dev/tty                   │
  │  │  NOTE: unlike DA1, DECRPM uses Sentinel_Query.              │
  │  │  Reason: DECRPM response (CSI ? Ps ; Pm $ y) is distinct    │
  │  │  from the DA1 sentinel (ESC [ c), so the sentinel safely    │
  │  │  marks the end of the DECRPM response in the buffer.        │
  │  │                                                              │
  │  │  Accumulation loop (Timeout_Ms = 100 ms):                   │
  │  │    Timed_Read (/dev/tty) → append to Response buffer        │
  │  │    Contains_DA1_Response (Response, Length)  [SPARK Silver] │
  │  │      → scan for ESC [ ? <digits/semicolons> c pattern       │
  │  │      → if found: record pre-sentinel length; exit loop      │
  │  │    if timeout or overflow: Timed_Out := True; exit loop     │
  │  └──────────────────────────────────────────────────────────────┘
  │
  │  Probe_Session.Finalize (unconditional RAII)
  │    → Restore_Termios, close /dev/tty, release single-session guard
  │
  └──► Response(1..Resp_Length) contains the pre-sentinel bytes
       (the DECRPM response, if received before the DA1 sentinel)
       Timed_Out reflects whether the DA1 sentinel was detected
```

### Phase C — Parse Pipeline (SPARK Silver)

```
  │
  │  Back in Detect_Mode:
  │
  │  if Timed_Out then
  │    return Mode_Query_Result'(Success => False, Error => Query_Timeout)
  │  end if
  │
  │  Parse_DECRPM_Response (Response, Resp_Length) → Report
  │    [Termicap.DECRPM — SPARK Silver]
  ▼
  │
  │  Step 5: Contains_DECRPM_Response (Response, Resp_Length)
  │    → check prefix ESC [ ? (0x1B 0x5B 0x3F)
  │    → check at least one decimal digit after ?
  │    → check semicolon (0x3B) separator
  │    → check at least one decimal digit after ;
  │    → check suffix $ y (0x24 0x79)
  │    → minimum 7 bytes (ESC [ ? d ; d $ y)
  │    → if False: return Mode_Report'(Mode => 0, Status => Not_Recognized)
  │
  │  Step 6: Extract decimal Ps (mode number) from position 4
  │    → accumulate ASCII digits (0x30..0x39) until semicolon
  │    → Ps = 2004  (for bracketed paste mode query)
  │
  │  Step 7: Extract decimal Pm (status code) after semicolon
  │    → accumulate ASCII digits until $
  │    → Map Pm to Mode_Status:
  │        0 → Not_Recognized   (mode not implemented)
  │        1 → Set              (mode currently enabled)
  │        2 → Reset            (mode currently disabled)
  │        3 → Permanently_Set  (mode always enabled)
  │        4 → Permanently_Reset (mode always disabled)
  │        others → Not_Recognized
  │
  │  Post (machine-verified):
  │    Contains_DECRPM_Response = True → Report.Mode > 0
  │
  │  if Report.Mode = 0 then   -- parse failure
  │    return Mode_Query_Result'(Success => False, Error => Parse_Failed)
  │  end if
  │
  └──► Mode_Query_Result'(Success => True,
                           Report  => (Mode => 2004, Status => Set))
         -- bracketed paste is currently enabled
```

**Key properties:**

- `Query_Mode` uses `Sentinel_Query` with `Retry => False`. DECRPM responses (`CSI ? Ps ; Pm $ y`) are structurally distinct from the DA1 sentinel (`ESC [ c`), making the sentinel-based boundary detection unambiguous.
- `Probe_Session.Finalize` is called unconditionally. Terminal state is always restored regardless of whether the query succeeded, timed out, or the session failed to open.
- `Contains_DECRPM_Response` and `Parse_DECRPM_Response` are both SPARK Silver functions with `Global => null`. They carry machine-verified preconditions and postconditions. The SPARK-provable parsing logic is isolated in `Termicap.DECRPM` while the session management and I/O remain in `SPARK_Mode => Off` in `Termicap.DECRPM.IO`.
- The multiplexer passthrough step (Phase A, Step 3) reuses `Termicap.OSC.Parsing.Wrap_For_Passthrough` — the same pure SPARK Silver function used by `Termicap.Color.BG_Query.IO`, `Termicap.XTVERSION.IO`, and `Termicap.DA1.IO`. No new C wrappers or POSIX calls are introduced by the DECRPM feature.
- For batch queries, `Detect_Modes` opens a single `Probe_Session` and calls `Sentinel_Query` once per mode in `Modes(1..Count)`. Per-mode timeout is `max(50, Timeout_Ms / Count)`. Modes that time out individually receive `Status => Not_Recognized` without failing the entire batch.

---

## Scenario 24: Windows Color Detection Flow

Executed on Windows when `Termicap.Capabilities.Detect` is called. Replaces the POSIX color/TTY/dimensions flows on that platform.

```
Caller (application / detection init)
  │
  │  Detect (Stream => Stdout)
  ▼
Termicap.Capabilities             [Windows body — SPARK_Mode => Off]
  │
  │  Step 1: Capture_Current (Env)          -- standard env snapshot
  │  Step 2: Is_TTY (Stdout)                -- via GetConsoleMode (Win32 body)
  │    → Get_Override                        -- override short-circuit
  │    → GetConsoleMode (Stdout handle)      -- if Auto
  │    → Win32_VT.Enable_VT_Processing (H)  -- side-effect: enable VT escapes
  │  Step 3: Get_Size                        -- via GetConsoleScreenBufferInfo
  │
  │  Step 4: Win32_Color.Detect_Windows_Color_Level (Env)
  │    [Termicap.Win32_Color — SPARK_Mode => Off for this wrapper]
  │    │
  │    │  WT_SESSION check (FUNC-WIN-007):
  │    │    Contains (Env, "WT_SESSION") and Value ≠ ""?
  │    │      Yes → return True_Color immediately
  │    │      No  → continue
  │    │
  │    │  Win32_Ntdll.Get_Build_Number        [SPARK_Mode => Off]
  │    │    → LoadLibraryA ("ntdll.dll")
  │    │    → GetProcAddress (..., "RtlGetNtVersionNumbers")
  │    │    → Call function pointer → (Major, Minor, Build_Raw)
  │    │    → FreeLibrary
  │    │    → return Build_Raw and 16#FFFF# (low 16 bits)
  │    │      (returns 0 on any failure)
  │    │
  │    │  Build_To_Color_Level (Build, Has_WT_Session => False)
  │    │    [Termicap.Win32_Color — SPARK Silver, Global => null]
  │    │    Build < 10_586  → None
  │    │    Build < 14_931  → Extended_256
  │    │    Build >= 14_931 → True_Color
  │    │
  │    └──► Win32_Level : Color_Level
  │
  │  Step 5: Env-var cascade
  │    Detect_Color_Level (Env, Is_TTY)      -- standard 11-step cascade
  │    (FORCE_COLOR / NO_COLOR / COLORTERM / TERM / …)
  │    └──► Env_Level : Color_Level
  │
  │  Step 6: Final color = Color_Level'Max (Win32_Level, Env_Level)
  │    FORCE_COLOR / NO_COLOR can still override via Env_Level
  │
  └──► Terminal_Capabilities assembled via Assemble (SPARK Silver)
```

**Key properties:**

- `WT_SESSION` is the fast path: if Windows Terminal is detected, the result is `True_Color` without any kernel API call.
- `Get_Build_Number` loads and unloads `ntdll.dll` dynamically — no link-time dependency. Returns `0` on any failure, which maps to `None` (safe default).
- `Build_To_Color_Level` is SPARK Silver (`Global => null`). Its postcondition machine-verifies that `Basic_16` is never returned (FUNC-WIN-013).
- `Color_Level'Max` ensures that env-var override steps (FORCE_COLOR, CLICOLOR_FORCE, NO_COLOR) still take priority over the Win32 hardware detection when they produce a higher (or lower, in the case of `None`) result.
- TTY detection uses `GetConsoleMode` instead of POSIX `isatty()`. As a side effect, `Enable_VT_Processing` is called on the first valid console handle to ensure ANSI escape sequences work in the Windows Console Host.
- Dimensions use `GetConsoleScreenBufferInfo`'s `srWindow` field (the visible viewport), not `dwSize` (the scroll-back buffer). This matches what the user sees in the terminal window.

---

## Scenario 25: Cygwin/MSYS2 TTY Detection Flow

Executed on Windows when `Is_TTY_Via_Handle` is called for a handle where `GetConsoleMode` fails (i.e., the handle is not a native Windows console object). This is the second-chance check introduced by FUNC-CYG-015.

```
Termicap.TTY (Windows body)      [SPARK_Mode => Off]
  │
  │  Is_TTY_Via_Handle (Handle)
  │
  │  Step 1: GetConsoleMode (Handle, Mode)
  │    → Succeeds?
  │      Yes → Enable_VT_Processing (Handle)   -- side-effect: enable VT escapes
  │             return True                     -- native Windows console: done
  │      No  → continue to Step 2
  │
  │  Step 2: Is_Cygwin_Terminal (Handle)
  │    [Termicap.Win32_Cygwin — SPARK_Mode => Off]
  │    │
  │    │  GetFileType (Handle)
  │    │    ≠ FILE_TYPE_PIPE?  → return False immediately
  │    │    = FILE_TYPE_PIPE   → continue
  │    │
  │    │  GetFileInformationByHandleEx        [primary path]
  │    │    (Handle, FileNameInfo, Buffer)
  │    │    Succeeds → Wide_String pipe name in Buffer
  │    │    Fails    → fall through to NtQueryObject path
  │    │
  │    │  Query_Object_Name (Handle)          [fallback path]
  │    │    [Termicap.Win32_Ntdll — dynamically loaded ntdll.dll]
  │    │    → NtQueryObject (Handle, ObjectNameInformation, …)
  │    │    → Returns Wide_String pipe name, or "" on failure
  │    │
  │    │  UTF-16 decode → ASCII pipe name string
  │    │    (non-ASCII characters → return False immediately)
  │    │
  │    │  Is_Cygwin_Pipe_Name (Name)
  │    │    [Termicap.Win32_Cygwin — SPARK Silver, Global => null]
  │    │    │
  │    │    │  Token[0] prefix: "\msys-" or "\cygwin-" (FUNC-CYG-007)
  │    │    │  Token[1] non-empty hex PID segment (FUNC-CYG-008)
  │    │    │  Token[2] starts with "pty" (FUNC-CYG-009)
  │    │    │  Token[3] is exactly "from" or "to" (FUNC-CYG-010)
  │    │    │  Token[4] is exactly "master" (FUNC-CYG-011)
  │    │    │  Minimum 5 '-'-delimited segments (FUNC-CYG-012)
  │    │    │
  │    │    └──► Boolean (True = Cygwin/MSYS2 PTY pipe name)
  │    │
  │    └──► Boolean result
  │
  │  Step 3: Return Is_Cygwin_Terminal result
  │    True  → handle is a Cygwin/MSYS2 PTY — report as TTY
  │    False → handle is neither a console nor a Cygwin PTY — report as non-TTY
  │
  └──► Boolean TTY result returned to caller
```

**Key properties:**

- `GetConsoleMode` remains the primary fast path. The Cygwin check only runs when `GetConsoleMode` fails, so the common case (native Windows console) has zero overhead from this feature.
- `GetFileType = FILE_TYPE_PIPE` is a mandatory guard: if the handle is not a named pipe, `Is_Cygwin_Terminal` returns `False` immediately without attempting any name retrieval.
- `GetFileInformationByHandleEx` is the primary pipe-name API (available since Windows Vista). `NtQueryObject` via `Termicap.Win32_Ntdll.Query_Object_Name` is the fallback for environments where the primary API is unavailable.
- `Is_Cygwin_Pipe_Name` is SPARK Silver (`Global => null`). Its five token-level rules are independently testable and are covered by 14 acceptance test vectors (FUNC-CYG-013).
- `Is_Cygwin_Terminal` never propagates an exception (FUNC-CYG-016). Any OS call failure causes `False` to be returned rather than raising.
- The Cygwin PTY detection is transparent to application code. `Termicap.TTY.Is_TTY` returns the same `Boolean` type on all paths; no Cygwin-specific types are exposed.

---

## Scenario 26: Keyboard Protocol Detection

End-to-end scenario for `Detect_Keyboard_Protocol`. Shows the Win32 fast-path gate, the two-probe Kitty → XTerm cascade, the DA1 sentinel-bounded read loops, the SPARK Silver parse pipeline, and the per-process cache. Worst-case cold-start latency is 2 s (1 s per probe × 2 probes). Cached calls return in < 1 µs.

### Phase A — Cache Check and Platform Gate

```
Caller (application)
  │
  │  Detect_Keyboard_Protocol
  ▼
Termicap.Keyboard.IO.Detect_Keyboard_Protocol      [SPARK_Mode => Off]
  │
  │  Step 1: Cache check (protected object)
  │    Is_Cached = True?
  │      Yes → return Cached_Result immediately  (< 1 µs)
  │      No  → continue
  │
  │  [Windows body only]
  │  Step 2: GetConsoleMode (STD_INPUT_HANDLE)    [Win32 FFI]
  │    Succeeds?
  │      Yes → Cached_Result :=
  │              (Protocol => Win32, Flags => NO_KITTY_FLAGS, Probed => False)
  │             Store in cache; return immediately
  │      No  → handle is Cygwin/MSYS2 PTY; continue to Step 3
  │  [End Windows-only block]
  │
  └──► Proceed to Phase B
```

### Phase B — Guards and Kitty Probe

```
  │
  │  Step 3: Non-TTY and foreground guards
  │    Is_TTY (Stdin) = False?       [Termicap.TTY — SPARK_Mode => Off]
  │      → return NO_KEYBOARD_CAPABILITY (Probed => False); cache and return
  │    Is_Foreground_Process = False? [Termicap.OSC — SPARK_Mode => Off]
  │      → return NO_KEYBOARD_CAPABILITY (Probed => False); cache and return
  │
  │  Step 4: Open Probe_Session      [Termicap.OSC — SPARK_Mode => Off]
  │    → Foreground check (Is_Foreground_Process)
  │    → /dev/tty open
  │    → Save termios, set raw mode, drain input
  │    Fails?
  │      → return NO_KEYBOARD_CAPABILITY; cache and return
  │
  │  Step 5: Kitty Sentinel_Query
  │    [Termicap.OSC.Sentinel_Query — SPARK_Mode => Off]
  │    ┌──────────────────────────────────────────────────────────────┐
  │    │  Write CSI_KITTY_QUERY (ESC [ ? u, 3 bytes) to /dev/tty     │
  │    │  Write DA1 sentinel (ESC [ c) to /dev/tty                   │
  │    │  Accumulation loop (KITTY_PROBE_TIMEOUT_MS = 1_000 ms):     │
  │    │    Timed_Read (/dev/tty) → append to Response buffer        │
  │    │    Contains_DA1_Response (Response, Length)  [SPARK Silver] │
  │    │      → scan for ESC [ ? <digits/semicolons> c pattern       │
  │    │      → if found: record pre-sentinel length; exit loop      │
  │    │    if timeout or overflow: Timed_Out := True; exit loop     │
  │    └──────────────────────────────────────────────────────────────┘
  │
  │  Step 6: Parse_Kitty_Response (Response, Resp_Length)
  │    [Termicap.Keyboard — SPARK Silver, Global => null]
  │    → check for ESC [ ? <digits>* u pattern
  │    → Result.Found = True?
  │      Yes → Capability :=
  │              (Protocol => Kitty,
  │               Flags    => Parse_Kitty_Flags (flags_int),
  │               Probed   => True)
  │            Probe_Session.Finalize (RAII)
  │            Store in cache; return Capability
  │      No  → continue to Phase C (XTerm probe)
  │
  └──► Kitty not detected; continue
```

### Phase C — XTerm Probe

```
  │
  │  Step 7: XTerm Sentinel_Query
  │    [Termicap.OSC.Sentinel_Query — SPARK_Mode => Off]
  │    ┌──────────────────────────────────────────────────────────────┐
  │    │  Write CSI_XTERM_KBD_QUERY (ESC [ ? 4 m, 5 bytes) to       │
  │    │    /dev/tty                                                  │
  │    │  Write DA1 sentinel (ESC [ c) to /dev/tty                   │
  │    │  Accumulation loop (XTERM_KBD_PROBE_TIMEOUT_MS = 1_000 ms): │
  │    │    Timed_Read (/dev/tty) → append to Response buffer        │
  │    │    Contains_DA1_Response (Response, Length)  [SPARK Silver] │
  │    │      → if found: record pre-sentinel length; exit loop      │
  │    │    if timeout or overflow: Timed_Out := True; exit loop     │
  │    └──────────────────────────────────────────────────────────────┘
  │
  │  Step 8: Parse_XTerm_Keyboard_Response (Response, Resp_Length)
  │    [Termicap.Keyboard — SPARK Silver, Global => null]
  │    → check for ESC [ ? 4 ; <digits>+ m pattern
  │    → Returns Boolean
  │    True?
  │      Yes → Capability :=
  │              (Protocol => XTerm_CSI,
  │               Flags    => NO_KITTY_FLAGS,
  │               Probed   => True)
  │      No  → Capability :=
  │              (Protocol => Legacy,
  │               Flags    => NO_KITTY_FLAGS,
  │               Probed   => True)
  │
  │  Probe_Session.Finalize (unconditional RAII)
  │    → Restore_Termios, close /dev/tty, release single-session guard
  │
  │  Store Capability in cache; return Capability
  │
  └──► Keyboard_Capability returned to caller
```

**Key properties:**

- **Worst-case latency:** 2 s cold-start (1 s × 2 probes: Kitty timeout + XTerm timeout). If the terminal responds to the Kitty probe, the XTerm probe is skipped; worst case applies only when both probes time out (legacy terminal).
- **Cached calls:** The protected-object cache is populated on the first call. All subsequent calls return the cached `Keyboard_Capability` without entering the probe cascade or opening a terminal session. Latency < 1 µs.
- **Windows fast path:** `GetConsoleMode (STD_INPUT_HANDLE)` is checked before any probe. A native Windows console succeeds immediately and returns `(Win32, Probed => False)` with zero I/O overhead.
- **Graceful degradation:** On any error — non-TTY stdin, background process, `Probe_Session` open failure, both probes timing out — the function returns `NO_KEYBOARD_CAPABILITY` (`Protocol => Unknown` or `Protocol => Legacy`) without raising an exception (FUNC-KKB-014, FUNC-KKB-016).
- **Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path. Terminal state is always restored regardless of probe outcome (FUNC-KKB-015).
- **SPARK boundary:** `Termicap.Keyboard` (parent spec and body) is fully SPARK Silver — three pure parsers with `Global => null`, no FFI, no global state. `Termicap.Keyboard.IO` is `SPARK_Mode => Off` throughout (session management, terminal I/O, protected cache object).

---

## Scenario 27: Mouse Protocol Detection

End-to-end scenario for `Detect_Mouse_Protocols`. Shows the Win32 fast-path gate (Windows only), the GPM heuristic (POSIX/Linux only), the three remaining guards, the single batched DECRPM probe (six queries + one DA1 sentinel), the SPARK Silver frame scanner, the `Resolve_Best_Encoding` cascade, and the per-process cache. Worst-case cold-start latency is 1 s (the full batch times out). Cached calls return in < 1 µs.

### Phase A — Cache Check and Platform Gates

```
Caller (application)
  │
  │  Detect_Mouse_Protocols
  ▼
Termicap.Mouse.IO.Detect_Mouse_Protocols      [SPARK_Mode => Off]
  │
  │  Step 1: Cache check (protected object)
  │    Is_Cached = True?
  │      Yes → return Cached_Result immediately  (< 1 µs)
  │      No  → continue
  │
  │  [Windows body only]
  │  Step 2: Win32 Console gate
  │    GetConsoleMode (STD_INPUT_HANDLE)
  │      Succeeds?
  │        Yes → Cached_Result :=
  │                (Best_Encoding        => Unknown,
  │                 Win32_Console_Mouse  => True,
  │                 Probed               => False, others => False)
  │              Store in cache; return immediately
  │        No  → handle is Cygwin/MSYS2 PTY; continue to Step 3
  │  [End Windows-only block]
  │
  │  [POSIX body only]
  │  Step 3: Linux/GPM heuristic
  │    Value (Env, "TERM") = "linux"
  │    and Ada.Directories.Exists ("/dev/gpmctl")  [ADR-0024]
  │      Both true?
  │        Yes → Cached_Result :=
  │                (Best_Encoding  => Unknown,
  │                 GPM_Available  => True,
  │                 Probed         => False, others => False)
  │              Store in cache; return immediately
  │        No  → continue to Step 4
  │  [End POSIX-only block]
  │
  └──► Proceed to Phase B
```

### Phase B — Guards and Session Open

```
  │
  │  Step 4: Non-TTY guard
  │    Is_TTY (Stdin) = False?          [Termicap.TTY — SPARK_Mode => Off]
  │      → return NO_MOUSE_CAPABILITIES (Probed => False); cache and return
  │
  │  Step 5: Foreground guard
  │    Is_Foreground_Process = False?   [Termicap.OSC — SPARK_Mode => Off]
  │      → return NO_MOUSE_CAPABILITIES (Probed => False); cache and return
  │
  │  Step 6: Open Probe_Session         [Termicap.OSC — SPARK_Mode => Off]
  │    → /dev/tty open
  │    → Save termios, set raw mode, drain input
  │    Fails?
  │      → return NO_MOUSE_CAPABILITIES; cache and return
  │
  └──► Session open; proceed to Phase C
```

### Phase C — Batched DECRPM Probe

```
  │
  │  Step 7: Write six DECRPM queries + DA1 sentinel in one batch
  │    [Termicap.OSC.Write_Query / Sentinel_Query — SPARK_Mode => Off]
  │    ┌──────────────────────────────────────────────────────────────────┐
  │    │  Write CSI ? 1000 $ p  (MODE_MOUSE_X10)                        │
  │    │  Write CSI ? 1002 $ p  (MODE_MOUSE_BUTTON_EVENT)               │
  │    │  Write CSI ? 1003 $ p  (MODE_MOUSE_ANY_EVENT)                  │
  │    │  Write CSI ? 1015 $ p  (MODE_MOUSE_URXVT)                      │
  │    │  Write CSI ? 1006 $ p  (MODE_MOUSE_SGR)                        │
  │    │  Write CSI ? 1016 $ p  (MODE_MOUSE_SGR_PIXELS)                 │
  │    │  Write DA1 sentinel    (ESC [ c)                                │
  │    └──────────────────────────────────────────────────────────────────┘
  │
  │  Step 8: Sentinel-bounded read loop  (MOUSE_PROBE_TIMEOUT_MS = 1_000 ms)
  │    ┌──────────────────────────────────────────────────────────────────┐
  │    │  Accumulation loop:                                              │
  │    │    Timed_Read (/dev/tty) → append to Response buffer            │
  │    │    Contains_DA1_Response (Response, Length)  [SPARK Silver]     │
  │    │      → scan for ESC [ ? <digits/semicolons> c pattern           │
  │    │      → if found: record pre-sentinel length; exit loop          │
  │    │    if timeout or overflow: Timed_Out := True; exit loop         │
  │    └──────────────────────────────────────────────────────────────────┘
  │
  │    Timed_Out = True and Resp_Length = 0?
  │      → Probe_Session.Finalize (RAII)
  │      → return NO_MOUSE_CAPABILITIES (Probed => False); cache and return
  │
  └──► Pre-sentinel bytes accumulated; proceed to Phase D
```

### Phase D — Frame Scan and Encoding Cascade

```
  │
  │  Step 9: Scan pre-sentinel bytes for DECRPM frames
  │    [Body-private scanner in Termicap.Mouse.IO]
  │    Caps := NO_MOUSE_CAPABILITIES;  Caps.Probed := True;
  │
  │    for Pos in Response'First .. Resp_Length loop
  │      │
  │      │  Parse_Mouse_DECRPM_Response (Response, Length_From_Pos)
  │      │    [Termicap.Mouse — SPARK Silver, Global => null]
  │      │    → match ESC [ ? <Ps_digits>+ ; <Pm_digit> $ y
  │      │    → Result.Valid = True?
  │      │        Yes → decode Mode (Ps) and Status (Pm)
  │      │              Pm in 1..4 (Set / Reset / Permanently_Set /
  │      │                          Permanently_Reset) => Supports_* := True
  │      │              Pm = 0 (Not_Recognized)         => Supports_* := False
  │      │              Map Mode to Supports_* field:
  │      │                1000 → Caps.Supports_X10
  │      │                1002 → Caps.Supports_Button_Event
  │      │                1003 → Caps.Supports_Any_Event
  │      │                1015 → Caps.Supports_URXVT
  │      │                1006 → Caps.Supports_SGR
  │      │                1016 → Caps.Supports_SGR_Pixels
  │      │              Advance Pos past this frame
  │      │        No  → advance Pos by 1 (garbled or partial frame)
  │      └──► continue
  │    end loop;
  │
  │  Step 10: Resolve_Best_Encoding (Caps)
  │    [Termicap.Mouse — SPARK Silver, Global => null]
  │    Encoding cascade (ADR-0023):
  │      Caps.Supports_SGR_Pixels? → SGR_Pixels
  │      Caps.Supports_SGR?        → SGR
  │      Caps.Supports_URXVT?      → URXVT
  │      Caps.Supports_X10?        → X10
  │      else                       → None
  │    Caps.Best_Encoding := cascade result
  │
  │  Step 11: Cleanup and cache
  │    Probe_Session.Finalize (unconditional RAII)
  │      → Restore_Termios, close /dev/tty, release single-session guard
  │    Store Caps in cache; return Caps
  │
  └──► Mouse_Capabilities returned to caller
```

**Key properties:**

- **Worst-case latency:** 1 s cold-start (single batch + DA1 sentinel timeout). Unlike the keyboard cascade (two serial probes × 1 s each), mouse detection uses one batched session for all six modes.
- **Cached calls:** The protected-object cache is populated on the first call. All subsequent calls return the cached `Mouse_Capabilities` without entering the probe cascade or opening a terminal session. Latency < 1 µs.
- **Windows fast path:** `GetConsoleMode (STD_INPUT_HANDLE)` is checked before any probe. A native Windows console returns `Win32_Console_Mouse = True` with zero I/O overhead.
- **GPM fast path (POSIX/Linux):** `TERM=linux` + `/dev/gpmctl` exists → `GPM_Available = True` with no DECRPM probe and no terminal I/O.
- **Partial results:** If the session times out after receiving some DECRPM responses, those responses are honoured and `Probed = True` is set. A total timeout with zero pre-sentinel bytes returns `NO_MOUSE_CAPABILITIES` (`Probed = False`).
- **Frame matching by mode number:** Responses are matched by the decoded `Ps` field (`Mode`), not by position, so a terminal that reorders or elides frames still produces a correct result.
- **Graceful degradation:** On any error — non-TTY stdin, background process, `Probe_Session` open failure, total timeout — the function returns `NO_MOUSE_CAPABILITIES` or a partial result without raising an exception (FUNC-MSE-014).
- **Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path. Terminal state is always restored regardless of probe outcome (FUNC-MSE-015).
- **SPARK boundary:** `Termicap.Mouse` (spec) is fully SPARK Silver — two pure functions with `Global => null`, no FFI, no global state. `Termicap.Mouse.IO` is `SPARK_Mode => Off` throughout (session management, terminal I/O, protected cache object).

---

## Scenario 28: Sixel / Kitty Graphics Detection

End-to-end scenario for `Detect_Graphics`. Shows the Win32 Console gate (Windows only), the non-TTY guard, passive Kitty and Sixel env-var harvests, the DA1 active probe for Sixel Ps=4 (reusing `Termicap.DA1.IO.Detect_DA1`), the XTVERSION name-substring Sixel fallback, the optional Kitty APC active probe (independent session), and the per-process cache. Unlike the MOUSE batched-sentinel approach, each active probe (DA1, APC) runs as an **independent session** with its own 1 000 ms budget (ADR-0028). Worst-case cold-start latency is 2 s (both probes time out). Cached calls return in < 1 µs.

### Phase A — Cache Check and Platform Gate

```
Caller (application)
  │
  │  Detect_Graphics
  ▼
Termicap.Graphics.IO.Detect_Graphics      [SPARK_Mode => Off]
  │
  │  Step 1: Cache check (protected object)
  │    Is_Cached = True?
  │      Yes → return Cached_Result immediately  (< 1 µs)
  │      No  → continue
  │
  │  [Windows body only]
  │  Step 2: Win32 Console gate
  │    GetConsoleMode (STD_OUTPUT_HANDLE)
  │      Succeeds?
  │        Yes → run passive env-var harvests (Steps 3–4) only;
  │              Probed := False; store in cache; return
  │        No  → handle is Cygwin/MSYS2 PTY; continue to Step 3
  │  [End Windows-only block]
  │
  └──► Proceed to Phase B
```

### Phase B — Passive Harvests and TTY Guard

```
  │
  │  Step 3: Passive Kitty env-var harvest  (FUNC-SXL-009)
  │    [Termicap.Environment — SPARK Silver, Global => null]
  │    Contains (Env, "KITTY_WINDOW_ID")?
  │      → Kitty_Graphics_Supported := True
  │    Value (Env, "TERM") = "xterm-kitty"?
  │      → Kitty_Graphics_Supported := True
  │    Value_Matches (Env, "TERM_PROGRAM", "WezTerm", Case_Insensitive)?
  │      → Kitty_Graphics_Supported := True
  │    (Passive only — no I/O; runs regardless of TTY status)
  │
  │  Step 4: Passive Sixel env-var harvest  (FUNC-SXL-008)
  │    [Termicap.Environment — SPARK Silver, Global => null]
  │    Value_Matches (Env, "TERM_PROGRAM", "WezTerm", Case_Insensitive)?
  │      → Sixel_Supported := True
  │    Value (Env, "TERM_PROGRAM") = "iTerm.app"?
  │      → Sixel_Supported := True
  │    Value (Env, "TERM") in {"xterm-kitty", "foot", "foot-extra",
  │                             "mlterm", "yaft"}?
  │      → Sixel_Supported := True
  │    Starts_With (Value (Env, "TERM"), "xterm")?
  │      → Sixel_Supported := True  (heuristic; DA1 probe provides authoritative answer)
  │    (Passive only — no I/O; runs regardless of TTY status)
  │
  │  Step 5: Non-TTY guard
  │    Is_TTY (Stdout) = False?          [Termicap.TTY — SPARK_Mode => Off]
  │      → Caps.Probed := False; return passive results (no active probes)
  │
  └──► Proceed to Phase C
```

### Phase C — DA1 Active Probe for Sixel

```
  │
  │  Step 6: Open DA1 Probe_Session (independent session 1)
  │    [Termicap.OSC — SPARK_Mode => Off]
  │    → /dev/tty open; foreground guard (Is_Foreground_Process)
  │    → Save termios, set raw mode, drain input
  │    Fails (not foreground, /dev/tty unopenable)?
  │      → Caps.Probed := False; return passive results
  │
  │  Step 7: DA1 probe for Sixel Ps=4  (FUNC-SXL-005, FUNC-SXL-006)
  │    Termicap.DA1.IO.Detect_DA1         [SPARK_Mode => Off]
  │      → Write DA1_QUERY (ESC [ c)
  │      → Timeout_Query (/dev/tty, GRAPHICS_PROBE_TIMEOUT_MS = 1_000 ms)
  │      → Parse_DA1_Response + Interpret_DA1
  │      [Termicap.DA1 — SPARK Silver, Global => null]
  │      Has_Capability (DA1_Result, Sixel_Graphics)?
  │        Yes → Caps.Sixel_Supported := True
  │              Caps.Sixel_Via_DA1    := True
  │              Caps.Probed           := True
  │        No  → (Sixel_Supported remains as set by passive harvest)
  │              Caps.Probed           := True
  │
  │  Session 1 closed:
  │    Probe_Session.Finalize (unconditional RAII)
  │      → Restore_Termios, close /dev/tty, release single-session guard
  │
  └──► Proceed to Phase D
```

### Phase D — XTVERSION Name-Substring Fallback

```
  │
  │  Step 8: XTVERSION Sixel fallback  (FUNC-SXL-007)
  │    Skipped when Caps.Sixel_Via_DA1 = True
  │    (DA1 result is authoritative; XTVERSION fallback is unnecessary)
  │
  │    When Sixel_Via_DA1 = False:
  │      Termicap.XTVERSION.IO.Query_And_Identify
  │        [SPARK_Mode => Off — opens its own internal session]
  │      Name_Contains (XTVERSION_Result, "kitty", Case_Insensitive)?
  │        → Caps.Sixel_Supported := True
  │      Name_Contains (XTVERSION_Result, "WezTerm", Case_Insensitive)?
  │        → Caps.Sixel_Supported := True
  │
  └──► Proceed to Phase E
```

### Phase E — Optional Kitty APC Active Probe

```
  │
  │  Step 9: Kitty APC active probe  (FUNC-SXL-010)
  │    Skipped when Caps.Kitty_Graphics_Supported = True
  │    (passive env-var harvest already confirmed Kitty support)
  │
  │    When Kitty_Graphics_Supported = False:
  │      Open DA1 Probe_Session (independent session 2)
  │        [Termicap.OSC — SPARK_Mode => Off]
  │        → /dev/tty open, foreground guard, raw mode
  │        Fails?
  │          → skip APC probe; retain current Caps
  │
  │      Step 10: Write APC query + DA1 sentinel
  │        [Termicap.OSC.Write_Query / Sentinel_Query — SPARK_Mode => Off]
  │        ┌──────────────────────────────────────────────────────────────┐
  │        │  Write KITTY_APC_QUERY (ESC _ G i=1,a=q ESC \)             │
  │        │  Write DA1 sentinel    (ESC [ c)  — response boundary       │
  │        └──────────────────────────────────────────────────────────────┘
  │
  │      Step 11: Sentinel-bounded read loop  (GRAPHICS_PROBE_TIMEOUT_MS = 1_000 ms)
  │        ┌──────────────────────────────────────────────────────────────┐
  │        │  Accumulation loop:                                          │
  │        │    Timed_Read (/dev/tty) → append to Response buffer        │
  │        │    Contains_DA1_Response (Response, Length)  [SPARK Silver] │
  │        │      → if found: record pre-sentinel length; exit loop      │
  │        │    if timeout or overflow: Timed_Out := True; exit loop     │
  │        └──────────────────────────────────────────────────────────────┘
  │
  │      Step 12: Parse Kitty APC response
  │        Parse_Kitty_APC_Response (Response, Pre_Sentinel_Length)
  │          [Termicap.Graphics — SPARK Silver, Global => null]
  │          → scan for ESC _ G <params> ESC \ (APC G envelope)
  │          → APC_Parse_Result:
  │              OK           → Caps.Kitty_Graphics_Supported  := True
  │                             Caps.Kitty_Via_Active_Probe    := True
  │                             Caps.Probed                    := True
  │              Not_Present  → Kitty_Graphics_Supported remains False
  │              Error        → Kitty_Graphics_Supported remains False
  │
  │      Session 2 closed:
  │        Probe_Session.Finalize (unconditional RAII)
  │          → Restore_Termios, close /dev/tty, release single-session guard
  │
  └──► Proceed to Phase F
```

### Phase F — Cache and Return

```
  │
  │  Step 13: Cache and return
  │    Store Caps in protected-object cache
  │    Return Caps to caller
  │
  └──► Graphics_Capabilities returned to caller
```

**Key properties:**

- **Worst-case latency:** 2 s cold-start (DA1 probe + APC probe, both timing out at 1 s each). Typical < 200 ms when the terminal responds. Cached calls < 1 µs.
- **Independent sessions (ADR-0028):** Unlike the Mouse batched probe, each active probe (DA1 for Sixel, APC for Kitty) runs in its own `Probe_Session` with its own 1 s budget. This avoids APC response pollution in the DA1 accumulation buffer and simplifies per-probe error handling.
- **DA1 reuse (ADR-0027):** The Sixel DA1 probe calls `Termicap.DA1.IO.Detect_DA1` directly rather than issuing a new low-level probe. This reuses the existing timeout-only loop, parsing, and interpretation logic and ensures the DA1 result is consistent with what `Termicap.Capabilities` would obtain independently.
- **Passive-first ordering:** Env-var harvests (Steps 3–4) run before any TTY guard, so callers that set `KITTY_WINDOW_ID` or `TERM=xterm-kitty` in non-TTY contexts still receive a useful result.
- **APC skip condition:** If the passive harvest already set `Kitty_Graphics_Supported = True`, the APC probe session is never opened (zero I/O overhead). This is the common case for kitty, WezTerm, and any terminal with `KITTY_WINDOW_ID` set.
- **XTVERSION skip condition:** If the DA1 probe already set `Sixel_Via_DA1 = True`, the XTVERSION query is skipped (DA1 is the authoritative source for Sixel support).
- **Cached calls:** The protected-object cache is populated on the first call. All subsequent calls return the cached `Graphics_Capabilities` without entering the probe cascade. Latency < 1 µs.
- **Windows fast path:** `GetConsoleMode (STD_OUTPUT_HANDLE)` is checked before any active probe. A native Windows console returns passive env-var results only (`Probed = False`).
- **Graceful degradation:** On any error — non-TTY, background process, `Probe_Session` open failure, total timeout — the function returns passive env-var results or `NO_GRAPHICS_CAPABILITIES` without raising an exception (FUNC-SXL-016).
- **Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path of each session. Terminal state is always restored regardless of probe outcome (FUNC-SXL-014).
- **SPARK boundary:** `Termicap.Graphics` (spec and body) is fully SPARK Silver — one pure parser function with `Global => null`, no FFI, no global state. `Termicap.Graphics.IO` is `SPARK_Mode => Off` throughout (session management, terminal I/O, protected cache object).

---

## Scenario 29: Terminfo Database Lookup and Parsing

Executed on demand when an application calls `Parse_Terminfo` to read the compiled terminfo database entry for the active terminal. No TTY device is opened; the operation is safe in non-TTY contexts.

```
Caller (application code)
  │
  │  Result : Terminfo_Result :=
  │    Termicap.Terminfo.IO.Parse_Terminfo (Env)
  ▼
Termicap.Terminfo.IO                    [SPARK_Mode => Off]
  │
  │  Step 1: Read TERM from Env          -- Contains / Value (SPARK Silver)
  │    TERM absent or empty?
  │      → return (Success => False, Error => Error_No_Term)
  │
  │  Step 2: Build candidate directory list
  │    $TERMINFO                         -- if set and non-empty
  │    each entry in $TERMINFO_DIRS      -- colon-separated, if set
  │    $HOME/.terminfo                   -- if HOME is set
  │    /usr/share/terminfo
  │    /etc/terminfo
  │    /lib/terminfo
  │
  │  Step 3: For each candidate directory D:
  │    │
  │    │  Primary path:   D / T(1) / T
  │    │  Alternate path: D / HH  / T   (HH = hex encoding of T[1])
  │    │
  │    │  Read_File (Path, Buffer, Size, Error)
  │    ▼
  │  Termicap.Terminfo.IO.Read_File      [POSIX open/read/close]
  │    │
  │    │  open (Path, O_RDONLY)
  │    │  read (FD, Buffer, MAX_TERMINFO_FILE_SIZE)
  │    │  close (FD)
  │    │
  │    │  Read_Not_Found  → continue to next candidate
  │    │  Read_IO_Error   → continue to next candidate
  │    │  Read_Too_Large  → continue to next candidate
  │    └──► Read_OK       → commit; proceed to Step 4
  │
  │  All candidates exhausted without Read_OK?
  │    → return (Success => False, Error => Error_File_Not_Found)
  │
  │  Step 4: Parse_Buffer (Buffer, Size)
  ▼
Termicap.Terminfo                       [SPARK Silver]
  │
  │  Detect_Format (Buffer, Size)
  │    Unknown → return Error_Invalid_Magic
  │    Legacy_16bit | Extended_32bit → continue
  │
  │  Parse_Header (Buffer, Size, Format, Header, Success)
  │    Success = False → return Error_Header_Corrupt
  │    Header_Is_Valid (Buffer, Header) holds (ghost, machine-verified)
  │
  │  Get_Numeric (Buffer, Header, Format, COLORS_INDEX)
  │    → Snapshot.Colors (ABSENT_NUMERIC if out of range)
  │
  │  Get_String (Buffer, Header, SETAF_INDEX, Setaf, Has_Setaf)
  │    → Snapshot.Setaf, Snapshot.Has_Setaf
  │
  │  Get_String (Buffer, Header, SETAB_INDEX, Setab, Has_Setab)
  │    → Snapshot.Setab, Snapshot.Has_Setab
  │
  │  Extract_Term_Name (Buffer, Header)
  │    → Snapshot.Term_Name (bounded 64-char string)
  │
  │  Parse_Extended_Header (Buffer, Size, Header, Ext, Success)
  │    Success = False → extended section absent (non-fatal)
  │                      Snapshot.Has_RGB_Flag := False
  │                      Snapshot.Has_Tc_Flag  := False
  │    Extended_Is_Valid (Buffer, Header, Ext) holds (ghost)
  │
  │  Extract_Truecolor_Flags (Buffer, Header, Ext, Format,
  │                            Has_RGB, Has_Tc)
  │    Iterates extended capability names (bounded loop, Loop_Variant)
  │    Compares each name against "RGB" and "Tc" (case-sensitive)
  │    → Snapshot.Has_RGB_Flag, Snapshot.Has_Tc_Flag
  │
  └──► return (Success => True, Snapshot => Snapshot)
```

**Key properties:**

- `Parse_Terminfo` is the sole entry point; all OS interaction is confined to `Read_File`.
- No `Probe_Session`, no TTY device; safe to call when `Is_TTY = False`.
- Per-path `Read_Not_Found`, `Read_IO_Error`, and `Read_Too_Large` results are non-fatal; the search continues to the next candidate (FUNC-TIF-020).
- A found-but-corrupt file (e.g., `Error_Invalid_Magic` or `Error_Header_Corrupt`) does not fall back to a lower-priority candidate; the error is returned immediately.
- All array-index proofs in `Termicap.Terminfo` are discharged by GNATprove at Silver level using the ghost predicates `Header_Is_Valid` and `Extended_Is_Valid`, which bundle the full set of structural invariants so downstream functions need only assert a single predicate in their preconditions.
- The `Terminfo_Result` discriminated type forces callers to test `Success` before accessing `Snapshot` or `Error` — no unchecked access is possible.
- `Parse_Terminfo` never propagates an Ada exception under any input condition (FUNC-TIF-019).

### Testability pattern

Tests construct a deterministic `Byte_Array` containing a synthetic terminfo binary and call `Parse_Buffer` directly, bypassing `Termicap.Terminfo.IO` entirely. No filesystem access is required. `Read_File` can be tested independently with paths to fixture files under `tests/data/`.

```
Test body
  │
  │  Buffer : Byte_Array := [...]   -- synthetic terminfo binary
  │  Size   : Natural    := Buffer'Length
  │
  │  Result : Terminfo_Result :=
  │    Termicap.Terminfo.Parse_Buffer (Buffer, Size)
  │
  ▼
Termicap.Terminfo                    [SPARK Silver, no OS calls]
  │  Detect_Format → Parse_Header → Get_Numeric → Get_String(×2)
  │  → Extract_Term_Name → Parse_Extended_Header
  │  → Extract_Truecolor_Flags → Terminfo_Result
  └──► deterministic, reproducible, OS-independent
```

---

## Scenario 30: OSC 52 Clipboard Detection

End-to-end scenario for `Detect_Clipboard`. Shows the Win32 Console gate (Windows only), the non-TTY guard, the three-phase detection cascade (Phase 1: DA1 passive probe for Ps=52; Phase 2: active OSC 52 read-back probe; Phase 3: env-var heuristics), multiplexer passthrough wrapping, and the per-process cache. Each active probe phase runs as an **independent session** with its own 1 000 ms budget, consistent with ADR-0028. Worst-case cold-start latency is 2 s (both probes time out). Cached calls return in < 1 µs.

### Phase A — Cache Check and Platform Gate

```
Caller (application)
  │
  │  Detect_Clipboard
  ▼
Termicap.Clipboard.IO.Detect_Clipboard    [SPARK_Mode => Off]
  │
  │  Step 1: Cache check (protected object)
  │    Is_Cached = True?
  │      Yes → return Cached_Result immediately  (< 1 µs)
  │      No  → continue
  │
  │  [Windows body only]
  │  Step 2: Win32 Console gate
  │    GetConsoleMode (STD_OUTPUT_HANDLE)
  │      Succeeds?
  │        Yes → run passive env-var heuristics (Step 7) only;
  │              Probed := False; store in cache; return
  │        No  → handle is Cygwin/MSYS2 PTY; continue to Step 3
  │  [End Windows-only block]
  │
  └──► Proceed to Phase B
```

### Phase B — TTY Guard

```
  │
  │  Step 3: Non-TTY guard
  │    Is_TTY (Stdout) = False?          [Termicap.TTY — SPARK_Mode => Off]
  │      → Caps.Probed := False; run passive env-var heuristics (Step 7);
  │        store in cache; return
  │
  └──► Proceed to Phase C
```

### Phase C — DA1 Passive Probe (Phase 1)

```
  │
  │  Step 4: Open DA1 Probe_Session (independent session 1)
  │    [Termicap.OSC — SPARK_Mode => Off]
  │    → /dev/tty open; foreground guard (Is_Foreground_Process)
  │    → Save termios, set raw mode, drain input
  │    Fails (not foreground, /dev/tty unopenable)?
  │      → Caps.Probed := False; run env-var heuristics (Step 7); return
  │
  │  Step 5: DA1 probe for Clipboard_Access Ps=52  (FUNC-C52-006)
  │    Termicap.DA1.IO.Detect_DA1          [SPARK_Mode => Off]
  │      → Write DA1_QUERY (ESC [ c)
  │      → Timeout_Query (/dev/tty, CLIPBOARD_PROBE_TIMEOUT_MS = 1_000 ms)
  │      → Parse_DA1_Response + Interpret_DA1
  │      [Termicap.DA1 — SPARK Silver, Global => null]
  │      Has_Capability (DA1_Result, Clipboard_Access)?
  │        Yes → Caps.Support   := Write_Only
  │              Caps.Via_DA1   := True
  │              Caps.Probed    := True
  │        No  → (Support remains None)
  │              Caps.Probed    := True
  │
  │  Session 1 closed:
  │    Probe_Session.Finalize (unconditional RAII)
  │      → Restore_Termios, close /dev/tty, release single-session guard
  │
  └──► Proceed to Phase D
```

### Phase D — Active OSC 52 Read-Back Probe (Phase 2)

```
  │
  │  Step 6: Active OSC 52 read-back probe  (FUNC-C52-007)
  │    Skipped when Caps.Support = Read_Write
  │    (read-write already confirmed; no benefit to re-probing)
  │
  │    When Support /= Read_Write:
  │      Open OSC 52 Probe_Session (independent session 2)
  │        [Termicap.OSC — SPARK_Mode => Off]
  │        → /dev/tty open, foreground guard, raw mode
  │        Fails?
  │          → skip OSC 52 probe; retain current Caps
  │
  │      Step 6a: Apply multiplexer passthrough wrap  (FUNC-C52-011)
  │        [Termicap.OSC.Parsing — SPARK Silver, Global => null]
  │        TMUX set in Env?  → Wrap_For_Passthrough (tmux DCS escape)
  │        STY  set in Env?  → Wrap_For_Passthrough (screen passthrough)
  │        Neither set?      → use OSC52_QUERY unchanged
  │
  │      Step 6b: Write OSC 52 query + DA1 sentinel
  │        [Termicap.OSC.Sentinel_Query — SPARK_Mode => Off]
  │        ┌──────────────────────────────────────────────────────────────┐
  │        │  Write OSC52_QUERY (ESC ] 52 ; c ; ? BEL)  -- 9 bytes      │
  │        │  Write DA1 sentinel (ESC [ c)  — response boundary marker   │
  │        └──────────────────────────────────────────────────────────────┘
  │
  │      Step 6c: Sentinel-bounded read loop
  │        ┌──────────────────────────────────────────────────────────────┐
  │        │  Accumulation loop (CLIPBOARD_PROBE_TIMEOUT_MS = 1_000 ms): │
  │        │    Timed_Read (/dev/tty) → append to Response buffer        │
  │        │    Contains_DA1_Response (Response, Length)  [SPARK Silver] │
  │        │      → if found: record pre-sentinel length; exit loop      │
  │        │    if timeout or overflow: exit loop                        │
  │        └──────────────────────────────────────────────────────────────┘
  │
  │      Step 6d: Parse OSC 52 response
  │        Parse_OSC52_Response (Response, Pre_Sentinel_Length)
  │          [Termicap.Clipboard — SPARK Silver, Global => null]
  │          → scan for ESC ] 52 ; <sel> ; <base64-or-empty> BEL|ST
  │          → OSC52_Parse_Result:
  │              Valid_Response → Caps.Support          := Read_Write
  │                               Caps.Via_Active_Probe := True
  │                               Caps.Probed           := True
  │              Not_Present   → Support unchanged (Write_Only or None)
  │              Malformed     → Support unchanged (Write_Only or None)
  │
  │      Session 2 closed:
  │        Probe_Session.Finalize (unconditional RAII)
  │          → Restore_Termios, close /dev/tty, release single-session guard
  │
  └──► Proceed to Phase E
```

### Phase E — Env-Var Heuristics (Phase 3)

```
  │
  │  Step 7: Passive env-var heuristics  (FUNC-C52-009)
  │    Applied when Support = None after Phases 1 and 2
  │    (or always when TTY guard blocked all active probes)
  │    [Termicap.Environment — SPARK Silver, Global => null]
  │
  │    TERM_PROGRAM=WezTerm (case-insensitive)?  → Support := Read_Write
  │    TERM_PROGRAM=iTerm.app (case-insensitive)? → Support := Read_Write
  │    TERM_PROGRAM=vscode (case-insensitive)?   → Support := Write_Only
  │    WT_SESSION set (non-empty)?               → Support := Write_Only
  │    TERM=xterm-kitty?                         → Support := Read_Write
  │    TERM starts with "xterm"?                 → Support := Write_Only
  │    (When Via_DA1 or Via_Active_Probe already set
  │     Support, these steps are skipped.)
  │    When any heuristic fires: Via_Env_Heuristic := True
  │
  └──► Proceed to Phase F
```

### Phase F — Cache and Return

```
  │
  │  Step 8: Cache and return
  │    Store Caps in protected-object cache
  │    Return Caps to caller
  │
  └──► Clipboard_Capabilities returned to caller
```

**Key properties:**

- **Worst-case latency:** 2 s cold-start (DA1 probe + OSC 52 probe, both timing out at 1 s each). Typical < 200 ms when the terminal responds. Cached calls < 1 µs.
- **Independent sessions:** Each active probe (DA1 for Phase 1, OSC 52 for Phase 2) runs in its own `Probe_Session` with its own 1 s budget, consistent with ADR-0028. This avoids OSC 52 response pollution in the DA1 accumulation buffer and simplifies per-probe error handling.
- **DA1 reuse:** Phase 1 calls `Termicap.DA1.IO.Detect_DA1` directly, reusing the existing timeout-only loop, parsing, and interpretation logic. The `Clipboard_Access` literal (Ps=52) was added to `Termicap.DA1.DA1_Capability` to enable this passive inference without a separate low-level probe.
- **Multiplexer passthrough:** When `TMUX` or `STY` is set, the OSC 52 query is wrapped using `Termicap.OSC.Parsing.Wrap_For_Passthrough` before being sent (FUNC-C52-011). The DA1 Phase 1 probe handles its own multiplexer wrapping independently via `Detect_DA1`.
- **Phase 3 condition:** Env-var heuristics (Step 7) are applied only when `Support = None` after Phases 1 and 2. When a DA1 or active probe already set `Support`, Phase 3 is skipped. When the TTY guard blocked all active probes, Phase 3 runs unconditionally and `Via_Env_Heuristic` is set when a heuristic matches.
- **Cached calls:** The protected-object cache is populated on the first call. All subsequent calls return the cached `Clipboard_Capabilities` without entering the probe cascade. Latency < 1 µs.
- **Windows fast path:** `GetConsoleMode (STD_OUTPUT_HANDLE)` is checked before any active probe. A native Windows console returns passive env-var heuristic results only (`Probed = False`).
- **Graceful degradation:** On any error — non-TTY, background process, `Probe_Session` open failure, total timeout — the function returns env-var heuristic results or `NO_CLIPBOARD_CAPABILITIES` without raising an exception (FUNC-C52-016).
- **Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path of each session. Terminal state is always restored regardless of probe outcome (FUNC-C52-014).
- **SPARK boundary:** `Termicap.Clipboard` (spec and body) is fully SPARK Silver — one pure parser function with `Global => null`, no FFI, no global state. `Termicap.Clipboard.IO` is `SPARK_Mode => Off` throughout (session management, terminal I/O, protected cache object).

---

## Scenario 31: wcwidth() Probing for Unicode Level

End-to-end scenario for the three-phase call sequence `Detect_Unicode_Level` → `Probe_Wcwidth_Level` → `Refine_Unicode_Level`. Shows the locale guard, the descending sentinel probe (16 → 13 → 3), the per-process cache, the Windows stub fast-path, and the upgrade-only integration with the env-var-based `Unicode_Level` result. The probe has no TTY dependency and requires no `Probe_Session`.

### Phase A — Environment Cascade (SPARK Silver)

```
Application Init (Ada-only region)
  │
  │  Env       : Environment;
  │  Env_Level : Termicap.Unicode.Unicode_Level;
  │
  │  Capture_Current (Env);              -- Scenario 1 (SPARK_Mode => Off)
  │
  ▼
Termicap.Unicode.Detect_Unicode_Level (Env)   [SPARK Silver, Global => null]
  │
  │  5-step env-var cascade (see Scenario 9):
  │    locale → TERM=linux exclusion → CI heuristics → Windows heuristics → default
  │
  └──► Env_Level : Unicode_Level  (None / Basic / Extended)
```

### Phase B — wcwidth() Probe (SPARK_Mode => Off)

```
  │
  │  Wcw_Level := Termicap.Wcwidth.Probe_Wcwidth_Level;
  │                   [spec: SPARK On, body: SPARK_Mode => Off]
  ▼
Termicap.Wcwidth body (POSIX or Windows)
  │
  │  [Windows body only]
  │    Return Unknown immediately (no POSIX wcwidth() available)
  │  [End Windows-only]
  │
  │  [POSIX body]
  │
  │  Step 1: Cache check (Wcwidth_Cache.Get)
  │    Is_Set = True?
  │      Yes → return cached Level immediately  (< 1 µs)
  │      No  → continue
  │
  │  Step 2: Locale guard  (FUNC-WCW-006)
  │    C_Setlocale (LC_CTYPE, Null_Ptr)
  │      [C binding to setlocale(LC_CTYPE, NULL) — SPARK_Mode => Off]
  │    Result is NULL?
  │      Yes → cache Unknown; return Unknown
  │    Result = "C" or "POSIX"?
  │      Yes → cache Unknown; return Unknown
  │            (locale not initialised with setlocale(LC_CTYPE, "");
  │             wcwidth() would return -1 for all non-ASCII codepoints)
  │
  │  Step 3: Probe Unicode 16  (FUNC-WCW-003, step 1)
  │    C_Wcwidth (wchar_t (WCW_SENTINEL_UNI16))
  │      [C binding to wcwidth() — SPARK_Mode => Off]
  │      WCW_SENTINEL_UNI16 = 16#1CD00# (U+1CD00, Unicode 16.0)
  │    Return value >= 1?
  │      Yes → cache Unicode_16; return Unicode_16
  │
  │  Step 4: Probe Unicode 13  (FUNC-WCW-003, step 2)
  │    C_Wcwidth (wchar_t (WCW_SENTINEL_UNI13))
  │      WCW_SENTINEL_UNI13 = 16#1FB38# (U+1FB38, Unicode 13.0)
  │    Return value >= 1?
  │      Yes → cache Unicode_13; return Unicode_13
  │
  │  Step 5: Probe Unicode 3  (FUNC-WCW-003, step 3)
  │    C_Wcwidth (wchar_t (WCW_SENTINEL_UNI3))
  │      WCW_SENTINEL_UNI3 = 16#28FF# (U+28FF, Unicode 3.0)
  │    Return value >= 1?
  │      Yes → cache Unicode_3; return Unicode_3
  │
  │  Step 6: All probes failed  (FUNC-WCW-003, step 4)
  │    cache Unknown; return Unknown
  │    (e.g., C/POSIX locale, non-conforming wcwidth(), very old glibc)
  │
  └──► Wcw_Level : Wcwidth_Level  (Unknown / Unicode_3 / Unicode_13 / Unicode_16)
```

### Phase C — Upgrade-Only Integration (SPARK Silver)

```
  │
  │  Final_Level := Termicap.Wcwidth.Refine_Unicode_Level
  │                   (Env_Level, Wcw_Level);
  │                   [SPARK Silver, Global => null]
  ▼
Termicap.Wcwidth.Refine_Unicode_Level  [SPARK Silver, Global => null]
  │
  │  case Wcw_Level is
  │    when Unknown =>
  │      return Env_Level;              -- probe contributes nothing
  │    when Unicode_3 | Unicode_13 =>
  │      return Unicode_Level'Max (Env_Level, Basic);
  │      -- upgrade to at least Basic; never downgrade Extended
  │    when Unicode_16 =>
  │      return Unicode_Level'Max (Env_Level, Extended);
  │      -- upgrade to at least Extended; no-op if already Extended
  │  end case;
  │
  └──► Final_Level : Unicode_Level  (None / Basic / Extended)
         — always >= Env_Level (upgrade-only rule)
```

**Key properties:**

- **No TTY required.** `Probe_Wcwidth_Level` calls the C library directly via `wcwidth()` — it never opens `/dev/tty`, creates a `Probe_Session`, or checks TTY status. The locale is a process-global property, not a TTY property.
- **Locale precondition.** `setlocale(LC_CTYPE, "")` (or `setlocale(LC_ALL, "")`) must have been called by the application before `Probe_Wcwidth_Level`. The library does not call `setlocale()` itself (it has process-global side effects). The locale guard in Step 2 detects the uninitialized "C"/"POSIX" locale and returns `Unknown` gracefully rather than returning a misleading `Unicode_3` result due to all sentinels returning -1.
- **Descending probe order.** Sentinels are tested in descending Unicode version order (16 → 13 → 3). On modern systems with Unicode 16 locale tables, the probe returns after one successful `wcwidth()` call. On older systems, the cascade continues until the first successful probe or exhaustion.
- **Upgrade-only integration.** `Refine_Unicode_Level` uses `Unicode_Level'Max` so the wcwidth probe may only raise the Unicode level inferred from environment variables — it never lowers it. A CI environment detected as `Basic` by FUNC-UNI-006 remains at least `Basic` even if the container's locale returns -1 for all probes (which gives `Wcw_Level = Unknown`, which is a no-op in `Refine_Unicode_Level`).
- **Per-process cache.** The first call to `Probe_Wcwidth_Level` performs all C FFI calls and stores the result in the `Wcwidth_Cache` protected object. Subsequent calls return the cached value in < 1 µs with no FFI overhead.
- **Thread safety.** The protected object (`Wcwidth_Cache`) makes first-call initialisation safe against concurrent callers. The `wcwidth()` and `setlocale()` calls are outside the protected region (POSIX does not require them to be serialised). The recommended usage is to call `Probe_Wcwidth_Level` once at startup, before spawning threads (FUNC-WCW-009).
- **Windows fallback.** The Windows body returns `Unknown` unconditionally. `Refine_Unicode_Level` then returns `Env_Level` unchanged. The Windows env-var cascade (WT_SESSION, TERM_PROGRAM) is still applied in Phase A, providing correct Unicode level detection on Windows without any `wcwidth()` call.
- **SPARK boundary.** `Refine_Unicode_Level` is fully SPARK Silver provable (pure case statement, `Global => null`). `Probe_Wcwidth_Level` spec is SPARK-visible so SPARK callers can call it and reason about its `Wcwidth_Level` return type; the Off body is an opaque black box to GNATprove.

**Integration test pattern (locale-dependent):**

```ada
--  Call once at process startup (after setlocale):
--    setlocale(LC_CTYPE, "")  -- required; Termicap does not call this
--
declare
   Env         : Environment;
   Env_Level   : Termicap.Unicode.Unicode_Level;
   Wcw_Level   : Termicap.Wcwidth.Wcwidth_Level;
   Final_Level : Termicap.Unicode.Unicode_Level;
begin
   Capture_Current (Env);
   Env_Level   := Termicap.Unicode.Detect_Unicode_Level (Env);
   Wcw_Level   := Termicap.Wcwidth.Probe_Wcwidth_Level;
   Final_Level := Termicap.Wcwidth.Refine_Unicode_Level (Env_Level, Wcw_Level);
   --  Final_Level >= Env_Level always (upgrade-only)
   pragma Assert (Final_Level >= Env_Level);
end;
```

---

## Related Documents

- **Building Blocks** (`docs/architecture/03-building-blocks.md`): Static package structure and SPARK boundary diagram
- **Tech Spec F1** (`docs/tech-specs/f1-environment-variable-abstraction.md`): Design rationale, especially Sections C (Type Design) and D (SPARK Strategy)
- **Tech Spec F2** (`docs/tech-specs/f2-tty-detection.md`): TTY detection design rationale
- **Tech Spec F3** (`docs/tech-specs/f3-color-level-detection.md`): Color level detection design rationale
- **Tech Spec F4** (`docs/tech-specs/terminal-dimensions.md`): Terminal dimensions detection design rationale
- **Tech Spec F5** (`docs/tech-specs/unicode-support.md`): Unicode support level detection design rationale
- **Tech Spec F6** (`docs/tech-specs/terminal-identification.md`): Terminal identification detection design rationale
- **Tech Spec F7** (`docs/tech-specs/color-downsampling.md`): Color downsampling design rationale, algorithm survey, and type design decisions (ADR-0009)
- **Tech Spec F8** (`docs/tech-specs/sigwinch.md`): SIGWINCH resize notification design rationale, self-pipe pattern, and C trampoline decision
- **Tech Spec F9** (`docs/tech-specs/override.md`): Global override feature design rationale, SPARK strategy, and framework survey
- **ADR-0006** (`docs/adr/0006-c-wrapper-for-ioctl-tiocgwinsz.md`): Rationale for the thin C wrapper over ioctl
- **ADR-0007** (`docs/adr/0007-unicode-level-three-value-enum.md`): Rationale for the three-value `Unicode_Level` enumeration
- **ADR-0008** (`docs/adr/0008-terminal-id-string-representation-spark-boundary.md`): Rationale for `SPARK_Mode => Off` body and `Ada.Strings.Unbounded` use in `Termicap.Terminal_Id`
- **ADR-0010** (`docs/adr/0010-override-mode-flat-enum.md`): Rationale for the five-literal flat enumeration over alternative override representations
- **ADR-0011** (`docs/adr/0011-capability-record-package-placement.md`): Rationale for placing the aggregation package as a top-level child of `Termicap`
- **ADR-0012** (`docs/adr/0012-capability-cache-design.md`): Rationale for the per-stream protected cache design
- **ADR-0013** (`docs/adr/0013-spark-annotation-split-capabilities.md`): Rationale for the SPARK/Ada split in `Termicap.Capabilities`
- **Tech Spec F10** (`docs/tech-specs/capability-record.md`): Capability record assembly design rationale
- **Tech Spec OSC** (`docs/tech-specs/osc-query-infra.md`): OSC query infrastructure design rationale — sentinel pattern, C helper design, session lifecycle
- **Tech Spec BG-COLOR** (`docs/tech-specs/bg-color-query.md`): Background/foreground color detection design rationale — SPARK split, discriminated result types, COLORFGBG fallback, multiplexer passthrough
- **ADR-0016** (`docs/adr/0016-discriminated-record-for-bg-color-results.md`): Rationale for discriminated record result types in the BG-COLOR feature
- **Tech Spec DARK-LIGHT** (`docs/tech-specs/dark-light.md`): Dark/light theme classification design rationale — BT.601 integer luminance, SPARK Gold boundary, framework survey
- **Tech Spec XTVERSION** (`docs/tech-specs/xtversion.md`): XTVERSION active terminal identification design rationale — DCS envelope recognition, name/version tokenisation formats, SPARK Silver boundary, multiplexer passthrough strategy
- **Tech Spec DA1** (`docs/tech-specs/da1-response-parsing.md`): DA1 Primary Device Attributes design rationale — capability enumeration design, VT conformance level mapping, timeout-only read loop, SPARK Silver boundary
- **ADR-0017** (`docs/adr/0017-da1-timeout-only-read-loop.md`): Rationale for the timeout-only read loop in `Query_DA1` — why `Sentinel_Query` cannot be used when the DA1 response is the sought data
- **Tech Spec DECRPM** (`docs/tech-specs/decrpm.md`): DECRPM DEC Private Mode Report design rationale — Mode_Status enumeration design, sentinel vs. timeout strategy, batch query pattern, SPARK Silver boundary
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`): Rationale for GPR `Source_Dirs` platform dispatch
- **ADR-0019** (`docs/adr/0019-win32ada-as-ffi-layer.md`): Rationale for using win32ada as the Win32 FFI layer
- **Tech Spec WIN32** (`docs/tech-specs/windows-console.md`): Windows Console API integration — full design rationale and build number threshold derivation
- **Tech Spec CYGWIN** (`docs/tech-specs/cygwin-pty.md`): Cygwin/MSYS2 PTY detection design — pipe name grammar, SPARK split, fallback strategy
- **ADR-0020** (`docs/adr/0020-cygwin-pty-detection-strategy.md`): Rationale for the named-pipe name inspection strategy over alternative PTY detection approaches
- **Tech Spec KITTY-KB** (`docs/tech-specs/kitty-keyboard.md`): Kitty Keyboard Protocol detection design rationale — cascade strategy, DA1 sentinel reuse, SPARK Silver boundary, platform dispatch for Win32 gate
- **ADR-0021** (`docs/adr/0021-defer-keyboard-capability-integration.md`): Rationale for deferring `Keyboard_Capability` integration into `Terminal_Capabilities`, and the forward-compatible migration path
- **Tech Spec MOUSE** (`docs/tech-specs/mouse-protocol.md`): Mouse protocol detection design rationale — batched DECRPM probe, encoding cascade, GPM heuristic, Win32 gate, SPARK Silver boundary
- **ADR-0022** (`docs/adr/0022-batched-single-sentinel-decrpm-mouse-probe.md`): Rationale for issuing all six DECRPM queries as a single batched session with one DA1 sentinel
- **ADR-0023** (`docs/adr/0023-mouse-encoding-cascade-order.md`): Rationale for the SGR_Pixels > SGR > URXVT > X10 > None cascade order
- **ADR-0024** (`docs/adr/0024-gpm-detection-heuristic.md`): Rationale for the `TERM=linux` + `/dev/gpmctl` GPM detection heuristic
- **ADR-0026** (`docs/adr/0026-defer-mouse-capability-integration.md`): Rationale for deferring `Mouse_Capabilities` integration into `Terminal_Capabilities` and the migration path
- **Tech Spec SIXEL** (`docs/tech-specs/sixel-graphics.md`): Sixel / Kitty Graphics detection design rationale — DA1 Ps=4 probe, APC active probe, XTVERSION name fallback, env-var heuristics, independent session strategy, SPARK boundary
- **ADR-0027** (`docs/adr/0027-da1-reuse-vs-fresh-probe.md`): Rationale for reusing `Termicap.DA1.IO.Detect_DA1` for the Sixel DA1 probe rather than issuing a fresh low-level probe
- **ADR-0028** (`docs/adr/0028-graphics-independent-probe-sessions.md`): Rationale for using two independent probe sessions rather than a batched single-sentinel approach
- **ADR-0029** (`docs/adr/0029-graphics-package-naming.md`): Rationale for the `Termicap.Graphics` / `Termicap.Graphics.IO` package naming and deferred integration
- **Tech Spec TERMINFO** (`docs/tech-specs/terminfo.md`): Terminfo database parsing design rationale — binary format variants, ghost predicate SPARK strategy, search-path resolution order, path construction algorithm, truecolor flag extraction
- **Tech Spec OSC52** (`docs/tech-specs/osc52-clipboard.md`): OSC 52 Clipboard Detection design rationale — three-phase cascade, DA1 Ps=52 extension, active read-back probe, env-var heuristics, multiplexer passthrough, independent session strategy, SPARK boundary
- **Tech Spec WCWIDTH** (`docs/tech-specs/wcwidth.md`): wcwidth() Probing for Unicode Level design rationale — sentinel codepoint selection, descending probe order, locale guard, caching strategy, platform dispatch, SPARK boundary
- **ADR-0032** (`docs/adr/0032-wcwidth-package-placement.md`): Rationale for placing wcwidth probing in `Termicap.Wcwidth` (sibling of `Termicap.Unicode`) rather than as a child package
- **Requirements** (`docs/requirements/`): FUNC-ENV-002, FUNC-ENV-004, FUNC-ENV-005, FUNC-ENV-007, FUNC-ENV-008, FUNC-TTY-001 through FUNC-TTY-006, FUNC-CLR-001 through FUNC-CLR-015, FUNC-DIM-001 through FUNC-DIM-008, FUNC-UNI-001 through FUNC-UNI-008, FUNC-TID-001 through FUNC-TID-012, FUNC-DSP-001 through FUNC-DSP-012, FUNC-SWC-001 through FUNC-SWC-011, FUNC-OVR-001 through FUNC-OVR-014, FUNC-CAP-001 through FUNC-CAP-014, FUNC-BGC-001 through FUNC-BGC-019, FUNC-DKL-001 through FUNC-DKL-007, FUNC-CYG-001 through FUNC-CYG-017, FUNC-MSE-001 through FUNC-MSE-018, FUNC-SXL-001 through FUNC-SXL-019
