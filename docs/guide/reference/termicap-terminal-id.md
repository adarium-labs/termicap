# API Reference: `Termicap.Terminal_Id`

Package providing passive, SPARK-annotated identification of the terminal emulator or multiplexer hosting the current session.

**File:** `src/termicap-terminal_id.ads`
**SPARK_Mode:** On (spec), Off (body — ADR-0008)
**License:** Apache-2.0

---

## Overview

`Termicap.Terminal_Id` exposes a single pure function, `Detect_Terminal_Identity`, that classifies the active terminal by inspecting environment variables. It accepts an immutable `Termicap.Environment.Environment` snapshot and performs no OS calls, no I/O, and reads no global state. The `Global => null` contract and two postconditions are machine-verified by GNATprove at Silver level.

The detection algorithm implements an 8-step priority cascade, checking seven well-known environment variables in strict order. The result is a `Terminal_Identity` record containing the classification, raw string values from the environment, and a derived `Is_Multiplexer` flag.

The body uses `Ada.Strings.Unbounded` to store raw variable values in the result record. Because `Ada.Strings.Unbounded` is a controlled type outside the SPARK subset, the body is compiled with `SPARK_Mode => Off` (ADR-0008). Callers in the SPARK zone see only the spec contracts, which remain fully verifiable.

---

## Types

### `Terminal_Kind`

```ada
type Terminal_Kind is
  (Unknown,
   Alacritty,
   Apple_Terminal,
   Dumb,
   Foot,
   Ghostty,
   ITerm2,
   JediTerm,
   Kitty,
   Konsole,
   Linux_Console,
   Mintty,
   Rxvt,
   Screen,
   Tmux,
   VSCode,
   VTE,
   WarpTerminal,
   WezTerm,
   Windows_Terminal,
   Xterm);
```

Twenty-value enumeration classifying the active terminal emulator or multiplexer.

| Value | Identification signal |
|-------|-----------------------|
| `Unknown` | No recognised environment variable signal found. |
| `Alacritty` | `TERM=alacritty` |
| `Apple_Terminal` | `TERM_PROGRAM=Apple_Terminal` |
| `Dumb` | `TERM=dumb` — terminal explicitly declared no capability. |
| `Foot` | `TERM=foot` or `TERM=foot-extra` |
| `Ghostty` | `TERM=xterm-ghostty` |
| `ITerm2` | `TERM_PROGRAM=iTerm.app` |
| `JediTerm` | `TERMINAL_EMULATOR=JetBrains-JediTerm` |
| `Kitty` | `TERM=xterm-kitty` |
| `Konsole` | `KONSOLE_VERSION` present (any value) |
| `Linux_Console` | `TERM=linux` — Linux kernel virtual console. |
| `Mintty` | `TERM_PROGRAM=mintty` |
| `Rxvt` | `TERM` starts with `rxvt` |
| `Screen` | `TMUX` absent and `TERM` starts with `screen` |
| `Tmux` | `TMUX` present, or `TERM` starts with `tmux` |
| `VSCode` | `TERM_PROGRAM=vscode` |
| `VTE` | `VTE_VERSION` present (any value) — covers GNOME Terminal, Tilix, etc. |
| `WarpTerminal` | `TERM_PROGRAM=WarpTerminal` |
| `WezTerm` | `TERM_PROGRAM=WezTerm` or `TERM=wezterm` |
| `Windows_Terminal` | `WT_SESSION` present (any value) |
| `Xterm` | `TERM` starts with `xterm` (fallback after more specific xterm variants) |

Callers performing exhaustive `case` analysis shall include an `others` branch to remain forward-compatible with future enumeration extensions.

**Requirement:** FUNC-TID-001

---

### `Multiplexer_Kind`

```ada
subtype Multiplexer_Kind is Terminal_Kind
   with Static_Predicate => Multiplexer_Kind in Tmux | Screen;
```

Subtype of `Terminal_Kind` restricted to terminal multiplexers. The static predicate allows `Multiplexer_Kind` to be used in membership tests (`Kind in Multiplexer_Kind`) and as case alternatives. When a new multiplexer is added in future, only this predicate and the `Is_Multiplexer` postcondition need updating.

**Requirement:** FUNC-TID-011

---

### `Terminal_Identity`

```ada
type Terminal_Identity is record
   Kind            : Terminal_Kind;
   Program_Name    : Ada.Strings.Unbounded.Unbounded_String;
   Program_Version : Ada.Strings.Unbounded.Unbounded_String;
   Term_Value      : Ada.Strings.Unbounded.Unbounded_String;
   Is_Multiplexer  : Boolean;
end record;
```

Aggregated result of passive terminal identification.

