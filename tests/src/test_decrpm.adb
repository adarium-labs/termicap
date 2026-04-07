-------------------------------------------------------------------------------
--  Test_DECRPM - Unit Tests for Termicap.DECRPM Parsing Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;  use AUnit.Assertions;
with AUnit.Test_Cases;  use AUnit.Test_Cases.Registration;

with Termicap.DECRPM;   use Termicap.DECRPM;

--  Bring equality operator into scope for Byte (Interfaces.C.unsigned_char) comparisons.
use type Termicap.DECRPM.Byte;

package body Test_DECRPM is

   ---------------------------------------------------------------------------
   --  Byte constant helpers
   ---------------------------------------------------------------------------

   --  Control bytes
   ESC_BYTE  : constant Byte := 16#1B#;  --  ESC (0x1B)
   LSB_BYTE  : constant Byte := 16#5B#;  --  [ (0x5B), CSI second byte
   QM_BYTE   : constant Byte := 16#3F#;  --  ? (0x3F), DEC private prefix
   SEMI_BYTE : constant Byte := 16#3B#;  --  ; (0x3B), parameter separator
   DOLL_BYTE : constant Byte := 16#24#;  --  $ (0x24), DECRPM suffix first byte
   Y_BYTE    : constant Byte := 16#79#;  --  y (0x79), DECRPM response suffix second byte
   P_BYTE    : constant Byte := 16#70#;  --  p (0x70), DECRPM query suffix second byte

   --  ASCII digit bytes
   D_0 : constant Byte := 16#30#;  --  '0'
   D_1 : constant Byte := 16#31#;  --  '1'
   D_2 : constant Byte := 16#32#;  --  '2'
   D_3 : constant Byte := 16#33#;  --  '3'
   D_4 : constant Byte := 16#34#;  --  '4'
   D_5 : constant Byte := 16#35#;  --  '5'
   D_6 : constant Byte := 16#36#;  --  '6'
   D_9 : constant Byte := 16#39#;  --  '9'


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.DECRPM");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-RPM-006: Contains_DECRPM_Response
      Register_Routine (T, Test_Contains_Valid_Mode_2004_Reset'Access,
         "FUNC-RPM-017 Contains case 1: mode 2004, status 2 (Reset) -> True");
      Register_Routine (T, Test_Contains_Valid_Mode_25_Set'Access,
         "FUNC-RPM-017 Contains case 2: mode 25, status 1 (Set) -> True");
      Register_Routine (T, Test_Contains_Valid_Mode_1000_Not_Recognized'Access,
         "FUNC-RPM-017 Contains case 3: mode 1000, status 0 (Not_Recognized) -> True");
      Register_Routine (T, Test_Contains_Empty_Input'Access,
         "FUNC-RPM-017 Contains case 4: empty input (Length=0) -> False");
      Register_Routine (T, Test_Contains_Missing_Question_Mark_Prefix'Access,
         "FUNC-RPM-017 Contains case 5: missing ? prefix (ANSI mode report) -> False");
      Register_Routine (T, Test_Contains_Missing_Semicolon'Access,
         "FUNC-RPM-017 Contains case 6: missing semicolon -> False");
      Register_Routine (T, Test_Contains_Missing_Dollar_Y_Suffix'Access,
         "FUNC-RPM-017 Contains case 7: missing $ y suffix -> False");
      Register_Routine (T, Test_Contains_Missing_Digit_Before_Semicolon'Access,
         "FUNC-RPM-017 Contains case 8: missing digit before semicolon -> False");
      Register_Routine (T, Test_Contains_Missing_Digit_After_Semicolon'Access,
         "FUNC-RPM-017 Contains case 9: missing digit after semicolon -> False");

      --  FUNC-RPM-007: Parse_DECRPM_Response
      Register_Routine (T, Test_Parse_Mode_2004_Reset'Access,
         "FUNC-RPM-017 Parse case 1: mode 2004, Pm=2 -> Mode_Report(2004, Reset)");
      Register_Routine (T, Test_Parse_Mode_2026_Set'Access,
         "FUNC-RPM-017 Parse case 2: mode 2026, Pm=1 -> Mode_Report(2026, Set)");
      Register_Routine (T, Test_Parse_Mode_1049_Permanently_Set'Access,
         "FUNC-RPM-017 Parse case 3: mode 1049, Pm=3 -> Mode_Report(1049, Permanently_Set)");
      Register_Routine (T, Test_Parse_Mode_25_Permanently_Reset'Access,
         "FUNC-RPM-017 Parse case 4: mode 25, Pm=4 -> Mode_Report(25, Permanently_Reset)");
      Register_Routine (T, Test_Parse_Mode_1000_Not_Recognized'Access,
         "FUNC-RPM-017 Parse case 5: mode 1000, Pm=0 -> Mode_Report(1000, Not_Recognized)");
      Register_Routine (T, Test_Parse_Unknown_Pm_Value'Access,
         "FUNC-RPM-017 Parse case 6: Pm=5 (unknown) -> Status=Not_Recognized");
      Register_Routine (T, Test_Parse_Empty_Input'Access,
         "FUNC-RPM-017 Parse case 7: empty input -> Mode_Report(0, Not_Recognized)");
      Register_Routine (T, Test_Parse_Invalid_No_Suffix'Access,
         "FUNC-RPM-017 Parse case 8: no $ y suffix -> Mode_Report(0, Not_Recognized)");

      --  FUNC-RPM-005: DECRPM_Query
      Register_Routine (T, Test_Query_Mode_25'Access,
         "FUNC-RPM-017 Query case 1: mode 25 -> ESC [ ? 2 5 $ p");
      Register_Routine (T, Test_Query_Mode_2004'Access,
         "FUNC-RPM-017 Query case 2: mode 2004 -> contains 2 0 0 4 between ? and $ p");
      Register_Routine (T, Test_Query_Mode_0'Access,
         "FUNC-RPM-017 Query case 3: mode 0 -> single digit 0 between ? and $ p");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies: Contains_DECRPM_Response
   ---------------------------------------------------------------------------


   procedure Test_Contains_Valid_Mode_2004_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 1:
      --  ESC [ ? 2 0 0 4 ; 2 $ y
      --  3-byte prefix + 4 digits + 1 semicolon + 1 digit + 2-byte suffix = 11 bytes
      Buf : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_0, D_0, D_4,
         SEMI_BYTE,
         D_2,
         DOLL_BYTE, Y_BYTE];
   begin
      Assert
        (Contains_DECRPM_Response (Buf, 11),
         "Contains_DECRPM_Response: mode 2004, status 2 (Reset) should return True");
   end Test_Contains_Valid_Mode_2004_Reset;


   procedure Test_Contains_Valid_Mode_25_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 2:
      --  ESC [ ? 2 5 ; 1 $ y
      --  3-byte prefix + 2 digits + 1 semicolon + 1 digit + 2-byte suffix = 9 bytes
      Buf : constant Byte_Array (1 .. 9) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_5,
         SEMI_BYTE,
         D_1,
         DOLL_BYTE, Y_BYTE];
   begin
      Assert
        (Contains_DECRPM_Response (Buf, 9),
         "Contains_DECRPM_Response: mode 25, status 1 (Set) should return True");
   end Test_Contains_Valid_Mode_25_Set;


   procedure Test_Contains_Valid_Mode_1000_Not_Recognized
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 3:
      --  ESC [ ? 1 0 0 0 ; 0 $ y
      --  3-byte prefix + 4 digits + 1 semicolon + 1 digit + 2-byte suffix = 11 bytes
      Buf : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_1, D_0, D_0, D_0,
         SEMI_BYTE,
         D_0,
         DOLL_BYTE, Y_BYTE];
   begin
      Assert
        (Contains_DECRPM_Response (Buf, 11),
         "Contains_DECRPM_Response: mode 1000, status 0 (Not_Recognized) should return True");
   end Test_Contains_Valid_Mode_1000_Not_Recognized;


   procedure Test_Contains_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 4: Length = 0
      Buf : constant Byte_Array (1 .. 9) := [others => 0];
   begin
      Assert
        (not Contains_DECRPM_Response (Buf, 0),
         "Contains_DECRPM_Response: empty input (Length=0) should return False");
   end Test_Contains_Empty_Input;


   procedure Test_Contains_Missing_Question_Mark_Prefix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 5:
      --  ESC [ 2 5 ; 1 $ y  — no ? prefix (ANSI mode report, not DEC private)
      --  2-byte CSI + 2 digits + 1 semicolon + 1 digit + 2-byte suffix = 8 bytes
      Buf : constant Byte_Array (1 .. 8) :=
        [ESC_BYTE, LSB_BYTE,
         D_2, D_5,
         SEMI_BYTE,
         D_1,
         DOLL_BYTE, Y_BYTE];
   begin
      Assert
        (not Contains_DECRPM_Response (Buf, 8),
         "Contains_DECRPM_Response: missing ? prefix (ANSI mode report) should return False");
   end Test_Contains_Missing_Question_Mark_Prefix;


   procedure Test_Contains_Missing_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 6:
      --  ESC [ ? 2 5 1 $ y  — digits run together, no semicolon separator
      --  3-byte prefix + 3 digits (no semicolon) + 2-byte suffix = 8 bytes
      Buf : constant Byte_Array (1 .. 8) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_5, D_1,
         DOLL_BYTE, Y_BYTE];
   begin
      Assert
        (not Contains_DECRPM_Response (Buf, 8),
         "Contains_DECRPM_Response: missing semicolon should return False");
   end Test_Contains_Missing_Semicolon;


   procedure Test_Contains_Missing_Dollar_Y_Suffix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 7:
      --  ESC [ ? 2 5 ; 1  — no $ y terminator
      --  3-byte prefix + 2 digits + 1 semicolon + 1 digit = 7 bytes, no suffix
      Buf : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_5,
         SEMI_BYTE,
         D_1];
   begin
      Assert
        (not Contains_DECRPM_Response (Buf, 7),
         "Contains_DECRPM_Response: missing $ y suffix should return False");
   end Test_Contains_Missing_Dollar_Y_Suffix;


   procedure Test_Contains_Missing_Digit_Before_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 8:
      --  ESC [ ? ; 1 $ y  — no digit before semicolon
      --  3-byte prefix + 0 digits + 1 semicolon + 1 digit + 2-byte suffix = 7 bytes
      Buf : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         SEMI_BYTE,
         D_1,
         DOLL_BYTE, Y_BYTE];
   begin
      Assert
        (not Contains_DECRPM_Response (Buf, 7),
         "Contains_DECRPM_Response: missing digit before semicolon should return False");
   end Test_Contains_Missing_Digit_Before_Semicolon;


   procedure Test_Contains_Missing_Digit_After_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Contains case 9:
      --  ESC [ ? 2 5 ; $ y  — no digit after semicolon
      --  3-byte prefix + 2 digits + 1 semicolon + 0 digits + 2-byte suffix = 8 bytes
      Buf : constant Byte_Array (1 .. 8) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_5,
         SEMI_BYTE,
         DOLL_BYTE, Y_BYTE];
   begin
      Assert
        (not Contains_DECRPM_Response (Buf, 8),
         "Contains_DECRPM_Response: missing digit after semicolon should return False");
   end Test_Contains_Missing_Digit_After_Semicolon;


   ---------------------------------------------------------------------------
   --  Test Bodies: Parse_DECRPM_Response
   ---------------------------------------------------------------------------


   procedure Test_Parse_Mode_2004_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 1:
      --  ESC [ ? 2 0 0 4 ; 2 $ y  -> Mode_Report(Mode => 2004, Status => Reset)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_0, D_0, D_4,
         SEMI_BYTE,
         D_2,
         DOLL_BYTE, Y_BYTE];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 11);
   begin
      Assert
        (Report.Mode = 2004,
         "Parse_DECRPM_Response mode 2004: Mode should be 2004");
      Assert
        (Report.Status = Reset,
         "Parse_DECRPM_Response mode 2004: Status should be Reset (Pm=2)");
   end Test_Parse_Mode_2004_Reset;


   procedure Test_Parse_Mode_2026_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 2:
      --  ESC [ ? 2 0 2 6 ; 1 $ y  -> Mode_Report(Mode => 2026, Status => Set)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_0, D_2, D_6,
         SEMI_BYTE,
         D_1,
         DOLL_BYTE, Y_BYTE];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 11);
   begin
      Assert
        (Report.Mode = 2026,
         "Parse_DECRPM_Response mode 2026: Mode should be 2026");
      Assert
        (Report.Status = Set,
         "Parse_DECRPM_Response mode 2026: Status should be Set (Pm=1)");
   end Test_Parse_Mode_2026_Set;


   procedure Test_Parse_Mode_1049_Permanently_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 3:
      --  ESC [ ? 1 0 4 9 ; 3 $ y  -> Mode_Report(Mode => 1049, Status => Permanently_Set)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_1, D_0, D_4, D_9,
         SEMI_BYTE,
         D_3,
         DOLL_BYTE, Y_BYTE];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 11);
   begin
      Assert
        (Report.Mode = 1049,
         "Parse_DECRPM_Response mode 1049: Mode should be 1049");
      Assert
        (Report.Status = Permanently_Set,
         "Parse_DECRPM_Response mode 1049: Status should be Permanently_Set (Pm=3)");
   end Test_Parse_Mode_1049_Permanently_Set;


   procedure Test_Parse_Mode_25_Permanently_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 4:
      --  ESC [ ? 2 5 ; 4 $ y  -> Mode_Report(Mode => 25, Status => Permanently_Reset)
      Buf    : constant Byte_Array (1 .. 9) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_5,
         SEMI_BYTE,
         D_4,
         DOLL_BYTE, Y_BYTE];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 9);
   begin
      Assert
        (Report.Mode = 25,
         "Parse_DECRPM_Response mode 25: Mode should be 25");
      Assert
        (Report.Status = Permanently_Reset,
         "Parse_DECRPM_Response mode 25: Status should be Permanently_Reset (Pm=4)");
   end Test_Parse_Mode_25_Permanently_Reset;


   procedure Test_Parse_Mode_1000_Not_Recognized
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 5:
      --  ESC [ ? 1 0 0 0 ; 0 $ y  -> Mode_Report(Mode => 1000, Status => Not_Recognized)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_1, D_0, D_0, D_0,
         SEMI_BYTE,
         D_0,
         DOLL_BYTE, Y_BYTE];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 11);
   begin
      Assert
        (Report.Mode = 1000,
         "Parse_DECRPM_Response mode 1000: Mode should be 1000");
      Assert
        (Report.Status = Not_Recognized,
         "Parse_DECRPM_Response mode 1000: Status should be Not_Recognized (Pm=0)");
   end Test_Parse_Mode_1000_Not_Recognized;


   procedure Test_Parse_Unknown_Pm_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 6:
      --  ESC [ ? 2 5 ; 5 $ y  — Pm=5 is outside the valid 0..4 range
      --  -> Mode_Report(Mode => 25, Status => Not_Recognized)
      Buf    : constant Byte_Array (1 .. 9) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_5,
         SEMI_BYTE,
         D_5,
         DOLL_BYTE, Y_BYTE];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 9);
   begin
      Assert
        (Report.Status = Not_Recognized,
         "Parse_DECRPM_Response Pm=5: unknown Pm value should map to Not_Recognized");
   end Test_Parse_Unknown_Pm_Value;


   procedure Test_Parse_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 7: Length = 0
      Buf    : constant Byte_Array (1 .. 9) := [others => 0];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 0);
   begin
      Assert
        (Report.Mode = 0,
         "Parse_DECRPM_Response empty input: Mode should be 0");
      Assert
        (Report.Status = Not_Recognized,
         "Parse_DECRPM_Response empty input: Status should be Not_Recognized");
   end Test_Parse_Empty_Input;


   procedure Test_Parse_Invalid_No_Suffix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Parse case 8:
      --  ESC [ ? 2 5 ; 1  — no $ y suffix, not a valid DECRPM response
      --  -> Mode_Report(Mode => 0, Status => Not_Recognized)
      Buf    : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE, LSB_BYTE, QM_BYTE,
         D_2, D_5,
         SEMI_BYTE,
         D_1];
      Report : constant Mode_Report := Parse_DECRPM_Response (Buf, 7);
   begin
      Assert
        (Report.Mode = 0,
         "Parse_DECRPM_Response invalid (no suffix): Mode should be 0");
      Assert
        (Report.Status = Not_Recognized,
         "Parse_DECRPM_Response invalid (no suffix): Status should be Not_Recognized");
   end Test_Parse_Invalid_No_Suffix;


   ---------------------------------------------------------------------------
   --  Test Bodies: DECRPM_Query
   ---------------------------------------------------------------------------


   procedure Test_Query_Mode_25
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Query case 1: Mode 25
      --  Expected: ESC [ ? 2 5 $ p  (7 bytes)
      Query : constant Byte_Array := DECRPM_Query (25);
   begin
      Assert
        (Query'Length >= 6,
         "DECRPM_Query mode 25: result length should be >= 6");
      Assert
        (Query (Query'First) = ESC_BYTE,
         "DECRPM_Query mode 25: first byte should be ESC (0x1B)");
      Assert
        (Query (Query'First + 1) = LSB_BYTE,
         "DECRPM_Query mode 25: second byte should be [ (0x5B)");
      Assert
        (Query (Query'First + 2) = QM_BYTE,
         "DECRPM_Query mode 25: third byte should be ? (0x3F)");
      Assert
        (Query (Query'Last) = P_BYTE,
         "DECRPM_Query mode 25: last byte should be p (0x70)");
      Assert
        (Query (Query'Last - 1) = DOLL_BYTE,
         "DECRPM_Query mode 25: second-to-last byte should be $ (0x24)");
      --  The digits for 25 are '2' then '5' immediately after the ? prefix
      Assert
        (Query (Query'First + 3) = D_2,
         "DECRPM_Query mode 25: fourth byte should be '2' (0x32)");
      Assert
        (Query (Query'First + 4) = D_5,
         "DECRPM_Query mode 25: fifth byte should be '5' (0x35)");
   end Test_Query_Mode_25;


   procedure Test_Query_Mode_2004
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Query case 2: Mode 2004
      --  Expected: ESC [ ? 2 0 0 4 $ p  (8 bytes)
      Query : constant Byte_Array := DECRPM_Query (2004);
   begin
      Assert
        (Query'Length >= 6,
         "DECRPM_Query mode 2004: result length should be >= 6");
      Assert
        (Query (Query'First) = ESC_BYTE,
         "DECRPM_Query mode 2004: first byte should be ESC (0x1B)");
      Assert
        (Query (Query'First + 1) = LSB_BYTE,
         "DECRPM_Query mode 2004: second byte should be [ (0x5B)");
      Assert
        (Query (Query'First + 2) = QM_BYTE,
         "DECRPM_Query mode 2004: third byte should be ? (0x3F)");
      Assert
        (Query (Query'Last) = P_BYTE,
         "DECRPM_Query mode 2004: last byte should be p (0x70)");
      Assert
        (Query (Query'Last - 1) = DOLL_BYTE,
         "DECRPM_Query mode 2004: second-to-last byte should be $ (0x24)");
      --  The digits for 2004 are '2', '0', '0', '4' after the ? prefix
      Assert
        (Query (Query'First + 3) = D_2,
         "DECRPM_Query mode 2004: fourth byte should be '2' (0x32)");
      Assert
        (Query (Query'First + 4) = D_0,
         "DECRPM_Query mode 2004: fifth byte should be '0' (0x30)");
      Assert
        (Query (Query'First + 5) = D_0,
         "DECRPM_Query mode 2004: sixth byte should be '0' (0x30)");
      Assert
        (Query (Query'First + 6) = D_4,
         "DECRPM_Query mode 2004: seventh byte should be '4' (0x34)");
   end Test_Query_Mode_2004;


   procedure Test_Query_Mode_0
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-RPM-017 Query case 3: Mode 0
      --  Expected: ESC [ ? 0 $ p  (6 bytes — minimum length per postcondition)
      Query : constant Byte_Array := DECRPM_Query (0);
   begin
      Assert
        (Query'Length = 6,
         "DECRPM_Query mode 0: result length should be exactly 6 (minimum)");
      Assert
        (Query (Query'First) = ESC_BYTE,
         "DECRPM_Query mode 0: first byte should be ESC (0x1B)");
      Assert
        (Query (Query'First + 1) = LSB_BYTE,
         "DECRPM_Query mode 0: second byte should be [ (0x5B)");
      Assert
        (Query (Query'First + 2) = QM_BYTE,
         "DECRPM_Query mode 0: third byte should be ? (0x3F)");
      --  Single digit '0' between ? and $ p
      Assert
        (Query (Query'First + 3) = D_0,
         "DECRPM_Query mode 0: fourth byte should be '0' (0x30)");
      Assert
        (Query (Query'First + 4) = DOLL_BYTE,
         "DECRPM_Query mode 0: fifth byte should be $ (0x24)");
      Assert
        (Query (Query'Last) = P_BYTE,
         "DECRPM_Query mode 0: last byte should be p (0x70)");
   end Test_Query_Mode_0;

end Test_DECRPM;
