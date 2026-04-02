# F5: Unicode Support Detection

**Feature:** Unicode Support Detection
**Requirements:** FUNC-UNI-001 through FUNC-UNI-008
**Status:** Approved
**Date:** 2026-04-02

---

## 1. Overview

Unicode support detection determines whether the terminal environment can render Unicode characters (box-drawing, checkmarks, mathematical symbols, emoji) or is limited to ASCII-only output. This capability allows CLI tools to choose between rich Unicode glyphs and plain ASCII fallbacks without manual user configuration.

The detection operates as a pure function over the `Termicap.Environment` snapshot, requiring no OS calls and no TTY status parameter. Unlike color detection, Unicode capability is a property of the terminal emulator and locale configuration, not of whether the output stream is connected to a TTY. A tool writing to a pipe may still need to know whether the eventual display supports Unicode in order to select the correct symbol set.

The feature is fully SPARK Silver provable with `Global => null` and no FFI boundary.

---

## 2. Framework Survey

### is-unicode-supported (JavaScript) -- The pragmatic heuristic

is-unicode-supported (`index.js`, 21 lines) is the most widely used Unicode detection library in the JavaScript ecosystem. Its algorithm is platform-asymmetric:

```
function isUnicodeSupported():
    if platform != Windows:
        return TERM != "linux"    // Linux console (kernel) -> false, everything else -> true
    else:  // Windows
        return WT_SESSION is set                // Windows Terminal
            or TERMINUS_SUBLIME is set          // Terminus plugin
            or ConEmuTask == "{cmd::Cmder}"     // ConEmu
            or TERM_PROGRAM == "Terminus-Sublime"
            or TERM_PROGRAM == "vscode"
            or TERM in {"xterm-256color", "alacritty", "rxvt-unicode", "rxvt-unicode-256color"}
            or TERMINAL_EMULATOR == "JetBrains-JediTerm"
```

**Strengths:** Extremely simple; correct for the vast majority of real-world terminals. The `TERM != "linux"` heuristic on non-Windows is surprisingly effective because virtually all modern terminal emulators on POSIX set TERM to something other than "linux".

**Weaknesses:** Returns a Boolean (no gradation). Does not inspect locale variables at all -- a POSIX system with `LANG=C` (no UTF-8) and `TERM=xterm` would incorrectly report Unicode as supported. No CI environment awareness.

### tcell (Go) -- Locale-first detection

tcell (`charset_unix.go`) extracts the character set from locale variables following the POSIX resolution order:

```
LC_ALL > LC_CTYPE > LANG
  - Strip modifier after '@'
  - Extract charset after '.'
  - If no '.' separator, assume UTF-8
  - If locale == "POSIX" or "C", return US-ASCII
```

tcell then compares the extracted charset against "UTF-8" (case-insensitive) to decide whether to enable Unicode output.

**Strengths:** Locale is the most authoritative signal on POSIX systems. Handles edge cases like `C.UTF-8` and bare locale strings without a charset suffix.

**Weaknesses:** No Windows heuristics. No CI awareness. Does not handle the Linux kernel console specially (relies on locale alone).

### notcurses (C) -- wcwidth() probing

notcurses goes further by probing `wcwidth()` at runtime to determine which Unicode planes the terminal font actually supports:

```
wcwidth(U+28FF) >= 0  -> braille supported (Unicode 3)
wcwidth(U+1FB38) >= 0 -> sextant supported (Unicode 13)
wcwidth(U+1CD00) >= 0 -> octant supported (Unicode 16)
```

**Strengths:** Measures actual rendering capability rather than inferring it from env vars.

**Weaknesses:** Requires FFI (`wcwidth` is a C library call). Results depend on the C library's Unicode tables, which may differ from the terminal's font. Not suitable for a pure SPARK function.

### What Termicap borrows and improves

