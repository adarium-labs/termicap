-------------------------------------------------------------------------------
--  Test_Mouse - Unit Tests for Termicap.Mouse Pure Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Mouse; use Termicap.Mouse;
with Termicap.Mouse.IO;
with Termicap.DECRPM;
use Termicap;

package body Test_Mouse is

   use type Termicap.DECRPM.Mode_Status;

   ---------------------------------------------------------------------------
   --  Byte constant helpers
   ---------------------------------------------------------------------------

   ESC_BYTE  : constant Byte := 16#1B#;  --  ESC  (0x1B)
   CSI_BYTE  : constant Byte := 16#5B#;  --  '['  (0x5B)
   QUES_BYTE : constant Byte := 16#3F#;  --  '?'  (0x3F)
   SEMI_BYTE : constant Byte := 16#3B#;  --  ';'  (0x3B)
   DOLL_BYTE : constant Byte := 16#24#;  --  '$'  (0x24)
   Y_BYTE    : constant Byte := 16#79#;  --  'y'  (0x79)

   --  ASCII digit bytes
   D_0 : constant Byte := 16#30#;  --  '0'
   D_1 : constant Byte := 16#31#;  --  '1'
   D_2 : constant Byte := 16#32#;  --  '2'
   D_3 : constant Byte := 16#33#;  --  '3'
   D_4 : constant Byte := 16#34#;  --  '4'
   D_5 : constant Byte := 16#35#;  --  '5'  (out-of-range status)
   D_6 : constant Byte := 16#36#;  --  '6'
   D_P : constant Byte := 16#50#;  --  'P'  wrong CSI introducer
   D_X : constant Byte := 16#78#;  --  'x'  non-digit letter

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Mouse pure functions");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-MSE-001: Mouse_Encoding enumeration
      Register_Routine (T, Test_Encoding_Unknown_Is_First'Access, "FUNC-MSE-001: Unknown is Mouse_Encoding'First");
      Register_Routine (T, Test_Encoding_SGR_Pixels_Is_Last'Access, "FUNC-MSE-001: SGR_Pixels is Mouse_Encoding'Last");
      Register_Routine
        (T, Test_Encoding_Ordering'Access, "FUNC-MSE-001: Unknown < None < X10 < URXVT < SGR < SGR_Pixels");

      --  FUNC-MSE-002: Mouse_Capabilities record / NO_MOUSE_CAPABILITIES
      Register_Routine
        (T,
         Test_Default_Equals_No_Mouse_Capabilities'Access,
         "FUNC-MSE-002: default record equals NO_MOUSE_CAPABILITIES");
      Register_Routine
        (T,
         Test_No_Mouse_Capabilities_Best_Encoding'Access,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Best_Encoding = Unknown");
      Register_Routine
        (T,
         Test_No_Mouse_Capabilities_Supports_Flags'Access,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES all Supports_* = False");
      Register_Routine
        (T,
         Test_No_Mouse_Capabilities_Platform_And_Probed'Access,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES Win32/GPM/Probed = False");

      --  FUNC-MSE-003: MODE_MOUSE_* constants
      Register_Routine (T, Test_Mode_X10_Value'Access, "FUNC-MSE-003: MODE_MOUSE_X10 = 1000");
      Register_Routine (T, Test_Mode_Button_Event_Value'Access, "FUNC-MSE-003: MODE_MOUSE_BUTTON_EVENT = 1002");
      Register_Routine (T, Test_Mode_Any_Event_Value'Access, "FUNC-MSE-003: MODE_MOUSE_ANY_EVENT = 1003");
      Register_Routine (T, Test_Mode_URXVT_Value'Access, "FUNC-MSE-003: MODE_MOUSE_URXVT = 1015");
      Register_Routine (T, Test_Mode_SGR_Value'Access, "FUNC-MSE-003: MODE_MOUSE_SGR = 1006");
      Register_Routine (T, Test_Mode_SGR_Pixels_Value'Access, "FUNC-MSE-003: MODE_MOUSE_SGR_PIXELS = 1016");

      --  FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS constant
      Register_Routine (T, Test_Timeout_Value'Access, "FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS = 1000");
      Register_Routine (T, Test_Timeout_At_Least_100'Access, "FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS >= 100");

      --  FUNC-MSE-007: valid parse frames
      Register_Routine
        (T, Test_Parse_Mode_1000_Set'Access, "FUNC-MSE-007: ESC [ ? 1000 ; 1 $ y -> Valid=True, Mode=1000, Status=Set");
      Register_Routine
        (T,
         Test_Parse_Mode_1006_Reset'Access,
         "FUNC-MSE-007: ESC [ ? 1006 ; 2 $ y -> Valid=True, Mode=1006, Status=Reset");
      Register_Routine
        (T,
         Test_Parse_Mode_1016_Not_Recognized'Access,
         "FUNC-MSE-007: ESC [ ? 1016 ; 0 $ y -> Valid=True, Mode=1016, Status=Not_Recognized");
      Register_Routine
        (T,
         Test_Parse_Mode_1015_Permanently_Set'Access,
         "FUNC-MSE-007: ESC [ ? 1015 ; 3 $ y -> Valid=True, Mode=1015, Status=Permanently_Set");
      Register_Routine
        (T,
         Test_Parse_Mode_1002_Permanently_Reset'Access,
         "FUNC-MSE-007: ESC [ ? 1002 ; 4 $ y -> Valid=True, Mode=1002, Status=Permanently_Reset");

      --  FUNC-MSE-007: invalid parse frames
      Register_Routine
        (T, Test_Parse_Empty_Buffer'Access, "FUNC-MSE-007: empty buffer (Length=0) -> Valid=False, Mode=0");
      Register_Routine
        (T, Test_Parse_Too_Short'Access, "FUNC-MSE-007: buffer shorter than 8 bytes -> Valid=False, Mode=0");
      Register_Routine (T, Test_Parse_Missing_ESC'Access, "FUNC-MSE-007: missing ESC prefix -> Valid=False");
      Register_Routine (T, Test_Parse_Missing_CSI'Access, "FUNC-MSE-007: missing '[' (CSI byte) -> Valid=False");
      Register_Routine (T, Test_Parse_Missing_Question'Access, "FUNC-MSE-007: missing '?' -> Valid=False");
      Register_Routine
        (T, Test_Parse_No_Digit_After_Question'Access, "FUNC-MSE-007: no digit after '?' -> Valid=False");
      Register_Routine (T, Test_Parse_Missing_Semicolon'Access, "FUNC-MSE-007: missing ';' separator -> Valid=False");
      Register_Routine
        (T, Test_Parse_Status_Out_Of_Range'Access, "FUNC-MSE-007: status digit '5' out of range -> Valid=False");
      Register_Routine (T, Test_Parse_Missing_Dollar'Access, "FUNC-MSE-007: missing '$' suffix -> Valid=False");
      Register_Routine (T, Test_Parse_Missing_Y'Access, "FUNC-MSE-007: missing 'y' suffix -> Valid=False");
      Register_Routine (T, Test_Parse_Mode_Zero_Invalid'Access, "FUNC-MSE-007: Mode=0 in response -> Valid=False");
      Register_Routine (T, Test_Parse_Invalid_Mode_Is_Zero'Access, "FUNC-MSE-007: postcondition Valid=False => Mode=0");

      --  FUNC-MSE-008: Resolve_Best_Encoding cascade
      Register_Routine (T, Test_Cascade_Unprobed_Returns_Unknown'Access, "FUNC-MSE-008: Probed=False -> Unknown");
      Register_Routine (T, Test_Cascade_All_False_Returns_None'Access, "FUNC-MSE-008: Probed=True, all False -> None");
      Register_Routine (T, Test_Cascade_X10_Only'Access, "FUNC-MSE-008: Probed=True, Supports_X10 only -> X10");
      Register_Routine (T, Test_Cascade_URXVT_Only'Access, "FUNC-MSE-008: Probed=True, Supports_URXVT only -> URXVT");
      Register_Routine (T, Test_Cascade_URXVT_Over_X10'Access, "FUNC-MSE-008: Probed=True, X10+URXVT -> URXVT wins");
      Register_Routine (T, Test_Cascade_SGR_Only'Access, "FUNC-MSE-008: Probed=True, Supports_SGR only -> SGR");
      Register_Routine (T, Test_Cascade_SGR_Over_URXVT'Access, "FUNC-MSE-008: Probed=True, SGR+URXVT -> SGR wins");
      Register_Routine
        (T, Test_Cascade_SGR_Pixels_Only'Access, "FUNC-MSE-008: Probed=True, Supports_SGR_Pixels only -> SGR_Pixels");
      Register_Routine
        (T, Test_Cascade_All_True_Returns_SGR_Pixels'Access, "FUNC-MSE-008: Probed=True, all True -> SGR_Pixels wins");
      Register_Routine
        (T,
         Test_Cascade_Win32_Unprobed_Unknown'Access,
         "FUNC-MSE-008: Win32_Console_Mouse=True, Probed=False -> Unknown");
      Register_Routine
        (T, Test_Cascade_GPM_Unprobed_Unknown'Access, "FUNC-MSE-008: GPM_Available=True, Probed=False -> Unknown");

      --  FUNC-MSE-014 / FUNC-MSE-016: IO smoke tests
      Register_Routine
        (T, Test_Detect_No_Exception'Access, "FUNC-MSE-014: Detect_Mouse_Protocols returns without exception");
      Register_Routine
        (T, Test_Detect_Cache_Consistency'Access, "FUNC-MSE-016: Detect_Mouse_Protocols called twice -> same encoding");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-001: Mouse_Encoding enumeration
   ---------------------------------------------------------------------------

   procedure Test_Encoding_Unknown_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Mouse_Encoding'First = Unknown, "FUNC-MSE-001: Mouse_Encoding'First should be Unknown");
      Assert (Mouse_Encoding'Pos (Unknown) = 0, "FUNC-MSE-001: Unknown should have ordinal position 0");
   end Test_Encoding_Unknown_Is_First;

   procedure Test_Encoding_SGR_Pixels_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Mouse_Encoding'Last = SGR_Pixels, "FUNC-MSE-001: Mouse_Encoding'Last should be SGR_Pixels");
   end Test_Encoding_SGR_Pixels_Is_Last;

   procedure Test_Encoding_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Unknown < None, "FUNC-MSE-001: Unknown < None");
      Assert (None < X10, "FUNC-MSE-001: None < X10");
      Assert (X10 < URXVT, "FUNC-MSE-001: X10 < URXVT");
      Assert (URXVT < SGR, "FUNC-MSE-001: URXVT < SGR");
      Assert (SGR < SGR_Pixels, "FUNC-MSE-001: SGR < SGR_Pixels");
   end Test_Encoding_Ordering;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-002: Mouse_Capabilities record / NO_MOUSE_CAPABILITIES
   ---------------------------------------------------------------------------

   procedure Test_Default_Equals_No_Mouse_Capabilities (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Default_Caps : constant Mouse_Capabilities := (others => <>);
   begin
      Assert
        (Default_Caps.Best_Encoding = NO_MOUSE_CAPABILITIES.Best_Encoding,
         "FUNC-MSE-002: default Best_Encoding equals NO_MOUSE_CAPABILITIES.Best_Encoding");
      Assert
        (Default_Caps.Supports_X10 = NO_MOUSE_CAPABILITIES.Supports_X10,
         "FUNC-MSE-002: default Supports_X10 equals NO_MOUSE_CAPABILITIES.Supports_X10");
      Assert
        (Default_Caps.Supports_Button_Event = NO_MOUSE_CAPABILITIES.Supports_Button_Event,
         "FUNC-MSE-002: default Supports_Button_Event equals NO_MOUSE_CAPABILITIES");
      Assert
        (Default_Caps.Supports_Any_Event = NO_MOUSE_CAPABILITIES.Supports_Any_Event,
         "FUNC-MSE-002: default Supports_Any_Event equals NO_MOUSE_CAPABILITIES");
      Assert
        (Default_Caps.Supports_URXVT = NO_MOUSE_CAPABILITIES.Supports_URXVT,
         "FUNC-MSE-002: default Supports_URXVT equals NO_MOUSE_CAPABILITIES");
      Assert
        (Default_Caps.Supports_SGR = NO_MOUSE_CAPABILITIES.Supports_SGR,
         "FUNC-MSE-002: default Supports_SGR equals NO_MOUSE_CAPABILITIES");
      Assert
        (Default_Caps.Supports_SGR_Pixels = NO_MOUSE_CAPABILITIES.Supports_SGR_Pixels,
         "FUNC-MSE-002: default Supports_SGR_Pixels equals NO_MOUSE_CAPABILITIES");
      Assert
        (Default_Caps.Win32_Console_Mouse = NO_MOUSE_CAPABILITIES.Win32_Console_Mouse,
         "FUNC-MSE-002: default Win32_Console_Mouse equals NO_MOUSE_CAPABILITIES");
      Assert
        (Default_Caps.GPM_Available = NO_MOUSE_CAPABILITIES.GPM_Available,
         "FUNC-MSE-002: default GPM_Available equals NO_MOUSE_CAPABILITIES");
      Assert
        (Default_Caps.Probed = NO_MOUSE_CAPABILITIES.Probed,
         "FUNC-MSE-002: default Probed equals NO_MOUSE_CAPABILITIES");
   end Test_Default_Equals_No_Mouse_Capabilities;

   procedure Test_No_Mouse_Capabilities_Best_Encoding (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (NO_MOUSE_CAPABILITIES.Best_Encoding = Unknown,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Best_Encoding should be Unknown");
   end Test_No_Mouse_Capabilities_Best_Encoding;

   procedure Test_No_Mouse_Capabilities_Supports_Flags (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_MOUSE_CAPABILITIES.Supports_X10, "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Supports_X10 should be False");
      Assert
        (not NO_MOUSE_CAPABILITIES.Supports_Button_Event,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Supports_Button_Event should be False");
      Assert
        (not NO_MOUSE_CAPABILITIES.Supports_Any_Event,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Supports_Any_Event should be False");
      Assert
        (not NO_MOUSE_CAPABILITIES.Supports_URXVT,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Supports_URXVT should be False");
      Assert
        (not NO_MOUSE_CAPABILITIES.Supports_SGR, "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Supports_SGR should be False");
      Assert
        (not NO_MOUSE_CAPABILITIES.Supports_SGR_Pixels,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Supports_SGR_Pixels should be False");
   end Test_No_Mouse_Capabilities_Supports_Flags;

   procedure Test_No_Mouse_Capabilities_Platform_And_Probed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_MOUSE_CAPABILITIES.Win32_Console_Mouse,
         "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Win32_Console_Mouse should be False");
      Assert
        (not NO_MOUSE_CAPABILITIES.GPM_Available, "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.GPM_Available should be False");
      Assert (not NO_MOUSE_CAPABILITIES.Probed, "FUNC-MSE-002: NO_MOUSE_CAPABILITIES.Probed should be False");
   end Test_No_Mouse_Capabilities_Platform_And_Probed;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-003: MODE_MOUSE_* constants
   ---------------------------------------------------------------------------

   procedure Test_Mode_X10_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MODE_MOUSE_X10 = 1000, "FUNC-MSE-003: MODE_MOUSE_X10 should equal 1000");
   end Test_Mode_X10_Value;

   procedure Test_Mode_Button_Event_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MODE_MOUSE_BUTTON_EVENT = 1002, "FUNC-MSE-003: MODE_MOUSE_BUTTON_EVENT should equal 1002");
   end Test_Mode_Button_Event_Value;

   procedure Test_Mode_Any_Event_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MODE_MOUSE_ANY_EVENT = 1003, "FUNC-MSE-003: MODE_MOUSE_ANY_EVENT should equal 1003");
   end Test_Mode_Any_Event_Value;

   procedure Test_Mode_URXVT_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MODE_MOUSE_URXVT = 1015, "FUNC-MSE-003: MODE_MOUSE_URXVT should equal 1015");
   end Test_Mode_URXVT_Value;

   procedure Test_Mode_SGR_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MODE_MOUSE_SGR = 1006, "FUNC-MSE-003: MODE_MOUSE_SGR should equal 1006");
   end Test_Mode_SGR_Value;

   procedure Test_Mode_SGR_Pixels_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MODE_MOUSE_SGR_PIXELS = 1016, "FUNC-MSE-003: MODE_MOUSE_SGR_PIXELS should equal 1016");
   end Test_Mode_SGR_Pixels_Value;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS constant
   ---------------------------------------------------------------------------

   procedure Test_Timeout_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MOUSE_PROBE_TIMEOUT_MS = 1_000, "FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS should equal 1000");
   end Test_Timeout_Value;

   procedure Test_Timeout_At_Least_100 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (MOUSE_PROBE_TIMEOUT_MS >= 100, "FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS must be >= 100 (spec minimum)");
   end Test_Timeout_At_Least_100;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-007: Parse_Mouse_DECRPM_Response — valid frames
   --
   --  Frame layout: ESC [ ? <mode_digits> ; <status_digit> $ y
   --    ESC  = 0x1B,  '[' = 0x5B,  '?' = 0x3F,  ';' = 0x3B
   --    '$'  = 0x24,  'y' = 0x79
   ---------------------------------------------------------------------------

   procedure Test_Parse_Mode_1000_Set (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 0 ; 1 $ y  (11 bytes)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_0, SEMI_BYTE, D_1, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (Result.Valid, "FUNC-MSE-007: ESC [ ? 1000 ; 1 $ y -> Valid should be True");
      Assert (Result.Mode = 1000, "FUNC-MSE-007: ESC [ ? 1000 ; 1 $ y -> Mode should be 1000");
      Assert (Result.Status = Termicap.DECRPM.Set, "FUNC-MSE-007: ESC [ ? 1000 ; 1 $ y -> Status should be Set");
   end Test_Parse_Mode_1000_Set;

   procedure Test_Parse_Mode_1006_Reset (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 6 ; 2 $ y  (11 bytes)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_6, SEMI_BYTE, D_2, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (Result.Valid, "FUNC-MSE-007: ESC [ ? 1006 ; 2 $ y -> Valid should be True");
      Assert (Result.Mode = 1006, "FUNC-MSE-007: ESC [ ? 1006 ; 2 $ y -> Mode should be 1006");
      Assert (Result.Status = Termicap.DECRPM.Reset, "FUNC-MSE-007: ESC [ ? 1006 ; 2 $ y -> Status should be Reset");
   end Test_Parse_Mode_1006_Reset;

   procedure Test_Parse_Mode_1016_Not_Recognized (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 1 6 ; 0 $ y  (11 bytes)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_1, D_6, SEMI_BYTE, D_0, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (Result.Valid, "FUNC-MSE-007: ESC [ ? 1016 ; 0 $ y -> Valid should be True");
      Assert (Result.Mode = 1016, "FUNC-MSE-007: ESC [ ? 1016 ; 0 $ y -> Mode should be 1016");
      Assert
        (Result.Status = Termicap.DECRPM.Not_Recognized,
         "FUNC-MSE-007: ESC [ ? 1016 ; 0 $ y -> Status should be Not_Recognized");
   end Test_Parse_Mode_1016_Not_Recognized;

   procedure Test_Parse_Mode_1015_Permanently_Set (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 1 5 ; 3 $ y  (11 bytes)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_1, D_5, SEMI_BYTE, D_3, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (Result.Valid, "FUNC-MSE-007: ESC [ ? 1015 ; 3 $ y -> Valid should be True");
      Assert (Result.Mode = 1015, "FUNC-MSE-007: ESC [ ? 1015 ; 3 $ y -> Mode should be 1015");
      Assert
        (Result.Status = Termicap.DECRPM.Permanently_Set,
         "FUNC-MSE-007: ESC [ ? 1015 ; 3 $ y -> Status should be Permanently_Set");
   end Test_Parse_Mode_1015_Permanently_Set;

   procedure Test_Parse_Mode_1002_Permanently_Reset (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 2 ; 4 $ y  (11 bytes)
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_2, SEMI_BYTE, D_4, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (Result.Valid, "FUNC-MSE-007: ESC [ ? 1002 ; 4 $ y -> Valid should be True");
      Assert (Result.Mode = 1002, "FUNC-MSE-007: ESC [ ? 1002 ; 4 $ y -> Mode should be 1002");
      Assert
        (Result.Status = Termicap.DECRPM.Permanently_Reset,
         "FUNC-MSE-007: ESC [ ? 1002 ; 4 $ y -> Status should be Permanently_Reset");
   end Test_Parse_Mode_1002_Permanently_Reset;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-007: Parse_Mouse_DECRPM_Response — invalid frames
   ---------------------------------------------------------------------------

   procedure Test_Parse_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Length = 0: precondition Length <= Buffer'Length is satisfied (0 <= 4).
      Buf    : constant Byte_Array (1 .. 4) := [others => 0];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 0);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: empty buffer (Length=0) -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: empty buffer -> Mode should be 0 (postcondition)");
   end Test_Parse_Empty_Buffer;

   procedure Test_Parse_Too_Short (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  7-byte buffer: minimum well-formed frame is 8 bytes (ESC [ ? d ; s $ y
      --  where d is one digit and s is one digit).
      --  Use 7 bytes with otherwise-valid content to ensure the length check fires.
      Buf    : constant Byte_Array (1 .. 7) := [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, SEMI_BYTE, D_1, DOLL_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 7);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: 7-byte buffer -> Valid should be False (too short)");
      Assert (Result.Mode = 0, "FUNC-MSE-007: 7-byte buffer -> Mode should be 0 (postcondition)");
   end Test_Parse_Too_Short;

   procedure Test_Parse_Missing_ESC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Replace ESC (0x1B) with 'A' (0x41); rest is valid.
      Buf    : constant Byte_Array (1 .. 11) :=
        [16#41#, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_0, SEMI_BYTE, D_1, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: missing ESC prefix ('A' instead) -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: missing ESC -> Mode should be 0");
   end Test_Parse_Missing_ESC;

   procedure Test_Parse_Missing_CSI (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Replace '[' (0x5B) with 'P' (0x50 — DCS introducer); rest is valid.
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, D_P, QUES_BYTE, D_1, D_0, D_0, D_0, SEMI_BYTE, D_1, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: missing '[' (CSI byte 'P' instead) -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: missing '[' -> Mode should be 0");
   end Test_Parse_Missing_CSI;

   procedure Test_Parse_Missing_Question (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Replace '?' (0x3F) with '!' (0x21); rest is valid.
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, 16#21#, D_1, D_0, D_0, D_0, SEMI_BYTE, D_1, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: missing '?' ('!' instead) -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: missing '?' -> Mode should be 0");
   end Test_Parse_Missing_Question;

   procedure Test_Parse_No_Digit_After_Question (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Place ';' immediately after '?': ESC [ ? ; 1 $ y  (8 bytes).
      --  No mode digit -> invalid.
      Buf    : constant Byte_Array (1 .. 8) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, SEMI_BYTE, D_1, DOLL_BYTE, Y_BYTE, 16#00#];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 7);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: no digit after '?' (';' immediately) -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: no digit after '?' -> Mode should be 0");
   end Test_Parse_No_Digit_After_Question;

   procedure Test_Parse_Missing_Semicolon (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 0 1 $ y  — no ';'; status digit immediately follows mode digits.
      --  Parsing should fail: the character after the mode digits is not ';'.
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_0, D_1, DOLL_BYTE, Y_BYTE, 16#00#];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 10);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: missing ';' -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: missing ';' -> Mode should be 0");
   end Test_Parse_Missing_Semicolon;

   procedure Test_Parse_Status_Out_Of_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 0 ; 5 $ y  (11 bytes) — status digit '5' is outside 0..4.
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_0, SEMI_BYTE, D_5, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: status digit '5' out of range -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: status out of range -> Mode should be 0");
   end Test_Parse_Status_Out_Of_Range;

   procedure Test_Parse_Missing_Dollar (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 0 ; 1 x y  (11 bytes) — 'x' instead of '$'.
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_0, SEMI_BYTE, D_1, D_X, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: missing '$' ('x' instead) -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: missing '$' -> Mode should be 0");
   end Test_Parse_Missing_Dollar;

   procedure Test_Parse_Missing_Y (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 0 ; 1 $ x  (11 bytes) — 'x' instead of 'y'.
      Buf    : constant Byte_Array (1 .. 11) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, D_0, SEMI_BYTE, D_1, DOLL_BYTE, D_X];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 11);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: missing 'y' ('x' instead) -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: missing 'y' -> Mode should be 0");
   end Test_Parse_Missing_Y;

   procedure Test_Parse_Mode_Zero_Invalid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 0 ; 1 $ y  (8 bytes) — Mode = 0 is invalid per spec postcondition.
      Buf    : constant Byte_Array (1 .. 8) := [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_0, SEMI_BYTE, D_1, DOLL_BYTE, Y_BYTE];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 8);
   begin
      --  Mode 0 is not a valid DEC private mode; the parser must reject it.
      --  When Valid=False the postcondition guarantees Mode=0.
      Assert (not Result.Valid, "FUNC-MSE-007: Mode=0 in response -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: Mode=0 in response -> Mode should be 0 (postcondition)");
   end Test_Parse_Mode_Zero_Invalid;

   procedure Test_Parse_Invalid_Mode_Is_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Use a clearly malformed buffer (all zeros) and verify the postcondition
      --  Valid=False => Mode=0.
      Buf    : constant Byte_Array (1 .. 12) := [others => 0];
      Result : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Buf, 12);
   begin
      Assert (not Result.Valid, "FUNC-MSE-007: all-zero buffer -> Valid should be False");
      Assert (Result.Mode = 0, "FUNC-MSE-007: postcondition not Valid => Mode = 0 (all-zero buffer)");
   end Test_Parse_Invalid_Mode_Is_Zero;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-008: Resolve_Best_Encoding cascade
   ---------------------------------------------------------------------------

   procedure Test_Cascade_Unprobed_Returns_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Probed=False; all Supports_* flags True — must still return Unknown.
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => True,
         Supports_Button_Event => True,
         Supports_Any_Event    => True,
         Supports_URXVT        => True,
         Supports_SGR          => True,
         Supports_SGR_Pixels   => True,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => False);
   begin
      Assert (Resolve_Best_Encoding (Caps) = Unknown, "FUNC-MSE-008: Probed=False with all flags True -> Unknown");
   end Test_Cascade_Unprobed_Returns_Unknown;

   procedure Test_Cascade_All_False_Returns_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Probed=True; all Supports_* False -> None.
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => False,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => False,
         Supports_SGR          => False,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert (Resolve_Best_Encoding (Caps) = None, "FUNC-MSE-008: Probed=True, all False -> None");
   end Test_Cascade_All_False_Returns_None;

   procedure Test_Cascade_X10_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => True,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => False,
         Supports_SGR          => False,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert (Resolve_Best_Encoding (Caps) = X10, "FUNC-MSE-008: Probed=True, Supports_X10 only -> X10");
   end Test_Cascade_X10_Only;

   procedure Test_Cascade_URXVT_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => False,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => True,
         Supports_SGR          => False,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert (Resolve_Best_Encoding (Caps) = URXVT, "FUNC-MSE-008: Probed=True, Supports_URXVT only -> URXVT");
   end Test_Cascade_URXVT_Only;

   procedure Test_Cascade_URXVT_Over_X10 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => True,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => True,
         Supports_SGR          => False,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert (Resolve_Best_Encoding (Caps) = URXVT, "FUNC-MSE-008: Probed=True, X10+URXVT -> URXVT wins over X10");
   end Test_Cascade_URXVT_Over_X10;

   procedure Test_Cascade_SGR_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => False,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => False,
         Supports_SGR          => True,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert (Resolve_Best_Encoding (Caps) = SGR, "FUNC-MSE-008: Probed=True, Supports_SGR only -> SGR");
   end Test_Cascade_SGR_Only;

   procedure Test_Cascade_SGR_Over_URXVT (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => False,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => True,
         Supports_SGR          => True,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert (Resolve_Best_Encoding (Caps) = SGR, "FUNC-MSE-008: Probed=True, SGR+URXVT -> SGR wins over URXVT");
   end Test_Cascade_SGR_Over_URXVT;

   procedure Test_Cascade_SGR_Pixels_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => False,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => False,
         Supports_SGR          => False,
         Supports_SGR_Pixels   => True,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert
        (Resolve_Best_Encoding (Caps) = SGR_Pixels,
         "FUNC-MSE-008: Probed=True, Supports_SGR_Pixels only -> SGR_Pixels");
   end Test_Cascade_SGR_Pixels_Only;

   procedure Test_Cascade_All_True_Returns_SGR_Pixels (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => True,
         Supports_Button_Event => True,
         Supports_Any_Event    => True,
         Supports_URXVT        => True,
         Supports_SGR          => True,
         Supports_SGR_Pixels   => True,
         Win32_Console_Mouse   => False,
         GPM_Available         => False,
         Probed                => True);
   begin
      Assert
        (Resolve_Best_Encoding (Caps) = SGR_Pixels, "FUNC-MSE-008: Probed=True, all True -> SGR_Pixels (highest wins)");
   end Test_Cascade_All_True_Returns_SGR_Pixels;

   procedure Test_Cascade_Win32_Unprobed_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Win32 path: Win32_Console_Mouse=True, Probed=False -> Unknown.
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => False,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => False,
         Supports_SGR          => False,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => True,
         GPM_Available         => False,
         Probed                => False);
   begin
      Assert
        (Resolve_Best_Encoding (Caps) = Unknown, "FUNC-MSE-008: Win32_Console_Mouse=True, Probed=False -> Unknown");
   end Test_Cascade_Win32_Unprobed_Unknown;

   procedure Test_Cascade_GPM_Unprobed_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  GPM path: GPM_Available=True, Probed=False -> Unknown.
      Caps : constant Mouse_Capabilities :=
        (Best_Encoding         => Unknown,
         Supports_X10          => False,
         Supports_Button_Event => False,
         Supports_Any_Event    => False,
         Supports_URXVT        => False,
         Supports_SGR          => False,
         Supports_SGR_Pixels   => False,
         Win32_Console_Mouse   => False,
         GPM_Available         => True,
         Probed                => False);
   begin
      Assert (Resolve_Best_Encoding (Caps) = Unknown, "FUNC-MSE-008: GPM_Available=True, Probed=False -> Unknown");
   end Test_Cascade_GPM_Unprobed_Unknown;


   ---------------------------------------------------------------------------
   --  FUNC-MSE-014 / FUNC-MSE-016: IO-level smoke tests
   ---------------------------------------------------------------------------

   procedure Test_Detect_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-MSE-014: Detect_Mouse_Protocols must not raise any exception.
      --  On a stub or non-TTY build this returns NO_MOUSE_CAPABILITIES.
      --  We only verify the no-exception contract; the returned value is
      --  environment-dependent and not asserted here.
      Result : Mouse_Capabilities;
   begin
      Result := Termicap.Mouse.IO.Detect_Mouse_Protocols;
      --  Verify the result is a valid Mouse_Capabilities (fields in range).
      Assert
        (Result.Best_Encoding in Mouse_Encoding'Range,
         "FUNC-MSE-014: Detect_Mouse_Protocols Best_Encoding in valid range");
   end Test_Detect_No_Exception;

   procedure Test_Detect_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-MSE-016: Detect_Mouse_Protocols called twice must return
      --  the same Best_Encoding (cache consistency).
      First  : constant Mouse_Capabilities := Termicap.Mouse.IO.Detect_Mouse_Protocols;
      Second : constant Mouse_Capabilities := Termicap.Mouse.IO.Detect_Mouse_Protocols;
   begin
      Assert
        (First.Best_Encoding = Second.Best_Encoding,
         "FUNC-MSE-016: two calls to Detect_Mouse_Protocols -> same Best_Encoding");
      Assert (First.Probed = Second.Probed, "FUNC-MSE-016: two calls to Detect_Mouse_Protocols -> same Probed flag");
   end Test_Detect_Cache_Consistency;

end Test_Mouse;
