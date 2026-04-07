-------------------------------------------------------------------------------
--  Test_DECRPM - Unit Tests for Termicap.DECRPM Parsing Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK functions in Termicap.DECRPM:
--  Contains_DECRPM_Response recognition, Parse_DECRPM_Response parsing, and
--  DECRPM_Query byte sequence construction.
--
--  All tests construct Byte_Array values programmatically and require no live
--  terminal.
--
--  Requirements Coverage:
--    - @relation(FUNC-RPM-005): DECRPM_Query construction
--    - @relation(FUNC-RPM-006): Contains_DECRPM_Response recognition
--    - @relation(FUNC-RPM-007): Parse_DECRPM_Response parsing
--    - @relation(FUNC-RPM-017): Twenty mandatory test cases

with AUnit.Test_Cases;

package Test_DECRPM is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-RPM-006: Contains_DECRPM_Response (9 cases)
   ---------------------------------------------------------------------------

   --  FUNC-RPM-017 case 1: Well-formed response for mode 2004, status 2 (Reset)
   --  ESC [ ? 2 0 0 4 ; 2 $ y -> True
   procedure Test_Contains_Valid_Mode_2004_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 2: Well-formed response for mode 25, status 1 (Set)
   --  ESC [ ? 2 5 ; 1 $ y -> True
   procedure Test_Contains_Valid_Mode_25_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 3: Well-formed response for mode 1000, status 0 (Not_Recognized)
   --  ESC [ ? 1 0 0 0 ; 0 $ y -> True
   procedure Test_Contains_Valid_Mode_1000_Not_Recognized
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 4: Empty input (Length = 0) -> False
   procedure Test_Contains_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 5: Missing ? prefix (ESC [ 2 5 ; 1 $ y, ANSI mode report) -> False
   procedure Test_Contains_Missing_Question_Mark_Prefix
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 6: Missing semicolon (ESC [ ? 2 5 1 $ y) -> False
   procedure Test_Contains_Missing_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 7: Missing $ y suffix (ESC [ ? 2 5 ; 1) -> False
   procedure Test_Contains_Missing_Dollar_Y_Suffix
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 8: Missing digit before semicolon (ESC [ ? ; 1 $ y) -> False
   procedure Test_Contains_Missing_Digit_Before_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 9: Missing digit after semicolon (ESC [ ? 2 5 ; $ y) -> False
   procedure Test_Contains_Missing_Digit_After_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-RPM-007: Parse_DECRPM_Response (8 cases)
   ---------------------------------------------------------------------------

   --  FUNC-RPM-017 case 1: Mode 2004 (bracketed paste), Pm = 2
   --  -> Mode_Report'(Mode => 2004, Status => Reset)
   procedure Test_Parse_Mode_2004_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 2: Mode 2026 (synchronized output), Pm = 1
   --  -> Mode_Report'(Mode => 2026, Status => Set)
   procedure Test_Parse_Mode_2026_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 3: Mode 1049 (alt screen), Pm = 3
   --  -> Mode_Report'(Mode => 1049, Status => Permanently_Set)
   procedure Test_Parse_Mode_1049_Permanently_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 4: Mode 25 (cursor visibility), Pm = 4
   --  -> Mode_Report'(Mode => 25, Status => Permanently_Reset)
   procedure Test_Parse_Mode_25_Permanently_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 5: Mode 1000 (X11 mouse), Pm = 0
   --  -> Mode_Report'(Mode => 1000, Status => Not_Recognized)
   procedure Test_Parse_Mode_1000_Not_Recognized
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 6: Unknown Pm value (Pm = 5)
   --  -> Mode_Report'(Mode => <mode>, Status => Not_Recognized)
   procedure Test_Parse_Unknown_Pm_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 7: Empty input (Length = 0)
   --  -> Mode_Report'(Mode => 0, Status => Not_Recognized)
   procedure Test_Parse_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 case 8: Invalid input (no $ y suffix)
   --  -> Mode_Report'(Mode => 0, Status => Not_Recognized)
   procedure Test_Parse_Invalid_No_Suffix
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-RPM-005: DECRPM_Query (3 cases)
   ---------------------------------------------------------------------------

   --  FUNC-RPM-017 DECRPM_Query case 1: Mode 25
   --  -> begins with ESC [ ?, ends with $ p, contains "25" in between
   procedure Test_Query_Mode_25
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 DECRPM_Query case 2: Mode 2004
   --  -> contains digit sequence 2 0 0 4 between ? and $ p
   procedure Test_Query_Mode_2004
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-RPM-017 DECRPM_Query case 3: Mode 0
   --  -> single digit '0' between ? and $ p
   procedure Test_Query_Mode_0
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_DECRPM;