| Aspect | Source | Termicap adaptation |
|--------|--------|---------------------|
| Locale-first detection | tcell | Adopted as the primary signal (Step 1). Termicap uses a simplified UTF-8 substring match rather than full charset extraction, because the requirement is only to detect "UTF-8" presence, not to identify the exact encoding. |
| `TERM=linux` exclusion | is-unicode-supported | Adopted but repositioned: locale and CI checks take priority, so `LANG=en_US.UTF-8` with `TERM=linux` correctly returns Basic (Step 3). |
| Windows heuristics | is-unicode-supported | Adopted with minor refinements: `OS_TYPE=Windows_NT` replaces a compile-time platform check, keeping the function pure. ConEmu/Terminus entries are omitted per FUNC-UNI-005. |
| CI awareness | (novel) | Termicap adds CI detection (GITHUB_ACTIONS, GITEA_ACTIONS, CIRCLECI) as a floor, which none of the reference libraries provide for Unicode. |
| Three-level enum | (novel) | `Unicode_Level` has `None`, `Basic`, `Extended` rather than a Boolean, preserving design space for future `wcwidth()` probing (see ADR-0007). |

---

## 3. Package Design

### Package: `Termicap.Unicode`

| Property | Value |
|----------|-------|
| Files | `src/termicap-unicode.ads`, `src/termicap-unicode.adb` |
| SPARK_Mode | On (spec and body) |
| Dependencies | `Termicap.Environment` |

### Unicode_Level type

```ada
type Unicode_Level is (None, Basic, Extended);
```

- `None` -- terminal cannot render Unicode; ASCII-only output.
- `Basic` -- Basic Multilingual Plane (BMP, U+0000..U+FFFF) supported; covers most scripts, symbols, box-drawing, checkmarks.
- `Extended` -- full Unicode including supplementary planes (U+10000..U+10FFFF); emoji, mathematical symbols, etc. Reserved for future `wcwidth()` probing; the v1 algorithm never returns `Extended`.

The values are ordered such that `None < Basic < Extended`, enabling `Unicode_Level'Max` for floor operations (same pattern as `Color_Level`).

### Detect_Unicode_Level function

```ada
function Detect_Unicode_Level
   (Env : Termicap.Environment.Environment) return Unicode_Level
   with Global => null;
```

**Key differences from `Detect_Color_Level`:**

1. No `Is_TTY` parameter -- Unicode capability is independent of TTY status (FUNC-UNI-002 comment).
2. Simpler cascade -- 5 steps vs. 11 steps for color.
3. No force/override mechanism -- there is no `FORCE_UNICODE` or `NO_UNICODE` standard.

### Relationship to `Termicap.Environment`

`Detect_Unicode_Level` receives the `Environment` snapshot as its sole parameter. It uses:
- `Contains` -- to test variable presence (CI variables, WT_SESSION).
- `Value` -- to retrieve variable values (LC_ALL, LC_CTYPE, LANG, TERM, OS_TYPE, etc.).
- `Equal_Case_Insensitive` -- for case-insensitive value comparisons (TERM = "linux", OS_TYPE = "windows_nt").
- `Value_Matches` -- for multi-candidate TERM matching on Windows.

No new operations on `Termicap.Environment` are required.

---

## 4. Detection Algorithm

The algorithm implements the 5-step priority cascade defined by FUNC-UNI-008.

### Step 1: Locale inspection (FUNC-UNI-003) -- highest priority

```ada
function Has_UTF8_Locale
   (Env : Termicap.Environment.Environment) return Boolean
   with Global => null;
```

Inspect `LC_ALL`, then `LC_CTYPE`, then `LANG` (first non-empty wins). Search the selected value for a UTF-8 indicator using the `Contains_UTF8` helper (see Section 5).

```
Locale_Var := first non-empty of (LC_ALL, LC_CTYPE, LANG)
if Locale_Var contains "UTF-8" (case-insensitive, non-alnum tolerant):
    return True
return False
```

If `Has_UTF8_Locale` returns `True`, the function establishes a floor of `Basic`. This floor cannot be reduced by any subsequent step.

