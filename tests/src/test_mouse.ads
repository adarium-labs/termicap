-------------------------------------------------------------------------------
--  Test_Mouse - Unit Tests for Termicap.Mouse Pure Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK types, constants, and functions
--  in Termicap.Mouse: Mouse_Encoding enumeration, Mouse_Capabilities record,
--  MODE_MOUSE_* constants, MOUSE_PROBE_TIMEOUT_MS, Parse_Mouse_DECRPM_Response,
--  and Resolve_Best_Encoding.
--
--  All tests construct Byte_Array values programmatically and require no live
--  terminal; every test vector is deterministic.
--
--  The IO-level smoke tests (Detect_Mouse_Protocols / Probe_Mouse_Protocols)
--  call Termicap.Mouse.IO functions which return NO_MOUSE_CAPABILITIES on
--  stub implementations; these tests verify the no-exception contract only.
--
--  Requirements Coverage:
--    - @relation(FUNC-MSE-001): Mouse_Encoding enumeration (3 vectors)
--    - @relation(FUNC-MSE-002): Mouse_Capabilities record / NO_MOUSE_CAPABILITIES (4 vectors)
--    - @relation(FUNC-MSE-003): MODE_MOUSE_* constants (6 vectors)
--    - @relation(FUNC-MSE-013): MOUSE_PROBE_TIMEOUT_MS constant (2 vectors)
--    - @relation(FUNC-MSE-007): Parse_Mouse_DECRPM_Response (16 vectors)
--    - @relation(FUNC-MSE-008): Resolve_Best_Encoding (11 vectors)
--    - @relation(FUNC-MSE-014): Detect / Probe no-exception contract (2 vectors)
--    - @relation(FUNC-MSE-016): Cache consistency (1 vector)

with AUnit.Test_Cases;

