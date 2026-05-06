-------------------------------------------------------------------------------
--  Test_Clipboard - Unit Tests for Termicap.Clipboard Pure Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK types, constants, and functions
--  in Termicap.Clipboard: Clipboard_Support enumeration, Clipboard_Capabilities
--  record, NO_CLIPBOARD_CAPABILITIES, named terminal identifier constants,
--  OSC52_QUERY bytes, OSC52_Parse_Result enumeration, and Parse_OSC52_Response.
--
--  Also covers the DA1 extension (FUNC-C52-003, FUNC-C52-004): the
--  Clipboard_Access literal in DA1_Capability and the DA1_PS_CLIPBOARD_ACCESS
--  constant in Termicap.DA1.
--
--  All tests construct Byte_Array values programmatically and require no live
--  terminal; every test vector is deterministic.
--
--  The IO-level smoke tests call Termicap.Clipboard.IO functions which return
--  NO_CLIPBOARD_CAPABILITIES on non-TTY builds; these tests verify the
--  no-exception contract only.
--
--  Requirements Coverage:
--    - @relation(FUNC-C52-001): Clipboard_Support enumeration ordering (4 vectors)
--    - @relation(FUNC-C52-002): Clipboard_Capabilities record / NO_CLIPBOARD_CAPABILITIES (8 vectors)
--    - @relation(FUNC-C52-003): Clipboard_Access literal in DA1_Capability (2 vectors)
--    - @relation(FUNC-C52-004): DA1_PS_CLIPBOARD_ACCESS = 52 constant (2 vectors)
--    - @relation(FUNC-C52-005): Named terminal identifier constants (8 vectors)
--    - @relation(FUNC-C52-007): OSC52_QUERY byte constant (4 vectors)
--    - @relation(FUNC-C52-008): OSC52_Parse_Result / Parse_OSC52_Response (19 vectors)
--    - @relation(FUNC-C52-015): CLIPBOARD_PROBE_TIMEOUT_MS constant (2 vectors)
--    - @relation(FUNC-C52-016): Detect_Clipboard no-exception contract (2 vectors)
--    - @relation(FUNC-C52-017): Cache consistency (1 vector)

with AUnit.Test_Cases;