### Step 2: CI heuristics (FUNC-UNI-006)

```ada
function Is_CI_Unicode
   (Env : Termicap.Environment.Environment) return Boolean
   with Global => null;
```

```
if Contains(Env, "GITHUB_ACTIONS")
   or Contains(Env, "GITEA_ACTIONS")
   or Contains(Env, "CIRCLECI"):
    return True
return False
```

If a CI environment is detected, the floor is raised to at least `Basic`. This step is evaluated after locale but the floor can only increase, never decrease.

### Step 3: TERM=linux exclusion (FUNC-UNI-004)

```
if Equal_Case_Insensitive(Value(Env, "TERM"), "linux"):
    if Floor = None:    -- no positive level from steps 1 or 2
        return None
    -- else: floor is already Basic from locale or CI; keep it
```

The `TERM=linux` exclusion applies only when no prior step has established a positive floor. A UTF-8 locale or a CI environment overrides this exclusion.

### Step 4: Windows heuristics (FUNC-UNI-005)

```
if Equal_Case_Insensitive(Value(Env, "OS_TYPE"), "Windows_NT"):
    if Contains(Env, "WT_SESSION"):
        Floor := Unicode_Level'Max(Floor, Basic)
    elsif Equal_Case_Insensitive(Value(Env, "TERM_PROGRAM"), "vscode"):
        Floor := Unicode_Level'Max(Floor, Basic)
    elsif Value_Matches(Env, "TERM",
            ["xterm-256color", "alacritty", "rxvt-unicode", "rxvt-unicode-256color"]):
        Floor := Unicode_Level'Max(Floor, Basic)
    elsif Equal_Case_Insensitive(Value(Env, "TERMINAL_EMULATOR"), "JetBrains-JediTerm"):
        Floor := Unicode_Level'Max(Floor, Basic)
```

Windows heuristics are positive signals -- they can raise the floor from `None` to `Basic` but never lower it from a level already established by locale or CI.

### Step 5: Default (return result)

```
return Floor    -- None if no positive signal was found
```

### Complete Ada-like code sketch

```ada
function Detect_Unicode_Level
   (Env : Termicap.Environment.Environment) return Unicode_Level
is
   Floor : Unicode_Level := None;
begin
   --  Step 1: Locale inspection (FUNC-UNI-003)
   if Has_UTF8_Locale (Env) then
      Floor := Basic;
   end if;

   --  Step 2: CI heuristics (FUNC-UNI-006)
   if Is_CI_Unicode (Env) then
      Floor := Unicode_Level'Max (Floor, Basic);
   end if;

   --  Step 3: TERM=linux exclusion (FUNC-UNI-004)
   --  Only returns None if no positive level established
   if Equal_Case_Insensitive (Value (Env, "TERM"), "linux")
      and then Floor = None
   then
      return None;
   end if;

   --  Step 4: Windows heuristics (FUNC-UNI-005)
   if Equal_Case_Insensitive (Value (Env, "OS_TYPE"), "Windows_NT") then
      Floor := Unicode_Level'Max (Floor, Detect_Windows_Unicode (Env));
   end if;

   --  Step 5: Default
   return Floor;
end Detect_Unicode_Level;
```

### Helper: `Detect_Windows_Unicode`

```ada
function Detect_Windows_Unicode
   (Env : Termicap.Environment.Environment) return Unicode_Level
   with Global => null;

function Detect_Windows_Unicode
   (Env : Termicap.Environment.Environment) return Unicode_Level
is
begin
   if Contains (Env, "WT_SESSION") then
      return Basic;
   end if;

   if Equal_Case_Insensitive (Value (Env, "TERM_PROGRAM"), "vscode") then
      return Basic;
   end if;

   if Value_Matches (Env, "TERM",
         ["xterm-256color", "alacritty", "rxvt-unicode", "rxvt-unicode-256color"])
   then
      return Basic;
   end if;

   if Equal_Case_Insensitive
         (Value (Env, "TERMINAL_EMULATOR"), "JetBrains-JediTerm")
   then
      return Basic;
   end if;

   return None;
end Detect_Windows_Unicode;
```

