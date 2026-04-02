-------------------------------------------------------------------------------
--  Test_Unicode - Unit Tests for Termicap.Unicode
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Unicode_Level type properties and the full
--  Detect_Unicode_Level 5-step priority cascade.
--
--  Requirements Coverage:
--    - @relation(FUNC-UNI-001): Unicode_Level enumeration type
--    - @relation(FUNC-UNI-003): Locale-based detection via LC_ALL, LC_CTYPE, LANG
--    - @relation(FUNC-UNI-004): TERM=linux exclusion
--    - @relation(FUNC-UNI-005): Windows terminal heuristics
--    - @relation(FUNC-UNI-006): CI environment Unicode awareness
--    - @relation(FUNC-UNI-008): Detection priority order

with AUnit.Test_Cases;

package Test_Unicode is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-001: Unicode_Level Enumeration Properties
   ---------------------------------------------------------------------------

   --  FUNC-UNI-001: Ordering None < Basic < Extended
   procedure Test_Unicode_Level_Ordering
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-001: Unicode_Level'Max works correctly
   procedure Test_Unicode_Level_Max
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-003: Locale-Based Detection
   ---------------------------------------------------------------------------

   --  FUNC-UNI-003: LC_ALL="en_US.UTF-8" -> Basic
   procedure Test_Locale_LC_All_UTF8_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LC_CTYPE="en_US.UTF-8", LC_ALL absent -> Basic
   procedure Test_Locale_LC_Ctype_UTF8_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="en_US.UTF-8", LC_ALL and LC_CTYPE absent -> Basic
   procedure Test_Locale_Lang_UTF8_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LC_ALL takes priority over LC_CTYPE -> Basic from LC_ALL
   procedure Test_Locale_LC_All_Priority_Over_LC_Ctype
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="utf8" (no separator) -> Basic
   procedure Test_Locale_UTF8_No_Separator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="UTF-8" (uppercase with hyphen) -> Basic
   procedure Test_Locale_UTF8_Uppercase_Hyphen
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="utf_8" (underscore separator) -> Basic
   procedure Test_Locale_UTF8_Underscore_Separator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="C.UTF-8" -> Basic
   procedure Test_Locale_C_UTF8 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="C.utf-8" (lowercase) -> Basic
   procedure Test_Locale_C_UTF8_Lowercase
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="C" (no UTF-8) -> None
   procedure Test_Locale_Lang_C_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="POSIX" -> None
   procedure Test_Locale_Lang_POSIX_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: All locale vars absent -> None (no other signals)
   procedure Test_Locale_All_Absent_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-004: TERM=linux Exclusion
   ---------------------------------------------------------------------------

   --  FUNC-UNI-004: TERM="linux", no locale -> None
   procedure Test_Term_Linux_No_Locale_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-004: TERM="LINUX" (uppercase), no locale -> None
   procedure Test_Term_Linux_Uppercase_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-004: TERM="linux", LANG="en_US.UTF-8" -> Basic (locale overrides)
   procedure Test_Term_Linux_With_UTF8_Locale_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-004: TERM="linux", GITHUB_ACTIONS present -> Basic (CI overrides)
   procedure Test_Term_Linux_With_CI_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-004: TERM="xterm-256color", no locale -> None (no positive signal)
   procedure Test_Term_Xterm_No_Locale_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-005: Windows Terminal Heuristics
   ---------------------------------------------------------------------------

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", WT_SESSION="some-guid" -> Basic
   procedure Test_Windows_WT_Session_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERM_PROGRAM="vscode" -> Basic
   procedure Test_Windows_Term_Program_Vscode_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERM="xterm-256color" -> Basic
   procedure Test_Windows_Term_Xterm_256color_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERM="alacritty" -> Basic
   procedure Test_Windows_Term_Alacritty_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERMINAL_EMULATOR="JetBrains-JediTerm" -> Basic
   procedure Test_Windows_JetBrains_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", no matching heuristic -> None
   procedure Test_Windows_No_Match_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE absent (not Windows), WT_SESSION present -> None
   procedure Test_Non_Windows_WT_Session_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-006: CI Environment Unicode Awareness
   ---------------------------------------------------------------------------

   --  FUNC-UNI-006: GITHUB_ACTIONS="true" -> Basic
   procedure Test_CI_Github_Actions_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: GITEA_ACTIONS present -> Basic
   procedure Test_CI_Gitea_Actions_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: CIRCLECI present -> Basic
   procedure Test_CI_CircleCI_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: CI="true" only (generic) -> None (not in FUNC-UNI-006)
   procedure Test_CI_Generic_Only_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: CI + TERM=linux -> Basic (CI overrides TERM=linux exclusion)
   procedure Test_CI_Overrides_Term_Linux
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-008: Priority Ordering
   ---------------------------------------------------------------------------

   --  FUNC-UNI-008: Locale takes priority (locale + CI both present -> Basic)
   procedure Test_Priority_Locale_And_CI_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-008: Locale Basic + TERM=linux -> Basic (floor not reduced)
   procedure Test_Priority_Locale_Floor_Not_Reduced_By_Linux
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-008: CI Basic + TERM=linux -> Basic (floor not reduced)
   procedure Test_Priority_CI_Floor_Not_Reduced_By_Linux
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-008: Empty environment -> None
   procedure Test_Priority_Empty_Environment_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Edge Cases
   ---------------------------------------------------------------------------

   --  Edge: All positive signals set simultaneously -> Basic
   procedure Test_Edge_All_Signals_Basic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Edge: Unicode_Level ordering: None < Basic < Extended (type check)
   procedure Test_Edge_Unicode_Level_Type_Ordering
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Unicode;
