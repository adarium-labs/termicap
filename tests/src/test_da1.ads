-------------------------------------------------------------------------------
--  Test_DA1 - Unit Tests for Termicap.DA1 Interpretation Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK functions in Termicap.DA1:
--  Interpret_DA1, Has_Capability, and VT_Level_Of.
--
--  All tests construct DA1_Params values programmatically and require no live
--  terminal.
--
--  Requirements Coverage:
--    - @relation(FUNC-DA1-004): Interpret_DA1
--    - @relation(FUNC-DA1-005): Has_Capability
--    - @relation(FUNC-DA1-006): VT_Level_Of
--    - @relation(FUNC-DA1-014): Eleven mandatory test cases

with AUnit.Test_Cases;

package Test_DA1 is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-DA1-004: Interpret_DA1
   ---------------------------------------------------------------------------

   --  FUNC-DA1-014 case 1: Count = 0 -> Supported = False, Level = Unknown,
   --  all Flags = False
   procedure Test_Interpret_Empty_Params (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 2: Count = 1, Values(1) = 62 -> Level = VT200,
   --  Supported = True, all Flags = False
   procedure Test_Interpret_Single_VT200 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 3: Count = 2, Values = [62, 4] -> Level = VT200,
   --  Flags(Sixel_Graphics) = True, all other Flags = False
   procedure Test_Interpret_VT200_Sixel (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 4: Count = 4, Values = [64, 4, 22, 28] ->
   --  Level = VT400, Sixel + ANSI_Color + Rectangular_Editing = True,
   --  Flags(Printer) = False
   procedure Test_Interpret_VT400_Multi_Cap (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 5: Count = 1, Values(1) = 99 ->
   --  Supported = True, Level = Unknown
   procedure Test_Interpret_Unknown_First_Param (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 6: Count = 3, Values = [65, 100, 200] ->
   --  Level = VT500, all Flags = False (unrecognised Ps silently ignored)
   procedure Test_Interpret_VT500_Unrecognised_Ps (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 11: Count = MAX_DA1_PARAMS, all recognised flags set ->
   --  no constraint error, all recognised Ps values flagged correctly
   procedure Test_Interpret_Max_Params (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DA1-005: Has_Capability
   ---------------------------------------------------------------------------

   --  FUNC-DA1-014 case 7: Has_Capability returns False when Supported = False
   procedure Test_Has_Capability_Not_Supported (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 8: Has_Capability returns True for Sixel_Graphics
   --  in a VT200+Sixel result
   procedure Test_Has_Capability_Sixel_True (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DA1-006: VT_Level_Of
   ---------------------------------------------------------------------------

   --  FUNC-DA1-014 case 9: VT_Level_Of returns Unknown when Supported = False
   procedure Test_VT_Level_Of_Not_Supported (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DA1-014 case 10: VT_Level_Of returns VT400 for a VT400-level result
   procedure Test_VT_Level_Of_VT400 (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_DA1;