---

## 5. String Matching Strategy

### The UTF-8 substring detection problem

FUNC-UNI-003 requires detecting the substring "UTF-8" in locale values, with the following rules:
- Case-insensitive: "utf-8", "UTF-8", "Utf-8" all match.
- Non-alphanumeric separator tolerance: "utf8", "UTF-8", "utf_8" all match.

This means the matching is not a simple substring search. The requirement is to find the characters `U`, `T`, `F`, `8` in sequence, ignoring case, where non-alphanumeric characters between `UTF` and `8` are skipped.

### Implementation: `Contains_UTF8` helper

The approach uses a finite state machine with 4 states, scanning the string character by character. No dynamic allocation, no unbounded loops -- the loop iterates exactly once over `Source'Range`, which is bounded by the string length.

```ada
function Contains_UTF8 (Source : String) return Boolean
   with Global => null;

function Contains_UTF8 (Source : String) return Boolean is
   --  States: looking for 'U', then 'T', then 'F', then '8'
   type Match_State is (Want_U, Want_T, Want_F, Want_8);
   State : Match_State := Want_U;
   C     : Character;
begin
   for I in Source'Range loop
      C := To_Lower_Char (Source (I));
      case State is
         when Want_U =>
            if C = 'u' then
               State := Want_T;
            end if;
         when Want_T =>
            if C = 't' then
               State := Want_F;
            elsif C = 'u' then
               State := Want_T;  --  restart: new potential 'U' start
            elsif C in 'a' .. 'z' | '0' .. '9' then
               State := Want_U;  --  alphanumeric break: reset
            end if;
            --  Non-alphanumeric characters are ignored (separator tolerance)
         when Want_F =>
            if C = 'f' then
               State := Want_8;
            elsif C = 'u' then
               State := Want_T;  --  restart
            elsif C in 'a' .. 'z' | '0' .. '9' then
               State := Want_U;
            end if;
         when Want_8 =>
            if C = '8' then
               return True;
            elsif C = 'u' then
               State := Want_T;  --  restart
            elsif C in 'a' .. 'z' | '0' .. '9' then
               State := Want_U;
            end if;
      end case;
   end loop;
   return False;
end Contains_UTF8;
```

### SPARK provability

- The loop is bounded: it iterates exactly over `Source'Range` (a finite index range).
- No dynamic allocation: all variables are stack-local scalars.
- No exceptions: the enumeration type `Match_State` and character comparisons cannot raise exceptions.
- `Global => null`: the function reads only its parameter and local variables.

### Consistency with Color_Level string matching

`Termicap.Color` uses three body-local string helpers (`Ends_With`, `Contains_Substring`, `Starts_With`) that follow the same patterns:
- Case-insensitive via a body-local `To_Lower_Char` function.
- Bounded loops over the source string's index range.
- `Global => null` contracts.
- `pragma Inline` for performance.

`Contains_UTF8` follows the same conventions. The `To_Lower_Char` helper will be duplicated in the `Termicap.Unicode` body (same pattern as `Termicap.Color`, which also declares its own copy). This avoids a cross-package dependency on a private helper.

### Has_UTF8_Locale implementation sketch

```ada
function Has_UTF8_Locale
   (Env : Termicap.Environment.Environment) return Boolean
is
begin
   --  LC_ALL > LC_CTYPE > LANG (POSIX resolution order)
   if Contains (Env, "LC_ALL") and then Value (Env, "LC_ALL")'Length > 0 then
      return Contains_UTF8 (Value (Env, "LC_ALL"));
   end if;

   if Contains (Env, "LC_CTYPE") and then Value (Env, "LC_CTYPE")'Length > 0 then
      return Contains_UTF8 (Value (Env, "LC_CTYPE"));
   end if;

   if Contains (Env, "LANG") and then Value (Env, "LANG")'Length > 0 then
      return Contains_UTF8 (Value (Env, "LANG"));
   end if;

   return False;
end Has_UTF8_Locale;
```

