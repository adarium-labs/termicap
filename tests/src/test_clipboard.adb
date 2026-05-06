-------------------------------------------------------------------------------
--  Test_Clipboard - Unit Tests for Termicap.Clipboard Pure Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Interfaces.C;

with Termicap.Clipboard;     use Termicap.Clipboard;
with Termicap.Clipboard.IO;
with Termicap.DA1;           use Termicap.DA1;
with Termicap.OSC.Parsing;   use Termicap.OSC.Parsing;

use type Interfaces.C.unsigned_char;

package body Test_Clipboard is

   ---------------------------------------------------------------------------
   --  Local aliases to avoid potential hiding between Termicap child packages.
   subtype C_Byte       is Termicap.Byte;
   subtype C_Byte_Array is Termicap.Byte_Array;

   ---------------------------------------------------------------------------
   --  Byte constant helpers for Parse_OSC52_Response tests
   --
   --  OSC 52 response structure:
   --    ESC ] 52 ; <selection> ; <base64-or-empty> BEL
   --    or: ESC ] 52 ; <selection> ; <base64-or-empty> ESC \
   --
   --  ESC  = 0x1B, ] = 0x5D, BEL = 0x07, ST  = ESC \ = 0x1B 0x5C
   ---------------------------------------------------------------------------

   ESC_BYTE  : constant C_Byte := 16#1B#;  --  ESC  (0x1B)
   OSC_BYTE  : constant C_Byte := 16#5D#;  --  ]    (0x5D, OSC introducer)
   BEL_BYTE  : constant C_Byte := 16#07#;  --  BEL  (0x07, OSC terminator)
   ST_BYTE   : constant C_Byte := 16#5C#;  --  \    (0x5C, ST second byte)
   SEMI_BYTE : constant C_Byte := 16#3B#;  --  ;    (0x3B, delimiter)
   CSI_BYTE  : constant C_Byte := 16#5B#;  --  [    (0x5B, CSI introducer)
   QUES_BYTE : constant C_Byte := 16#3F#;  --  ?    (0x3F)
   DA1_C_BYTE : constant C_Byte := Character'Pos ('c');  --  'c' (0x63, DA1 final byte)
   FIVE_BYTE : constant C_Byte := Character'Pos ('5');  --  '5' (0x35)
   TWO_BYTE  : constant C_Byte := Character'Pos ('2');  --  '2' (0x32)
   SEL_BYTE  : constant C_Byte := Character'Pos ('c');  --  'c' (selection)
   SEL_P     : constant C_Byte := Character'Pos ('p');  --  'p' (primary selection)
   B64_BYTE  : constant C_Byte := Character'Pos ('A');  --  'A' (base64 char)
   SPACE     : constant C_Byte := 16#20#;  --  space (noise / filler)

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Clipboard pure functions");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-C52-001: Clipboard_Support enumeration ordering
      Register_Routine
        (T, Test_Support_None_Is_First'Access, "FUNC-C52-001: None is Clipboard_Support'First");
      Register_Routine
        (T, Test_Support_Read_Write_Is_Last'Access, "FUNC-C52-001: Read_Write is Clipboard_Support'Last");
      Register_Routine
        (T, Test_Support_Ordering'Access, "FUNC-C52-001: ordering None < Write_Only < Read_Write");
      Register_Routine
        (T, Test_Support_Ge_Write_Only_Self'Access, "FUNC-C52-001: Write_Only >= Write_Only is True");
      Register_Routine
        (T,
         Test_Support_Ge_Read_Write_Vs_Write_Only'Access,
         "FUNC-C52-001: Read_Write >= Write_Only is True");
      Register_Routine
        (T, Test_Support_None_Not_Ge_Write_Only'Access, "FUNC-C52-001: None >= Write_Only is False");

      --  FUNC-C52-002: Clipboard_Capabilities record / NO_CLIPBOARD_CAPABILITIES
      Register_Routine
        (T, Test_No_Caps_Support_None'Access, "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Support = None");
      Register_Routine
        (T, Test_No_Caps_Via_DA1_False'Access, "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_DA1 = False");
      Register_Routine
        (T,
         Test_No_Caps_Via_Active_Probe_False'Access,
         "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_Active_Probe = False");
      Register_Routine
        (T,
         Test_No_Caps_Via_Env_Heuristic_False'Access,
         "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_Env_Heuristic = False");
      Register_Routine
        (T, Test_No_Caps_Probed_False'Access, "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Probed = False");
      Register_Routine
        (T,
         Test_Default_Equals_No_Clipboard_Capabilities'Access,
         "FUNC-C52-002: default record equals NO_CLIPBOARD_CAPABILITIES");
      Register_Routine
        (T, Test_Caps_Fields_Independent'Access, "FUNC-C52-002: Via_DA1 and Via_Active_Probe are independent fields");
      Register_Routine
        (T, Test_Caps_Support_Assignable'Access, "FUNC-C52-002: Support field can be assigned independently");

      --  FUNC-C52-003: Clipboard_Access literal in DA1_Capability
      Register_Routine
        (T, Test_DA1_Clipboard_Access_Exists'Access, "FUNC-C52-003: Clipboard_Access is a valid DA1_Capability");
      Register_Routine
        (T,
         Test_DA1_Interpret_Ps52_Sets_Clipboard_Access'Access,
         "FUNC-C52-003: Interpret_DA1 with Ps=52 sets Flags(Clipboard_Access)=True");
      Register_Routine
        (T,
         Test_DA1_Has_Capability_Clipboard_Access_True'Access,
         "FUNC-C52-003: Has_Capability=True for Clipboard_Access when Ps=52 present");
      Register_Routine
        (T,
         Test_DA1_Has_Capability_Clipboard_Access_False'Access,
         "FUNC-C52-003: Has_Capability=False for Clipboard_Access when Ps=52 absent");

      --  FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS constant
      Register_Routine
        (T, Test_DA1_Ps_Clipboard_Access_Value'Access, "FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS = 52");
      Register_Routine
        (T,
         Test_DA1_Ps_Clipboard_Access_Positive'Access,
         "FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS is a positive integer");

      --  FUNC-C52-005: Named terminal identifier constants
      Register_Routine
        (T,
         Test_Constant_Term_Program_Wezterm'Access,
         "FUNC-C52-005: TERM_PROGRAM_WEZTERM = ""WezTerm""");
      Register_Routine
        (T, Test_Constant_Term_Program_Iterm2'Access, "FUNC-C52-005: TERM_PROGRAM_ITERM2 = ""iTerm.app""");
      Register_Routine
        (T, Test_Constant_Term_Program_Vscode'Access, "FUNC-C52-005: TERM_PROGRAM_VSCODE = ""vscode""");
      Register_Routine
        (T, Test_Constant_Env_Wt_Session'Access, "FUNC-C52-005: ENV_WT_SESSION = ""WT_SESSION""");
      Register_Routine (T, Test_Constant_Env_Tmux'Access, "FUNC-C52-005: ENV_TMUX = ""TMUX""");
      Register_Routine (T, Test_Constant_Env_Sty'Access, "FUNC-C52-005: ENV_STY = ""STY""");
      Register_Routine
        (T, Test_Constant_Term_Xterm_Kitty'Access, "FUNC-C52-005: TERM_XTERM_KITTY = ""xterm-kitty""");
      Register_Routine (T, Test_Constant_Term_Xterm'Access, "FUNC-C52-005: TERM_XTERM = ""xterm""");
      Register_Routine
        (T, Test_Constants_Non_Empty'Access, "FUNC-C52-005: all named constants are non-empty strings");

      --  FUNC-C52-007: OSC52_QUERY byte constant
      Register_Routine (T, Test_Query_Length'Access, "FUNC-C52-007: OSC52_QUERY has length 9");
      Register_Routine
        (T,
         Test_Query_Starts_With_ESC_Bracket'Access,
         "FUNC-C52-007: OSC52_QUERY starts with ESC ] (0x1B 0x5D)");
      Register_Routine
        (T, Test_Query_Ends_With_BEL'Access, "FUNC-C52-007: OSC52_QUERY ends with BEL (0x07)");
      Register_Routine
        (T,
         Test_Query_Payload_Content'Access,
         "FUNC-C52-007: OSC52_QUERY payload contains ""52;c;?"" as ASCII bytes");

      --  FUNC-C52-008: OSC52_Parse_Result enumeration distinctness
      Register_Routine
        (T,
         Test_Parse_Result_Not_Present_Neq_Valid'Access,
         "FUNC-C52-008: OSC52_Parse_Result Not_Present /= Valid_Response");
      Register_Routine
        (T,
         Test_Parse_Result_Valid_Neq_Malformed'Access,
         "FUNC-C52-008: OSC52_Parse_Result Valid_Response /= Malformed");
      Register_Routine
        (T,
         Test_Parse_Result_Not_Present_Neq_Malformed'Access,
         "FUNC-C52-008: OSC52_Parse_Result Not_Present /= Malformed");

      --  FUNC-C52-008: Parse_OSC52_Response — Not_Present cases
      Register_Routine
        (T, Test_Parse_Empty_Buffer'Access, "FUNC-C52-008: empty buffer (Length=0) -> Not_Present");
      Register_Routine
        (T, Test_Parse_No_OSC52_Introducer'Access, "FUNC-C52-008: noise bytes only, no ESC ] 52 -> Not_Present");
      Register_Routine
        (T, Test_Parse_DA1_Response_Only'Access, "FUNC-C52-008: DA1 response only (no OSC 52) -> Not_Present");
      Register_Routine
        (T,
         Test_Parse_Length_Zero_Non_Empty_Buffer'Access,
         "FUNC-C52-008: Length=0 on non-empty buffer -> Not_Present");
      Register_Routine
        (T, Test_Parse_Too_Short'Access, "FUNC-C52-008: buffer shorter than minimum OSC 52 header -> Not_Present");

      --  FUNC-C52-008: Parse_OSC52_Response — Valid_Response cases
      Register_Routine
        (T,
         Test_Parse_Valid_BEL_Terminated'Access,
         "FUNC-C52-008: ESC ] 52;c;<base64> BEL -> Valid_Response");
      Register_Routine
        (T,
         Test_Parse_Valid_ST_Terminated'Access,
         "FUNC-C52-008: ESC ] 52;c;<base64> ESC \\ -> Valid_Response");
      Register_Routine
        (T,
         Test_Parse_Valid_Empty_Payload'Access,
         "FUNC-C52-008: ESC ] 52;c; BEL (empty payload) -> Valid_Response");
      Register_Routine
        (T,
         Test_Parse_Valid_Primary_Selection'Access,
         "FUNC-C52-008: response with ""p"" selection -> Valid_Response");
      Register_Routine
        (T,
         Test_Parse_Valid_With_Leading_Noise'Access,
         "FUNC-C52-008: OSC 52 response preceded by noise -> Valid_Response");
      Register_Routine
        (T,
         Test_Parse_Valid_Before_DA1'Access,
         "FUNC-C52-008: OSC 52 response followed by DA1 sentinel -> Valid_Response");
      Register_Routine
        (T, Test_Parse_Partial_Fill'Access, "FUNC-C52-008: Length < Buffer'Length uses only valid slice");

      --  FUNC-C52-008: Parse_OSC52_Response — Malformed cases
      Register_Routine
        (T,
         Test_Parse_Malformed_No_Terminator'Access,
         "FUNC-C52-008: OSC 52 introducer found but no BEL or ST -> Malformed");
      Register_Routine
        (T,
         Test_Parse_Malformed_Too_Few_Semicolons'Access,
         "FUNC-C52-008: OSC 52 introducer with fewer than 2 semicolons before BEL -> Malformed");

      --  FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS constant
      Register_Routine
        (T, Test_Timeout_Value'Access, "FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS = 1000");
      Register_Routine
        (T, Test_Timeout_At_Least_100'Access, "FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS >= 100");

      --  FUNC-C52-016 / FUNC-C52-017: IO smoke tests
      Register_Routine
        (T, Test_Detect_No_Exception'Access, "FUNC-C52-016: Detect_Clipboard returns without exception");
      Register_Routine
        (T,
         Test_Detect_Cache_Consistency'Access,
         "FUNC-C52-017: Detect_Clipboard called twice -> same Probed flag");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  FUNC-C52-001: Clipboard_Support enumeration ordering
   ---------------------------------------------------------------------------

   procedure Test_Support_None_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Clipboard_Support'First = None,
         "FUNC-C52-001: None should be Clipboard_Support'First (lowest capability level)");
   end Test_Support_None_Is_First;

   procedure Test_Support_Read_Write_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Clipboard_Support'Last = Read_Write,
         "FUNC-C52-001: Read_Write should be Clipboard_Support'Last (highest capability level)");
   end Test_Support_Read_Write_Is_Last;

   procedure Test_Support_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (None < Write_Only, "FUNC-C52-001: None < Write_Only ordering must hold");
      Assert (Write_Only < Read_Write, "FUNC-C52-001: Write_Only < Read_Write ordering must hold");
      Assert (None < Read_Write, "FUNC-C52-001: None < Read_Write ordering must hold (transitivity)");
   end Test_Support_Ordering;

   procedure Test_Support_Ge_Write_Only_Self (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Write_Only >= Write_Only,
         "FUNC-C52-001: Write_Only >= Write_Only must be True (at-least-write-only gate)");
   end Test_Support_Ge_Write_Only_Self;

   procedure Test_Support_Ge_Read_Write_Vs_Write_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Read_Write >= Write_Only,
         "FUNC-C52-001: Read_Write >= Write_Only must be True (highest level passes write-only gate)");
   end Test_Support_Ge_Read_Write_Vs_Write_Only;

   procedure Test_Support_None_Not_Ge_Write_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not (None >= Write_Only),
         "FUNC-C52-001: None >= Write_Only must be False (no clipboard access does not pass gate)");
   end Test_Support_None_Not_Ge_Write_Only;


   ---------------------------------------------------------------------------
   --  FUNC-C52-002: Clipboard_Capabilities record / NO_CLIPBOARD_CAPABILITIES
   ---------------------------------------------------------------------------

   procedure Test_No_Caps_Support_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (NO_CLIPBOARD_CAPABILITIES.Support = None,
         "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Support should be None");
   end Test_No_Caps_Support_None;

   procedure Test_No_Caps_Via_DA1_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_CLIPBOARD_CAPABILITIES.Via_DA1,
         "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_DA1 should be False");
   end Test_No_Caps_Via_DA1_False;

   procedure Test_No_Caps_Via_Active_Probe_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_CLIPBOARD_CAPABILITIES.Via_Active_Probe,
         "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_Active_Probe should be False");
   end Test_No_Caps_Via_Active_Probe_False;

   procedure Test_No_Caps_Via_Env_Heuristic_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_CLIPBOARD_CAPABILITIES.Via_Env_Heuristic,
         "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_Env_Heuristic should be False");
   end Test_No_Caps_Via_Env_Heuristic_False;

   procedure Test_No_Caps_Probed_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not NO_CLIPBOARD_CAPABILITIES.Probed,
         "FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Probed should be False");
   end Test_No_Caps_Probed_False;

   procedure Test_Default_Equals_No_Clipboard_Capabilities (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  A default-initialised Clipboard_Capabilities must have the same field values
      --  as NO_CLIPBOARD_CAPABILITIES.  We verify each field individually since the
      --  record type may not have "=" operator in scope without an explicit use clause.
      Default_Caps : constant Clipboard_Capabilities := (others => <>);
   begin
      Assert
        (Default_Caps.Support = NO_CLIPBOARD_CAPABILITIES.Support,
         "FUNC-C52-002: default Support equals NO_CLIPBOARD_CAPABILITIES.Support");
      Assert
        (Default_Caps.Via_DA1 = NO_CLIPBOARD_CAPABILITIES.Via_DA1,
         "FUNC-C52-002: default Via_DA1 equals NO_CLIPBOARD_CAPABILITIES.Via_DA1");
      Assert
        (Default_Caps.Via_Active_Probe = NO_CLIPBOARD_CAPABILITIES.Via_Active_Probe,
         "FUNC-C52-002: default Via_Active_Probe equals NO_CLIPBOARD_CAPABILITIES.Via_Active_Probe");
      Assert
        (Default_Caps.Via_Env_Heuristic = NO_CLIPBOARD_CAPABILITIES.Via_Env_Heuristic,
         "FUNC-C52-002: default Via_Env_Heuristic equals NO_CLIPBOARD_CAPABILITIES.Via_Env_Heuristic");
      Assert
        (Default_Caps.Probed = NO_CLIPBOARD_CAPABILITIES.Probed,
         "FUNC-C52-002: default Probed equals NO_CLIPBOARD_CAPABILITIES.Probed");
   end Test_Default_Equals_No_Clipboard_Capabilities;

   procedure Test_Caps_Fields_Independent (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Setting Via_DA1 must not affect Via_Active_Probe or Via_Env_Heuristic.
      Caps : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
   begin
      Caps.Via_DA1 := True;
      Assert (Caps.Via_DA1, "FUNC-C52-002: Via_DA1 should be True after assignment");
      Assert (not Caps.Via_Active_Probe, "FUNC-C52-002: Via_Active_Probe must not be affected by setting Via_DA1");
      Assert (not Caps.Via_Env_Heuristic, "FUNC-C52-002: Via_Env_Heuristic must not be affected by setting Via_DA1");
      Caps.Via_Active_Probe := True;
      Assert (Caps.Via_Active_Probe, "FUNC-C52-002: Via_Active_Probe should be True after assignment");
      Assert (not Caps.Via_Env_Heuristic, "FUNC-C52-002: Via_Env_Heuristic must not change when Via_Active_Probe set");
   end Test_Caps_Fields_Independent;

   procedure Test_Caps_Support_Assignable (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  The Support field can hold all three enumeration values independently.
      Caps : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
   begin
      Caps.Support := Write_Only;
      Assert (Caps.Support = Write_Only, "FUNC-C52-002: Support should be Write_Only after assignment");
      Assert (not Caps.Probed, "FUNC-C52-002: assigning Support must not affect Probed");
      Caps.Support := Read_Write;
      Assert (Caps.Support = Read_Write, "FUNC-C52-002: Support should be Read_Write after re-assignment");
   end Test_Caps_Support_Assignable;


   ---------------------------------------------------------------------------
   --  FUNC-C52-003: Clipboard_Access literal in DA1_Capability
   ---------------------------------------------------------------------------

   procedure Test_DA1_Clipboard_Access_Exists (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Verify that Clipboard_Access is a valid DA1_Capability value by using
      --  it in a Has_Capability call on a default-initialised (unsupported) record.
      --  The call must not raise Constraint_Error or any other exception.
      Caps   : constant DA1_Capabilities := (Supported => False, Level => Unknown, Flags => [others => False]);
      Result : constant Boolean := Has_Capability (Caps, Clipboard_Access);
   begin
      --  When Supported=False, Has_Capability always returns False.
      Assert (not Result, "FUNC-C52-003: Clipboard_Access is a valid DA1_Capability literal (call did not raise)");
   end Test_DA1_Clipboard_Access_Exists;

   procedure Test_DA1_Interpret_Ps52_Sets_Clipboard_Access (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  DA1 params: VT400 (Ps=64) + Clipboard_Access (Ps=52).
      --  According to FUNC-DA1-004 / FUNC-C52-003, Ps=52 must set Flags(Clipboard_Access)=True.
      Params : constant DA1_Params := (Count => 2, Values => [64, 52, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (Caps.Supported, "FUNC-C52-003: Interpret_DA1 with [64,52]: Supported should be True");
      Assert
        (Caps.Flags (Clipboard_Access),
         "FUNC-C52-003: Interpret_DA1 with Ps=52 must set Flags(Clipboard_Access)=True");
      --  Verify that unrelated flags are not spuriously set.
      Assert
        (not Caps.Flags (Sixel_Graphics),
         "FUNC-C52-003: Interpret_DA1 with Ps=52 must not set Flags(Sixel_Graphics)");
      Assert
        (not Caps.Flags (ANSI_Color),
         "FUNC-C52-003: Interpret_DA1 with Ps=52 must not set Flags(ANSI_Color)");
   end Test_DA1_Interpret_Ps52_Sets_Clipboard_Access;

   procedure Test_DA1_Has_Capability_Clipboard_Access_True (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Params : constant DA1_Params := (Count => 2, Values => [65, 52, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert
        (Has_Capability (Caps, Clipboard_Access),
         "FUNC-C52-003: Has_Capability must return True for Clipboard_Access when Ps=52 present");
   end Test_DA1_Has_Capability_Clipboard_Access_True;

   procedure Test_DA1_Has_Capability_Clipboard_Access_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  DA1 params with no Ps=52 -> Clipboard_Access flag must stay False.
      Params : constant DA1_Params := (Count => 3, Values => [64, 4, 22, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert
        (not Has_Capability (Caps, Clipboard_Access),
         "FUNC-C52-003: Has_Capability must return False for Clipboard_Access when Ps=52 absent");
      --  Verify that the other flags are unaffected.
      Assert
        (Has_Capability (Caps, Sixel_Graphics),
         "FUNC-C52-003: Sixel_Graphics should still be True (sanity)");
   end Test_DA1_Has_Capability_Clipboard_Access_False;


   ---------------------------------------------------------------------------
   --  FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS constant
   ---------------------------------------------------------------------------

   procedure Test_DA1_Ps_Clipboard_Access_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (DA1_PS_CLIPBOARD_ACCESS = 52,
         "FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS should equal 52");
   end Test_DA1_Ps_Clipboard_Access_Value;

   procedure Test_DA1_Ps_Clipboard_Access_Positive (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (DA1_PS_CLIPBOARD_ACCESS > 0,
         "FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS must be a positive integer constant");
   end Test_DA1_Ps_Clipboard_Access_Positive;


   ---------------------------------------------------------------------------
   --  FUNC-C52-005: Named terminal identifier constants
   ---------------------------------------------------------------------------

   procedure Test_Constant_Term_Program_Wezterm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (TERM_PROGRAM_WEZTERM = "WezTerm",
         "FUNC-C52-005: TERM_PROGRAM_WEZTERM should equal ""WezTerm""");
   end Test_Constant_Term_Program_Wezterm;

   procedure Test_Constant_Term_Program_Iterm2 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (TERM_PROGRAM_ITERM2 = "iTerm.app",
         "FUNC-C52-005: TERM_PROGRAM_ITERM2 should equal ""iTerm.app""");
   end Test_Constant_Term_Program_Iterm2;

   procedure Test_Constant_Term_Program_Vscode (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (TERM_PROGRAM_VSCODE = "vscode",
         "FUNC-C52-005: TERM_PROGRAM_VSCODE should equal ""vscode""");
   end Test_Constant_Term_Program_Vscode;

   procedure Test_Constant_Env_Wt_Session (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (ENV_WT_SESSION = "WT_SESSION",
         "FUNC-C52-005: ENV_WT_SESSION should equal ""WT_SESSION""");
   end Test_Constant_Env_Wt_Session;

   procedure Test_Constant_Env_Tmux (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (ENV_TMUX = "TMUX", "FUNC-C52-005: ENV_TMUX should equal ""TMUX""");
   end Test_Constant_Env_Tmux;

   procedure Test_Constant_Env_Sty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (ENV_STY = "STY", "FUNC-C52-005: ENV_STY should equal ""STY""");
   end Test_Constant_Env_Sty;

   procedure Test_Constant_Term_Xterm_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (TERM_XTERM_KITTY = "xterm-kitty",
         "FUNC-C52-005: TERM_XTERM_KITTY should equal ""xterm-kitty""");
   end Test_Constant_Term_Xterm_Kitty;

   procedure Test_Constant_Term_Xterm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_XTERM = "xterm", "FUNC-C52-005: TERM_XTERM should equal ""xterm""");
   end Test_Constant_Term_Xterm;

   procedure Test_Constants_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (TERM_PROGRAM_WEZTERM'Length > 0, "FUNC-C52-005: TERM_PROGRAM_WEZTERM must be non-empty");
      Assert (TERM_PROGRAM_ITERM2'Length > 0, "FUNC-C52-005: TERM_PROGRAM_ITERM2 must be non-empty");
      Assert (TERM_PROGRAM_VSCODE'Length > 0, "FUNC-C52-005: TERM_PROGRAM_VSCODE must be non-empty");
      Assert (ENV_WT_SESSION'Length > 0, "FUNC-C52-005: ENV_WT_SESSION must be non-empty");
      Assert (ENV_TMUX'Length > 0, "FUNC-C52-005: ENV_TMUX must be non-empty");
      Assert (ENV_STY'Length > 0, "FUNC-C52-005: ENV_STY must be non-empty");
      Assert (TERM_XTERM_KITTY'Length > 0, "FUNC-C52-005: TERM_XTERM_KITTY must be non-empty");
      Assert (TERM_XTERM'Length > 0, "FUNC-C52-005: TERM_XTERM must be non-empty");
   end Test_Constants_Non_Empty;


   ---------------------------------------------------------------------------
   --  FUNC-C52-007: OSC52_QUERY byte constant
   --
   --  Expected content: ESC ] 5 2 ; c ; ? BEL  (9 bytes)
   --    [1] = 0x1B  ESC
   --    [2] = 0x5D  ]    (OSC introducer)
   --    [3] = 0x35  '5'
   --    [4] = 0x32  '2'
   --    [5] = 0x3B  ';'
   --    [6] = 0x63  'c'  (clipboard selection)
   --    [7] = 0x3B  ';'
   --    [8] = 0x3F  '?'  (read query)
   --    [9] = 0x07  BEL
   ---------------------------------------------------------------------------

   procedure Test_Query_Length (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (OSC52_QUERY'Length = 9, "FUNC-C52-007: OSC52_QUERY should have length 9");
   end Test_Query_Length;

   procedure Test_Query_Starts_With_ESC_Bracket (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      First : constant Positive := OSC52_QUERY'First;
   begin
      Assert (OSC52_QUERY (First) = 16#1B#, "FUNC-C52-007: OSC52_QUERY byte 1 should be ESC (0x1B)");
      Assert
        (OSC52_QUERY (First + 1) = 16#5D#,
         "FUNC-C52-007: OSC52_QUERY byte 2 should be ']' (0x5D, OSC introducer)");
   end Test_Query_Starts_With_ESC_Bracket;

   procedure Test_Query_Ends_With_BEL (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Last : constant Positive := OSC52_QUERY'Last;
   begin
      Assert (OSC52_QUERY (Last) = 16#07#, "FUNC-C52-007: OSC52_QUERY last byte should be BEL (0x07)");
   end Test_Query_Ends_With_BEL;

   procedure Test_Query_Payload_Content (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Bytes 3..9 (offset from First) encode: 5 2 ; c ; ? BEL
      First : constant Positive := OSC52_QUERY'First;
   begin
      Assert (OSC52_QUERY (First + 2) = Character'Pos ('5'), "FUNC-C52-007: OSC52_QUERY byte 3 should be '5'");
      Assert (OSC52_QUERY (First + 3) = Character'Pos ('2'), "FUNC-C52-007: OSC52_QUERY byte 4 should be '2'");
      Assert (OSC52_QUERY (First + 4) = Character'Pos (';'), "FUNC-C52-007: OSC52_QUERY byte 5 should be ';'");
      Assert (OSC52_QUERY (First + 5) = Character'Pos ('c'), "FUNC-C52-007: OSC52_QUERY byte 6 should be 'c'");
      Assert (OSC52_QUERY (First + 6) = Character'Pos (';'), "FUNC-C52-007: OSC52_QUERY byte 7 should be ';'");
      Assert (OSC52_QUERY (First + 7) = Character'Pos ('?'), "FUNC-C52-007: OSC52_QUERY byte 8 should be '?'");
   end Test_Query_Payload_Content;


   ---------------------------------------------------------------------------
   --  FUNC-C52-008: OSC52_Parse_Result enumeration distinctness
   ---------------------------------------------------------------------------

   procedure Test_Parse_Result_Not_Present_Neq_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Not_Present /= Valid_Response,
         "FUNC-C52-008: Not_Present and Valid_Response must be distinct literals");
   end Test_Parse_Result_Not_Present_Neq_Valid;

   procedure Test_Parse_Result_Valid_Neq_Malformed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Valid_Response /= Malformed,
         "FUNC-C52-008: Valid_Response and Malformed must be distinct literals");
   end Test_Parse_Result_Valid_Neq_Malformed;

   procedure Test_Parse_Result_Not_Present_Neq_Malformed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Not_Present /= Malformed,
         "FUNC-C52-008: Not_Present and Malformed must be distinct literals");
   end Test_Parse_Result_Not_Present_Neq_Malformed;


   ---------------------------------------------------------------------------
   --  FUNC-C52-008: Parse_OSC52_Response — Not_Present cases
   ---------------------------------------------------------------------------

   procedure Test_Parse_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Length = 0: precondition 0 <= Buffer'Length is satisfied.
      Buf    : constant C_Byte_Array (1 .. 4) := [others => 0];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 0);
   begin
      Assert (Result = Not_Present, "FUNC-C52-008: empty buffer (Length=0) -> Not_Present");
   end Test_Parse_Empty_Buffer;

   procedure Test_Parse_No_OSC52_Introducer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Buffer contains only noise bytes, no ESC ] 52 introducer.
      Buf    : constant C_Byte_Array (1 .. 8) :=
        [SPACE, SPACE, SPACE, SPACE, SPACE, SPACE, SPACE, SPACE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 8);
   begin
      Assert (Result = Not_Present, "FUNC-C52-008: noise bytes only -> Not_Present");
   end Test_Parse_No_OSC52_Introducer;

   procedure Test_Parse_DA1_Response_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Typical DA1 response: ESC [ ? 6 4 c  (no OSC 52 bytes anywhere).
      Buf    : constant C_Byte_Array (1 .. 6) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, Character'Pos ('6'), Character'Pos ('4'), DA1_C_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 6);
   begin
      Assert (Result = Not_Present, "FUNC-C52-008: DA1 response only (no OSC 52) -> Not_Present");
   end Test_Parse_DA1_Response_Only;

   procedure Test_Parse_Length_Zero_Non_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Buffer contains a valid OSC 52 response but Length = 0.
      --  The function must scan only bytes 1..0, i.e., nothing.
      --  Well-formed frame: ESC ] 52;c;AAAA BEL  (12 bytes)
      Buf : constant C_Byte_Array (1 .. 12) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_BYTE,
         SEMI_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, BEL_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 0);
   begin
      Assert
        (Result = Not_Present,
         "FUNC-C52-008: Length=0 on non-empty buffer -> Not_Present (nothing scanned)");
   end Test_Parse_Length_Zero_Non_Empty_Buffer;

   procedure Test_Parse_Too_Short (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Buffer has only 3 bytes: ESC ] 5  — not enough to contain a complete
      --  OSC 52 introducer (ESC ] 52) plus the required structure.
      Buf    : constant C_Byte_Array (1 .. 3) := [ESC_BYTE, OSC_BYTE, FIVE_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 3);
   begin
      Assert (Result = Not_Present, "FUNC-C52-008: buffer too short for OSC 52 header -> Not_Present");
   end Test_Parse_Too_Short;


   ---------------------------------------------------------------------------
   --  FUNC-C52-008: Parse_OSC52_Response — Valid_Response cases
   --
   --  Minimal BEL-terminated frame structure:
   --    ESC ] 52 ; c ; <payload> BEL
   --    0x1B 0x5D 0x35 0x32 0x3B 0x63 0x3B <payload-bytes...> 0x07
   --
   --  Minimal ST-terminated frame:
   --    ESC ] 52 ; c ; <payload> ESC \
   --    0x1B 0x5D 0x35 0x32 0x3B 0x63 0x3B <payload-bytes...> 0x1B 0x5C
   --
   --  The parser requires at least two semicolons before the terminator.
   --  In the above structure: the first ';' after '2' and the second ';' after 'c'
   --  are the required two semicolons.
   ---------------------------------------------------------------------------

   procedure Test_Parse_Valid_BEL_Terminated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC ] 52;c;AAAA BEL  (well-formed BEL-terminated response)
      --  12 bytes: ESC ] 5 2 ; c ; A A A A BEL
      Buf    : constant C_Byte_Array (1 .. 12) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_BYTE,
         SEMI_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, BEL_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 12);
   begin
      Assert (Result = Valid_Response, "FUNC-C52-008: ESC ] 52;c;AAAA BEL -> Valid_Response");
   end Test_Parse_Valid_BEL_Terminated;

   procedure Test_Parse_Valid_ST_Terminated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC ] 52;c;AAAA ESC \  (well-formed ST-terminated response)
      --  13 bytes: ESC ] 5 2 ; c ; A A A A ESC \
      Buf    : constant C_Byte_Array (1 .. 13) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_BYTE,
         SEMI_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, ESC_BYTE, ST_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 13);
   begin
      Assert (Result = Valid_Response, "FUNC-C52-008: ESC ] 52;c;AAAA ESC \\ -> Valid_Response");
   end Test_Parse_Valid_ST_Terminated;

   procedure Test_Parse_Valid_Empty_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Empty clipboard content: ESC ] 52;c; BEL  (8 bytes)
      --  ESC ] 5 2 ; c ; BEL
      Buf    : constant C_Byte_Array (1 .. 8) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_BYTE, SEMI_BYTE, BEL_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 8);
   begin
      Assert
        (Result = Valid_Response,
         "FUNC-C52-008: ESC ] 52;c; BEL (empty payload, clipboard empty) -> Valid_Response");
   end Test_Parse_Valid_Empty_Payload;

   procedure Test_Parse_Valid_Primary_Selection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Response with "p" (primary) selection: ESC ] 52;p;AAAA BEL  (12 bytes)
      Buf    : constant C_Byte_Array (1 .. 12) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_P,
         SEMI_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, B64_BYTE, BEL_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 12);
   begin
      Assert
        (Result = Valid_Response,
         "FUNC-C52-008: response with ""p"" (primary) selection -> Valid_Response");
   end Test_Parse_Valid_Primary_Selection;

   procedure Test_Parse_Valid_With_Leading_Noise (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Some noise bytes before the OSC 52 response.
      --  Structure: SPACE SPACE ESC ] 52;c;AA BEL  (10 bytes total)
      Buf    : constant C_Byte_Array (1 .. 10) :=
        [SPACE, SPACE, ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE,
         SEMI_BYTE, SEL_BYTE, SEMI_BYTE, BEL_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 10);
   begin
      Assert
        (Result = Valid_Response,
         "FUNC-C52-008: OSC 52 response preceded by noise bytes -> Valid_Response (scan skips noise)");
   end Test_Parse_Valid_With_Leading_Noise;

   procedure Test_Parse_Valid_Before_DA1 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  OSC 52 response followed by a DA1 sentinel response in the same buffer.
      --  Frame 1: ESC ] 52;c;AA BEL  (9 bytes)
      --  Frame 2: ESC [ ? 6 4 c      (6 bytes)
      --  Total: 15 bytes
      Buf    : constant C_Byte_Array (1 .. 15) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_BYTE,
         SEMI_BYTE, B64_BYTE, B64_BYTE, BEL_BYTE,
         ESC_BYTE, CSI_BYTE, QUES_BYTE, Character'Pos ('6'), Character'Pos ('4')];
      --  Note: actual DA1 final byte 'c' is not included (15 bytes enough to test the logic).
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 15);
   begin
      --  The OSC 52 response (frame 1) is scanned first and returns Valid_Response.
      Assert
        (Result = Valid_Response,
         "FUNC-C52-008: OSC 52 response followed by DA1 data -> Valid_Response (OSC 52 found first)");
   end Test_Parse_Valid_Before_DA1;

   procedure Test_Parse_Partial_Fill (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Buffer is larger than actual data.  Length = 8 covers ESC ] 52;c; BEL;
      --  the rest of the buffer beyond byte 8 is noise (all 0xFF).
      Buf    : constant C_Byte_Array (1 .. 16) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_BYTE, SEMI_BYTE, BEL_BYTE,
         16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 8);
   begin
      Assert
        (Result = Valid_Response,
         "FUNC-C52-008: Length < Buffer'Length -> only valid slice scanned, OSC 52 response found");
   end Test_Parse_Partial_Fill;


   ---------------------------------------------------------------------------
   --  FUNC-C52-008: Parse_OSC52_Response — Malformed cases
   ---------------------------------------------------------------------------

   procedure Test_Parse_Malformed_No_Terminator (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  OSC 52 introducer found (ESC ] 52;c;AAAA) but no BEL or ESC \ terminator.
      --  7 bytes: ESC ] 5 2 ; c ;  (no BEL at the end)
      Buf    : constant C_Byte_Array (1 .. 7) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, SEL_BYTE, SEMI_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 7);
   begin
      Assert
        (Result = Malformed,
         "FUNC-C52-008: OSC 52 introducer found but no BEL or ST terminator -> Malformed");
   end Test_Parse_Malformed_No_Terminator;

   procedure Test_Parse_Malformed_Too_Few_Semicolons (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  OSC 52 introducer found but only one semicolon before BEL (malformed structure).
      --  6 bytes: ESC ] 5 2 ; BEL  (only one ';' after "52"; fewer than 2 semicolons)
      Buf    : constant C_Byte_Array (1 .. 6) :=
        [ESC_BYTE, OSC_BYTE, FIVE_BYTE, TWO_BYTE, SEMI_BYTE, BEL_BYTE];
      Result : constant OSC52_Parse_Result := Parse_OSC52_Response (Buf, 6);
   begin
      Assert
        (Result = Malformed,
         "FUNC-C52-008: OSC 52 introducer with only one semicolon before BEL -> Malformed");
   end Test_Parse_Malformed_Too_Few_Semicolons;


   ---------------------------------------------------------------------------
   --  FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS constant
   ---------------------------------------------------------------------------

   procedure Test_Timeout_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (CLIPBOARD_PROBE_TIMEOUT_MS = 1_000,
         "FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS should equal 1000 ms");
   end Test_Timeout_Value;

   procedure Test_Timeout_At_Least_100 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (CLIPBOARD_PROBE_TIMEOUT_MS >= 100,
         "FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS must be >= 100 (spec minimum)");
   end Test_Timeout_At_Least_100;


   ---------------------------------------------------------------------------
   --  FUNC-C52-016 / FUNC-C52-017: IO-level smoke tests
   ---------------------------------------------------------------------------

   procedure Test_Detect_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-C52-016: Detect_Clipboard must not raise any exception.
      --  On a non-TTY build this returns NO_CLIPBOARD_CAPABILITIES.
      --  We only verify the no-exception contract and that the result is
      --  a valid Clipboard_Capabilities (fields in a sensible state).
      Result : Clipboard_Capabilities;
   begin
      Result := Termicap.Clipboard.IO.Detect_Clipboard;
      --  A valid result: if not Probed then provenance flags must be False (I4).
      if not Result.Probed then
         Assert (not Result.Via_DA1, "FUNC-C52-016: Probed=False implies Via_DA1=False (invariant I4)");
         Assert
           (not Result.Via_Active_Probe,
            "FUNC-C52-016: Probed=False implies Via_Active_Probe=False (invariant I4)");
      end if;
      --  I3: Via_Env_Heuristic=True implies Via_DA1=False and Via_Active_Probe=False.
      if Result.Via_Env_Heuristic then
         Assert (not Result.Via_DA1, "FUNC-C52-016: Via_Env_Heuristic=True implies Via_DA1=False (invariant I3)");
         Assert
           (not Result.Via_Active_Probe,
            "FUNC-C52-016: Via_Env_Heuristic=True implies Via_Active_Probe=False (invariant I3)");
      end if;
   end Test_Detect_No_Exception;

   procedure Test_Detect_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-C52-017: Detect_Clipboard called twice must return the same
      --  Probed flag and Support level (cache consistency).
      First  : constant Clipboard_Capabilities := Termicap.Clipboard.IO.Detect_Clipboard;
      Second : constant Clipboard_Capabilities := Termicap.Clipboard.IO.Detect_Clipboard;
   begin
      Assert
        (First.Probed = Second.Probed,
         "FUNC-C52-017: two calls to Detect_Clipboard -> same Probed flag (cache consistency)");
      Assert
        (First.Support = Second.Support,
         "FUNC-C52-017: two calls to Detect_Clipboard -> same Support level (cache consistency)");
      Assert
        (First.Via_DA1 = Second.Via_DA1,
         "FUNC-C52-017: two calls to Detect_Clipboard -> same Via_DA1 flag (cache consistency)");
   end Test_Detect_Cache_Consistency;

end Test_Clipboard;