| Field | Type | Description |
|-------|------|-------------|
| `Kind` | `Terminal_Kind` | Classified terminal or multiplexer; `Unknown` if no recognised signal was found. |
| `Program_Name` | `Unbounded_String` | Raw value of `TERM_PROGRAM`, or the empty string if the variable is absent. |
| `Program_Version` | `Unbounded_String` | Raw value of `TERM_PROGRAM_VERSION`, or the empty string if absent. Useful for version-gating within `ITerm2`. |
| `Term_Value` | `Unbounded_String` | Raw value of `TERM`, or the empty string if absent. |
| `Is_Multiplexer` | `Boolean` | `True` when `Kind in Multiplexer_Kind` (i.e., `Kind` is `Tmux` or `Screen`); `False` for all other values. Always derived from `Kind` — never set independently. |

String fields are populated from the environment snapshot unconditionally, regardless of which variable drove the `Kind` classification. For example, if `TERM_PROGRAM=WezTerm` is present and `TERM=tmux-256color` is also set, `Kind` will be `WezTerm` and `Term_Value` will still hold `"tmux-256color"`.

**Requirement:** FUNC-TID-002

---

## Functions

### `Detect_Terminal_Identity`

```ada
function Detect_Terminal_Identity
   (Env : Termicap.Environment.Environment) return Terminal_Identity
with
   Global => null,
   Post   =>
     (if not Termicap.Environment.Contains (Env, "TERM_PROGRAM")
        and then not Termicap.Environment.Contains (Env, "TERMINAL_EMULATOR")
        and then not Termicap.Environment.Contains (Env, "WT_SESSION")
        and then not Termicap.Environment.Contains (Env, "KONSOLE_VERSION")
        and then not Termicap.Environment.Contains (Env, "VTE_VERSION")
        and then not Termicap.Environment.Contains (Env, "TMUX")
        and then not Termicap.Environment.Contains (Env, "TERM")
      then
        Detect_Terminal_Identity'Result.Kind = Unknown
        and then not Detect_Terminal_Identity'Result.Is_Multiplexer)
      and then (Detect_Terminal_Identity'Result.Is_Multiplexer
                = (Detect_Terminal_Identity'Result.Kind in Multiplexer_Kind));
```

Detect the terminal identity from an environment snapshot.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | Immutable environment variable snapshot. Obtain via `Termicap.Environment.Capture.Capture_Current` or build programmatically with `Insert` for testing. |

**Returns:** A `Terminal_Identity` record. `Kind` is set by the 8-step cascade; string fields are always populated from the snapshot; `Is_Multiplexer` is derived from `Kind`.

**SPARK contracts:**
- `Global => null` — no hidden state; fully GNATprove-verifiable at Silver level for callers in the SPARK zone.
- Postcondition 1 (unknown fallback): if none of the seven probe variables is present in `Env`, the result has `Kind = Unknown` and `Is_Multiplexer = False`.
- Postcondition 2 (multiplexer consistency): `Is_Multiplexer = (Kind in Multiplexer_Kind)` in every case.

**Requirements:** FUNC-TID-003, FUNC-TID-005, FUNC-TID-006, FUNC-TID-007

---

## Detection Priority Order

The 8-step cascade is evaluated in strict order. Each step runs only if `Kind` is still `Unknown` at that point. All string comparisons are case-insensitive (FUNC-TID-010).

| Priority | Environment Variable | Matching Rule | Result |
|----------|---------------------|---------------|--------|
| 1 | `TERM_PROGRAM` | Exact match (case-insensitive) against `iTerm.app`, `Apple_Terminal`, `vscode`, `WezTerm`, `WarpTerminal`, `mintty` | Sets `Kind` to the corresponding value |
| 2 | `TERMINAL_EMULATOR` | Exact match against `JetBrains-JediTerm` | `Kind := JediTerm` |
| 3 | `WT_SESSION` | Presence (any value) | `Kind := Windows_Terminal` |
| 4 | `KONSOLE_VERSION` | Presence (any value) | `Kind := Konsole` |
| 5 | `VTE_VERSION` | Presence (any value) | `Kind := VTE` |
| 6 | `TMUX` | Presence (any value) | `Kind := Tmux` |
| 7 | `TERM` | Exact match or prefix match (case-insensitive): `"dumb"` → `Dumb`; `"linux"` → `Linux_Console`; prefix `"tmux"` → `Tmux`; prefix `"screen"` → `Screen`; `"xterm-kitty"` → `Kitty`; `"xterm-ghostty"` → `Ghostty`; `"alacritty"` → `Alacritty`; `"wezterm"` → `WezTerm`; prefix `"rxvt"` → `Rxvt`; `"foot"`/`"foot-extra"` → `Foot`; prefix `"xterm"` → `Xterm` | Sets `Kind` |
| 8 | *(default)* | No rule matched | `Kind` remains `Unknown` |

After step 8, `Is_Multiplexer` is derived: `Kind in Multiplexer_Kind`.

---

## Environment Variables Reference

