-------------------------------------------------------------------------------
--  Test_XTVERSION - Unit Tests for Termicap.XTVERSION
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK functions in Termicap.XTVERSION:
--  Contains_XTVERSION_Response recognition, Extract_XTV_Payload offset/length
--  extraction, Split_XTV_Payload name/version tokenisation (Format A and B),
--  and Parse_XTVERSION_Response end-to-end orchestration.
--
--  All tests construct Byte_Array values programmatically and require no live
--  terminal.
--
--  Requirements Coverage:
--    - @relation(FUNC-XTV-003): Contains_XTVERSION_Response
--    - @relation(FUNC-XTV-004): Extract_XTV_Payload
--    - @relation(FUNC-XTV-005): Split_XTV_Payload (Format A and Format B)
--    - @relation(FUNC-XTV-006): Parse_XTVERSION_Response
--    - @relation(FUNC-XTV-017): Nine mandatory test cases

with AUnit.Test_Cases;

package Test_XTVERSION is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-XTV-003: Contains_XTVERSION_Response
   ---------------------------------------------------------------------------

   --  FUNC-XTV-003: Well-formed xterm response (ESC \ terminated) -> True
   procedure Test_Contains_Valid_ST_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-003: Well-formed response BEL-terminated (0x07) -> True
   procedure Test_Contains_Valid_BEL_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-003: Empty input (Length = 0) -> False
   procedure Test_Contains_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-003: Too short (< 6 bytes) -> False
   procedure Test_Contains_Too_Short
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-003: Wrong discriminator (ESC P < | instead of ESC P > |) -> False
   procedure Test_Contains_Wrong_Discriminator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-003: Missing ST terminator (no ESC \ and no BEL) -> False
   procedure Test_Contains_No_ST_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-003: Valid envelope but empty payload (ESC P > | ESC \) -> False
   procedure Test_Contains_Empty_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-XTV-004: Extract_XTV_Payload
   ---------------------------------------------------------------------------

   --  FUNC-XTV-004: xterm response -> Offset = 5 (1-based after 4-byte prefix)
   procedure Test_Extract_Payload_Offset_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-004: xterm response -> Length equals payload byte count
   procedure Test_Extract_Payload_Length_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-004: BEL-terminated -> correct payload length
   procedure Test_Extract_Payload_BEL_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-XTV-005: Split_XTV_Payload
   ---------------------------------------------------------------------------

   --  FUNC-XTV-005: Format B "xterm(388)" -> Name="xterm", Version="388"
   procedure Test_Split_Format_B_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-005: Format A "tmux 3.4" -> Name="tmux", Version="3.4"
   procedure Test_Split_Format_A_Tmux
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-005: Format A WezTerm date-hash -> Name="WezTerm", Version="20231203-110809-5046fc22"
   procedure Test_Split_Format_A_WezTerm
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-005: No delimiter -> Name = full payload, Version = ""
   procedure Test_Split_No_Delimiter
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-XTV-006: Parse_XTVERSION_Response (FUNC-XTV-017 mandatory cases)
   ---------------------------------------------------------------------------

   --  FUNC-XTV-017 case 1: Well-formed xterm Format B (ESC \ terminated)
   --  -> Status=Success, Name="xterm", Version="388"
   procedure Test_Parse_Xterm_Format_B
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 2: Well-formed tmux Format A (ESC \ terminated)
   --  -> Status=Success, Name="tmux", Version="3.4"
   procedure Test_Parse_Tmux_Format_A
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 3: Well-formed WezTerm Format A with date-hash version
   --  -> Status=Success, Name="WezTerm", Version="20231203-110809-5046fc22"
   procedure Test_Parse_WezTerm_Format_A
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 4: BEL-terminated response (ST = 0x07)
   --  -> same Name/Version as ESC \ terminated equivalent
   procedure Test_Parse_BEL_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 5: Empty input (Length = 0) -> Status=Parse_Error
   procedure Test_Parse_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 6: Wrong discriminator (ESC P < | instead of ESC P > |)
   --  -> Status=Parse_Error
   procedure Test_Parse_Wrong_Discriminator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 7: No ST terminator -> Status=Parse_Error
   procedure Test_Parse_No_ST_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 8: Valid envelope but empty payload (ESC P > | ESC \)
   --  -> Status=Parse_Error
   procedure Test_Parse_Empty_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-XTV-017 case 9: Payload with no space and no parenthesis
   --  -> Status=Success, Name=full payload, Version=""
   procedure Test_Parse_No_Delimiter_In_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_XTVERSION;
