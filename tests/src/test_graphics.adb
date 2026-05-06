-------------------------------------------------------------------------------
--  Test_Graphics - Unit Tests for Termicap.Graphics Pure Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Interfaces.C;

with Termicap.Graphics; use Termicap.Graphics;
with Termicap.Graphics.IO;
use Termicap;

package body Test_Graphics is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Byte constant helpers (ESC sequences for APC parse tests)
   ---------------------------------------------------------------------------

   ESC_BYTE  : constant Byte := 16#1B#;  --  ESC   (0x1B)
   APC_BYTE  : constant Byte := 16#5F#;  --  '_'   (0x5F, APC introducer)
   ST_BYTE   : constant Byte := 16#5C#;  --  '\'   (0x5C, ST terminator)
   CSI_BYTE  : constant Byte := 16#5B#;  --  '['   (0x5B, CSI)
   G_BYTE    : constant Byte := Character'Pos ('G');  --  'G' (0x47)
   O_BYTE    : constant Byte := Character'Pos ('O');  --  'O' (0x4F)
   K_BYTE    : constant Byte := Character'Pos ('K');  --  'K' (0x4B)
   E_BYTE    : constant Byte := Character'Pos ('E');  --  'E' (0x45)
   I_BYTE    : constant Byte := Character'Pos ('I');  --  'I' (0x49)
   N_BYTE    : constant Byte := Character'Pos ('N');  --  'N' (0x4E)
   V_BYTE    : constant Byte := Character'Pos ('V');  --  'V' (0x56)
   A_BYTE    : constant Byte := Character'Pos ('A');  --  'A' (0x41)
   L_BYTE    : constant Byte := Character'Pos ('L');  --  'L' (0x4C)
   QUES_BYTE : constant Byte := 16#3F#;  --  '?'   (0x3F)
   SEMI_BYTE : constant Byte := 16#3B#;  --  ';'   (0x3B)
   C_BYTE    : constant Byte := Character'Pos ('c');  --  'c' (0x63, DA1 final)
   D_6       : constant Byte := 16#36#;  --  '6'
   SPACE     : constant Byte := 16#20#;  --  space (filler / noise)

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Graphics pure functions");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-SXL-001: Graphics_Capabilities record / NO_GRAPHICS_CAPABILITIES
      Register_Routine
        (T, Test_No_Graphics_Sixel_False'Access, "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Sixel_Supported = False");
      Register_Routine
        (T,
         Test_No_Graphics_Kitty_False'Access,
         "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Supported = False");
      Register_Routine
        (T,
         Test_No_Graphics_Provenance_Flags_False'Access,
         "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES provenance flags all False");
      Register_Routine
        (T, Test_No_Graphics_Probed_False'Access, "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Probed = False");
      Register_Routine
        (T,
         Test_Default_Equals_No_Graphics_Capabilities'Access,
         "FUNC-SXL-001: default record equals NO_GRAPHICS_CAPABILITIES");
      Register_Routine
        (T, Test_Sixel_Independent_Of_Kitty'Access, "FUNC-SXL-001: Sixel_Supported independent of Kitty field");
      Register_Routine
        (T,
         Test_Provenance_Independent_Of_Support'Access,
         "FUNC-SXL-001: provenance flags independent of support flags");

      --  FUNC-SXL-002: Sixel_Color_Registers optional field
      Register_Routine
        (T,
         Test_No_Graphics_Color_Registers_Zero'Access,
         "FUNC-SXL-002: NO_GRAPHICS_CAPABILITIES.Sixel_Color_Registers = 0");

      --  FUNC-SXL-003: Kitty_Graphics_Version optional field
      Register_Routine
        (T, Test_No_Graphics_Version_Zero'Access, "FUNC-SXL-003: NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Version = 0");

      --  FUNC-SXL-004: Named terminal identifier constants
      Register_Routine (T, Test_Constant_Term_Xterm_Kitty'Access, "FUNC-SXL-004: TERM_XTERM_KITTY = ""xterm-kitty""");
      Register_Routine (T, Test_Constant_Term_Foot'Access, "FUNC-SXL-004: TERM_FOOT = ""foot""");
      Register_Routine (T, Test_Constant_Term_Foot_Extra'Access, "FUNC-SXL-004: TERM_FOOT_EXTRA = ""foot-extra""");
      Register_Routine (T, Test_Constant_Term_Xterm'Access, "FUNC-SXL-004: TERM_XTERM = ""xterm""");
      Register_Routine (T, Test_Constant_Term_Mlterm'Access, "FUNC-SXL-004: TERM_MLTERM = ""mlterm""");
      Register_Routine (T, Test_Constant_Term_Yaft'Access, "FUNC-SXL-004: TERM_YAFT = ""yaft""");
      Register_Routine
        (T, Test_Constant_Term_Program_Wezterm'Access, "FUNC-SXL-004: TERM_PROGRAM_WEZTERM = ""WezTerm""");
      Register_Routine
        (T, Test_Constant_Term_Program_Iterm2'Access, "FUNC-SXL-004: TERM_PROGRAM_ITERM2 = ""iTerm.app""");
      Register_Routine
        (T, Test_Constant_Env_Kitty_Window_Id'Access, "FUNC-SXL-004: ENV_KITTY_WINDOW_ID = ""KITTY_WINDOW_ID""");
      Register_Routine (T, Test_Constant_Xtversion_Kitty'Access, "FUNC-SXL-004: XTVERSION_NAME_KITTY = ""kitty""");
      Register_Routine
        (T, Test_Constant_Xtversion_Wezterm'Access, "FUNC-SXL-004: XTVERSION_NAME_WEZTERM = ""WezTerm""");

      --  FUNC-SXL-010: KITTY_APC_QUERY constant
      Register_Routine (T, Test_Apc_Query_Length'Access, "FUNC-SXL-010: KITTY_APC_QUERY length = 12");
      Register_Routine
        (T,
         Test_Apc_Query_Starts_With_ESC_Underscore'Access,
         "FUNC-SXL-010: KITTY_APC_QUERY starts with ESC _ (0x1B 0x5F)");
      Register_Routine
        (T, Test_Apc_Query_Ends_With_ST'Access, "FUNC-SXL-010: KITTY_APC_QUERY ends with ESC \\ (0x1B 0x5C)");
      Register_Routine
        (T, Test_Apc_Query_Payload_Content'Access, "FUNC-SXL-010: KITTY_APC_QUERY payload contains ""Gi=1,a=q""");

      --  FUNC-SXL-011: APC_Parse_Result enumeration distinctness
      Register_Routine
        (T, Test_Apc_Result_Not_Present_Neq_OK'Access, "FUNC-SXL-011: APC_Parse_Result Not_Present /= OK");
      Register_Routine (T, Test_Apc_Result_OK_Neq_Error'Access, "FUNC-SXL-011: APC_Parse_Result OK /= Error");
      Register_Routine
        (T, Test_Apc_Result_Not_Present_Neq_Error'Access, "FUNC-SXL-011: APC_Parse_Result Not_Present /= Error");

      --  FUNC-SXL-011: Parse_Kitty_APC_Response — Not_Present cases
      Register_Routine (T, Test_Parse_Empty_Buffer'Access, "FUNC-SXL-011: empty buffer (Length=0) -> Not_Present");
      Register_Routine
        (T, Test_Parse_No_Apc_Sequence'Access, "FUNC-SXL-011: buffer with no APC sequence -> Not_Present");
      Register_Routine
        (T, Test_Parse_Da1_Response_Only'Access, "FUNC-SXL-011: DA1 response only (no APC) -> Not_Present");
      Register_Routine
        (T, Test_Parse_Partial_Apc_No_St'Access, "FUNC-SXL-011: partial APC (no ST terminator) -> Not_Present");
      Register_Routine
        (T,
         Test_Parse_Length_Zero_Non_Empty_Buffer'Access,
         "FUNC-SXL-011: Length=0 on non-empty buffer -> Not_Present");

      --  FUNC-SXL-011: Parse_Kitty_APC_Response — OK case
      Register_Routine (T, Test_Parse_Apc_OK'Access, "FUNC-SXL-011: ESC _ G OK ESC \\ -> OK");
      Register_Routine
        (T, Test_Parse_Apc_OK_Embedded'Access, "FUNC-SXL-011: APC with ""OK"" embedded in longer params -> OK");
      Register_Routine (T, Test_Parse_Apc_Before_Da1'Access, "FUNC-SXL-011: APC OK before DA1 response -> OK");

      --  FUNC-SXL-011: Parse_Kitty_APC_Response — Error case
      Register_Routine (T, Test_Parse_Apc_Error'Access, "FUNC-SXL-011: ESC _ G EINVAL ESC \\ -> Error");
      Register_Routine
        (T,
         Test_Parse_Apc_Error_Embedded'Access,
         "FUNC-SXL-011: APC with ""EINVAL"" embedded in longer params -> Error");

      --  FUNC-SXL-011: Parse_Kitty_APC_Response — boundary / robustness
      Register_Routine
        (T, Test_Parse_Partial_Fill'Access, "FUNC-SXL-011: Length < Buffer'Length uses only the valid slice");
      Register_Routine
        (T,
         Test_Parse_Multiple_Apc_First_Used'Access,
         "FUNC-SXL-011: multiple APC sequences -> first APC G result used");

      --  FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS constant
      Register_Routine (T, Test_Timeout_Value'Access, "FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS = 1000");
      Register_Routine (T, Test_Timeout_At_Least_100'Access, "FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS >= 100");

      --  FUNC-SXL-016 / FUNC-SXL-017: IO smoke tests
      Register_Routine (T, Test_Detect_No_Exception'Access, "FUNC-SXL-016: Detect_Graphics returns without exception");
      Register_Routine
        (T, Test_Detect_Cache_Consistency'Access, "FUNC-SXL-017: Detect_Graphics called twice -> same Probed flag");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-001: Graphics_Capabilities record / NO_GRAPHICS_CAPABILITIES
   ---------------------------------------------------------------------------

   procedure Test_No_Graphics_Sixel_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_GRAPHICS_CAPABILITIES.Sixel_Supported,
         "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Sixel_Supported should be False");
   end Test_No_Graphics_Sixel_False;

   procedure Test_No_Graphics_Kitty_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Supported,
         "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Supported should be False");
   end Test_No_Graphics_Kitty_False;

   procedure Test_No_Graphics_Provenance_Flags_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_GRAPHICS_CAPABILITIES.Sixel_Via_DA1,
         "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Sixel_Via_DA1 should be False");
      Assert
        (not NO_GRAPHICS_CAPABILITIES.Kitty_Via_Active_Probe,
         "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Kitty_Via_Active_Probe should be False");
   end Test_No_Graphics_Provenance_Flags_False;

   procedure Test_No_Graphics_Probed_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (not NO_GRAPHICS_CAPABILITIES.Probed, "FUNC-SXL-001: NO_GRAPHICS_CAPABILITIES.Probed should be False");
   end Test_No_Graphics_Probed_False;

   procedure Test_Default_Equals_No_Graphics_Capabilities (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Default_Caps : constant Graphics_Capabilities := (others => <>);
   begin
      Assert
        (Default_Caps.Sixel_Supported = NO_GRAPHICS_CAPABILITIES.Sixel_Supported,
         "FUNC-SXL-001: default Sixel_Supported equals NO_GRAPHICS_CAPABILITIES.Sixel_Supported");
      Assert
        (Default_Caps.Kitty_Graphics_Supported = NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Supported,
         "FUNC-SXL-001: default Kitty_Graphics_Supported equals NO_GRAPHICS_CAPABILITIES");
      Assert
        (Default_Caps.Sixel_Via_DA1 = NO_GRAPHICS_CAPABILITIES.Sixel_Via_DA1,
         "FUNC-SXL-001: default Sixel_Via_DA1 equals NO_GRAPHICS_CAPABILITIES.Sixel_Via_DA1");
      Assert
        (Default_Caps.Kitty_Via_Active_Probe = NO_GRAPHICS_CAPABILITIES.Kitty_Via_Active_Probe,
         "FUNC-SXL-001: default Kitty_Via_Active_Probe equals NO_GRAPHICS_CAPABILITIES");
      Assert
        (Default_Caps.Probed = NO_GRAPHICS_CAPABILITIES.Probed,
         "FUNC-SXL-001: default Probed equals NO_GRAPHICS_CAPABILITIES.Probed");
      Assert
        (Default_Caps.Sixel_Color_Registers = NO_GRAPHICS_CAPABILITIES.Sixel_Color_Registers,
         "FUNC-SXL-001: default Sixel_Color_Registers equals NO_GRAPHICS_CAPABILITIES");
      Assert
        (Default_Caps.Kitty_Graphics_Version = NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Version,
         "FUNC-SXL-001: default Kitty_Graphics_Version equals NO_GRAPHICS_CAPABILITIES");
   end Test_Default_Equals_No_Graphics_Capabilities;

   procedure Test_Sixel_Independent_Of_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Set Sixel_Supported; verify Kitty_Graphics_Supported remains unaffected.
      Caps : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
   begin
      Caps.Sixel_Supported := True;
      Assert (Caps.Sixel_Supported, "FUNC-SXL-001: Sixel_Supported should be True after assignment");
      Assert
        (not Caps.Kitty_Graphics_Supported,
         "FUNC-SXL-001: setting Sixel_Supported must not affect Kitty_Graphics_Supported");
   end Test_Sixel_Independent_Of_Kitty;

   procedure Test_Provenance_Independent_Of_Support (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Provenance flags can be set independently of support flags.
      Caps : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
   begin
      Caps.Sixel_Via_DA1 := True;
      Assert
        (not Caps.Kitty_Via_Active_Probe, "FUNC-SXL-001: setting Sixel_Via_DA1 must not affect Kitty_Via_Active_Probe");
      Caps.Kitty_Via_Active_Probe := True;
      Assert (not Caps.Sixel_Supported, "FUNC-SXL-001: setting Kitty_Via_Active_Probe must not affect Sixel_Supported");
   end Test_Provenance_Independent_Of_Support;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-002: Sixel_Color_Registers optional field
   ---------------------------------------------------------------------------

   procedure Test_No_Graphics_Color_Registers_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (NO_GRAPHICS_CAPABILITIES.Sixel_Color_Registers = 0,
         "FUNC-SXL-002: NO_GRAPHICS_CAPABILITIES.Sixel_Color_Registers should be 0 (unknown)");
   end Test_No_Graphics_Color_Registers_Zero;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-003: Kitty_Graphics_Version optional field
   ---------------------------------------------------------------------------

   procedure Test_No_Graphics_Version_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Version = 0,
         "FUNC-SXL-003: NO_GRAPHICS_CAPABILITIES.Kitty_Graphics_Version should be 0 (unknown)");
   end Test_No_Graphics_Version_Zero;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-004: Named terminal identifier constants
   ---------------------------------------------------------------------------

   procedure Test_Constant_Term_Xterm_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_XTERM_KITTY = "xterm-kitty", "FUNC-SXL-004: TERM_XTERM_KITTY should equal ""xterm-kitty""");
   end Test_Constant_Term_Xterm_Kitty;

   procedure Test_Constant_Term_Foot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_FOOT = "foot", "FUNC-SXL-004: TERM_FOOT should equal ""foot""");
   end Test_Constant_Term_Foot;

   procedure Test_Constant_Term_Foot_Extra (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_FOOT_EXTRA = "foot-extra", "FUNC-SXL-004: TERM_FOOT_EXTRA should equal ""foot-extra""");
   end Test_Constant_Term_Foot_Extra;

   procedure Test_Constant_Term_Xterm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_XTERM = "xterm", "FUNC-SXL-004: TERM_XTERM should equal ""xterm""");
   end Test_Constant_Term_Xterm;

   procedure Test_Constant_Term_Mlterm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_MLTERM = "mlterm", "FUNC-SXL-004: TERM_MLTERM should equal ""mlterm""");
   end Test_Constant_Term_Mlterm;

   procedure Test_Constant_Term_Yaft (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_YAFT = "yaft", "FUNC-SXL-004: TERM_YAFT should equal ""yaft""");
   end Test_Constant_Term_Yaft;

   procedure Test_Constant_Term_Program_Wezterm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_PROGRAM_WEZTERM = "WezTerm", "FUNC-SXL-004: TERM_PROGRAM_WEZTERM should equal ""WezTerm""");
   end Test_Constant_Term_Program_Wezterm;

   procedure Test_Constant_Term_Program_Iterm2 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_PROGRAM_ITERM2 = "iTerm.app", "FUNC-SXL-004: TERM_PROGRAM_ITERM2 should equal ""iTerm.app""");
   end Test_Constant_Term_Program_Iterm2;

   procedure Test_Constant_Env_Kitty_Window_Id (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (ENV_KITTY_WINDOW_ID = "KITTY_WINDOW_ID", "FUNC-SXL-004: ENV_KITTY_WINDOW_ID should equal ""KITTY_WINDOW_ID""");
   end Test_Constant_Env_Kitty_Window_Id;

   procedure Test_Constant_Xtversion_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (XTVERSION_NAME_KITTY = "kitty", "FUNC-SXL-004: XTVERSION_NAME_KITTY should equal ""kitty""");
   end Test_Constant_Xtversion_Kitty;

   procedure Test_Constant_Xtversion_Wezterm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (XTVERSION_NAME_WEZTERM = "WezTerm", "FUNC-SXL-004: XTVERSION_NAME_WEZTERM should equal ""WezTerm""");
   end Test_Constant_Xtversion_Wezterm;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-010: KITTY_APC_QUERY constant
   ---------------------------------------------------------------------------

   procedure Test_Apc_Query_Length (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (KITTY_APC_QUERY'Length = 12, "FUNC-SXL-010: KITTY_APC_QUERY should have length 12");
   end Test_Apc_Query_Length;

   procedure Test_Apc_Query_Starts_With_ESC_Underscore (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      First : constant Positive := KITTY_APC_QUERY'First;
   begin
      Assert (KITTY_APC_QUERY (First) = 16#1B#, "FUNC-SXL-010: KITTY_APC_QUERY byte 1 should be ESC (0x1B)");
      Assert
        (KITTY_APC_QUERY (First + 1) = 16#5F#,
         "FUNC-SXL-010: KITTY_APC_QUERY byte 2 should be '_' (0x5F, APC introducer)");
   end Test_Apc_Query_Starts_With_ESC_Underscore;

   procedure Test_Apc_Query_Ends_With_ST (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Last : constant Positive := KITTY_APC_QUERY'Last;
   begin
      Assert
        (KITTY_APC_QUERY (Last - 1) = 16#1B#, "FUNC-SXL-010: KITTY_APC_QUERY penultimate byte should be ESC (0x1B)");
      Assert
        (KITTY_APC_QUERY (Last) = 16#5C#,
         "FUNC-SXL-010: KITTY_APC_QUERY last byte should be '\' (0x5C, ST terminator)");
   end Test_Apc_Query_Ends_With_ST;

   procedure Test_Apc_Query_Payload_Content (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Payload is bytes 3..10 (1-indexed within the array, offset from First):
      --  G i = 1 , a = q  (8 bytes)
      First : constant Positive := KITTY_APC_QUERY'First;
   begin
      Assert (KITTY_APC_QUERY (First + 2) = Character'Pos ('G'), "FUNC-SXL-010: payload byte 1 should be 'G'");
      Assert (KITTY_APC_QUERY (First + 3) = Character'Pos ('i'), "FUNC-SXL-010: payload byte 2 should be 'i'");
      Assert (KITTY_APC_QUERY (First + 4) = Character'Pos ('='), "FUNC-SXL-010: payload byte 3 should be '='");
      Assert (KITTY_APC_QUERY (First + 5) = Character'Pos ('1'), "FUNC-SXL-010: payload byte 4 should be '1'");
      Assert (KITTY_APC_QUERY (First + 6) = Character'Pos (','), "FUNC-SXL-010: payload byte 5 should be ','");
      Assert (KITTY_APC_QUERY (First + 7) = Character'Pos ('a'), "FUNC-SXL-010: payload byte 6 should be 'a'");
      Assert (KITTY_APC_QUERY (First + 8) = Character'Pos ('='), "FUNC-SXL-010: payload byte 7 should be '='");
      Assert (KITTY_APC_QUERY (First + 9) = Character'Pos ('q'), "FUNC-SXL-010: payload byte 8 should be 'q'");
   end Test_Apc_Query_Payload_Content;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: APC_Parse_Result enumeration distinctness
   ---------------------------------------------------------------------------

   procedure Test_Apc_Result_Not_Present_Neq_OK (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Not_Present /= OK, "FUNC-SXL-011: APC_Parse_Result Not_Present and OK must be distinct literals");
   end Test_Apc_Result_Not_Present_Neq_OK;

   procedure Test_Apc_Result_OK_Neq_Error (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (OK /= Error, "FUNC-SXL-011: APC_Parse_Result OK and Error must be distinct literals");
   end Test_Apc_Result_OK_Neq_Error;

   procedure Test_Apc_Result_Not_Present_Neq_Error (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Not_Present /= Error, "FUNC-SXL-011: APC_Parse_Result Not_Present and Error must be distinct literals");
   end Test_Apc_Result_Not_Present_Neq_Error;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — Not_Present cases
   --
   --  APC frame structure:
   --    ESC _ G <params> ESC \
   --    (0x1B 0x5F 'G' ... 0x1B 0x5C)
   --  "OK"    in params -> return OK
   --  "EINVAL" in params -> return Error
   --  No APC G frame -> return Not_Present
   ---------------------------------------------------------------------------

   procedure Test_Parse_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Length = 0: precondition Length <= Buffer'Length is satisfied (0 <= 4).
      Buf    : constant Byte_Array (1 .. 4) := [others => 0];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 0);
   begin
      Assert (Result = Not_Present, "FUNC-SXL-011: empty buffer (Length=0) -> Not_Present");
   end Test_Parse_Empty_Buffer;

   procedure Test_Parse_No_Apc_Sequence (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Buffer contains only noise bytes, no ESC _ introducer.
      Buf    : constant Byte_Array (1 .. 8) := [SPACE, SPACE, SPACE, SPACE, SPACE, SPACE, SPACE, SPACE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 8);
   begin
      Assert (Result = Not_Present, "FUNC-SXL-011: buffer with no APC sequence -> Not_Present");
   end Test_Parse_No_Apc_Sequence;

   procedure Test_Parse_Da1_Response_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Typical DA1 response: ESC [ ? 6 4 ; 1 ; 2 c  (no APC G anywhere).
      --  Use a simplified form: ESC [ ? 6 c (6 bytes).
      Buf    : constant Byte_Array (1 .. 6) := [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_6, SEMI_BYTE, C_BYTE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 6);
   begin
      Assert (Result = Not_Present, "FUNC-SXL-011: DA1 response only (no APC G) -> Not_Present");
   end Test_Parse_Da1_Response_Only;

   procedure Test_Parse_Partial_Apc_No_St (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  APC introducer + G + params but no ST terminator: ESC _ G O K  (5 bytes, no ESC \)
      Buf    : constant Byte_Array (1 .. 5) := [ESC_BYTE, APC_BYTE, G_BYTE, O_BYTE, K_BYTE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 5);
   begin
      Assert (Result = Not_Present, "FUNC-SXL-011: partial APC (no ST terminator ESC \\) -> Not_Present");
   end Test_Parse_Partial_Apc_No_St;

   procedure Test_Parse_Length_Zero_Non_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  The buffer contains a valid APC OK frame but Length = 0.
      --  The function must examine only bytes 1..0, i.e., nothing.
      --  Full frame: ESC _ G O K ESC \  (7 bytes).
      Buf    : constant Byte_Array (1 .. 7) := [ESC_BYTE, APC_BYTE, G_BYTE, O_BYTE, K_BYTE, ESC_BYTE, ST_BYTE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 0);
   begin
      Assert (Result = Not_Present, "FUNC-SXL-011: Length=0 on non-empty buffer -> Not_Present (nothing scanned)");
   end Test_Parse_Length_Zero_Non_Empty_Buffer;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — OK case
   ---------------------------------------------------------------------------

   procedure Test_Parse_Apc_OK (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Minimal well-formed APC OK frame: ESC _ G O K ESC \  (7 bytes)
      Buf    : constant Byte_Array (1 .. 7) := [ESC_BYTE, APC_BYTE, G_BYTE, O_BYTE, K_BYTE, ESC_BYTE, ST_BYTE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 7);
   begin
      Assert (Result = OK, "FUNC-SXL-011: ESC _ G OK ESC \\ -> OK");
   end Test_Parse_Apc_OK;

   procedure Test_Parse_Apc_OK_Embedded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  "OK" embedded in longer params: ESC _ G i=1,a=q;OK ESC \
      --  Params bytes: i=1,a=q;OK  -> use ASCII codes
      --  i=0x69  ==0x3D  1=0x31  ,=0x2C  a=0x61  ==0x3D  q=0x71  ;=0x3B  O=0x4F  K=0x4B
      Buf    : constant Byte_Array (1 .. 15) :=
        [ESC_BYTE,
         APC_BYTE,
         G_BYTE,
         Character'Pos ('i'),
         Character'Pos ('='),
         Character'Pos ('1'),
         Character'Pos (','),
         Character'Pos ('a'),
         Character'Pos ('='),
         Character'Pos ('q'),
         Character'Pos (';'),
         O_BYTE,
         K_BYTE,
         ESC_BYTE,
         ST_BYTE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 15);
   begin
      Assert (Result = OK, "FUNC-SXL-011: APC with ""OK"" substring in longer params -> OK");
   end Test_Parse_Apc_OK_Embedded;

   procedure Test_Parse_Apc_Before_Da1 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  APC OK frame followed by DA1 response in the same buffer.
      --  Frame 1: ESC _ G O K ESC \   (7 bytes)
      --  Frame 2: ESC [ ? 6 c          (5 bytes)
      Buf    : constant Byte_Array (1 .. 12) :=
        [ESC_BYTE, APC_BYTE, G_BYTE, O_BYTE, K_BYTE, ESC_BYTE, ST_BYTE, ESC_BYTE, CSI_BYTE, QUES_BYTE, D_6, C_BYTE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 12);
   begin
      Assert (Result = OK, "FUNC-SXL-011: APC OK before DA1 response -> OK (APC G result extracted)");
   end Test_Parse_Apc_Before_Da1;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — Error case
   ---------------------------------------------------------------------------

   procedure Test_Parse_Apc_Error (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Minimal EINVAL frame: ESC _ G E I N V A L ESC \  (12 bytes)
      Buf    : constant Byte_Array (1 .. 12) :=
        [ESC_BYTE, APC_BYTE, G_BYTE, E_BYTE, I_BYTE, N_BYTE, V_BYTE, A_BYTE, L_BYTE, ESC_BYTE, ST_BYTE, 16#00#];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 11);
   begin
      Assert (Result = Error, "FUNC-SXL-011: ESC _ G EINVAL ESC \\ -> Error");
   end Test_Parse_Apc_Error;

   procedure Test_Parse_Apc_Error_Embedded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  "EINVAL" embedded after other params: ESC _ G i=1;EINVAL ESC \
      --  Params: i=0x69  ==0x3D  1=0x31  ;=0x3B  E I N V A L
      Buf    : constant Byte_Array (1 .. 16) :=
        [ESC_BYTE,
         APC_BYTE,
         G_BYTE,
         Character'Pos ('i'),
         Character'Pos ('='),
         Character'Pos ('1'),
         Character'Pos (';'),
         E_BYTE,
         I_BYTE,
         N_BYTE,
         V_BYTE,
         A_BYTE,
         L_BYTE,
         ESC_BYTE,
         ST_BYTE,
         16#00#];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 15);
   begin
      Assert (Result = Error, "FUNC-SXL-011: APC with ""EINVAL"" substring in longer params -> Error");
   end Test_Parse_Apc_Error_Embedded;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-011: Parse_Kitty_APC_Response — boundary / robustness
   ---------------------------------------------------------------------------

   procedure Test_Parse_Partial_Fill (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Buffer is larger than the actual data.  Length = 7 covers only the
      --  APC OK frame; the rest of the buffer beyond byte 7 is noise.
      --  The function must use only Buffer (1 .. 7).
      Buf    : constant Byte_Array (1 .. 16) :=
        [ESC_BYTE,
         APC_BYTE,
         G_BYTE,
         O_BYTE,
         K_BYTE,
         ESC_BYTE,
         ST_BYTE,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 7);
   begin
      Assert (Result = OK, "FUNC-SXL-011: Length < Buffer'Length -> only valid slice scanned, APC OK found");
   end Test_Parse_Partial_Fill;

   procedure Test_Parse_Multiple_Apc_First_Used (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Two APC G frames back-to-back.
      --  Frame 1: ESC _ G E I N V A L ESC \   (Error, 11 bytes)
      --  Frame 2: ESC _ G O K ESC \           (OK,    7 bytes)
      --  Expect: first frame wins -> Error.
      Buf    : constant Byte_Array (1 .. 18) :=
        [ESC_BYTE,
         APC_BYTE,
         G_BYTE,
         E_BYTE,
         I_BYTE,
         N_BYTE,
         V_BYTE,
         A_BYTE,
         L_BYTE,
         ESC_BYTE,
         ST_BYTE,
         ESC_BYTE,
         APC_BYTE,
         G_BYTE,
         O_BYTE,
         K_BYTE,
         ESC_BYTE,
         ST_BYTE];
      Result : constant APC_Parse_Result := Parse_Kitty_APC_Response (Buf, 18);
   begin
      Assert
        (Result = Error, "FUNC-SXL-011: multiple APC sequences -> first APC G result used (EINVAL before OK -> Error)");
   end Test_Parse_Multiple_Apc_First_Used;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS constant
   ---------------------------------------------------------------------------

   procedure Test_Timeout_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (GRAPHICS_PROBE_TIMEOUT_MS = 1_000, "FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS should equal 1000");
   end Test_Timeout_Value;

   procedure Test_Timeout_At_Least_100 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (GRAPHICS_PROBE_TIMEOUT_MS >= 100, "FUNC-SXL-015: GRAPHICS_PROBE_TIMEOUT_MS must be >= 100 (spec minimum)");
   end Test_Timeout_At_Least_100;


   ---------------------------------------------------------------------------
   --  FUNC-SXL-016 / FUNC-SXL-017: IO-level smoke tests
   ---------------------------------------------------------------------------

   procedure Test_Detect_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-SXL-016: Detect_Graphics must not raise any exception.
      --  On a non-TTY build this returns NO_GRAPHICS_CAPABILITIES.
      --  We only verify the no-exception contract and that the result is
      --  a valid Graphics_Capabilities (fields in a sensible state).
      Result : Graphics_Capabilities;
   begin
      Result := Termicap.Graphics.IO.Detect_Graphics;
      --  A valid result: if not Probed then provenance flags must be False.
      if not Result.Probed then
         Assert (not Result.Sixel_Via_DA1, "FUNC-SXL-016: Probed=False implies Sixel_Via_DA1=False");
         Assert (not Result.Kitty_Via_Active_Probe, "FUNC-SXL-016: Probed=False implies Kitty_Via_Active_Probe=False");
      end if;
   end Test_Detect_No_Exception;

   procedure Test_Detect_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-SXL-017: Detect_Graphics called twice must return the same
      --  Probed flag (cache consistency).
      First  : constant Graphics_Capabilities := Termicap.Graphics.IO.Detect_Graphics;
      Second : constant Graphics_Capabilities := Termicap.Graphics.IO.Detect_Graphics;
   begin
      Assert (First.Probed = Second.Probed, "FUNC-SXL-017: two calls to Detect_Graphics -> same Probed flag");
      Assert
        (First.Sixel_Supported = Second.Sixel_Supported,
         "FUNC-SXL-017: two calls to Detect_Graphics -> same Sixel_Supported");
      Assert
        (First.Kitty_Graphics_Supported = Second.Kitty_Graphics_Supported,
         "FUNC-SXL-017: two calls to Detect_Graphics -> same Kitty_Graphics_Supported");
   end Test_Detect_Cache_Consistency;

end Test_Graphics;
