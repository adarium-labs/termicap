-------------------------------------------------------------------------------
--  Test_DA1 - Unit Tests for Termicap.DA1 Interpretation Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.DA1;         use Termicap.DA1;
with Termicap.OSC.Parsing;
use Termicap.OSC.Parsing;

--  Bring equality operators into scope for VT_Level comparisons.
use type Termicap.DA1.VT_Level;

package body Test_DA1 is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.DA1");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-DA1-004: Interpret_DA1
      Register_Routine
        (T,
         Test_Interpret_Empty_Params'Access,
         "FUNC-DA1-014 case 1: Count=0 -> Supported=False, Level=Unknown, all Flags=False");
      Register_Routine
        (T,
         Test_Interpret_Single_VT200'Access,
         "FUNC-DA1-014 case 2: Count=1, Values(1)=62 -> Level=VT200, Supported=True");
      Register_Routine
        (T,
         Test_Interpret_VT200_Sixel'Access,
         "FUNC-DA1-014 case 3: [62,4] -> Level=VT200, Flags(Sixel_Graphics)=True");
      Register_Routine
        (T,
         Test_Interpret_VT400_Multi_Cap'Access,
         "FUNC-DA1-014 case 4: [64,4,22,28] -> VT400, Sixel+ANSI_Color+Rectangular_Editing");
      Register_Routine
        (T,
         Test_Interpret_Unknown_First_Param'Access,
         "FUNC-DA1-014 case 5: Values(1)=99 -> Supported=True, Level=Unknown");
      Register_Routine
        (T,
         Test_Interpret_VT500_Unrecognised_Ps'Access,
         "FUNC-DA1-014 case 6: [65,100,200] -> Level=VT500, all Flags=False");
      Register_Routine
        (T,
         Test_Interpret_Max_Params'Access,
         "FUNC-DA1-014 case 11: Count=MAX_DA1_PARAMS -> no constraint error, recognised flags set");

      --  FUNC-DA1-005: Has_Capability
      Register_Routine
        (T, Test_Has_Capability_Not_Supported'Access, "FUNC-DA1-014 case 7: Has_Capability=False when Supported=False");
      Register_Routine
        (T,
         Test_Has_Capability_Sixel_True'Access,
         "FUNC-DA1-014 case 8: Has_Capability=True for Sixel_Graphics in VT200+Sixel");

      --  FUNC-DA1-006: VT_Level_Of
      Register_Routine
        (T, Test_VT_Level_Of_Not_Supported'Access, "FUNC-DA1-014 case 9: VT_Level_Of=Unknown when Supported=False");
      Register_Routine
        (T, Test_VT_Level_Of_VT400'Access, "FUNC-DA1-014 case 10: VT_Level_Of=VT400 for VT400-level capabilities");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  FUNC-DA1-004: Interpret_DA1 test bodies
   ---------------------------------------------------------------------------

   procedure Test_Interpret_Empty_Params (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Params : constant DA1_Params := (Count => 0, Values => [others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (not Caps.Supported, "Interpret_DA1 with Count=0: Supported should be False");
      Assert (Caps.Level = Unknown, "Interpret_DA1 with Count=0: Level should be Unknown");
      Assert (not Caps.Flags (Printer), "Interpret_DA1 with Count=0: Flags(Printer) should be False");
      Assert (not Caps.Flags (ReGIS_Graphics), "Interpret_DA1 with Count=0: Flags(ReGIS_Graphics) should be False");
      Assert (not Caps.Flags (Sixel_Graphics), "Interpret_DA1 with Count=0: Flags(Sixel_Graphics) should be False");
      Assert (not Caps.Flags (Selective_Erase), "Interpret_DA1 with Count=0: Flags(Selective_Erase) should be False");
      Assert
        (not Caps.Flags (User_Defined_Keys), "Interpret_DA1 with Count=0: Flags(User_Defined_Keys) should be False");
      Assert (not Caps.Flags (Windowing), "Interpret_DA1 with Count=0: Flags(Windowing) should be False");
      Assert (not Caps.Flags (ANSI_Color), "Interpret_DA1 with Count=0: Flags(ANSI_Color) should be False");
      Assert
        (not Caps.Flags (Rectangular_Editing),
         "Interpret_DA1 with Count=0: Flags(Rectangular_Editing) should be False");
   end Test_Interpret_Empty_Params;

   procedure Test_Interpret_Single_VT200 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Params : constant DA1_Params := (Count => 1, Values => [62, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (Caps.Supported, "Interpret_DA1 with VT200 (Ps=62): Supported should be True");
      Assert (Caps.Level = VT200, "Interpret_DA1 with VT200 (Ps=62): Level should be VT200");
      Assert (not Caps.Flags (Sixel_Graphics), "Interpret_DA1 with VT200 only: Flags(Sixel_Graphics) should be False");
      Assert (not Caps.Flags (ANSI_Color), "Interpret_DA1 with VT200 only: Flags(ANSI_Color) should be False");
      Assert (not Caps.Flags (Printer), "Interpret_DA1 with VT200 only: Flags(Printer) should be False");
   end Test_Interpret_Single_VT200;

   procedure Test_Interpret_VT200_Sixel (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Params : constant DA1_Params := (Count => 2, Values => [62, 4, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (Caps.Supported, "Interpret_DA1 VT200+Sixel: Supported should be True");
      Assert (Caps.Level = VT200, "Interpret_DA1 VT200+Sixel: Level should be VT200");
      Assert (Caps.Flags (Sixel_Graphics), "Interpret_DA1 VT200+Sixel: Flags(Sixel_Graphics) should be True");
      Assert (not Caps.Flags (Printer), "Interpret_DA1 VT200+Sixel: Flags(Printer) should be False");
      Assert (not Caps.Flags (ReGIS_Graphics), "Interpret_DA1 VT200+Sixel: Flags(ReGIS_Graphics) should be False");
      Assert (not Caps.Flags (Selective_Erase), "Interpret_DA1 VT200+Sixel: Flags(Selective_Erase) should be False");
      Assert
        (not Caps.Flags (User_Defined_Keys), "Interpret_DA1 VT200+Sixel: Flags(User_Defined_Keys) should be False");
      Assert (not Caps.Flags (Windowing), "Interpret_DA1 VT200+Sixel: Flags(Windowing) should be False");
      Assert (not Caps.Flags (ANSI_Color), "Interpret_DA1 VT200+Sixel: Flags(ANSI_Color) should be False");
      Assert
        (not Caps.Flags (Rectangular_Editing), "Interpret_DA1 VT200+Sixel: Flags(Rectangular_Editing) should be False");
   end Test_Interpret_VT200_Sixel;

   procedure Test_Interpret_VT400_Multi_Cap (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Params : constant DA1_Params := (Count => 4, Values => [64, 4, 22, 28, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (Caps.Supported, "Interpret_DA1 VT400+multi: Supported should be True");
      Assert (Caps.Level = VT400, "Interpret_DA1 VT400+multi: Level should be VT400");
      Assert (Caps.Flags (Sixel_Graphics), "Interpret_DA1 VT400+multi: Flags(Sixel_Graphics) should be True (Ps=4)");
      Assert (Caps.Flags (ANSI_Color), "Interpret_DA1 VT400+multi: Flags(ANSI_Color) should be True (Ps=22)");
      Assert
        (Caps.Flags (Rectangular_Editing),
         "Interpret_DA1 VT400+multi: Flags(Rectangular_Editing) should be True (Ps=28)");
      Assert
        (not Caps.Flags (Printer), "Interpret_DA1 VT400+multi: Flags(Printer) should be False (Ps=2 not in params)");
   end Test_Interpret_VT400_Multi_Cap;

   procedure Test_Interpret_Unknown_First_Param (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Params : constant DA1_Params := (Count => 1, Values => [99, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (Caps.Supported, "Interpret_DA1 with unknown Ps=99: Supported should be True (response received)");
      Assert (Caps.Level = Unknown, "Interpret_DA1 with unknown Ps=99: Level should be Unknown");
   end Test_Interpret_Unknown_First_Param;

   procedure Test_Interpret_VT500_Unrecognised_Ps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Params : constant DA1_Params := (Count => 3, Values => [65, 100, 200, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (Caps.Supported, "Interpret_DA1 VT500+unrecognised: Supported should be True");
      Assert (Caps.Level = VT500, "Interpret_DA1 VT500+unrecognised: Level should be VT500");
      Assert (not Caps.Flags (Printer), "Interpret_DA1 VT500+unrecognised: Flags(Printer) should be False");
      Assert
        (not Caps.Flags (ReGIS_Graphics), "Interpret_DA1 VT500+unrecognised: Flags(ReGIS_Graphics) should be False");
      Assert
        (not Caps.Flags (Sixel_Graphics), "Interpret_DA1 VT500+unrecognised: Flags(Sixel_Graphics) should be False");
      Assert
        (not Caps.Flags (Selective_Erase), "Interpret_DA1 VT500+unrecognised: Flags(Selective_Erase) should be False");
      Assert
        (not Caps.Flags (User_Defined_Keys),
         "Interpret_DA1 VT500+unrecognised: Flags(User_Defined_Keys) should be False");
      Assert (not Caps.Flags (Windowing), "Interpret_DA1 VT500+unrecognised: Flags(Windowing) should be False");
      Assert (not Caps.Flags (ANSI_Color), "Interpret_DA1 VT500+unrecognised: Flags(ANSI_Color) should be False");
      Assert
        (not Caps.Flags (Rectangular_Editing),
         "Interpret_DA1 VT500+unrecognised: Flags(Rectangular_Editing) should be False");
   end Test_Interpret_VT500_Unrecognised_Ps;

   procedure Test_Interpret_Max_Params (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Fill all MAX_DA1_PARAMS slots.  First param = 64 (VT400).
      --  Ps values 2,3,4,6,8,18,22,28 activate all recognised capabilities.
      --  Remaining slots are filled with 0 (unrecognised, silently ignored).
      Params : constant DA1_Params :=
        (Count => MAX_DA1_PARAMS, Values => [64, 2, 3, 4, 6, 8, 18, 22, 28, 0, 0, 0, 0, 0, 0, 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (Caps.Supported, "Interpret_DA1 max params: Supported should be True");
      Assert (Caps.Level = VT400, "Interpret_DA1 max params: Level should be VT400");
      Assert (Caps.Flags (Printer), "Interpret_DA1 max params: Flags(Printer) should be True (Ps=2)");
      Assert (Caps.Flags (ReGIS_Graphics), "Interpret_DA1 max params: Flags(ReGIS_Graphics) should be True (Ps=3)");
      Assert (Caps.Flags (Sixel_Graphics), "Interpret_DA1 max params: Flags(Sixel_Graphics) should be True (Ps=4)");
      Assert (Caps.Flags (Selective_Erase), "Interpret_DA1 max params: Flags(Selective_Erase) should be True (Ps=6)");
      Assert
        (Caps.Flags (User_Defined_Keys), "Interpret_DA1 max params: Flags(User_Defined_Keys) should be True (Ps=8)");
      Assert (Caps.Flags (Windowing), "Interpret_DA1 max params: Flags(Windowing) should be True (Ps=18)");
      Assert (Caps.Flags (ANSI_Color), "Interpret_DA1 max params: Flags(ANSI_Color) should be True (Ps=22)");
      Assert
        (Caps.Flags (Rectangular_Editing),
         "Interpret_DA1 max params: Flags(Rectangular_Editing) should be True (Ps=28)");
   end Test_Interpret_Max_Params;


   ---------------------------------------------------------------------------
   --  FUNC-DA1-005: Has_Capability test bodies
   ---------------------------------------------------------------------------

   procedure Test_Has_Capability_Not_Supported (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Default DA1_Capabilities has Supported = False.
      Caps : constant DA1_Capabilities := (Supported => False, Level => Unknown, Flags => [others => False]);
   begin
      Assert
        (not Has_Capability (Caps, Sixel_Graphics),
         "Has_Capability: should return False when Supported = False (Sixel_Graphics)");
      Assert
        (not Has_Capability (Caps, ANSI_Color),
         "Has_Capability: should return False when Supported = False (ANSI_Color)");
      Assert
        (not Has_Capability (Caps, Printer), "Has_Capability: should return False when Supported = False (Printer)");
      Assert
        (not Has_Capability (Caps, Rectangular_Editing),
         "Has_Capability: should return False when Supported = False (Rectangular_Editing)");
   end Test_Has_Capability_Not_Supported;

   procedure Test_Has_Capability_Sixel_True (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Build VT200 + Sixel result via Interpret_DA1 (case 3).
      Params : constant DA1_Params := (Count => 2, Values => [62, 4, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert
        (Has_Capability (Caps, Sixel_Graphics),
         "Has_Capability: should return True for Sixel_Graphics in VT200+Sixel result");
      Assert
        (not Has_Capability (Caps, ANSI_Color),
         "Has_Capability: should return False for ANSI_Color in VT200+Sixel result");
      Assert
        (not Has_Capability (Caps, Printer), "Has_Capability: should return False for Printer in VT200+Sixel result");
   end Test_Has_Capability_Sixel_True;


   ---------------------------------------------------------------------------
   --  FUNC-DA1-006: VT_Level_Of test bodies
   ---------------------------------------------------------------------------

   procedure Test_VT_Level_Of_Not_Supported (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Caps : constant DA1_Capabilities := (Supported => False, Level => Unknown, Flags => [others => False]);
   begin
      Assert (VT_Level_Of (Caps) = Unknown, "VT_Level_Of: should return Unknown when Supported = False");
   end Test_VT_Level_Of_Not_Supported;

   procedure Test_VT_Level_Of_VT400 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Build VT400 result via Interpret_DA1.
      Params : constant DA1_Params := (Count => 1, Values => [64, others => 0]);
      Caps   : constant DA1_Capabilities := Interpret_DA1 (Params);
   begin
      Assert (VT_Level_Of (Caps) = VT400, "VT_Level_Of: should return VT400 for a VT400-level DA1_Capabilities");
   end Test_VT_Level_Of_VT400;

end Test_DA1;
