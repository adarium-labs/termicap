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
   procedure Test_Unicode_Level_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-001: Unicode_Level'Max works correctly
   procedure Test_Unicode_Level_Max (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-003: Locale-Based Detection
   ---------------------------------------------------------------------------

   --  FUNC-UNI-003: LC_ALL="en_US.UTF-8" -> Extended
   --  Note: covered by Test_B1_LC_All_UTF8_Extended.

   --  FUNC-UNI-003: LC_CTYPE="en_US.UTF-8", LC_ALL absent -> Extended
   procedure Test_Locale_LC_Ctype_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="en_US.UTF-8", LC_ALL and LC_CTYPE absent -> Extended
   --  Note: covered by Test_B1_Lang_English_UTF8_Extended.

   --  FUNC-UNI-003: LC_ALL takes priority over LC_CTYPE -> Extended from LC_ALL
   procedure Test_Locale_LC_All_Priority_Over_LC_Ctype (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="utf8" (no separator) -> Extended
   procedure Test_Locale_UTF8_No_Separator (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="UTF-8" (uppercase with hyphen) -> Extended
   procedure Test_Locale_UTF8_Uppercase_Hyphen (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="utf_8" (underscore separator) -> Extended
   procedure Test_Locale_UTF8_Underscore_Separator (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="C.UTF-8" -> Extended
   procedure Test_Locale_C_UTF8 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="C.utf-8" (lowercase) -> Extended
   procedure Test_Locale_C_UTF8_Lowercase (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="C" (no UTF-8) -> None
   procedure Test_Locale_Lang_C_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: LANG="POSIX" -> None
   procedure Test_Locale_Lang_POSIX_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-003: All locale vars absent -> None (no other signals)
   procedure Test_Locale_All_Absent_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-004: TERM=linux Exclusion
   ---------------------------------------------------------------------------

   --  FUNC-UNI-004: TERM="linux", no locale -> None
   procedure Test_Term_Linux_No_Locale_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-004: TERM="LINUX" (uppercase), no locale -> None
   procedure Test_Term_Linux_Uppercase_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-004: TERM="linux", LANG="en_US.UTF-8" -> None (TERM=linux is authoritative)
   --  Note: covered by Test_B1_Term_Linux_With_UTF8_Locale_None.

   --  FUNC-UNI-004: TERM="linux", GITHUB_ACTIONS present -> None (TERM=linux is authoritative)
   procedure Test_Term_Linux_With_CI_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-004: TERM="xterm-256color", no locale -> None (no positive signal)
   procedure Test_Term_Xterm_No_Locale_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-005: Windows Terminal Heuristics
   ---------------------------------------------------------------------------

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", WT_SESSION="some-guid" -> Extended
   --  Note: covered by Test_B1_Windows_WT_Session_No_Locale_Extended.

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERM_PROGRAM="vscode" -> Extended
   procedure Test_Windows_Term_Program_Vscode_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERM="xterm-256color" -> Basic
   procedure Test_Windows_Term_Xterm_256color_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERM="alacritty" -> Basic
   procedure Test_Windows_Term_Alacritty_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", TERMINAL_EMULATOR="JetBrains-JediTerm" -> Extended
   procedure Test_Windows_JetBrains_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE="Windows_NT", no matching heuristic -> None
   procedure Test_Windows_No_Match_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-005: OS_TYPE absent (not Windows), WT_SESSION present -> None
   procedure Test_Non_Windows_WT_Session_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-006: CI Environment Unicode Awareness
   ---------------------------------------------------------------------------

   --  FUNC-UNI-006: GITHUB_ACTIONS="true" -> Basic
   procedure Test_CI_Github_Actions_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: GITEA_ACTIONS present -> Basic
   procedure Test_CI_Gitea_Actions_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: CIRCLECI present -> Basic
   procedure Test_CI_CircleCI_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: CI="true" only (generic) -> None (not in FUNC-UNI-006)
   procedure Test_CI_Generic_Only_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-006: CI + TERM=linux -> None (TERM=linux is authoritative; CI cannot override)
   procedure Test_CI_Does_Not_Override_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-UNI-008: Priority Ordering
   ---------------------------------------------------------------------------

   --  FUNC-UNI-008: Locale takes priority (locale + CI both present -> Extended)
   procedure Test_Priority_Locale_And_CI_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-008: Locale UTF-8 + TERM=linux -> None (TERM=linux is authoritative)
   procedure Test_Priority_Locale_Reduced_By_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-008: CI + TERM=linux -> None (TERM=linux is authoritative)
   procedure Test_Priority_CI_Reduced_By_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-UNI-008: Empty environment -> None
   procedure Test_Priority_Empty_Environment_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Edge Cases
   ---------------------------------------------------------------------------

   --  Edge: All positive signals set simultaneously with TERM=linux -> None
   --  (TERM=linux is authoritative per FUNC-UNI-004)
   procedure Test_Edge_All_Signals_None_Due_To_Term_Linux (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Edge: Unicode_Level ordering: None < Basic < Extended (type check)
   procedure Test_Edge_Unicode_Level_Type_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  B1 — Conformance Divergence Regression Tests (FUNC-UNI-008)
   --
   --  Per reference-frameworks/analysis/divergence/2026-05-08-conformance-
   --  divergences.md §B1: a UTF-8 locale signal should promote the result to
   --  Extended (matching is-unicode-supported / rich / prompt_toolkit /
   --  spectre-console).  These tests are expected to FAIL until the
   --  implementation is updated; they are added in TDD style.
   ---------------------------------------------------------------------------

   --  B1: LANG="fr_FR.UTF-8" only -> Extended (per Option A in report)
   procedure Test_B1_Lang_French_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  B1: LANG="en_US.UTF-8" only -> Extended (per Option A in report)
   procedure Test_B1_Lang_English_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  B1: LC_ALL="en_US.UTF-8" only -> Extended (per Option A in report)
   procedure Test_B1_LC_All_UTF8_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  B1 regression: LANG="C" -> None (must remain None even after upgrade)
   procedure Test_B1_Lang_C_None_Regression (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  B1 regression: LANG="POSIX" -> None (must remain None)
   procedure Test_B1_Lang_POSIX_None_Regression (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  B1 regression: TERM=linux + LANG="en_US.UTF-8" -> None
   --  per FUNC-UNI-004 the TERM=linux exclusion must still win when the user
   --  intent is the kernel console (note: this overrides the existing
   --  Test_Term_Linux_With_UTF8_Locale_Basic case which is also affected by
   --  the cascade redesign — the report is explicit that TERM=linux remains
   --  None).
   procedure Test_B1_Term_Linux_With_UTF8_Locale_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  B1: LANG="fr_FR.UTF-8" + LC_ALL="C" -> None (LC_ALL precedence)
   procedure Test_B1_LC_All_C_Overrides_Lang_UTF8 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  B1: OS_TYPE="Windows_NT" + WT_SESSION="..." (no LANG) -> Extended
   --  per Option A in the report.
   procedure Test_B1_Windows_WT_Session_No_Locale_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Unicode;