---

## 6. SPARK Contract

### Package spec annotations

```ada
package Termicap.Unicode
   with SPARK_Mode
is
   type Unicode_Level is (None, Basic, Extended);

   function Detect_Unicode_Level
      (Env : Termicap.Environment.Environment) return Unicode_Level
      with Global => null;
end Termicap.Unicode;
```

### Package body annotations

```ada
package body Termicap.Unicode
   with SPARK_Mode
is
   --  All body-local helpers carry Global => null
   --  No SPARK_Mode => Off needed anywhere (no FFI)
   ...
end Termicap.Unicode;
```

### Contract rationale

| Annotation | Justification |
|------------|---------------|
| `SPARK_Mode` on spec | Entire spec is SPARK-verifiable; no FFI types or access types. |
| `SPARK_Mode` on body | Entire body is SPARK-verifiable; all logic is enum comparisons and bounded string scans via `Termicap.Environment` API calls that are themselves `Global => null`. |
| `Global => null` on `Detect_Unicode_Level` | The function reads no global state. All inputs come via the `Env` parameter. GNATprove will verify this at Silver level. |
| No `Pre` condition | `Detect_Unicode_Level` is total: it accepts any `Environment` value and always returns a valid `Unicode_Level`. There is no precondition to violate. |
| No `Post` condition | A meaningful postcondition would be `Result >= Basic when Has_UTF8_Locale(Env)`, but this duplicates the implementation logic without adding verification value. The cascade semantics are better validated through testing. |
| No `SPARK_Mode => Off` | Unlike `Termicap.TTY` and `Termicap.Dimensions`, Unicode detection has no FFI component. The entire package is provable. |

---

## 7. Integration with Top-Level API

### Package hierarchy after this feature

```
Termicap                              (root namespace)
+-- Termicap.Environment              [SPARK Silver] -- snapshot type
|   +-- Termicap.Environment.Capture  [SPARK_Mode => Off] -- OS FFI
+-- Termicap.TTY                      [spec: SPARK, body: Off] -- TTY detection
+-- Termicap.Color                    [SPARK Silver] -- color detection
+-- Termicap.Dimensions               [spec: SPARK, body: Off] -- dimensions
+-- Termicap.Unicode                  [SPARK Silver] -- Unicode detection (NEW)
```

### Usage example

```ada
with Termicap.Environment;         use Termicap.Environment;
with Termicap.Environment.Capture; use Termicap.Environment.Capture;
with Termicap.Unicode;             use Termicap.Unicode;
with Termicap.Color;               use Termicap.Color;
with Termicap.TTY;                 use Termicap.TTY;
with Ada.Text_IO;                  use Ada.Text_IO;

procedure My_CLI_Tool is
   Env       : Environment;
   Is_Stdout : Boolean;
   Colors    : Color_Level;
   Unicode   : Unicode_Level;
begin
   --  Phase 1: Capture (Ada-only, SPARK_Mode => Off)
   Capture_Current (Env);
   Is_Stdout := Is_TTY (Stdout);

   --  Phase 2: Detect capabilities (SPARK Silver, Global => null)
   Colors  := Detect_Color_Level (Env, Is_Stdout);
   Unicode := Detect_Unicode_Level (Env);

   --  Phase 3: Use capabilities
   if Unicode >= Basic then
      Put_Line ("Status: " & Character'Val (16#E2#) & "...");  --  checkmark
   else
      Put_Line ("Status: [OK]");
   end if;
end My_CLI_Tool;
```

### Planned Terminal_Capabilities record

When Termicap introduces a top-level convenience record, `Unicode_Level` will be a field alongside `Color_Level`, `Terminal_Size`, and TTY status:

```ada
type Terminal_Capabilities is record
   Colors    : Termicap.Color.Color_Level;
   Unicode   : Termicap.Unicode.Unicode_Level;
   Size      : Termicap.Dimensions.Terminal_Size;
   Is_TTY    : Boolean;
end record;
```

Note that `Detect_Unicode_Level` does not require `Is_TTY`, so populating the record can be done with `Is_TTY` passed only to detection functions that need it (color, dimensions).

### Test example

```ada
declare
   Env   : Environment := EMPTY_ENVIRONMENT;
   Level : Unicode_Level;
begin
   --  UTF-8 locale detected
   Insert (Env, "LANG", "en_US.UTF-8");
   Level := Detect_Unicode_Level (Env);
   pragma Assert (Level = Basic);

   --  UTF-8 locale overrides TERM=linux
   Insert (Env, "TERM", "linux");
   Level := Detect_Unicode_Level (Env);
   pragma Assert (Level = Basic);  --  locale wins over TERM=linux

   --  No locale, TERM=linux -> None
   Env := EMPTY_ENVIRONMENT;
   Insert (Env, "TERM", "linux");
   Level := Detect_Unicode_Level (Env);
   pragma Assert (Level = None);

   --  CI environment provides floor
   Env := EMPTY_ENVIRONMENT;
   Insert (Env, "GITHUB_ACTIONS", "true");
   Level := Detect_Unicode_Level (Env);
   pragma Assert (Level = Basic);

   --  Windows Terminal
   Env := EMPTY_ENVIRONMENT;
   Insert (Env, "OS_TYPE", "Windows_NT");
   Insert (Env, "WT_SESSION", "some-guid");
   Level := Detect_Unicode_Level (Env);
   pragma Assert (Level = Basic);
end;
```

---

## 8. ADR

**ADR-0007** (`docs/adr/0007-unicode-level-three-value-enum.md`): Documents the decision to use a three-value `Unicode_Level` enumeration (`None`, `Basic`, `Extended`) instead of a Boolean (`Is_Unicode_Supported`).

---

## 9. Files to Create/Modify

### Files to create

| File | Description |
|------|-------------|
| `src/termicap-unicode.ads` | Package spec: `Unicode_Level` type and `Detect_Unicode_Level` function with SPARK contracts. |
| `src/termicap-unicode.adb` | Package body: 5-step detection cascade with body-local helpers (`Has_UTF8_Locale`, `Contains_UTF8`, `Is_CI_Unicode`, `Detect_Windows_Unicode`, `To_Lower_Char`). |
| `tests/src/termicap-unicode-tests.ads` | Test package spec for Unicode detection tests. |
| `tests/src/termicap-unicode-tests.adb` | Test cases covering all 5 steps, edge cases (utf8, UTF-8, utf_8), and priority interactions. |
| `examples/unicode_demo/` | Interactive demo showing Unicode detection results (following the pattern of existing demo directories). |
| `docs/adr/0007-unicode-level-three-value-enum.md` | ADR documenting the three-level enum decision. |

### Files to modify

| File | Description |
|------|-------------|
| `termicap.gpr` | Add `termicap-unicode.ads` and `termicap-unicode.adb` to source files (if not auto-discovered). |
| `tests/termicap_tests.gpr` | Add test source files for Unicode detection. |
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Unicode` to the package overview, types table, and SPARK boundary diagram. |
| `docs/architecture/04-runtime-view.md` | Add a Unicode detection flow scenario. |

---

## Related Documents

- **Requirements:** `docs/requirements/unicode-support.sdoc` (FUNC-UNI-001 through FUNC-UNI-008)
- **ADR-0007:** `docs/adr/0007-unicode-level-three-value-enum.md` (three-level enum decision)
- **Tech Spec F3:** `docs/tech-specs/f3-color-level-detection.md` (analogous detection pattern)
- **Architecture:** `docs/architecture/03-building-blocks.md` (package structure)
- **Global Synthesis:** `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` (section 2.10)