package Test_Clipboard is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-C52-001: Clipboard_Support enumeration ordering
   ---------------------------------------------------------------------------

   --  FUNC-C52-001: None is Clipboard_Support'First (lowest capability)
   procedure Test_Support_None_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-001: Read_Write is Clipboard_Support'Last (highest capability)
   procedure Test_Support_Read_Write_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-001: ordering None < Write_Only < Read_Write
   procedure Test_Support_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-001: >= operator: Write_Only >= Write_Only is True
   procedure Test_Support_Ge_Write_Only_Self (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-001: >= operator: Read_Write >= Write_Only is True
   procedure Test_Support_Ge_Read_Write_Vs_Write_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-001: >= operator: None >= Write_Only is False
   procedure Test_Support_None_Not_Ge_Write_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-002: Clipboard_Capabilities record / NO_CLIPBOARD_CAPABILITIES
   ---------------------------------------------------------------------------

   --  FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Support = None
   procedure Test_No_Caps_Support_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_DA1 = False
   procedure Test_No_Caps_Via_DA1_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_Active_Probe = False
   procedure Test_No_Caps_Via_Active_Probe_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Via_Env_Heuristic = False
   procedure Test_No_Caps_Via_Env_Heuristic_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-002: NO_CLIPBOARD_CAPABILITIES.Probed = False
   procedure Test_No_Caps_Probed_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-002: default-initialised Clipboard_Capabilities equals NO_CLIPBOARD_CAPABILITIES
   procedure Test_Default_Equals_No_Clipboard_Capabilities (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-002: fields are independent — setting Via_DA1 does not affect Via_Active_Probe
   procedure Test_Caps_Fields_Independent (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-002: Support field can be assigned independently
   procedure Test_Caps_Support_Assignable (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-003: Clipboard_Access literal in DA1_Capability
   ---------------------------------------------------------------------------

   --  FUNC-C52-003: Clipboard_Access is a member of DA1_Capability
   procedure Test_DA1_Clipboard_Access_Exists (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-003: Interpret_DA1 with Ps=52 sets Flags(Clipboard_Access)=True
   procedure Test_DA1_Interpret_Ps52_Sets_Clipboard_Access (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-003: Has_Capability returns True for Clipboard_Access when Ps=52 present
   procedure Test_DA1_Has_Capability_Clipboard_Access_True (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-003: Has_Capability returns False for Clipboard_Access when Ps=52 absent
   procedure Test_DA1_Has_Capability_Clipboard_Access_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS constant
   ---------------------------------------------------------------------------

   --  FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS = 52
   procedure Test_DA1_Ps_Clipboard_Access_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-004: DA1_PS_CLIPBOARD_ACCESS is a positive integer constant
   procedure Test_DA1_Ps_Clipboard_Access_Positive (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-005: Named terminal identifier constants
   ---------------------------------------------------------------------------

   --  FUNC-C52-005: TERM_PROGRAM_WEZTERM = "WezTerm"
   procedure Test_Constant_Term_Program_Wezterm (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: TERM_PROGRAM_ITERM2 = "iTerm.app"
   procedure Test_Constant_Term_Program_Iterm2 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: TERM_PROGRAM_VSCODE = "vscode"
   procedure Test_Constant_Term_Program_Vscode (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: ENV_WT_SESSION = "WT_SESSION"
   procedure Test_Constant_Env_Wt_Session (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: ENV_TMUX = "TMUX"
   procedure Test_Constant_Env_Tmux (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: ENV_STY = "STY"
   procedure Test_Constant_Env_Sty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: TERM_XTERM_KITTY = "xterm-kitty"
   procedure Test_Constant_Term_Xterm_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: TERM_XTERM = "xterm"
   procedure Test_Constant_Term_Xterm (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-005: all constants are non-empty strings
   procedure Test_Constants_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-007: OSC52_QUERY byte constant
   ---------------------------------------------------------------------------

   --  FUNC-C52-007: OSC52_QUERY has length 9
   procedure Test_Query_Length (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-007: OSC52_QUERY starts with ESC ] (0x1B 0x5D)
   procedure Test_Query_Starts_With_ESC_Bracket (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-007: OSC52_QUERY ends with BEL (0x07)
   procedure Test_Query_Ends_With_BEL (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-007: OSC52_QUERY contains "52;c;?" as ASCII bytes at positions 3..8
   procedure Test_Query_Payload_Content (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-008: OSC52_Parse_Result enumeration distinctness
   ---------------------------------------------------------------------------

   --  FUNC-C52-008: Not_Present /= Valid_Response
   procedure Test_Parse_Result_Not_Present_Neq_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: Valid_Response /= Malformed
   procedure Test_Parse_Result_Valid_Neq_Malformed (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: Not_Present /= Malformed
   procedure Test_Parse_Result_Not_Present_Neq_Malformed (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-008: Parse_OSC52_Response — Not_Present cases
   ---------------------------------------------------------------------------

   --  FUNC-C52-008: empty buffer (Length=0) -> Not_Present
   procedure Test_Parse_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: buffer with noise bytes only (no ESC ] 52) -> Not_Present
   procedure Test_Parse_No_OSC52_Introducer (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: DA1 response only (no OSC 52 bytes) -> Not_Present
   procedure Test_Parse_DA1_Response_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: Length = 0 on non-empty buffer -> Not_Present (nothing scanned)
   procedure Test_Parse_Length_Zero_Non_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: buffer shorter than the minimum OSC 52 header -> Not_Present
   procedure Test_Parse_Too_Short (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-008: Parse_OSC52_Response — Valid_Response cases
   ---------------------------------------------------------------------------

   --  FUNC-C52-008: minimal BEL-terminated response ESC ] 52;c;<base64> BEL -> Valid_Response
   procedure Test_Parse_Valid_BEL_Terminated (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: ST-terminated response ESC ] 52;c;<base64> ESC \ -> Valid_Response
   procedure Test_Parse_Valid_ST_Terminated (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: empty payload (clipboard empty) ESC ] 52;c; BEL -> Valid_Response
   procedure Test_Parse_Valid_Empty_Payload (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: response with "p" selection character -> Valid_Response
   procedure Test_Parse_Valid_Primary_Selection (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: OSC 52 response preceded by noise bytes -> Valid_Response
   procedure Test_Parse_Valid_With_Leading_Noise (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: OSC 52 response followed by DA1 sentinel -> Valid_Response
   procedure Test_Parse_Valid_Before_DA1 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: Length < Buffer'Length uses only the valid slice
   procedure Test_Parse_Partial_Fill (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-008: Parse_OSC52_Response — Malformed cases
   ---------------------------------------------------------------------------

   --  FUNC-C52-008: OSC 52 introducer found but no terminator -> Malformed
   procedure Test_Parse_Malformed_No_Terminator (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-008: OSC 52 introducer found but only one semicolon before BEL -> Malformed
   procedure Test_Parse_Malformed_Too_Few_Semicolons (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS constant
   ---------------------------------------------------------------------------

   --  FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS = 1000
   procedure Test_Timeout_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-015: CLIPBOARD_PROBE_TIMEOUT_MS >= 100 (spec minimum)
   procedure Test_Timeout_At_Least_100 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-C52-016, FUNC-C52-017: IO-level smoke tests
   ---------------------------------------------------------------------------

   --  FUNC-C52-016: Detect_Clipboard returns without exception
   procedure Test_Detect_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-C52-017: Calling Detect_Clipboard twice returns same Probed flag (cache consistency)
   procedure Test_Detect_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Clipboard;
