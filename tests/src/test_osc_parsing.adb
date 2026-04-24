-------------------------------------------------------------------------------
--  Test_OSC_Parsing - Unit Tests for Termicap.OSC.Parsing
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Interfaces.C; use Interfaces.C;

with Termicap.OSC;         use Termicap.OSC;
with Termicap.OSC.Parsing; use Termicap.OSC.Parsing;

package body Test_OSC_Parsing is

   ---------------------------------------------------------------------------
   --  Byte constant helpers
   ---------------------------------------------------------------------------

   ESC_BYTE : constant Byte := 16#1B#;  --  ESC (0x1B)
   CSI_L    : constant Byte := 16#5B#;  --  [ (0x5B)
   QUEST    : constant Byte := 16#3F#;  --  ? (0x3F)
   SEMI     : constant Byte := 16#3B#;  --  ; (0x3B)
   TERM_C   : constant Byte := 16#63#;  --  c (0x63), DA1 terminator
   DCS_P    : constant Byte := 16#50#;  --  P (0x50), DCS introducer second byte
   ST_BACK  : constant Byte := 16#5C#;  --  \ (0x5C), ST second byte
   DIG_0    : constant Byte := 16#30#;  --  '0'
   DIG_1    : constant Byte := 16#31#;  --  '1'
   DIG_2    : constant Byte := 16#32#;  --  '2'
   DIG_4    : constant Byte := 16#34#;  --  '4'
   DIG_5    : constant Byte := 16#35#;  --  '5'
   DIG_6    : constant Byte := 16#36#;  --  '6'
   DIG_9    : constant Byte := 16#39#;  --  '9'
   LOWER_N  : constant Byte := 16#6E#;  --  n (0x6E), CPR terminator
   CHR_T    : constant Byte := 16#74#;  --  t (0x74)
   CHR_M    : constant Byte := 16#6D#;  --  m (0x6D)
   CHR_U    : constant Byte := 16#75#;  --  u (0x75)
   CHR_X    : constant Byte := 16#78#;  --  x (0x78)

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.OSC.Parsing");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-OSC-006: Contains_DA1_Response
      Register_Routine (T, Test_Contains_DA1_Empty_Buffer'Access, "FUNC-OSC-006: Empty buffer (Length=0) -> False");
      Register_Routine (T, Test_Contains_DA1_No_Esc'Access, "FUNC-OSC-006: Buffer with no ESC bytes -> False");
      Register_Routine
        (T, Test_Contains_DA1_Incomplete_No_Quest'Access, "FUNC-OSC-006: Incomplete DA1 - ESC [ only, no ? -> False");
      Register_Routine
        (T,
         Test_Contains_DA1_Incomplete_No_Term'Access,
         "FUNC-OSC-006: Incomplete DA1 - ESC [ ? but no c terminator -> False");
      Register_Routine (T, Test_Contains_DA1_Valid_Two_Params'Access, "FUNC-OSC-006: Valid ESC [ ? 6 4 ; 1 c -> True");
      Register_Routine (T, Test_Contains_DA1_Non_DA1_CSI'Access, "FUNC-OSC-006: Non-DA1 CSI ESC [ 6 n (no ?) -> False");
      Register_Routine
        (T, Test_Contains_DA1_After_OSC_Response'Access, "FUNC-OSC-006: DA1 preceded by OSC response bytes -> True");
      Register_Routine
        (T,
         Test_Contains_DA1_Minimal_No_Params'Access,
         "FUNC-OSC-006: Minimal DA1 ESC [ ? c (no digit params) -> True");
      Register_Routine
        (T,
         Test_Contains_DA1_Multiple_Esc_Last_Is_DA1'Access,
         "FUNC-OSC-006: Multiple ESC sequences, only last is DA1 -> True");

      --  FUNC-OSC-006: DA1_Response_Start
      Register_Routine
        (T,
         Test_DA1_Start_Empty_Buffer'Access,
         "FUNC-OSC-006: DA1_Response_Start empty buffer -> returns 0 (= Length)");
      Register_Routine
        (T, Test_DA1_Start_No_DA1'Access, "FUNC-OSC-006: DA1_Response_Start no DA1 present -> returns Length");
      Register_Routine
        (T, Test_DA1_Start_At_First_Byte'Access, "FUNC-OSC-006: DA1_Response_Start DA1 at first byte -> returns 1");
      Register_Routine
        (T,
         Test_DA1_Start_After_Prefix'Access,
         "FUNC-OSC-006: DA1_Response_Start DA1 after prefix bytes -> correct index");
      Register_Routine
        (T,
         Test_DA1_Start_After_OSC11_Response'Access,
         "FUNC-OSC-006: DA1_Response_Start after OSC11 response -> DA1 ESC position");
      Register_Routine
        (T, Test_DA1_Start_Result_Le_Length'Access, "FUNC-OSC-006: DA1_Response_Start result always <= Length");

      --  FUNC-OSC-010: Parse_DA1_Response
      Register_Routine (T, Test_Parse_DA1_Empty'Access, "FUNC-OSC-010: Empty input (Length=0) -> Count=0");
      Register_Routine
        (T, Test_Parse_DA1_Two_Params'Access, "FUNC-OSC-010: ESC [ ? 6 4 ; 1 c -> Count=2, Values=(64,1)");
      Register_Routine (T, Test_Parse_DA1_Single_Param'Access, "FUNC-OSC-010: ESC [ ? 6 c -> Count=1, Values(1)=6");
      Register_Routine (T, Test_Parse_DA1_Many_Params'Access, "FUNC-OSC-010: ESC [ ? 1 ; 2 ; 4 ; 6 ; 9 c -> Count=5");
      Register_Routine (T, Test_Parse_DA1_No_Match'Access, "FUNC-OSC-010: No matching pattern -> Count=0");
      Register_Routine
        (T, Test_Parse_DA1_Incomplete'Access, "FUNC-OSC-010: Incomplete DA1 (no terminating c) -> Count=0");
      Register_Routine (T, Test_Parse_DA1_Wrong_Prefix'Access, "FUNC-OSC-010: Wrong prefix (no ? after [) -> Count=0");
      Register_Routine
        (T, Test_Parse_DA1_Count_Bounded'Access, "FUNC-OSC-010: Count <= MAX_DA1_PARAMS postcondition holds");
      Register_Routine
        (T, Test_Parse_DA1_Multi_Digit_Params'Access, "FUNC-OSC-010: ESC [ ? 1 5 ; 2 2 c -> Count=2, Values=(15,22)");

      --  FUNC-OSC-014: Wrap_For_Passthrough
      Register_Routine
        (T, Test_Wrap_No_Passthrough_Identity'Access, "FUNC-OSC-014: No_Passthrough returns Query unchanged");
      Register_Routine
        (T, Test_Wrap_No_Passthrough_Empty'Access, "FUNC-OSC-014: No_Passthrough with empty query -> empty result");
      Register_Routine (T, Test_Wrap_Tmux_Has_DCS_Prefix'Access, "FUNC-OSC-014: Tmux wrap starts with ESC P and tmux;");
      Register_Routine (T, Test_Wrap_Tmux_Has_ST_Suffix'Access, "FUNC-OSC-014: Tmux wrap ends with ESC \\");
      Register_Routine
        (T, Test_Wrap_Tmux_Inner_Esc'Access, "FUNC-OSC-014: Tmux wrap contains inner ESC before query bytes");
      Register_Routine
        (T, Test_Wrap_Tmux_Empty_Query'Access, "FUNC-OSC-014: Tmux wrap with empty query still has wrapper bytes");
      Register_Routine (T, Test_Wrap_Screen_Has_DCS_Prefix'Access, "FUNC-OSC-014: Screen wrap starts with ESC P");
      Register_Routine (T, Test_Wrap_Screen_Has_ST_Suffix'Access, "FUNC-OSC-014: Screen wrap ends with ESC \\");
      Register_Routine (T, Test_Wrap_Screen_Length'Access, "FUNC-OSC-014: Screen wrap length = 4 + Query'Length");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------


   ---------------------------------------------------------------------------
   --  FUNC-OSC-006: Contains_DA1_Response
   ---------------------------------------------------------------------------

   procedure Test_Contains_DA1_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buf : constant Byte_Array (1 .. 8) := [others => 0];
   begin
      Assert (not Contains_DA1_Response (Buf, 0), "Contains_DA1_Response with Length=0 should return False");
   end Test_Contains_DA1_Empty_Buffer;

   procedure Test_Contains_DA1_No_Esc (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Plain ASCII bytes, no ESC
      Buf : constant Byte_Array (1 .. 5) := [16#41#, 16#42#, 16#43#, 16#44#, 16#45#];  --  A B C D E
   begin
      Assert
        (not Contains_DA1_Response (Buf, Buf'Length), "Contains_DA1_Response with no ESC bytes should return False");
   end Test_Contains_DA1_No_Esc;

   procedure Test_Contains_DA1_Incomplete_No_Quest (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ only — missing ? and c
      Buf : constant Byte_Array (1 .. 2) := [ESC_BYTE, CSI_L];
   begin
      Assert
        (not Contains_DA1_Response (Buf, Buf'Length),
         "Contains_DA1_Response with ESC [ only (no ?) should return False");
   end Test_Contains_DA1_Incomplete_No_Quest;

   procedure Test_Contains_DA1_Incomplete_No_Term (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 6 4 — no terminating c
      Buf : constant Byte_Array (1 .. 5) := [ESC_BYTE, CSI_L, QUEST, DIG_6, DIG_4];
   begin
      Assert
        (not Contains_DA1_Response (Buf, Buf'Length),
         "Contains_DA1_Response with ESC [ ? 6 4 but no c should return False");
   end Test_Contains_DA1_Incomplete_No_Term;

   procedure Test_Contains_DA1_Valid_Two_Params (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 6 4 ; 1 c — valid DA1 with two parameters
      Buf : constant Byte_Array (1 .. 8) := [ESC_BYTE, CSI_L, QUEST, DIG_6, DIG_4, SEMI, DIG_1, TERM_C];
   begin
      Assert
        (Contains_DA1_Response (Buf, Buf'Length), "Contains_DA1_Response with ESC [ ? 6 4 ; 1 c should return True");
   end Test_Contains_DA1_Valid_Two_Params;

   procedure Test_Contains_DA1_Non_DA1_CSI (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ 6 n — CPR response, no ? after [
      Buf : constant Byte_Array (1 .. 4) := [ESC_BYTE, CSI_L, DIG_6, LOWER_N];
   begin
      Assert
        (not Contains_DA1_Response (Buf, Buf'Length),
         "Contains_DA1_Response with ESC [ 6 n (CPR, no ?) should return False");
   end Test_Contains_DA1_Non_DA1_CSI;

   procedure Test_Contains_DA1_After_OSC_Response (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Realistic case: OSC 11 response (simplified) followed by DA1
      --  OSC 11 response bytes (stub): ESC ] 1 1 ; r g b ESC \
      --  then DA1: ESC [ ? 6 4 ; 1 c
      Buf : constant Byte_Array (1 .. 17) :=
        [ESC_BYTE,
         16#5D#,              --  ESC ]
         DIG_1,
         DIG_1,
         SEMI,            --  1 1 ;
         16#72#,
         16#67#,
         16#62#,        --  r g b (stub)
         ESC_BYTE,
         ST_BACK,             --  ESC \ (ST)
         ESC_BYTE,
         CSI_L,
         QUEST,        --  ESC [ ?
         DIG_6,
         DIG_4,
         SEMI,
         TERM_C];   --  6 4 ; c
   begin
      Assert
        (Contains_DA1_Response (Buf, Buf'Length),
         "Contains_DA1_Response with OSC response followed by DA1 should return True");
   end Test_Contains_DA1_After_OSC_Response;

   procedure Test_Contains_DA1_Minimal_No_Params (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? c — minimal DA1 with no digit parameters between ? and c
      Buf : constant Byte_Array (1 .. 4) := [ESC_BYTE, CSI_L, QUEST, TERM_C];
   begin
      Assert
        (Contains_DA1_Response (Buf, Buf'Length), "Contains_DA1_Response with minimal ESC [ ? c should return True");
   end Test_Contains_DA1_Minimal_No_Params;

   procedure Test_Contains_DA1_Multiple_Esc_Last_Is_DA1 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Two CSI sequences: first is CPR (ESC [ 6 n), second is DA1 (ESC [ ? 1 c)
      Buf : constant Byte_Array (1 .. 9) :=
        [ESC_BYTE,
         CSI_L,
         DIG_6,
         LOWER_N,  --  ESC [ 6 n  (CPR, not DA1)
         16#41#,                            --  some other byte
         ESC_BYTE,
         CSI_L,
         QUEST,
         TERM_C];   --  ESC [ ? c  (DA1)
   begin
      Assert
        (Contains_DA1_Response (Buf, Buf'Length),
         "Contains_DA1_Response with DA1 as second ESC sequence should return True");
   end Test_Contains_DA1_Multiple_Esc_Last_Is_DA1;


   ---------------------------------------------------------------------------
   --  FUNC-OSC-006: DA1_Response_Start
   ---------------------------------------------------------------------------

   procedure Test_DA1_Start_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buf    : constant Byte_Array (1 .. 4) := [others => 0];
      Result : constant Natural := DA1_Response_Start (Buf, 0);
   begin
      Assert
        (Result = 0, "DA1_Response_Start with Length=0 should return 0 (= Length)," & " got" & Natural'Image (Result));
   end Test_DA1_Start_Empty_Buffer;

   procedure Test_DA1_Start_No_DA1 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Plain bytes, no DA1
      Buf    : constant Byte_Array (1 .. 4) := [16#41#, 16#42#, 16#43#, 16#44#];
      Result : constant Natural := DA1_Response_Start (Buf, Buf'Length);
   begin
      Assert
        (Result = Buf'Length,
         "DA1_Response_Start with no DA1 should return Length="
         & Natural'Image (Buf'Length)
         & ", got"
         & Natural'Image (Result));
   end Test_DA1_Start_No_DA1;

   procedure Test_DA1_Start_At_First_Byte (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  DA1 starting at byte 1: ESC [ ? 6 4 c
      Buf    : constant Byte_Array (1 .. 6) := [ESC_BYTE, CSI_L, QUEST, DIG_6, DIG_4, TERM_C];
      Result : constant Natural := DA1_Response_Start (Buf, Buf'Length);
   begin
      Assert (Result = 1, "DA1_Response_Start with DA1 at byte 1 should return 1," & " got" & Natural'Image (Result));
   end Test_DA1_Start_At_First_Byte;

   procedure Test_DA1_Start_After_Prefix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  3 prefix bytes then DA1: A B C ESC [ ? 1 c
      Buf    : constant Byte_Array (1 .. 8) :=
        [16#41#,
         16#42#,
         16#43#,             --  A B C
         ESC_BYTE,
         CSI_L,
         QUEST,
         DIG_1,
         TERM_C];
      Result : constant Natural := DA1_Response_Start (Buf, Buf'Length);
   begin
      Assert
        (Result = 4,
         "DA1_Response_Start with 3 prefix bytes should return 4 (ESC position)," & " got" & Natural'Image (Result));
   end Test_DA1_Start_After_Prefix;

   procedure Test_DA1_Start_After_OSC11_Response (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  OSC 11 response (10 bytes) then DA1 (4 bytes): total 14 bytes
      --  OSC 11: ESC ] 1 1 ; r g b ESC \
      --  DA1:    ESC [ ? 1 c
      Buf    : constant Byte_Array (1 .. 14) :=
        [ESC_BYTE,
         16#5D#,          --  ESC ]
         DIG_1,
         DIG_1,
         SEMI,        --  1 1 ;
         16#72#,
         16#67#,
         16#62#,    --  r g b
         ESC_BYTE,
         ST_BACK,         --  ESC \ (ST)
         ESC_BYTE,
         CSI_L,
         QUEST,
         TERM_C];  --  ESC [ ? c (DA1)
      Result : constant Natural := DA1_Response_Start (Buf, Buf'Length);
   begin
      --  The DA1 ESC is at position 11
      Assert
        (Result = 11, "DA1_Response_Start after OSC 11 response should return 11," & " got" & Natural'Image (Result));
   end Test_DA1_Start_After_OSC11_Response;

   procedure Test_DA1_Start_Result_Le_Length (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Test postcondition: result <= Length in both found and not-found cases
      Buf_With    : constant Byte_Array (1 .. 4) := [ESC_BYTE, CSI_L, QUEST, TERM_C];
      Buf_Without : constant Byte_Array (1 .. 3) := [16#41#, 16#42#, 16#43#];
      R1          : constant Natural := DA1_Response_Start (Buf_With, Buf_With'Length);
      R2          : constant Natural := DA1_Response_Start (Buf_Without, Buf_Without'Length);
   begin
      Assert
        (R1 <= Buf_With'Length,
         "DA1_Response_Start postcondition: result <= Length violated (found case)," & " result=" & Natural'Image (R1));
      Assert
        (R2 <= Buf_Without'Length,
         "DA1_Response_Start postcondition: result <= Length violated (not-found case),"
         & " result="
         & Natural'Image (R2));
   end Test_DA1_Start_Result_Le_Length;


   ---------------------------------------------------------------------------
   --  FUNC-OSC-010: Parse_DA1_Response
   ---------------------------------------------------------------------------

   procedure Test_Parse_DA1_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buf    : constant Byte_Array (1 .. 8) := [others => 0];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, 0);
   begin
      Assert
        (Result.Count = 0,
         "Parse_DA1_Response with Length=0 should return Count=0," & " got" & Natural'Image (Result.Count));
   end Test_Parse_DA1_Empty;

   procedure Test_Parse_DA1_Two_Params (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 6 4 ; 1 c
      Buf    : constant Byte_Array (1 .. 8) := [ESC_BYTE, CSI_L, QUEST, DIG_6, DIG_4, SEMI, DIG_1, TERM_C];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count = 2,
         "Parse_DA1_Response ESC [ ? 6 4 ; 1 c should return Count=2," & " got" & Natural'Image (Result.Count));
      Assert
        (Result.Values (1) = 64,
         "Parse_DA1_Response first param should be 64," & " got" & Natural'Image (Result.Values (1)));
      Assert
        (Result.Values (2) = 1,
         "Parse_DA1_Response second param should be 1," & " got" & Natural'Image (Result.Values (2)));
   end Test_Parse_DA1_Two_Params;

   procedure Test_Parse_DA1_Single_Param (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 6 c
      Buf    : constant Byte_Array (1 .. 5) := [ESC_BYTE, CSI_L, QUEST, DIG_6, TERM_C];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count = 1,
         "Parse_DA1_Response ESC [ ? 6 c should return Count=1," & " got" & Natural'Image (Result.Count));
      Assert
        (Result.Values (1) = 6,
         "Parse_DA1_Response single param should be 6," & " got" & Natural'Image (Result.Values (1)));
   end Test_Parse_DA1_Single_Param;

   procedure Test_Parse_DA1_Many_Params (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 ; 2 ; 4 ; 6 ; 9 c  (5 parameters)
      Buf    : constant Byte_Array (1 .. 13) :=
        [ESC_BYTE, CSI_L, QUEST, DIG_1, SEMI, DIG_2, SEMI, DIG_4, SEMI, DIG_6, SEMI, DIG_9, TERM_C];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count = 5,
         "Parse_DA1_Response with 5 params should return Count=5," & " got" & Natural'Image (Result.Count));
      Assert
        (Result.Values (1) = 1, "Parse_DA1_Response param 1 should be 1," & " got" & Natural'Image (Result.Values (1)));
      Assert
        (Result.Values (3) = 4, "Parse_DA1_Response param 3 should be 4," & " got" & Natural'Image (Result.Values (3)));
      Assert
        (Result.Values (5) = 9, "Parse_DA1_Response param 5 should be 9," & " got" & Natural'Image (Result.Values (5)));
   end Test_Parse_DA1_Many_Params;

   procedure Test_Parse_DA1_No_Match (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Random bytes with no DA1 pattern
      Buf    : constant Byte_Array (1 .. 5) := [16#41#, 16#42#, 16#43#, 16#44#, 16#45#];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count = 0,
         "Parse_DA1_Response with no DA1 pattern should return Count=0," & " got" & Natural'Image (Result.Count));
   end Test_Parse_DA1_No_Match;

   procedure Test_Parse_DA1_Incomplete (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 6 4 — no terminating c
      Buf    : constant Byte_Array (1 .. 5) := [ESC_BYTE, CSI_L, QUEST, DIG_6, DIG_4];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count = 0,
         "Parse_DA1_Response without terminating c should return Count=0," & " got" & Natural'Image (Result.Count));
   end Test_Parse_DA1_Incomplete;

   procedure Test_Parse_DA1_Wrong_Prefix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ 6 n — CSI without ?, terminator is n not c
      Buf    : constant Byte_Array (1 .. 4) := [ESC_BYTE, CSI_L, DIG_6, LOWER_N];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count = 0,
         "Parse_DA1_Response with wrong prefix (no ?) should return Count=0," & " got" & Natural'Image (Result.Count));
   end Test_Parse_DA1_Wrong_Prefix;

   procedure Test_Parse_DA1_Count_Bounded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Valid DA1 with two parameters — verify postcondition Count <= MAX_DA1_PARAMS
      Buf    : constant Byte_Array (1 .. 8) := [ESC_BYTE, CSI_L, QUEST, DIG_6, DIG_4, SEMI, DIG_1, TERM_C];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count <= MAX_DA1_PARAMS,
         "Parse_DA1_Response postcondition: Count <= MAX_DA1_PARAMS violated,"
         & " Count="
         & Natural'Image (Result.Count)
         & " MAX_DA1_PARAMS="
         & Natural'Image (MAX_DA1_PARAMS));
   end Test_Parse_DA1_Count_Bounded;

   procedure Test_Parse_DA1_Multi_Digit_Params (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  ESC [ ? 1 5 ; 2 2 c  -> two params: 15 and 22
      Buf    : constant Byte_Array (1 .. 9) :=
        [ESC_BYTE,
         CSI_L,
         QUEST,
         DIG_1,
         DIG_5,    --  15
         SEMI,
         DIG_2,
         DIG_2,    --  22
         TERM_C];
      Result : constant DA1_Params := Parse_DA1_Response (Buf, Buf'Length);
   begin
      Assert
        (Result.Count = 2,
         "Parse_DA1_Response with multi-digit params should return Count=2," & " got" & Natural'Image (Result.Count));
      Assert
        (Result.Values (1) = 15,
         "Parse_DA1_Response first multi-digit param should be 15," & " got" & Natural'Image (Result.Values (1)));
      Assert
        (Result.Values (2) = 22,
         "Parse_DA1_Response second multi-digit param should be 22," & " got" & Natural'Image (Result.Values (2)));
   end Test_Parse_DA1_Multi_Digit_Params;


   ---------------------------------------------------------------------------
   --  FUNC-OSC-014: Wrap_For_Passthrough
   ---------------------------------------------------------------------------

   procedure Test_Wrap_No_Passthrough_Identity (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  A sample OSC 11 query: ESC ] 1 1 ; ? ESC \
      Query  : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE,
         16#5D#,               --  ESC ]
         DIG_1,
         DIG_1,
         SEMI,             --  1 1 ;
         16#3F#,                         --  ?
         ESC_BYTE];                      --  ESC (beginning of ST, simplified)
      Result : constant Byte_Array := Wrap_For_Passthrough (Query, No_Passthrough);
   begin
      Assert
        (Result'Length = Query'Length,
         "Wrap_For_Passthrough No_Passthrough should return same length as Query,"
         & " expected"
         & Natural'Image (Query'Length)
         & " got"
         & Natural'Image (Result'Length));
      for I in Query'Range loop
         Assert
           (Result (Result'First + (I - Query'First)) = Query (I),
            "Wrap_For_Passthrough No_Passthrough should preserve byte at index" & Positive'Image (I));
      end loop;
   end Test_Wrap_No_Passthrough_Identity;

   procedure Test_Wrap_No_Passthrough_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty  : constant Byte_Array (1 .. 0) := [];
      Result : constant Byte_Array := Wrap_For_Passthrough (Empty, No_Passthrough);
   begin
      Assert
        (Result'Length = 0,
         "Wrap_For_Passthrough No_Passthrough with empty query should return empty,"
         & " got length"
         & Natural'Image (Result'Length));
   end Test_Wrap_No_Passthrough_Empty;

   procedure Test_Wrap_Tmux_Has_DCS_Prefix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  A one-byte query for simplicity
      Query  : constant Byte_Array (1 .. 1) := [16#41#];  --  A
      Result : constant Byte_Array := Wrap_For_Passthrough (Query, Tmux_Passthrough);
      --  Expected prefix: ESC P t m u x ;  (7 bytes)
      --  Byte layout: 0x1B 0x50 't' 'm' 'u' 'x' ';'
   begin
      Assert
        (Result'Length >= 7,
         "Wrap_For_Passthrough Tmux result must be at least 7 bytes (DCS prefix),"
         & " got"
         & Natural'Image (Result'Length));
      Assert (Result (Result'First) = ESC_BYTE, "Wrap_For_Passthrough Tmux: byte 1 should be ESC (0x1B)");
      Assert
        (Result (Result'First + 1) = DCS_P, "Wrap_For_Passthrough Tmux: byte 2 should be P (0x50, DCS introducer)");
      --  Bytes 3-7 should spell "tmux;"
      Assert (Result (Result'First + 2) = CHR_T, "Wrap_For_Passthrough Tmux: byte 3 should be 't'");
      Assert (Result (Result'First + 3) = CHR_M, "Wrap_For_Passthrough Tmux: byte 4 should be 'm'");
      Assert (Result (Result'First + 4) = CHR_U, "Wrap_For_Passthrough Tmux: byte 5 should be 'u'");
      Assert (Result (Result'First + 5) = CHR_X, "Wrap_For_Passthrough Tmux: byte 6 should be 'x'");
      Assert (Result (Result'First + 6) = SEMI, "Wrap_For_Passthrough Tmux: byte 7 should be ';'");
   end Test_Wrap_Tmux_Has_DCS_Prefix;

   procedure Test_Wrap_Tmux_Has_ST_Suffix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Query  : constant Byte_Array (1 .. 1) := [16#41#];
      Result : constant Byte_Array := Wrap_For_Passthrough (Query, Tmux_Passthrough);
   begin
      Assert (Result'Length >= 2, "Wrap_For_Passthrough Tmux result must have at least 2 bytes for ST suffix");
      Assert
        (Result (Result'Last - 1) = ESC_BYTE, "Wrap_For_Passthrough Tmux: penultimate byte should be ESC (ST start)");
      Assert (Result (Result'Last) = ST_BACK, "Wrap_For_Passthrough Tmux: last byte should be \\ (0x5C, ST end)");
   end Test_Wrap_Tmux_Has_ST_Suffix;

   procedure Test_Wrap_Tmux_Inner_Esc (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Query is a single byte 0x41; inner ESC should appear at position 8
      --  (after the 7-byte "ESC P tmux;" prefix)
      Query  : constant Byte_Array (1 .. 1) := [16#41#];
      Result : constant Byte_Array := Wrap_For_Passthrough (Query, Tmux_Passthrough);
   begin
      Assert
        (Result'Length >= 8,
         "Wrap_For_Passthrough Tmux result must be at least 8 bytes for inner ESC,"
         & " got"
         & Natural'Image (Result'Length));
      Assert
        (Result (Result'First + 7) = ESC_BYTE, "Wrap_For_Passthrough Tmux: byte 8 should be inner ESC before query");
   end Test_Wrap_Tmux_Inner_Esc;

   procedure Test_Wrap_Tmux_Empty_Query (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Empty query: ESC P tmux ; ESC ESC \  -> 9 bytes
      --  DCS prefix (7) + inner ESC (1) + ST (2) = 10 bytes
      Empty  : constant Byte_Array (1 .. 0) := [];
      Result : constant Byte_Array := Wrap_For_Passthrough (Empty, Tmux_Passthrough);
   begin
      Assert
        (Result'Length > 0,
         "Wrap_For_Passthrough Tmux with empty query should still have wrapper bytes," & " got length 0");
      Assert (Result (Result'First) = ESC_BYTE, "Wrap_For_Passthrough Tmux empty: first byte should be ESC");
      Assert (Result (Result'Last) = ST_BACK, "Wrap_For_Passthrough Tmux empty: last byte should be \\ (ST end)");
   end Test_Wrap_Tmux_Empty_Query;

   procedure Test_Wrap_Screen_Has_DCS_Prefix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Query  : constant Byte_Array (1 .. 1) := [16#41#];
      Result : constant Byte_Array := Wrap_For_Passthrough (Query, Screen_Passthrough);
   begin
      Assert (Result'Length >= 2, "Wrap_For_Passthrough Screen result must have at least 2 bytes for DCS prefix");
      Assert (Result (Result'First) = ESC_BYTE, "Wrap_For_Passthrough Screen: byte 1 should be ESC");
      Assert
        (Result (Result'First + 1) = DCS_P, "Wrap_For_Passthrough Screen: byte 2 should be P (0x50, DCS introducer)");
   end Test_Wrap_Screen_Has_DCS_Prefix;

   procedure Test_Wrap_Screen_Has_ST_Suffix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Query  : constant Byte_Array (1 .. 1) := [16#41#];
      Result : constant Byte_Array := Wrap_For_Passthrough (Query, Screen_Passthrough);
   begin
      Assert (Result'Length >= 2, "Wrap_For_Passthrough Screen result must have at least 2 bytes for ST suffix");
      Assert
        (Result (Result'Last - 1) = ESC_BYTE, "Wrap_For_Passthrough Screen: penultimate byte should be ESC (ST start)");
      Assert (Result (Result'Last) = ST_BACK, "Wrap_For_Passthrough Screen: last byte should be \\ (0x5C, ST end)");
   end Test_Wrap_Screen_Has_ST_Suffix;

   procedure Test_Wrap_Screen_Length (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Screen wrapping adds: ESC P (2) + ESC \ (2) = 4 bytes overhead
      Query    : constant Byte_Array (1 .. 5) := [16#41#, 16#42#, 16#43#, 16#44#, 16#45#];
      Result   : constant Byte_Array := Wrap_For_Passthrough (Query, Screen_Passthrough);
      Expected : constant Natural := Query'Length + 4;
   begin
      Assert
        (Result'Length = Expected,
         "Wrap_For_Passthrough Screen length should be Query'Length + 4 ="
         & Natural'Image (Expected)
         & ", got"
         & Natural'Image (Result'Length));
   end Test_Wrap_Screen_Length;

end Test_OSC_Parsing;