package Test_Mouse is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-001: Mouse_Encoding enumeration
   ---------------------------------------------------------------------------

   --  FUNC-MSE-001: enumeration values exist and Unknown is Mouse_Encoding'First
   procedure Test_Encoding_Unknown_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-001: SGR_Pixels is Mouse_Encoding'Last
   procedure Test_Encoding_SGR_Pixels_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-001: full ordering Unknown < None < X10 < URXVT < SGR < SGR_Pixels
   procedure Test_Encoding_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-002: Mouse_Capabilities record and NO_MOUSE_CAPABILITIES
   ---------------------------------------------------------------------------

   --  FUNC-MSE-002: default-initialised record equals NO_MOUSE_CAPABILITIES
   procedure Test_Default_Equals_No_Mouse_Capabilities (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-002: NO_MOUSE_CAPABILITIES has Best_Encoding = Unknown
   procedure Test_No_Mouse_Capabilities_Best_Encoding (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-002: NO_MOUSE_CAPABILITIES has all Supports_* = False
   procedure Test_No_Mouse_Capabilities_Supports_Flags (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-002: NO_MOUSE_CAPABILITIES has Win32/GPM/Probed = False
   procedure Test_No_Mouse_Capabilities_Platform_And_Probed (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-003: MODE_MOUSE_* constants
   ---------------------------------------------------------------------------

   --  FUNC-MSE-003: MODE_MOUSE_X10 = 1000
   procedure Test_Mode_X10_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-003: MODE_MOUSE_BUTTON_EVENT = 1002
   procedure Test_Mode_Button_Event_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-003: MODE_MOUSE_ANY_EVENT = 1003
   procedure Test_Mode_Any_Event_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-003: MODE_MOUSE_URXVT = 1015
   procedure Test_Mode_URXVT_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-003: MODE_MOUSE_SGR = 1006
   procedure Test_Mode_SGR_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-003: MODE_MOUSE_SGR_PIXELS = 1016
   procedure Test_Mode_SGR_Pixels_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS constant
   ---------------------------------------------------------------------------

   --  FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS = 1000
   procedure Test_Timeout_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-013: MOUSE_PROBE_TIMEOUT_MS >= 100 (spec minimum)
   procedure Test_Timeout_At_Least_100 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-007: Parse_Mouse_DECRPM_Response — valid frames
   ---------------------------------------------------------------------------

   --  FUNC-MSE-007: ESC [ ? 1 0 0 0 ; 1 $ y -> Valid=True, Mode=1000, Status=Set
   procedure Test_Parse_Mode_1000_Set (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: ESC [ ? 1 0 0 6 ; 2 $ y -> Valid=True, Mode=1006, Status=Reset
   procedure Test_Parse_Mode_1006_Reset (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: ESC [ ? 1 0 1 6 ; 0 $ y -> Valid=True, Mode=1016, Status=Not_Recognized
   procedure Test_Parse_Mode_1016_Not_Recognized (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: ESC [ ? 1 0 1 5 ; 3 $ y -> Valid=True, Mode=1015, Status=Permanently_Set
   procedure Test_Parse_Mode_1015_Permanently_Set (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: ESC [ ? 1 0 0 2 ; 4 $ y -> Valid=True, Mode=1002, Status=Permanently_Reset
   procedure Test_Parse_Mode_1002_Permanently_Reset (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-007: Parse_Mouse_DECRPM_Response — invalid frames
   ---------------------------------------------------------------------------

   --  FUNC-MSE-007: empty buffer (Length=0) -> Valid=False, Mode=0
   procedure Test_Parse_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: buffer shorter than 8 bytes -> Valid=False, Mode=0
   procedure Test_Parse_Too_Short (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: missing ESC prefix -> Valid=False
   procedure Test_Parse_Missing_ESC (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: missing '[' (CSI byte) -> Valid=False
   procedure Test_Parse_Missing_CSI (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: missing '?' -> Valid=False
   procedure Test_Parse_Missing_Question (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: no digit after '?' (semicolon immediately after '?') -> Valid=False
   procedure Test_Parse_No_Digit_After_Question (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: missing ';' separator -> Valid=False
   procedure Test_Parse_Missing_Semicolon (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: status digit out of range (digit '5') -> Valid=False
   procedure Test_Parse_Status_Out_Of_Range (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: missing '$' suffix -> Valid=False
   procedure Test_Parse_Missing_Dollar (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: missing 'y' suffix -> Valid=False
   procedure Test_Parse_Missing_Y (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: Mode=0 in response (treated as invalid) -> Valid=False
   procedure Test_Parse_Mode_Zero_Invalid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-007: postcondition Valid=False => Mode=0 (invariant check)
   procedure Test_Parse_Invalid_Mode_Is_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-008: Resolve_Best_Encoding cascade
   ---------------------------------------------------------------------------

   --  FUNC-MSE-008: Probed=False -> Unknown regardless of Supports_* flags
   procedure Test_Cascade_Unprobed_Returns_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, all Supports_* False -> None
   procedure Test_Cascade_All_False_Returns_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, only Supports_X10=True -> X10
   procedure Test_Cascade_X10_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, only Supports_URXVT=True -> URXVT
   procedure Test_Cascade_URXVT_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, Supports_X10=True and Supports_URXVT=True -> URXVT wins
   procedure Test_Cascade_URXVT_Over_X10 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, only Supports_SGR=True -> SGR
   procedure Test_Cascade_SGR_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, Supports_SGR=True and Supports_URXVT=True -> SGR wins
   procedure Test_Cascade_SGR_Over_URXVT (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, only Supports_SGR_Pixels=True -> SGR_Pixels
   procedure Test_Cascade_SGR_Pixels_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Probed=True, all Supports_* True -> SGR_Pixels wins
   procedure Test_Cascade_All_True_Returns_SGR_Pixels (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: Win32_Console_Mouse=True, Probed=False -> Unknown
   procedure Test_Cascade_Win32_Unprobed_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-008: GPM_Available=True, Probed=False -> Unknown
   procedure Test_Cascade_GPM_Unprobed_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-MSE-014, FUNC-MSE-016: IO-level smoke tests
   ---------------------------------------------------------------------------

   --  FUNC-MSE-014: Detect_Mouse_Protocols returns without exception
   procedure Test_Detect_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-MSE-016: Calling Detect_Mouse_Protocols twice returns same encoding
   procedure Test_Detect_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Mouse;
