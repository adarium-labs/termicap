-------------------------------------------------------------------------------
--  Test_OSC_Parsing - Unit Tests for Termicap.OSC.Parsing
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK functions in Termicap.OSC.Parsing:
--  DA1 sentinel detection, DA1 response start location, DA1 parameter parsing,
--  and multiplexer passthrough query wrapping.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-006): Contains_DA1_Response and DA1_Response_Start
--    - @relation(FUNC-OSC-010): Parse_DA1_Response
--    - @relation(FUNC-OSC-014): Wrap_For_Passthrough

with AUnit.Test_Cases;

package Test_OSC_Parsing is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-006: Contains_DA1_Response
   ---------------------------------------------------------------------------

   --  FUNC-OSC-006: Empty buffer (Length = 0) -> False
   procedure Test_Contains_DA1_Empty_Buffer
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Buffer with no ESC bytes -> False
   procedure Test_Contains_DA1_No_Esc
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Buffer with only ESC [ (incomplete, no ?) -> False
   procedure Test_Contains_DA1_Incomplete_No_Quest
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Buffer with ESC [ ? but no terminating c -> False
   procedure Test_Contains_DA1_Incomplete_No_Term
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Buffer with valid ESC [ ? 6 4 ; 1 c -> True
   procedure Test_Contains_DA1_Valid_Two_Params
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Non-DA1 CSI: ESC [ 6 n (CPR, no ?) -> False
   procedure Test_Contains_DA1_Non_DA1_CSI
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: DA1 preceded by OSC response bytes (realistic case) -> True
   procedure Test_Contains_DA1_After_OSC_Response
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Minimal DA1 with no params: ESC [ ? c -> True
   procedure Test_Contains_DA1_Minimal_No_Params
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Multiple ESC sequences, only last one is DA1 -> True
   procedure Test_Contains_DA1_Multiple_Esc_Last_Is_DA1
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-006: DA1_Response_Start
   ---------------------------------------------------------------------------

   --  FUNC-OSC-006: Empty buffer -> returns Length (= 0)
   procedure Test_DA1_Start_Empty_Buffer
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: No DA1 present -> returns Length
   procedure Test_DA1_Start_No_DA1
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: DA1 at start of buffer -> returns Bytes'First (= 1)
   procedure Test_DA1_Start_At_First_Byte
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: DA1 preceded by other bytes -> returns correct index
   procedure Test_DA1_Start_After_Prefix
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: OSC 11 response followed by DA1 -> returns position of DA1's ESC
   procedure Test_DA1_Start_After_OSC11_Response
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-006: Postcondition: result always <= Length
   procedure Test_DA1_Start_Result_Le_Length
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-010: Parse_DA1_Response
   ---------------------------------------------------------------------------

   --  FUNC-OSC-010: Empty input (Length = 0) -> Count = 0
   procedure Test_Parse_DA1_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: Valid ESC [ ? 6 4 ; 1 c -> Count = 2, Values = (64, 1)
   procedure Test_Parse_DA1_Two_Params
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: Single parameter: ESC [ ? 6 c -> Count = 1, Values(1) = 6
   procedure Test_Parse_DA1_Single_Param
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: Many parameters: ESC [ ? 1 ; 2 ; 4 ; 6 ; 9 c -> Count = 5
   procedure Test_Parse_DA1_Many_Params
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: No matching pattern -> Count = 0
   procedure Test_Parse_DA1_No_Match
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: Incomplete DA1 (no terminating c) -> Count = 0
   procedure Test_Parse_DA1_Incomplete
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: Wrong prefix (no ? after [) -> Count = 0
   procedure Test_Parse_DA1_Wrong_Prefix
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: Postcondition: Count <= MAX_DA1_PARAMS always holds
   procedure Test_Parse_DA1_Count_Bounded
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-010: Multi-digit parameter: ESC [ ? 1 5 ; 2 2 c -> (15, 22)
   procedure Test_Parse_DA1_Multi_Digit_Params
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-014: Wrap_For_Passthrough
   ---------------------------------------------------------------------------

   --  FUNC-OSC-014: No_Passthrough returns Query unchanged (same bytes)
   procedure Test_Wrap_No_Passthrough_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: No_Passthrough with empty query returns empty
   procedure Test_Wrap_No_Passthrough_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: Tmux_Passthrough wraps with ESC P tmux ; ESC <query> ESC \
   procedure Test_Wrap_Tmux_Has_DCS_Prefix
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: Tmux_Passthrough result ends with ESC \
   procedure Test_Wrap_Tmux_Has_ST_Suffix
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: Tmux_Passthrough result contains inner ESC before query
   procedure Test_Wrap_Tmux_Inner_Esc
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: Tmux_Passthrough with empty query -> still has wrapper bytes
   procedure Test_Wrap_Tmux_Empty_Query
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: Screen_Passthrough wraps with ESC P <query> ESC \
   procedure Test_Wrap_Screen_Has_DCS_Prefix
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: Screen_Passthrough result ends with ESC \
   procedure Test_Wrap_Screen_Has_ST_Suffix
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-014: Screen_Passthrough result length = 4 + Query'Length
   procedure Test_Wrap_Screen_Length
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_OSC_Parsing;
