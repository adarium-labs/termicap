-------------------------------------------------------------------------------
--  Test_Win32_Color - Unit Tests for Termicap.Win32_Color
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Windows build-number to color-level mapping and
--  WT_SESSION environment variable detection.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-007): WT_SESSION environment variable detection
--    - @relation(FUNC-WIN-008): Build number to color level mapping
--    - @relation(FUNC-WIN-013): SPARK contracts on Build_To_Color_Level

with AUnit.Test_Cases;

package Test_Win32_Color is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-WIN-013: SPARK Postcondition — Result Always In Valid Set
   ---------------------------------------------------------------------------

   --  FUNC-WIN-013: result is always None, Extended_256, or True_Color (never Basic_16)
   procedure Test_Result_Never_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WIN-007 + FUNC-WIN-013: Has_WT_Session Overrides Build Number
   ---------------------------------------------------------------------------

   --  FUNC-WIN-007+013: Has_WT_Session=True, Build=0 -> True_Color
   procedure Test_Wt_Session_True_Build_Zero
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-007+013: Has_WT_Session=True, Build=99999 -> True_Color
   procedure Test_Wt_Session_True_Build_High
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WIN-008: Build Number Threshold Mapping
   ---------------------------------------------------------------------------

   --  FUNC-WIN-008: Build=0 -> None (far below threshold)
   procedure Test_Build_Zero_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Build=10000 -> None (below 10586 threshold)
   procedure Test_Build_10000_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Build=10585 -> None (one below lower threshold)
   procedure Test_Build_10585_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Build=10586 -> Extended_256 (exact lower threshold)
   procedure Test_Build_10586_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Build=14930 -> Extended_256 (one below upper threshold)
   procedure Test_Build_14930_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Build=14931 -> True_Color (exact upper threshold)
   procedure Test_Build_14931_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Build=20000 -> True_Color (well above threshold)
   procedure Test_Build_20000_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Has_WT_Session=False, Build=10586 -> Extended_256 (no WT_SESSION)
   procedure Test_No_Wt_Session_Build_10586_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-008: Has_WT_Session=True, Build=10586 -> True_Color (WT_SESSION overrides)
   procedure Test_Wt_Session_Overrides_Build_10586
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WIN-007: Detect_Windows_Color_Level via Environment
   ---------------------------------------------------------------------------

   --  FUNC-WIN-007: Env with WT_SESSION="abc123" (present, non-empty) -> True_Color
   procedure Test_Detect_Wt_Session_Present_Non_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-007: Env with WT_SESSION="" (present, empty) -> does not force True_Color
   procedure Test_Detect_Wt_Session_Present_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Win32_Color;
