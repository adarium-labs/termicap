-------------------------------------------------------------------------------
--  Test_Graphics - Unit Tests for Termicap.Graphics Pure Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK types, constants, and functions
--  in Termicap.Graphics: Graphics_Capabilities record, NO_GRAPHICS_CAPABILITIES,
--  named terminal identifier constants, KITTY_APC_QUERY bytes,
--  APC_Parse_Result enumeration, and Parse_Kitty_APC_Response.
--
--  All tests construct Byte_Array values programmatically and require no live
--  terminal; every test vector is deterministic.
--
--  The IO-level smoke tests call Termicap.Graphics.IO functions which return
--  NO_GRAPHICS_CAPABILITIES on non-TTY builds; these tests verify the
--  no-exception contract only.
--
--  Requirements Coverage:
--    - @relation(FUNC-SXL-001): Graphics_Capabilities record / NO_GRAPHICS_CAPABILITIES (5 vectors)
--    - @relation(FUNC-SXL-002): Sixel_Color_Registers optional field (1 vector)
--    - @relation(FUNC-SXL-003): Kitty_Graphics_Version optional field (1 vector)
--    - @relation(FUNC-SXL-004): Named terminal identifier constants (11 vectors)
--    - @relation(FUNC-SXL-010): KITTY_APC_QUERY constant (4 vectors)
--    - @relation(FUNC-SXL-011): APC_Parse_Result / Parse_Kitty_APC_Response (16 vectors)
--    - @relation(FUNC-SXL-015): GRAPHICS_PROBE_TIMEOUT_MS constant (2 vectors)
--    - @relation(FUNC-SXL-016): Detect_Graphics no-exception contract (2 vectors)
--    - @relation(FUNC-SXL-017): Cache consistency (1 vector)

with AUnit.Test_Cases;