| Variable | Steps checked | Effect |
|----------|--------------|--------|
| `TERM_PROGRAM` | 1 | Primary classification source for well-known GUI terminals |
| `TERM_PROGRAM_VERSION` | — (not probed) | Stored verbatim in `Program_Version`; available for downstream version gating |
| `TERMINAL_EMULATOR` | 2 | JetBrains JediTerm identification |
| `WT_SESSION` | 3 | Windows Terminal identification (presence only) |
| `KONSOLE_VERSION` | 4 | Konsole / KDE terminal identification (presence only) |
| `VTE_VERSION` | 5 | VTE-based terminals (GNOME Terminal, Tilix, etc.) (presence only) |
| `TMUX` | 6 | tmux multiplexer identification (presence only) |
| `TERM` | 7 | Fallback classification via value or prefix matching |

---

## Usage Examples

### Standard production use

```ada
with Ada.Strings.Unbounded;            use Ada.Strings.Unbounded;
with Termicap.Terminal_Id;             use Termicap.Terminal_Id;
with Termicap.Environment;             use Termicap.Environment;
with Termicap.Environment.Capture;     use Termicap.Environment.Capture;

procedure Main is
   Env    : Environment;
   Result : Terminal_Identity;
begin
   Capture_Current (Env);
   Result := Detect_Terminal_Identity (Env);

   case Result.Kind is
      when ITerm2          => Ada.Text_IO.Put_Line ("iTerm2: " & To_String (Result.Program_Version));
      when Windows_Terminal => Ada.Text_IO.Put_Line ("Windows Terminal");
      when Tmux | Screen   => Ada.Text_IO.Put_Line ("Multiplexer detected");
      when Unknown         => Ada.Text_IO.Put_Line ("Unknown terminal");
      when others          => Ada.Text_IO.Put_Line (Result.Kind'Image);
   end case;

   if Result.Is_Multiplexer then
      --  Apply multiplexer-specific colour caps, e.g. cap at Extended_256
      null;
   end if;
end Main;
```

### Deterministic unit test (no OS interaction)

```ada
Env    : Environment := EMPTY_ENVIRONMENT;
Result : Terminal_Identity;

--  TERM_PROGRAM identification
Insert (Env, "TERM_PROGRAM", "WezTerm");
Result := Detect_Terminal_Identity (Env);
pragma Assert (Result.Kind = WezTerm);
pragma Assert (not Result.Is_Multiplexer);

--  TMUX presence → multiplexer
Insert (Env, "TMUX", "/tmp/tmux-1000/default,12345,0");
Result := Detect_Terminal_Identity (Env);
--  TERM_PROGRAM still wins (higher priority)
pragma Assert (Result.Kind = WezTerm);

--  Without TERM_PROGRAM, TMUX is reached
Env := EMPTY_ENVIRONMENT;
Insert (Env, "TMUX", "/tmp/tmux-1000/default,12345,0");
Result := Detect_Terminal_Identity (Env);
pragma Assert (Result.Kind = Tmux);
pragma Assert (Result.Is_Multiplexer);

--  Empty environment → Unknown
Env := EMPTY_ENVIRONMENT;
Result := Detect_Terminal_Identity (Env);
pragma Assert (Result.Kind = Unknown);
pragma Assert (not Result.Is_Multiplexer);
```

### Integrating with `Termicap.Color` for multiplexer colour capping

```ada
with Termicap.Color;       use Termicap.Color;
with Termicap.Terminal_Id; use Termicap.Terminal_Id;

--  Detect identity and color separately, then combine
Identity := Detect_Terminal_Identity (Env);
Level    := Detect_Color_Level (Env, Is_TTY => Is_Interactive);

if Identity.Is_Multiplexer and then Level = True_Color then
   Level := Extended_256;   --  multiplexer passthrough cap
end if;
```

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-TID-001 | `Terminal_Kind` type — 20-value enumeration | Silver (spec) |
| FUNC-TID-002 | `Terminal_Identity` record type | Silver (spec) |
| FUNC-TID-003 | `Detect_Terminal_Identity` function signature | Silver (spec) |
| FUNC-TID-004 | Environment variable reading order and string field population | Ada (body) |
| FUNC-TID-005 | Unknown fallback postcondition | Silver (spec) |
| FUNC-TID-006 | `Is_Multiplexer` derivation rule postcondition | Silver (spec) |
| FUNC-TID-007 | SPARK Silver provability for `Detect_Terminal_Identity` | Silver (spec) |
| FUNC-TID-008 | Version string stored verbatim in `Program_Version` | Ada (body) |
| FUNC-TID-009 | `Program_Name` as authoritative source for downstream modules | Silver (spec) |
| FUNC-TID-010 | Case-insensitive string comparison for all classifications | Ada (body) |
| FUNC-TID-011 | `Multiplexer_Kind` subtype with static predicate | Silver (spec) |
| FUNC-TID-012 | Unit testability of each classification rule | Ada (body) |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, detection cascade table, SPARK boundary diagram
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 13: full end-to-end terminal identity detection flow
- **Tech Spec F6** (`docs/tech-specs/terminal-identification.md`) — full design rationale
- **ADR-0008** (`docs/adr/0008-terminal-id-string-representation-spark-boundary.md`) — rationale for `SPARK_Mode => Off` body and `Ada.Strings.Unbounded` use
- **[Termicap.Environment](termicap-environment.md)** — environment snapshot type used as input
