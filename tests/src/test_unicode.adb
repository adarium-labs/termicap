-------------------------------------------------------------------------------
--  Test_Unicode - Unit Tests for Termicap.Unicode
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Unicode;     use Termicap.Unicode;
with Termicap.Environment; use Termicap.Environment;

package body Test_Unicode is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Unicode");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-UNI-001
      Register_Routine
        (T, Test_Unicode_Level_Ordering'Access, "FUNC-UNI-001: Unicode_Level ordering: None < Basic < Extended");
      Register_Routine
        (T, Test_Unicode_Level_Max'Access, "FUNC-UNI-001: Unicode_Level'Max returns higher of two levels");

      --  FUNC-UNI-003
      --  Note: LC_ALL='en_US.UTF-8' -> Extended is covered by Test_B1_LC_All_UTF8_Extended.
      Register_Routine
        (T,
         Test_Locale_LC_Ctype_UTF8_Extended'Access,
         "FUNC-UNI-003: LC_CTYPE='en_US.UTF-8', LC_ALL absent -> Extended");
      --  Note: LANG='en_US.UTF-8' -> Extended is covered by Test_B1_Lang_English_UTF8_Extended.
      Register_Routine
        (T,
         Test_Locale_LC_All_Priority_Over_LC_Ctype'Access,
         "FUNC-UNI-003: LC_ALL takes priority over LC_CTYPE -> Extended from LC_ALL");
      Register_Routine
        (T, Test_Locale_UTF8_No_Separator'Access, "FUNC-UNI-003: LANG='utf8' (no separator) -> Extended");
      Register_Routine
        (T, Test_Locale_UTF8_Uppercase_Hyphen'Access, "FUNC-UNI-003: LANG='UTF-8' (uppercase with hyphen) -> Extended");
      Register_Routine
        (T,
         Test_Locale_UTF8_Underscore_Separator'Access,
         "FUNC-UNI-003: LANG='utf_8' (underscore separator) -> Extended");
      Register_Routine (T, Test_Locale_C_UTF8'Access, "FUNC-UNI-003: LANG='C.UTF-8' -> Extended");
      Register_Routine (T, Test_Locale_C_UTF8_Lowercase'Access, "FUNC-UNI-003: LANG='C.utf-8' (lowercase) -> Extended");
      Register_Routine
        (T, Test_Locale_Lang_C_None'Access, "FUNC-UNI-003: LANG='C' (no UTF-8), no other signals -> None");
      Register_Routine (T, Test_Locale_Lang_POSIX_None'Access, "FUNC-UNI-003: LANG='POSIX', no other signals -> None");
      Register_Routine
        (T, Test_Locale_All_Absent_None'Access, "FUNC-UNI-003: All locale vars absent, no other signals -> None");

      --  FUNC-UNI-004
      Register_Routine (T, Test_Term_Linux_No_Locale_None'Access, "FUNC-UNI-004: TERM='linux', no locale -> None");
      Register_Routine
        (T, Test_Term_Linux_Uppercase_None'Access, "FUNC-UNI-004: TERM='LINUX' (uppercase), no locale -> None");
      --  Note: TERM='linux' + LANG='en_US.UTF-8' -> None is covered by Test_B1_Term_Linux_With_UTF8_Locale_None.
      Register_Routine
        (T,
         Test_Term_Linux_With_CI_None'Access,
         "FUNC-UNI-004: TERM='linux', GITHUB_ACTIONS present -> None (TERM=linux is authoritative)");
      Register_Routine
        (T,
         Test_Term_Xterm_No_Locale_None'Access,
         "FUNC-UNI-004: TERM='xterm-256color', no locale, no other signals -> None");

      --  FUNC-UNI-005
      --  Note: OS_TYPE='Windows_NT' + WT_SESSION -> Extended is covered by
      --  Test_B1_Windows_WT_Session_No_Locale_Extended.
      Register_Routine
        (T,
         Test_Windows_Term_Program_Vscode_Extended'Access,
         "FUNC-UNI-005: OS_TYPE='Windows_NT', TERM_PROGRAM='vscode' -> Extended");
      Register_Routine
        (T,
         Test_Windows_Term_Xterm_256color_Basic'Access,
         "FUNC-UNI-005: OS_TYPE='Windows_NT', TERM='xterm-256color' -> Basic");
      Register_Routine
        (T, Test_Windows_Term_Alacritty_Basic'Access, "FUNC-UNI-005: OS_TYPE='Windows_NT', TERM='alacritty' -> Basic");
      Register_Routine
        (T,
         Test_Windows_JetBrains_Extended'Access,
         "FUNC-UNI-005: OS_TYPE='Windows_NT', TERMINAL_EMULATOR='JetBrains-JediTerm' -> Extended");
      Register_Routine
        (T, Test_Windows_No_Match_None'Access, "FUNC-UNI-005: OS_TYPE='Windows_NT', no matching heuristic -> None");
      Register_Routine
        (T,
         Test_Non_Windows_WT_Session_None'Access,
         "FUNC-UNI-005: OS_TYPE absent (not Windows), WT_SESSION present -> None");

      --  FUNC-UNI-006
      Register_Routine (T, Test_CI_Github_Actions_Basic'Access, "FUNC-UNI-006: GITHUB_ACTIONS='true' -> Basic");
      Register_Routine (T, Test_CI_Gitea_Actions_Basic'Access, "FUNC-UNI-006: GITEA_ACTIONS present -> Basic");
      Register_Routine (T, Test_CI_CircleCI_Basic'Access, "FUNC-UNI-006: CIRCLECI present -> Basic");
      Register_Routine
        (T, Test_CI_Generic_Only_None'Access, "FUNC-UNI-006: CI='true' only (generic CI), no other signals -> None");
      Register_Routine
        (T,
         Test_CI_Does_Not_Override_Term_Linux'Access,
         "FUNC-UNI-006: CI + TERM=linux -> None (TERM=linux is authoritative)");

      --  FUNC-UNI-008
      Register_Routine
        (T,
         Test_Priority_Locale_And_CI_Extended'Access,
         "FUNC-UNI-008: Locale + CI both present -> Extended (locale is first)");
      Register_Routine
        (T,
         Test_Priority_Locale_Reduced_By_Term_Linux'Access,
         "FUNC-UNI-008: Locale UTF-8 + TERM=linux -> None (TERM=linux is authoritative)");
      Register_Routine
        (T,
         Test_Priority_CI_Reduced_By_Term_Linux'Access,
         "FUNC-UNI-008: CI + TERM=linux -> None (TERM=linux is authoritative)");
      Register_Routine (T, Test_Priority_Empty_Environment_None'Access, "FUNC-UNI-008: Empty environment -> None");

      --  Edge cases
      Register_Routine
        (T,
         Test_Edge_All_Signals_None_Due_To_Term_Linux'Access,
         "Edge: All signals set (locale + CI + TERM=linux + Windows) -> None (TERM=linux is authoritative)");
      Register_Routine
        (T, Test_Edge_Unicode_Level_Type_Ordering'Access, "Edge: Unicode_Level type ordering None < Basic < Extended");

      --  B1 — Conformance Divergence regression (2026-05-08)
      Register_Routine
        (T, Test_B1_Lang_French_UTF8_Extended'Access, "B1 (FUNC-UNI-008): LANG='fr_FR.UTF-8' only -> Extended");
      Register_Routine
        (T, Test_B1_Lang_English_UTF8_Extended'Access, "B1 (FUNC-UNI-008): LANG='en_US.UTF-8' only -> Extended");
      Register_Routine (T, Test_B1_LC_All_UTF8_Extended'Access, "B1 (FUNC-UNI-008): LC_ALL='en_US.UTF-8' -> Extended");
      Register_Routine (T, Test_B1_Lang_C_None_Regression'Access, "B1 (FUNC-UNI-008): LANG='C' -> None (regression)");
      Register_Routine
        (T, Test_B1_Lang_POSIX_None_Regression'Access, "B1 (FUNC-UNI-008): LANG='POSIX' -> None (regression)");
      Register_Routine
        (T,
         Test_B1_Term_Linux_With_UTF8_Locale_None'Access,
         "B1 (FUNC-UNI-004): TERM=linux + LANG='en_US.UTF-8' -> None");
      Register_Routine
        (T,
         Test_B1_LC_All_C_Overrides_Lang_UTF8'Access,
         "B1 (FUNC-UNI-008): LANG='fr_FR.UTF-8' + LC_ALL='C' -> None (LC_ALL precedence)");
      Register_Routine
        (T,
         Test_B1_Windows_WT_Session_No_Locale_Extended'Access,
         "B1 (FUNC-UNI-008): OS_TYPE=Windows_NT + WT_SESSION + no LANG -> Extended");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  FUNC-UNI-001: Unicode_Level Enumeration Properties
   ---------------------------------------------------------------------------

   procedure Test_Unicode_Level_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Unicode_Level'First = None, "Unicode_Level'First should be None");
      Assert (Unicode_Level'Last = Extended, "Unicode_Level'Last should be Extended");
      Assert (None < Basic, "None should be less than Basic");
      Assert (Basic < Extended, "Basic should be less than Extended");
      Assert (None < Extended, "None should be less than Extended");
   end Test_Unicode_Level_Ordering;

   procedure Test_Unicode_Level_Max (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Unicode_Level'Max (None, None) = None, "Max(None, None) should be None");
      Assert (Unicode_Level'Max (None, Basic) = Basic, "Max(None, Basic) should be Basic");
      Assert (Unicode_Level'Max (Basic, Extended) = Extended, "Max(Basic, Extended) should be Extended");
      Assert (Unicode_Level'Max (Extended, None) = Extended, "Max(Extended, None) should be Extended");
      Assert (Unicode_Level'Max (Basic, None) = Basic, "Max(Basic, None) should be Basic");
      Assert (Unicode_Level'Max (Extended, Basic) = Extended, "Max(Extended, Basic) should be Extended");
   end Test_Unicode_Level_Max;

   ---------------------------------------------------------------------------
   --  FUNC-UNI-003: Locale-Based Detection
   ---------------------------------------------------------------------------

   --  Test_Locale_LC_All_UTF8_Basic deleted: covered by Test_B1_LC_All_UTF8_Extended.

   procedure Test_Locale_LC_Ctype_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LC_CTYPE", "en_US.UTF-8");
      Assert
        (Detect_Unicode_Level (Env) = Extended, "LC_CTYPE='en_US.UTF-8' with LC_ALL absent should return Extended");
   end Test_Locale_LC_Ctype_UTF8_Extended;

   --  Test_Locale_Lang_UTF8_Basic deleted: covered by Test_B1_Lang_English_UTF8_Extended.

   procedure Test_Locale_LC_All_Priority_Over_LC_Ctype (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  LC_ALL="en_US.UTF-8" takes priority; LC_CTYPE is non-UTF-8 but irrelevant
      Insert (Env, "LC_ALL", "en_US.UTF-8");
      Insert (Env, "LC_CTYPE", "C");
      Assert
        (Detect_Unicode_Level (Env) = Extended,
         "LC_ALL='en_US.UTF-8' should take priority over LC_CTYPE='C' and return Extended");
   end Test_Locale_LC_All_Priority_Over_LC_Ctype;

   procedure Test_Locale_UTF8_No_Separator (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "utf8");
      Assert (Detect_Unicode_Level (Env) = Extended, "LANG='utf8' (no separator) should return Extended");
   end Test_Locale_UTF8_No_Separator;

   procedure Test_Locale_UTF8_Uppercase_Hyphen (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "UTF-8");
      Assert (Detect_Unicode_Level (Env) = Extended, "LANG='UTF-8' (uppercase with hyphen) should return Extended");
   end Test_Locale_UTF8_Uppercase_Hyphen;

   procedure Test_Locale_UTF8_Underscore_Separator (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "utf_8");
      Assert (Detect_Unicode_Level (Env) = Extended, "LANG='utf_8' (underscore separator) should return Extended");
   end Test_Locale_UTF8_Underscore_Separator;

   procedure Test_Locale_C_UTF8 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "C.UTF-8");
      Assert (Detect_Unicode_Level (Env) = Extended, "LANG='C.UTF-8' should return Extended");
   end Test_Locale_C_UTF8;

   procedure Test_Locale_C_UTF8_Lowercase (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "C.utf-8");
      Assert (Detect_Unicode_Level (Env) = Extended, "LANG='C.utf-8' (lowercase) should return Extended");
   end Test_Locale_C_UTF8_Lowercase;

   procedure Test_Locale_Lang_C_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "C");
      Assert (Detect_Unicode_Level (Env) = None, "LANG='C' (no UTF-8) with no other signals should return None");
   end Test_Locale_Lang_C_None;

   procedure Test_Locale_Lang_POSIX_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "POSIX");
      Assert (Detect_Unicode_Level (Env) = None, "LANG='POSIX' with no other signals should return None");
   end Test_Locale_Lang_POSIX_None;

   procedure Test_Locale_All_Absent_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Assert (Detect_Unicode_Level (Env) = None, "All locale vars absent with no other signals should return None");
   end Test_Locale_All_Absent_None;

   ---------------------------------------------------------------------------
   --  FUNC-UNI-004: TERM=linux Exclusion
   ---------------------------------------------------------------------------

   procedure Test_Term_Linux_No_Locale_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "linux");
      Assert (Detect_Unicode_Level (Env) = None, "TERM='linux' with no locale and no other signals should return None");
   end Test_Term_Linux_No_Locale_None;

   procedure Test_Term_Linux_Uppercase_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "LINUX");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "TERM='LINUX' (uppercase) with no locale should return None (case-insensitive)");
   end Test_Term_Linux_Uppercase_None;

   --  Test_Term_Linux_With_UTF8_Locale_Basic deleted: covered by Test_B1_Term_Linux_With_UTF8_Locale_None.

   procedure Test_Term_Linux_With_CI_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Per FUNC-UNI-004 (and the divergence report §B1 "Tests to add"),
      --  TERM=linux is authoritative: neither CI nor locale can override it.
      Insert (Env, "TERM", "linux");
      Insert (Env, "GITHUB_ACTIONS", "true");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "TERM='linux' with GITHUB_ACTIONS present should return None (TERM=linux is authoritative)");
   end Test_Term_Linux_With_CI_None;

   procedure Test_Term_Xterm_No_Locale_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "xterm-256color");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "TERM='xterm-256color' with no locale and no other signals should return None");
   end Test_Term_Xterm_No_Locale_None;

   ---------------------------------------------------------------------------
   --  FUNC-UNI-005: Windows Terminal Heuristics
   ---------------------------------------------------------------------------

   --  Test_Windows_WT_Session_Basic deleted: covered by Test_B1_Windows_WT_Session_No_Locale_Extended.

   procedure Test_Windows_Term_Program_Vscode_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "OS_TYPE", "Windows_NT");
      Insert (Env, "TERM_PROGRAM", "vscode");
      Assert
        (Detect_Unicode_Level (Env) = Extended,
         "OS_TYPE='Windows_NT' with TERM_PROGRAM='vscode' should return Extended");
   end Test_Windows_Term_Program_Vscode_Extended;

   procedure Test_Windows_Term_Xterm_256color_Basic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "OS_TYPE", "Windows_NT");
      Insert (Env, "TERM", "xterm-256color");
      Assert
        (Detect_Unicode_Level (Env) = Basic, "OS_TYPE='Windows_NT' with TERM='xterm-256color' should return Basic");
   end Test_Windows_Term_Xterm_256color_Basic;

   procedure Test_Windows_Term_Alacritty_Basic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "OS_TYPE", "Windows_NT");
      Insert (Env, "TERM", "alacritty");
      Assert (Detect_Unicode_Level (Env) = Basic, "OS_TYPE='Windows_NT' with TERM='alacritty' should return Basic");
   end Test_Windows_Term_Alacritty_Basic;

   procedure Test_Windows_JetBrains_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "OS_TYPE", "Windows_NT");
      Insert (Env, "TERMINAL_EMULATOR", "JetBrains-JediTerm");
      Assert
        (Detect_Unicode_Level (Env) = Extended,
         "OS_TYPE='Windows_NT' with TERMINAL_EMULATOR='JetBrains-JediTerm' should return Extended");
   end Test_Windows_JetBrains_Extended;

   procedure Test_Windows_No_Match_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Windows platform identified but none of the Unicode-capable heuristics match
      Insert (Env, "OS_TYPE", "Windows_NT");
      Insert (Env, "TERM", "cmd");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "OS_TYPE='Windows_NT' with no matching Unicode heuristic should return None");
   end Test_Windows_No_Match_None;

   procedure Test_Non_Windows_WT_Session_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  WT_SESSION present but OS_TYPE is not Windows_NT; Windows heuristics not applied
      Insert (Env, "WT_SESSION", "some-guid-1234");
      Assert
        (Detect_Unicode_Level (Env) = None, "WT_SESSION present but OS_TYPE absent (not Windows) should return None");
   end Test_Non_Windows_WT_Session_None;

   ---------------------------------------------------------------------------
   --  FUNC-UNI-006: CI Environment Unicode Awareness
   ---------------------------------------------------------------------------

   procedure Test_CI_Github_Actions_Basic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "GITHUB_ACTIONS", "true");
      Assert (Detect_Unicode_Level (Env) = Basic, "GITHUB_ACTIONS='true' should return Basic");
   end Test_CI_Github_Actions_Basic;

   procedure Test_CI_Gitea_Actions_Basic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "GITEA_ACTIONS", "true");
      Assert (Detect_Unicode_Level (Env) = Basic, "GITEA_ACTIONS present should return Basic");
   end Test_CI_Gitea_Actions_Basic;

   procedure Test_CI_CircleCI_Basic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CIRCLECI", "true");
      Assert (Detect_Unicode_Level (Env) = Basic, "CIRCLECI present should return Basic");
   end Test_CI_CircleCI_Basic;

   procedure Test_CI_Generic_Only_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Generic CI=true is deliberately excluded from FUNC-UNI-006
      Insert (Env, "CI", "true");
      Assert
        (Detect_Unicode_Level (Env) = None, "Generic CI='true' only (not in FUNC-UNI-006 list) should return None");
   end Test_CI_Generic_Only_None;

   procedure Test_CI_Does_Not_Override_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Per FUNC-UNI-004 (and the divergence report §B1 "Tests to add"),
      --  TERM=linux is authoritative: the CI floor cannot override it.
      Insert (Env, "CI", "true");
      Insert (Env, "CIRCLECI", "true");
      Insert (Env, "TERM", "linux");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "CIRCLECI present + TERM='linux' should return None (TERM=linux is authoritative)");
   end Test_CI_Does_Not_Override_Term_Linux;

   ---------------------------------------------------------------------------
   --  FUNC-UNI-008: Priority Ordering
   ---------------------------------------------------------------------------

   procedure Test_Priority_Locale_And_CI_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Both locale and CI present; locale is highest priority and promotes to Extended.
      Insert (Env, "LANG", "en_US.UTF-8");
      Insert (Env, "GITHUB_ACTIONS", "true");
      Assert
        (Detect_Unicode_Level (Env) = Extended,
         "Locale UTF-8 + GITHUB_ACTIONS present -> Extended (locale is first priority)");
   end Test_Priority_Locale_And_CI_Extended;

   procedure Test_Priority_Locale_Reduced_By_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Per FUNC-UNI-004 (and the divergence report §B1 "Tests to add"),
      --  TERM=linux is authoritative: it overrides the locale floor.
      Insert (Env, "LANG", "en_US.UTF-8");
      Insert (Env, "TERM", "linux");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "Locale UTF-8 floor with TERM='linux' -> None (TERM=linux is authoritative)");
   end Test_Priority_Locale_Reduced_By_Term_Linux;

   procedure Test_Priority_CI_Reduced_By_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Per FUNC-UNI-004, TERM=linux is authoritative and overrides the CI floor.
      Insert (Env, "GITHUB_ACTIONS", "true");
      Insert (Env, "TERM", "linux");
      Assert (Detect_Unicode_Level (Env) = None, "CI floor with TERM='linux' -> None (TERM=linux is authoritative)");
   end Test_Priority_CI_Reduced_By_Term_Linux;

   procedure Test_Priority_Empty_Environment_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Assert (Detect_Unicode_Level (Env) = None, "Empty environment should return None");
   end Test_Priority_Empty_Environment_None;

   ---------------------------------------------------------------------------
   --  Edge Cases
   ---------------------------------------------------------------------------

   procedure Test_Edge_All_Signals_None_Due_To_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  All positive signals set simultaneously; TERM=linux is authoritative per
      --  FUNC-UNI-004 and forces the result to None regardless of the locale, CI,
      --  and Windows heuristics.
      Insert (Env, "LANG", "en_US.UTF-8");
      Insert (Env, "GITHUB_ACTIONS", "true");
      Insert (Env, "TERM", "linux");
      Insert (Env, "OS_TYPE", "Windows_NT");
      Insert (Env, "WT_SESSION", "some-guid");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "All signals set with TERM='linux' should return None (TERM=linux is authoritative)");
   end Test_Edge_All_Signals_None_Due_To_Term_Linux;

   procedure Test_Edge_Unicode_Level_Type_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (None < Basic, "None < Basic should hold for Unicode_Level type");
      Assert (Basic < Extended, "Basic < Extended should hold for Unicode_Level type");
      Assert (None < Extended, "None < Extended should hold for Unicode_Level type");
      Assert (not (Basic < None), "not (Basic < None) should hold for Unicode_Level type");
      Assert (not (Extended < Basic), "not (Extended < Basic) should hold for Unicode_Level type");
   end Test_Edge_Unicode_Level_Type_Ordering;

   ---------------------------------------------------------------------------
   --  B1 — Conformance Divergence Regression Tests
   --
   --  Source: reference-frameworks/analysis/divergence/
   --          2026-05-08-conformance-divergences.md §B1
   --
   --  Expected to FAIL until Detect_Unicode_Level promotes UTF-8 locales to
   --  Extended (Option A in the report).
   ---------------------------------------------------------------------------

   procedure Test_B1_Lang_French_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Reproduces the conformance scenario observed on every panel terminal
      --  on 2026-05-08: LANG=fr_FR.UTF-8 with no other locale variables.
      --  Per the reference panel (is-unicode-supported, rich, prompt_toolkit,
      --  spectre-console), a UTF-8 locale should yield Extended.
      Insert (Env, "LANG", "fr_FR.UTF-8");
      Assert (Detect_Unicode_Level (Env) = Extended, "B1: LANG='fr_FR.UTF-8' alone should return Extended");
   end Test_B1_Lang_French_UTF8_Extended;

   procedure Test_B1_Lang_English_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LANG", "en_US.UTF-8");
      Assert (Detect_Unicode_Level (Env) = Extended, "B1: LANG='en_US.UTF-8' alone should return Extended");
   end Test_B1_Lang_English_UTF8_Extended;

   procedure Test_B1_LC_All_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "LC_ALL", "en_US.UTF-8");
      Assert (Detect_Unicode_Level (Env) = Extended, "B1: LC_ALL='en_US.UTF-8' alone should return Extended");
   end Test_B1_LC_All_UTF8_Extended;

   procedure Test_B1_Lang_C_None_Regression (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  After B1 fix, LANG=C must still produce None.
      Insert (Env, "LANG", "C");
      Assert (Detect_Unicode_Level (Env) = None, "B1 regression: LANG='C' must still return None");
   end Test_B1_Lang_C_None_Regression;

   procedure Test_B1_Lang_POSIX_None_Regression (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  After B1 fix, LANG=POSIX must still produce None.
      Insert (Env, "LANG", "POSIX");
      Assert (Detect_Unicode_Level (Env) = None, "B1 regression: LANG='POSIX' must still return None");
   end Test_B1_Lang_POSIX_None_Regression;

   procedure Test_B1_Term_Linux_With_UTF8_Locale_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Per the report (B1 §"Tests to add"): TERM=linux + LANG=en_US.UTF-8
      --  should yield None — the kernel console exclusion must remain
      --  authoritative once the cascade is corrected.  This contradicts
      --  the legacy Test_Term_Linux_With_UTF8_Locale_Basic case which
      --  represents the OLD behaviour.
      Insert (Env, "TERM", "linux");
      Insert (Env, "LANG", "en_US.UTF-8");
      Assert
        (Detect_Unicode_Level (Env) = None, "B1: TERM='linux' + LANG='en_US.UTF-8' must return None per FUNC-UNI-004");
   end Test_B1_Term_Linux_With_UTF8_Locale_None;

   procedure Test_B1_LC_All_C_Overrides_Lang_UTF8 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Per the report: LANG=fr_FR.UTF-8 + LC_ALL=C must yield None because
      --  LC_ALL takes precedence over LANG.
      Insert (Env, "LANG", "fr_FR.UTF-8");
      Insert (Env, "LC_ALL", "C");
      Assert
        (Detect_Unicode_Level (Env) = None,
         "B1: LANG='fr_FR.UTF-8' + LC_ALL='C' must return None (LC_ALL overrides LANG)");
   end Test_B1_LC_All_C_Overrides_Lang_UTF8;

   procedure Test_B1_Windows_WT_Session_No_Locale_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Per Option A in the report: OS_TYPE=Windows_NT + WT_SESSION (Windows
      --  Terminal) supports full Unicode; no LANG present.
      --  TODO B1: this assertion depends on the implementation extending the
      --  Windows heuristic to return Extended; if the chosen fix follows
      --  Option B instead, this test will need to be adjusted to assert Basic.
      Insert (Env, "OS_TYPE", "Windows_NT");
      Insert (Env, "WT_SESSION", "some-guid-1234");
      Assert
        (Detect_Unicode_Level (Env) = Extended,
         "B1: OS_TYPE='Windows_NT' + WT_SESSION + no LANG should return Extended (Option A)");
   end Test_B1_Windows_WT_Session_No_Locale_Extended;

end Test_Unicode;
