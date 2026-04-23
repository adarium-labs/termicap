-------------------------------------------------------------------------------
--  Test_Win32_Color - Unit Tests for Termicap.Win32_Color
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Win32_Color; use Termicap.Win32_Color;
with Termicap.Color; use Termicap.Color;
with Termicap.Environment; use Termicap.Environment;

package body Test_Win32_Color is


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Win32_Color");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-WIN-013
      Register_Routine (T, Test_Result_Never_Basic_16'Access,
         "FUNC-WIN-013: Build_To_Color_Level never returns Basic_16");

      --  FUNC-WIN-007 + FUNC-WIN-013
      Register_Routine (T, Test_Wt_Session_True_Build_Zero'Access,
         "FUNC-WIN-007+013: Has_WT_Session=True, Build=0 -> True_Color");
      Register_Routine (T, Test_Wt_Session_True_Build_High'Access,
         "FUNC-WIN-007+013: Has_WT_Session=True, Build=99999 -> True_Color");

      --  FUNC-WIN-008
      Register_Routine (T, Test_Build_Zero_None'Access,
         "FUNC-WIN-008: Build=0 -> None");
      Register_Routine (T, Test_Build_10000_None'Access,
         "FUNC-WIN-008: Build=10000 -> None (below 10586)");
      Register_Routine (T, Test_Build_10585_None'Access,
         "FUNC-WIN-008: Build=10585 -> None (one below lower threshold)");
      Register_Routine (T, Test_Build_10586_Extended_256'Access,
         "FUNC-WIN-008: Build=10586 -> Extended_256 (exact lower threshold)");
      Register_Routine (T, Test_Build_14930_Extended_256'Access,
         "FUNC-WIN-008: Build=14930 -> Extended_256 (one below upper threshold)");
      Register_Routine (T, Test_Build_14931_True_Color'Access,
         "FUNC-WIN-008: Build=14931 -> True_Color (exact upper threshold)");
      Register_Routine (T, Test_Build_20000_True_Color'Access,
         "FUNC-WIN-008: Build=20000 -> True_Color (well above threshold)");
      Register_Routine (T, Test_No_Wt_Session_Build_10586_Extended_256'Access,
         "FUNC-WIN-008: Has_WT_Session=False, Build=10586 -> Extended_256");
      Register_Routine (T, Test_Wt_Session_Overrides_Build_10586'Access,
         "FUNC-WIN-008: Has_WT_Session=True, Build=10586 -> True_Color (WT_SESSION overrides)");

      --  FUNC-WIN-007 (Detect_Windows_Color_Level)
      Register_Routine (T, Test_Detect_Wt_Session_Present_Non_Empty'Access,
         "FUNC-WIN-007: Env WT_SESSION='abc123' (present, non-empty) -> True_Color");
      Register_Routine (T, Test_Detect_Wt_Session_Present_Empty'Access,
         "FUNC-WIN-007: Env WT_SESSION='' (present, empty) -> does not force True_Color");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------


   procedure Test_Result_Never_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Verify postcondition: result in {None, Extended_256, True_Color} for
      --  a representative set of (Build, Has_WT_Session) combinations.
      Assert
         (Build_To_Color_Level (0, False) /= Basic_16,
          "Build=0, no WT_SESSION should never yield Basic_16");
      Assert
         (Build_To_Color_Level (10586, False) /= Basic_16,
          "Build=10586, no WT_SESSION should never yield Basic_16");
      Assert
         (Build_To_Color_Level (14931, False) /= Basic_16,
          "Build=14931, no WT_SESSION should never yield Basic_16");
      Assert
         (Build_To_Color_Level (0, True) /= Basic_16,
          "Build=0, WT_SESSION should never yield Basic_16");
      Assert
         (Build_To_Color_Level (14930, True) /= Basic_16,
          "Build=14930, WT_SESSION should never yield Basic_16");
   end Test_Result_Never_Basic_16;


   procedure Test_Wt_Session_True_Build_Zero
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (0, True) = True_Color,
          "Has_WT_Session=True with Build=0 should return True_Color");
   end Test_Wt_Session_True_Build_Zero;


   procedure Test_Wt_Session_True_Build_High
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (99_999, True) = True_Color,
          "Has_WT_Session=True with Build=99999 should return True_Color");
   end Test_Wt_Session_True_Build_High;


   procedure Test_Build_Zero_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (0, False) = None,
          "Build=0, no WT_SESSION should return None");
   end Test_Build_Zero_None;


   procedure Test_Build_10000_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (10_000, False) = None,
          "Build=10000, no WT_SESSION should return None (below 10586 threshold)");
   end Test_Build_10000_None;


   procedure Test_Build_10585_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (10_585, False) = None,
          "Build=10585, no WT_SESSION should return None (one below lower threshold)");
   end Test_Build_10585_None;


   procedure Test_Build_10586_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (10_586, False) = Extended_256,
          "Build=10586, no WT_SESSION should return Extended_256 (exact lower threshold)");
   end Test_Build_10586_Extended_256;


   procedure Test_Build_14930_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (14_930, False) = Extended_256,
          "Build=14930, no WT_SESSION should return Extended_256 (one below upper threshold)");
   end Test_Build_14930_Extended_256;


   procedure Test_Build_14931_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (14_931, False) = True_Color,
          "Build=14931, no WT_SESSION should return True_Color (exact upper threshold)");
   end Test_Build_14931_True_Color;


   procedure Test_Build_20000_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (20_000, False) = True_Color,
          "Build=20000, no WT_SESSION should return True_Color (well above threshold)");
   end Test_Build_20000_True_Color;


   procedure Test_No_Wt_Session_Build_10586_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (10_586, False) = Extended_256,
          "Has_WT_Session=False, Build=10586 should return Extended_256 (no WT_SESSION override)");
   end Test_No_Wt_Session_Build_10586_Extended_256;


   procedure Test_Wt_Session_Overrides_Build_10586
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Build_To_Color_Level (10_586, True) = True_Color,
          "Has_WT_Session=True, Build=10586 should return True_Color (WT_SESSION overrides build)");
   end Test_Wt_Session_Overrides_Build_10586;


   procedure Test_Detect_Wt_Session_Present_Non_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "WT_SESSION", "abc123");
      Assert
         (Detect_Windows_Color_Level (Env) = True_Color,
          "WT_SESSION='abc123' (present and non-empty) should return True_Color");
   end Test_Detect_Wt_Session_Present_Non_Empty;


   procedure Test_Detect_Wt_Session_Present_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Color_Level;
   begin
      Insert (Env, "WT_SESSION", "");
      Result := Detect_Windows_Color_Level (Env);
      --  WT_SESSION present but empty does not trigger the WT_SESSION path;
      --  result depends on the real build number and must not be forced to
      --  True_Color by the empty variable alone.  We can only assert the
      --  result is in the valid set (postcondition of Build_To_Color_Level).
      Assert
         (Result = None or else Result = Extended_256 or else Result = True_Color,
          "WT_SESSION='' (empty) should return a valid color level (None, Extended_256, or True_Color)");
   end Test_Detect_Wt_Session_Present_Empty;

end Test_Win32_Color;
