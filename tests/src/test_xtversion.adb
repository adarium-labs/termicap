-------------------------------------------------------------------------------
--  Test_XTVERSION - Unit Tests for Termicap.XTVERSION
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;          use AUnit.Assertions;
with AUnit.Test_Cases;          use AUnit.Test_Cases.Registration;

with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;

with Termicap.XTVERSION;        use Termicap.XTVERSION;

package body Test_XTVERSION is

   ---------------------------------------------------------------------------
   --  Byte constant helpers
   ---------------------------------------------------------------------------

   ESC_BYTE : constant Byte := 16#1B#;  --  ESC (0x1B)
   DCS_P    : constant Byte := 16#50#;  --  P (0x50), DCS introducer second byte
   GT_BYTE  : constant Byte := 16#3E#;  --  > (0x3E), XTVERSION discriminator
   LT_BYTE  : constant Byte := 16#3C#;  --  < (0x3C), wrong discriminator
   PIPE     : constant Byte := 16#7C#;  --  | (0x7C), XTVERSION discriminator
   ST_BACK  : constant Byte := 16#5C#;  --  \ (0x5C), ST second byte
   BEL_BYTE : constant Byte := 16#07#;  --  BEL (0x07), alternative ST

   --  Payload character helpers
   CHR_x  : constant Byte := 16#78#;  --  'x'
   CHR_t  : constant Byte := 16#74#;  --  't'
   CHR_e  : constant Byte := 16#65#;  --  'e'
   CHR_r  : constant Byte := 16#72#;  --  'r'
   CHR_m  : constant Byte := 16#6D#;  --  'm'
   CHR_LP : constant Byte := 16#28#;  --  '(' left parenthesis
   CHR_RP : constant Byte := 16#29#;  --  ')' right parenthesis
   CHR_3  : constant Byte := 16#33#;  --  '3'
   CHR_8  : constant Byte := 16#38#;  --  '8'
   CHR_u  : constant Byte := 16#75#;  --  'u'
   CHR_SP : constant Byte := 16#20#;  --  ' ' (ASCII space)
   CHR_DT : constant Byte := 16#2E#;  --  '.'
   CHR_4  : constant Byte := 16#34#;  --  '4'
   CHR_W  : constant Byte := 16#57#;  --  'W'
   CHR_z  : constant Byte := 16#7A#;  --  'z'
   CHR_TUC : constant Byte := 16#54#;  --  'T' (uppercase, distinct from CHR_t = lowercase t)
   CHR_2  : constant Byte := 16#32#;  --  '2'
   CHR_0  : constant Byte := 16#30#;  --  '0'
   CHR_1  : constant Byte := 16#31#;  --  '1'
   CHR_9  : constant Byte := 16#39#;  --  '9'
   CHR_hy : constant Byte := 16#2D#;  --  '-' (hyphen)
   CHR_5  : constant Byte := 16#35#;  --  '5'
   CHR_6  : constant Byte := 16#36#;  --  '6'
   CHR_c  : constant Byte := 16#63#;  --  'c'
   CHR_f  : constant Byte := 16#66#;  --  'f'

   ---------------------------------------------------------------------------
   --  Shared DCS prefix (ESC P > |) and ST suffix (ESC \)
   ---------------------------------------------------------------------------
   --  ESC P > |  — four-byte DCS XTVERSION prefix
   DCS_PREFIX_1 : constant Byte := ESC_BYTE;
   DCS_PREFIX_2 : constant Byte := DCS_P;
   DCS_PREFIX_3 : constant Byte := GT_BYTE;
   DCS_PREFIX_4 : constant Byte := PIPE;

   --  ESC \  — two-byte String Terminator
   ST_1 : constant Byte := ESC_BYTE;
   ST_2 : constant Byte := ST_BACK;


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.XTVERSION");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-XTV-003: Contains_XTVERSION_Response
      Register_Routine (T, Test_Contains_Valid_ST_Terminated'Access,
         "FUNC-XTV-003: well-formed ESC \\ terminated -> True");
      Register_Routine (T, Test_Contains_Valid_BEL_Terminated'Access,
         "FUNC-XTV-003: well-formed BEL terminated -> True");
      Register_Routine (T, Test_Contains_Empty_Input'Access,
         "FUNC-XTV-003: empty input (Length=0) -> False");
      Register_Routine (T, Test_Contains_Too_Short'Access,
         "FUNC-XTV-003: fewer than 6 bytes -> False");
      Register_Routine (T, Test_Contains_Wrong_Discriminator'Access,
         "FUNC-XTV-003: ESC P < | wrong discriminator -> False");
      Register_Routine (T, Test_Contains_No_ST_Terminator'Access,
         "FUNC-XTV-003: no ST terminator -> False");
      Register_Routine (T, Test_Contains_Empty_Payload'Access,
         "FUNC-XTV-003: valid envelope but empty payload (ESC P > | ESC \\) -> False");

      --  FUNC-XTV-004: Extract_XTV_Payload
      Register_Routine (T, Test_Extract_Payload_Offset_Xterm'Access,
         "FUNC-XTV-004: xterm response -> Offset = Buf'First + 4");
      Register_Routine (T, Test_Extract_Payload_Length_Xterm'Access,
         "FUNC-XTV-004: xterm response -> Length = payload byte count");
      Register_Routine (T, Test_Extract_Payload_BEL_Terminated'Access,
         "FUNC-XTV-004: BEL-terminated -> correct payload length");

      --  FUNC-XTV-005: Split_XTV_Payload
      Register_Routine (T, Test_Split_Format_B_Xterm'Access,
         "FUNC-XTV-005: Format B xterm(388) -> Name=xterm, Version=388");
      Register_Routine (T, Test_Split_Format_A_Tmux'Access,
         "FUNC-XTV-005: Format A tmux 3.4 -> Name=tmux, Version=3.4");
      Register_Routine (T, Test_Split_Format_A_WezTerm'Access,
         "FUNC-XTV-005: Format A WezTerm date-hash -> correct tokens");
      Register_Routine (T, Test_Split_No_Delimiter'Access,
         "FUNC-XTV-005: no delimiter -> Name=full payload, Version=empty");

      --  FUNC-XTV-006 / FUNC-XTV-017: Parse_XTVERSION_Response
      Register_Routine (T, Test_Parse_Xterm_Format_B'Access,
         "FUNC-XTV-017 case 1: xterm Format B -> Success, Name=xterm, Version=388");
      Register_Routine (T, Test_Parse_Tmux_Format_A'Access,
         "FUNC-XTV-017 case 2: tmux Format A -> Success, Name=tmux, Version=3.4");
      Register_Routine (T, Test_Parse_WezTerm_Format_A'Access,
         "FUNC-XTV-017 case 3: WezTerm date-hash -> Success, correct tokens");
      Register_Routine (T, Test_Parse_BEL_Terminated'Access,
         "FUNC-XTV-017 case 4: BEL-terminated -> Success, same tokens as ESC \\");
      Register_Routine (T, Test_Parse_Empty_Input'Access,
         "FUNC-XTV-017 case 5: empty input -> Parse_Error");
      Register_Routine (T, Test_Parse_Wrong_Discriminator'Access,
         "FUNC-XTV-017 case 6: ESC P < | wrong discriminator -> Parse_Error");
      Register_Routine (T, Test_Parse_No_ST_Terminator'Access,
         "FUNC-XTV-017 case 7: no ST terminator -> Parse_Error");
      Register_Routine (T, Test_Parse_Empty_Payload'Access,
         "FUNC-XTV-017 case 8: valid envelope, empty payload -> Parse_Error");
      Register_Routine (T, Test_Parse_No_Delimiter_In_Payload'Access,
         "FUNC-XTV-017 case 9: no delimiter -> Success, Name=full payload, Version=empty");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies: Contains_XTVERSION_Response
   ---------------------------------------------------------------------------


   procedure Test_Contains_Valid_ST_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P > | x t e r m ( 3 8 8 ) ESC \
      --  4-byte prefix + 10-byte payload + 2-byte ST = 16 bytes
      Buf : constant Byte_Array (1 .. 16) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         ST_1, ST_2];
   begin
      Assert
        (Contains_XTVERSION_Response (Buf, 16),
         "Contains_XTVERSION_Response: well-formed xterm ESC \\ response should return True");
   end Test_Contains_Valid_ST_Terminated;


   procedure Test_Contains_Valid_BEL_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P > | x t e r m ( 3 8 8 ) BEL
      --  4-byte prefix + 10-byte payload + 1-byte BEL = 15 bytes
      Buf : constant Byte_Array (1 .. 15) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         BEL_BYTE];
   begin
      Assert
        (Contains_XTVERSION_Response (Buf, 15),
         "Contains_XTVERSION_Response: BEL-terminated response should return True");
   end Test_Contains_Valid_BEL_Terminated;


   procedure Test_Contains_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Length = 0: pre-condition allows this (0 <= Buf'Length)
      Buf : constant Byte_Array (1 .. 6) := [others => 0];
   begin
      Assert
        (not Contains_XTVERSION_Response (Buf, 0),
         "Contains_XTVERSION_Response: empty input (Length=0) should return False");
   end Test_Contains_Empty_Input;


   procedure Test_Contains_Too_Short
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  5 bytes: ESC P > | x  — has prefix and one payload byte but no ST
      Buf : constant Byte_Array (1 .. 5) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4, CHR_x];
   begin
      Assert
        (not Contains_XTVERSION_Response (Buf, 5),
         "Contains_XTVERSION_Response: 5-byte buffer with no ST should return False");
   end Test_Contains_Too_Short;


   procedure Test_Contains_Wrong_Discriminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P < | x t e r m ( 3 8 8 ) ESC \  — wrong '>' replaced by '<'
      Buf : constant Byte_Array (1 .. 16) :=
        [ESC_BYTE, DCS_P, LT_BYTE, PIPE,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         ST_1, ST_2];
   begin
      Assert
        (not Contains_XTVERSION_Response (Buf, 16),
         "Contains_XTVERSION_Response: wrong discriminator < should return False");
   end Test_Contains_Wrong_Discriminator;


   procedure Test_Contains_No_ST_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P > | x t e r m ( 3 8 8 )  — no ST, no BEL
      Buf : constant Byte_Array (1 .. 14) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP];
   begin
      Assert
        (not Contains_XTVERSION_Response (Buf, 14),
         "Contains_XTVERSION_Response: no ST terminator should return False");
   end Test_Contains_No_ST_Terminator;


   procedure Test_Contains_Empty_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P > | ESC \  — valid DCS envelope but zero payload bytes
      Buf : constant Byte_Array (1 .. 6) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4, ST_1, ST_2];
   begin
      Assert
        (not Contains_XTVERSION_Response (Buf, 6),
         "Contains_XTVERSION_Response: empty payload should return False");
   end Test_Contains_Empty_Payload;


   ---------------------------------------------------------------------------
   --  Test Bodies: Extract_XTV_Payload
   ---------------------------------------------------------------------------


   procedure Test_Extract_Payload_Offset_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P > | x t e r m ( 3 8 8 ) ESC \
      Buf    : constant Byte_Array (1 .. 16) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         ST_1, ST_2];
      Slice  : constant Payload_Slice := Extract_XTV_Payload (Buf, 16);
   begin
      Assert
        (Slice.Offset = Buf'First + 4,
         "Extract_XTV_Payload: Offset should be Buf'First + 4 (= 5)");
   end Test_Extract_Payload_Offset_Xterm;


   procedure Test_Extract_Payload_Length_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P > | x t e r m ( 3 8 8 ) ESC \
      --  Payload = "xterm(388)" = 10 bytes
      Buf    : constant Byte_Array (1 .. 16) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         ST_1, ST_2];
      Slice  : constant Payload_Slice := Extract_XTV_Payload (Buf, 16);
   begin
      Assert
        (Slice.Length = 10,
         "Extract_XTV_Payload: Length should be 10 for 'xterm(388)'");
   end Test_Extract_Payload_Length_Xterm;


   procedure Test_Extract_Payload_BEL_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P > | x t e r m ( 3 8 8 ) BEL
      --  Payload = "xterm(388)" = 10 bytes, BEL counts as 1-byte terminator
      Buf    : constant Byte_Array (1 .. 15) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         BEL_BYTE];
      Slice  : constant Payload_Slice := Extract_XTV_Payload (Buf, 15);
   begin
      Assert
        (Slice.Length = 10,
         "Extract_XTV_Payload: BEL-terminated: Length should be 10 for 'xterm(388)'");
      Assert
        (Slice.Offset = Buf'First + 4,
         "Extract_XTV_Payload: BEL-terminated: Offset should be Buf'First + 4");
   end Test_Extract_Payload_BEL_Terminated;


   ---------------------------------------------------------------------------
   --  Test Bodies: Split_XTV_Payload
   ---------------------------------------------------------------------------


   procedure Test_Split_Format_B_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Payload "xterm(388)" starting at offset 1 in a 10-byte buffer
      --  x t e r m ( 3 8 8 )
      Buf    : constant Byte_Array (1 .. 10) :=
        [CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP];
      Tokens : constant Token_Pair := Split_XTV_Payload (Buf, 1, 10);
   begin
      Assert
        (Tokens.Name = To_Unbounded_String ("xterm"),
         "Split_XTV_Payload Format B: Name should be 'xterm'");
      Assert
        (Tokens.Version = To_Unbounded_String ("388"),
         "Split_XTV_Payload Format B: Version should be '388'");
   end Test_Split_Format_B_Xterm;


   procedure Test_Split_Format_A_Tmux
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Payload "tmux 3.4" starting at offset 1 in an 8-byte buffer
      --  t m u x SP 3 . 4
      Buf    : constant Byte_Array (1 .. 8) :=
        [CHR_t, CHR_m, CHR_u, CHR_x,
         CHR_SP, CHR_3, CHR_DT, CHR_4];
      Tokens : constant Token_Pair := Split_XTV_Payload (Buf, 1, 8);
   begin
      Assert
        (Tokens.Name = To_Unbounded_String ("tmux"),
         "Split_XTV_Payload Format A: Name should be 'tmux'");
      Assert
        (Tokens.Version = To_Unbounded_String ("3.4"),
         "Split_XTV_Payload Format A: Version should be '3.4'");
   end Test_Split_Format_A_Tmux;


   procedure Test_Split_Format_A_WezTerm
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Payload "WezTerm 20231203-110809-5046fc22"
      --  W e z T e r m SP 2 0 2 3 1 2 0 3 - 1 1 0 8 0 9 - 5 0 4 6 f c 2 2
      --  7 + 1 + 24 = 32 bytes
      Buf    : constant Byte_Array (1 .. 32) :=
        [CHR_W, CHR_e, CHR_z, CHR_TUC, CHR_e, CHR_r, CHR_m,
         CHR_SP,
         CHR_2, CHR_0, CHR_2, CHR_3, CHR_1, CHR_2, CHR_0, CHR_3,
         CHR_hy,
         CHR_1, CHR_1, CHR_0, CHR_8, CHR_0, CHR_9,
         CHR_hy,
         CHR_5, CHR_0, CHR_4, CHR_6, CHR_f, CHR_c, CHR_2, CHR_2];
      Tokens : constant Token_Pair := Split_XTV_Payload (Buf, 1, 32);
   begin
      Assert
        (Tokens.Name = To_Unbounded_String ("WezTerm"),
         "Split_XTV_Payload WezTerm Format A: Name should be 'WezTerm'");
      Assert
        (Tokens.Version = To_Unbounded_String ("20231203-110809-5046fc22"),
         "Split_XTV_Payload WezTerm Format A: Version should be '20231203-110809-5046fc22'");
   end Test_Split_Format_A_WezTerm;


   procedure Test_Split_No_Delimiter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Payload "myterm" — no '(' and no space
      --  m y t e r m
      Buf    : constant Byte_Array (1 .. 6) :=
        [CHR_m, CHR_t, CHR_e, CHR_r, CHR_m, CHR_t];
      Tokens : constant Token_Pair := Split_XTV_Payload (Buf, 1, 6);
   begin
      Assert
        (Length (Tokens.Name) > 0,
         "Split_XTV_Payload no delimiter: Name should be non-empty");
      Assert
        (Tokens.Version = Null_Unbounded_String,
         "Split_XTV_Payload no delimiter: Version should be empty string");
   end Test_Split_No_Delimiter;


   ---------------------------------------------------------------------------
   --  Test Bodies: Parse_XTVERSION_Response (FUNC-XTV-017 mandatory cases)
   ---------------------------------------------------------------------------


   procedure Test_Parse_Xterm_Format_B
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 1:
      --  ESC P > | x t e r m ( 3 8 8 ) ESC \
      Buf    : constant Byte_Array (1 .. 16) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         ST_1, ST_2];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 16);
   begin
      Assert
        (Result.Status = Success,
         "Parse_XTVERSION_Response xterm Format B: Status should be Success");
      Assert
        (Result.Terminal_Name = To_Unbounded_String ("xterm"),
         "Parse_XTVERSION_Response xterm Format B: Terminal_Name should be 'xterm'");
      Assert
        (Result.Terminal_Version = To_Unbounded_String ("388"),
         "Parse_XTVERSION_Response xterm Format B: Terminal_Version should be '388'");
   end Test_Parse_Xterm_Format_B;


   procedure Test_Parse_Tmux_Format_A
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 2:
      --  ESC P > | t m u x SP 3 . 4 ESC \
      Buf    : constant Byte_Array (1 .. 14) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_t, CHR_m, CHR_u, CHR_x,
         CHR_SP, CHR_3, CHR_DT, CHR_4,
         ST_1, ST_2];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 14);
   begin
      Assert
        (Result.Status = Success,
         "Parse_XTVERSION_Response tmux Format A: Status should be Success");
      Assert
        (Result.Terminal_Name = To_Unbounded_String ("tmux"),
         "Parse_XTVERSION_Response tmux Format A: Terminal_Name should be 'tmux'");
      Assert
        (Result.Terminal_Version = To_Unbounded_String ("3.4"),
         "Parse_XTVERSION_Response tmux Format A: Terminal_Version should be '3.4'");
   end Test_Parse_Tmux_Format_A;


   procedure Test_Parse_WezTerm_Format_A
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 3:
      --  ESC P > | W e z T e r m SP 2 0 2 3 1 2 0 3 - 1 1 0 8 0 9 - 5 0 4 6 f c 2 2 ESC \
      --  4 + 32 + 2 = 38 bytes
      Buf    : constant Byte_Array (1 .. 38) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_W, CHR_e, CHR_z, CHR_TUC, CHR_e, CHR_r, CHR_m,
         CHR_SP,
         CHR_2, CHR_0, CHR_2, CHR_3, CHR_1, CHR_2, CHR_0, CHR_3,
         CHR_hy,
         CHR_1, CHR_1, CHR_0, CHR_8, CHR_0, CHR_9,
         CHR_hy,
         CHR_5, CHR_0, CHR_4, CHR_6, CHR_f, CHR_c, CHR_2, CHR_2,
         ST_1, ST_2];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 38);
   begin
      Assert
        (Result.Status = Success,
         "Parse_XTVERSION_Response WezTerm Format A: Status should be Success");
      Assert
        (Result.Terminal_Name = To_Unbounded_String ("WezTerm"),
         "Parse_XTVERSION_Response WezTerm Format A: Terminal_Name should be 'WezTerm'");
      Assert
        (Result.Terminal_Version = To_Unbounded_String ("20231203-110809-5046fc22"),
         "Parse_XTVERSION_Response WezTerm Format A: Terminal_Version should be '20231203-110809-5046fc22'");
   end Test_Parse_WezTerm_Format_A;


   procedure Test_Parse_BEL_Terminated
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 4:
      --  ESC P > | t m u x SP 3 . 4 BEL  — same payload as case 2, BEL instead of ESC \
      Buf    : constant Byte_Array (1 .. 13) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_t, CHR_m, CHR_u, CHR_x,
         CHR_SP, CHR_3, CHR_DT, CHR_4,
         BEL_BYTE];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 13);
   begin
      Assert
        (Result.Status = Success,
         "Parse_XTVERSION_Response BEL-terminated: Status should be Success");
      Assert
        (Result.Terminal_Name = To_Unbounded_String ("tmux"),
         "Parse_XTVERSION_Response BEL-terminated: Terminal_Name should be 'tmux'");
      Assert
        (Result.Terminal_Version = To_Unbounded_String ("3.4"),
         "Parse_XTVERSION_Response BEL-terminated: Terminal_Version should be '3.4'");
   end Test_Parse_BEL_Terminated;


   procedure Test_Parse_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 5: Length = 0
      Buf    : constant Byte_Array (1 .. 4) := [others => 0];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 0);
   begin
      Assert
        (Result.Status = Parse_Error,
         "Parse_XTVERSION_Response empty input: Status should be Parse_Error");
   end Test_Parse_Empty_Input;


   procedure Test_Parse_Wrong_Discriminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 6:
      --  ESC P < | x t e r m ( 3 8 8 ) ESC \  — '<' instead of '>'
      Buf    : constant Byte_Array (1 .. 16) :=
        [ESC_BYTE, DCS_P, LT_BYTE, PIPE,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP,
         ST_1, ST_2];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 16);
   begin
      Assert
        (Result.Status = Parse_Error,
         "Parse_XTVERSION_Response wrong discriminator: Status should be Parse_Error");
   end Test_Parse_Wrong_Discriminator;


   procedure Test_Parse_No_ST_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 7:
      --  ESC P > | x t e r m ( 3 8 8 )  — no ST and no BEL
      Buf    : constant Byte_Array (1 .. 14) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_x, CHR_t, CHR_e, CHR_r, CHR_m,
         CHR_LP, CHR_3, CHR_8, CHR_8, CHR_RP];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 14);
   begin
      Assert
        (Result.Status = Parse_Error,
         "Parse_XTVERSION_Response no ST terminator: Status should be Parse_Error");
   end Test_Parse_No_ST_Terminator;


   procedure Test_Parse_Empty_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 8:
      --  ESC P > | ESC \  — valid DCS envelope, zero payload bytes
      Buf    : constant Byte_Array (1 .. 6) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4, ST_1, ST_2];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 6);
   begin
      Assert
        (Result.Status = Parse_Error,
         "Parse_XTVERSION_Response empty payload: Status should be Parse_Error");
   end Test_Parse_Empty_Payload;


   procedure Test_Parse_No_Delimiter_In_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  FUNC-XTV-017 case 9:
      --  ESC P > | f o o t e r m ESC \  — no '(' and no space in payload
      --  "footerm" = 7 bytes payload; total = 4 + 7 + 2 = 13 bytes
      Buf    : constant Byte_Array (1 .. 13) :=
        [DCS_PREFIX_1, DCS_PREFIX_2, DCS_PREFIX_3, DCS_PREFIX_4,
         CHR_f, CHR_0, CHR_0, CHR_t, CHR_e, CHR_r, CHR_m,
         ST_1, ST_2];
      Result : constant XTVERSION_Result := Parse_XTVERSION_Response (Buf, 13);
   begin
      Assert
        (Result.Status = Success,
         "Parse_XTVERSION_Response no delimiter: Status should be Success");
      Assert
        (Length (Result.Terminal_Name) > 0,
         "Parse_XTVERSION_Response no delimiter: Terminal_Name should be non-empty");
      Assert
        (Result.Terminal_Version = Null_Unbounded_String,
         "Parse_XTVERSION_Response no delimiter: Terminal_Version should be empty");
   end Test_Parse_No_Delimiter_In_Payload;

end Test_XTVERSION;