package Test_Graphics is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-001: Graphics_Capabilities record / NO_GRAPHICS_CAPABILITIES
   ---------------------------------------------------------------------------

   --  FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES has Sixel_Supported = False
   procedure Test_No_Graphics_Sixel_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES has Kitty_Graphics_Supported = False
   procedure Test_No_Graphics_Kitty_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES has all provenance flags False
   procedure Test_No_Graphics_Provenance_Flags_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES has Probed = False
   procedure Test_No_Graphics_Probed_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-001: default-initialised Graphics_Capabilities equals NO_GRAPHICS_CAPABILITIES
   procedure Test_Default_Equals_No_Graphics_Capabilities (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-001: setting Sixel_Supported does not affect Kitty_Graphics_Supported (independence)
   procedure Test_Sixel_Independent_Of_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-001: provenance flags are independent of support flags
   procedure Test_Provenance_Independent_Of_Support (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-002: Sixel_Color_Registers optional field
   ---------------------------------------------------------------------------

   --  FUNC-SXL-002: NO_GRAPHICS_CAPABILITIES.Sixel_Color_Registers = 0
   procedure Test_No_Graphics_Color_Registers_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-003: Kitty_Graphics_Version optional field
   ---------------------------------------------------------------------------

   --  FUNC-SXL-003: NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Version = 0
   procedure Test_No_Graphics_Version_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-004: Named terminal identifier constants
   ---------------------------------------------------------------------------

   --  FUNC-SXL-004: TERM_XTERM_KITTY = "xterm-kitty"
   procedure Test_Constant_Term_Xterm_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: TERM_FOOT = "foot"
   procedure Test_Constant_Term_Foot (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: TERM_FOOT_EXTRA = "foot-extra"
   procedure Test_Constant_Term_Foot_Extra (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: TERM_XTERM = "xterm"
   procedure Test_Constant_Term_Xterm (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: TERM_MLTERM = "mlterm"
   procedure Test_Constant_Term_Mlterm (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: TERM_YAFT = "yaft"
   procedure Test_Constant_Term_Yaft (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: TERM_PROGRAM_WEZTERM = "WezTerm"
   procedure Test_Constant_Term_Program_Wezterm (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: TERM_PROGRAM_ITERM2 = "iTerm.app"
   procedure Test_Constant_Term_Program_Iterm2 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: ENV_KITTY_WINDOW_ID = "KITTY_WINDOW_ID"
   procedure Test_Constant_Env_Kitty_Window_Id (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: XTVERSION_NAME_KITTY = "kitty"
   procedure Test_Constant_Xtversion_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-004: XTVERSION_NAME_WEZTERM = "WezTerm"
   procedure Test_Constant_Xtversion_Wezterm (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-010: KITTY_APC_QUERY constant
   ---------------------------------------------------------------------------

   --  FUNC-SXL-010: KITTY_APC_QUERY has length 12
   procedure Test_Apc_Query_Length (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-010: KITTY_APC_QUERY starts with ESC _ (0x1B 0x5F)
   procedure Test_Apc_Query_Starts_With_ESC_Underscore (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-010: KITTY_APC_QUERY ends with ESC \ (0x1B 0x5C)
   procedure Test_Apc_Query_Ends_With_ST (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-010: KITTY_APC_QUERY payload contains "Gi=1,a=q" as ASCII bytes
   procedure Test_Apc_Query_Payload_Content (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: APC_Parse_Result enumeration
   ---------------------------------------------------------------------------

   --  FUNC-SXL-011: APC_Parse_Result literals are distinct (Not_Present /= OK)
   procedure Test_Apc_Result_Not_Present_Neq_OK (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: OK /= Error
   procedure Test_Apc_Result_OK_Neq_Error (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: Not_Present /= Error
   procedure Test_Apc_Result_Not_Present_Neq_Error (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — Not_Present cases
   ---------------------------------------------------------------------------

   --  FUNC-SXL-011: empty buffer (Length=0) -> Not_Present
   procedure Test_Parse_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: buffer with no APC sequence -> Not_Present
   procedure Test_Parse_No_Apc_Sequence (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: DA1 response only (no APC) -> Not_Present
   procedure Test_Parse_Da1_Response_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: partial APC (no ST terminator) -> Not_Present
   procedure Test_Parse_Partial_Apc_No_St (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: Length = 0 on non-empty buffer -> Not_Present
   procedure Test_Parse_Length_Zero_Non_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — OK case
   ---------------------------------------------------------------------------

   --  FUNC-SXL-011: ESC _ G OK ESC \ -> OK
   procedure Test_Parse_Apc_OK (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: APC with "OK" substring embedded in longer params -> OK
   procedure Test_Parse_Apc_OK_Embedded (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: APC before DA1 response -> OK extracted from APC
   procedure Test_Parse_Apc_Before_Da1 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — Error case
   ---------------------------------------------------------------------------

   --  FUNC-SXL-011: ESC _ G EINVAL ESC \ -> Error
   procedure Test_Parse_Apc_Error (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: APC with "EINVAL" substring embedded in longer params -> Error
   procedure Test_Parse_Apc_Error_Embedded (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — boundary / robustness
   ---------------------------------------------------------------------------

   --  FUNC-SXL-011: Length < Buffer'Length uses only the valid slice
   procedure Test_Parse_Partial_Fill (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-011: multiple APC sequences -> first APC G result used
   procedure Test_Parse_Multiple_Apc_First_Used (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS constant
   ---------------------------------------------------------------------------

   --  FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS = 1000
   procedure Test_Timeout_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS >= 100 (spec minimum)
   procedure Test_Timeout_At_Least_100 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-SXL-016, FUNC-SXL-017: IO-level smoke tests
   ---------------------------------------------------------------------------

   --  FUNC-SXL-016: Detect_Graphics returns without exception
   procedure Test_Detect_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SXL-017: Calling Detect_Graphics twice returns same Probed flag (cache consistency)
   procedure Test_Detect_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Graphics;
