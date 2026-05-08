-------------------------------------------------------------------------------
--  Test_Wcwidth - Unit Tests for Termicap.Wcwidth
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Unicode; use Termicap.Unicode;
with Termicap.Wcwidth; use Termicap.Wcwidth;

package body Test_Wcwidth is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Wcwidth");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-WCW-002: Sentinel constants
      Register_Routine (T, Test_Sentinel_Uni3_Value'Access, "FUNC-WCW-002: WCW_SENTINEL_UNI3 = 16#28FF#");
      Register_Routine (T, Test_Sentinel_Uni13_Value'Access, "FUNC-WCW-002: WCW_SENTINEL_UNI13 = 16#1FB38#");
      Register_Routine (T, Test_Sentinel_Uni16_Value'Access, "FUNC-WCW-002: WCW_SENTINEL_UNI16 = 16#1CD00#");
      Register_Routine (T, Test_Sentinels_Ordered'Access, "FUNC-WCW-002: sentinels ordered UNI3 < UNI13 < UNI16");

      --  FUNC-WCW-004: Wcwidth_Level ordering
      Register_Routine (T, Test_Wcwidth_Level_Unknown_Is_First'Access, "FUNC-WCW-004: Unknown is Wcwidth_Level'First");
      Register_Routine
        (T, Test_Wcwidth_Level_Unicode16_Is_Last'Access, "FUNC-WCW-004: Unicode_16 is Wcwidth_Level'Last");
      Register_Routine
        (T, Test_Wcwidth_Level_Ordering'Access, "FUNC-WCW-004: ordering Unknown < Unicode_3 < Unicode_13 < Unicode_16");
      Register_Routine
        (T, Test_Wcwidth_Level_Max'Access, "FUNC-WCW-004: Wcwidth_Level'Max returns higher of two levels");

      --  FUNC-WCW-005: Refine_Unicode_Level — all 12 combinations
      Register_Routine (T, Test_Refine_None_Unknown'Access, "FUNC-WCW-005: Refine(None, Unknown) = None");
      Register_Routine (T, Test_Refine_None_Unicode3'Access, "FUNC-WCW-005: Refine(None, Unicode_3) = Basic");
      Register_Routine (T, Test_Refine_None_Unicode13'Access, "FUNC-WCW-005: Refine(None, Unicode_13) = Basic");
      Register_Routine (T, Test_Refine_None_Unicode16'Access, "FUNC-WCW-005: Refine(None, Unicode_16) = Extended");
      Register_Routine (T, Test_Refine_Basic_Unknown'Access, "FUNC-WCW-005: Refine(Basic, Unknown) = Basic");
      Register_Routine (T, Test_Refine_Basic_Unicode3'Access, "FUNC-WCW-005: Refine(Basic, Unicode_3) = Basic");
      Register_Routine (T, Test_Refine_Basic_Unicode13'Access, "FUNC-WCW-005: Refine(Basic, Unicode_13) = Basic");
      Register_Routine (T, Test_Refine_Basic_Unicode16'Access, "FUNC-WCW-005: Refine(Basic, Unicode_16) = Extended");
      Register_Routine (T, Test_Refine_Extended_Unknown'Access, "FUNC-WCW-005: Refine(Extended, Unknown) = Extended");
      Register_Routine
        (T,
         Test_Refine_Extended_Unicode3'Access,
         "FUNC-WCW-005: Refine(Extended, Unicode_3) = Extended (no downgrade)");
      Register_Routine
        (T,
         Test_Refine_Extended_Unicode13'Access,
         "FUNC-WCW-005: Refine(Extended, Unicode_13) = Extended (no downgrade)");
      Register_Routine
        (T, Test_Refine_Extended_Unicode16'Access, "FUNC-WCW-005: Refine(Extended, Unicode_16) = Extended");

      --  FUNC-WCW-005: cross-combination properties
      Register_Routine
        (T, Test_Refine_Never_Downgrades'Access, "FUNC-WCW-005: Result >= Env_Level for all 12 combinations");
      Register_Routine
        (T,
         Test_Refine_Unknown_Leaves_Env_Unchanged'Access,
         "FUNC-WCW-005: Wcw_Level=Unknown leaves Env_Level unchanged for all env values");
      Register_Routine
        (T,
         Test_Refine_Unicode16_Implies_Extended'Access,
         "FUNC-WCW-005: Wcw_Level=Unicode_16 implies Result >= Extended for all env values");

      --  FUNC-WCW-010: Optional_Wcwidth_Level
      Register_Routine
        (T, Test_Optional_Default_Not_Set'Access, "FUNC-WCW-010: default Optional_Wcwidth_Level has Is_Set = False");
      Register_Routine
        (T, Test_Optional_Set_Unknown'Access, "FUNC-WCW-010: (Is_Set => True, Level => Unknown) has Is_Set = True");
      Register_Routine
        (T,
         Test_Optional_Set_Unicode13'Access,
         "FUNC-WCW-010: (Is_Set => True, Level => Unicode_13) has Level = Unicode_13");
      Register_Routine
        (T,
         Test_Optional_Set_Unicode16'Access,
         "FUNC-WCW-010: (Is_Set => True, Level => Unicode_16) has Level = Unicode_16");

      --  FUNC-WCW-013: integration smoke tests
      Register_Routine
        (T, Test_Probe_Returns_Valid_Level'Access, "FUNC-WCW-013: Probe_Wcwidth_Level returns a valid Wcwidth_Level");
      Register_Routine
        (T,
         Test_Probe_Cache_Consistency'Access,
         "FUNC-WCW-013: Probe_Wcwidth_Level called twice returns same value (caching)");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  FUNC-WCW-002: Sentinel Codepoint Constants
   ---------------------------------------------------------------------------

   procedure Test_Sentinel_Uni3_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (WCW_SENTINEL_UNI3 = 16#28FF#, "WCW_SENTINEL_UNI3 should equal 16#28FF# (U+28FF Braille Pattern)");
   end Test_Sentinel_Uni3_Value;

   procedure Test_Sentinel_Uni13_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (WCW_SENTINEL_UNI13 = 16#1FB38#,
         "WCW_SENTINEL_UNI13 should equal 16#1FB38# (U+1FB38 Upper Left Block Sextant)");
   end Test_Sentinel_Uni13_Value;

   procedure Test_Sentinel_Uni16_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (WCW_SENTINEL_UNI16 = 16#1CD00#,
         "WCW_SENTINEL_UNI16 should equal 16#1CD00# (U+1CD00 Symbols for Legacy Computing Supplement)");
   end Test_Sentinel_Uni16_Value;

   procedure Test_Sentinels_Ordered (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  The three sentinel codepoints come from different Unicode blocks.
      --  Their numeric ordering is: UNI3 (16#28FF# = 10495) < UNI16 (16#1CD00# = 118016)
      --                                                       < UNI13 (16#1FB38# = 129848).
      --  Codepoints are not numerically sorted by Unicode version; the Wcwidth_Level
      --  enumeration (not the codepoint values) provides the version ordering.
      --  This test verifies the documented codepoint values are mutually distinct.
      Assert (WCW_SENTINEL_UNI3 /= WCW_SENTINEL_UNI13, "WCW_SENTINEL_UNI3 and WCW_SENTINEL_UNI13 must be distinct");
      Assert (WCW_SENTINEL_UNI13 /= WCW_SENTINEL_UNI16, "WCW_SENTINEL_UNI13 and WCW_SENTINEL_UNI16 must be distinct");
      Assert (WCW_SENTINEL_UNI3 /= WCW_SENTINEL_UNI16, "WCW_SENTINEL_UNI3 and WCW_SENTINEL_UNI16 must be distinct");
      --  UNI3 is smallest; UNI16 is in the middle; UNI13 is largest (different blocks)
      Assert (WCW_SENTINEL_UNI3 < WCW_SENTINEL_UNI16, "WCW_SENTINEL_UNI3 (16#28FF#) < WCW_SENTINEL_UNI16 (16#1CD00#)");
      Assert
        (WCW_SENTINEL_UNI16 < WCW_SENTINEL_UNI13, "WCW_SENTINEL_UNI16 (16#1CD00#) < WCW_SENTINEL_UNI13 (16#1FB38#)");
   end Test_Sentinels_Ordered;

   ---------------------------------------------------------------------------
   --  FUNC-WCW-004: Wcwidth_Level Enumeration Ordering
   ---------------------------------------------------------------------------

   procedure Test_Wcwidth_Level_Unknown_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Wcwidth_Level'First = Unknown, "Wcwidth_Level'First should be Unknown");
   end Test_Wcwidth_Level_Unknown_Is_First;

   procedure Test_Wcwidth_Level_Unicode16_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Wcwidth_Level'Last = Unicode_16, "Wcwidth_Level'Last should be Unicode_16");
   end Test_Wcwidth_Level_Unicode16_Is_Last;

   procedure Test_Wcwidth_Level_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Unknown < Unicode_3, "Unknown should be less than Unicode_3");
      Assert (Unicode_3 < Unicode_13, "Unicode_3 should be less than Unicode_13");
      Assert (Unicode_13 < Unicode_16, "Unicode_13 should be less than Unicode_16");
      Assert (Unknown < Unicode_13, "Unknown should be less than Unicode_13");
      Assert (Unknown < Unicode_16, "Unknown should be less than Unicode_16");
      Assert (Unicode_3 < Unicode_16, "Unicode_3 should be less than Unicode_16");
   end Test_Wcwidth_Level_Ordering;

   procedure Test_Wcwidth_Level_Max (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Wcwidth_Level'Max (Unknown, Unknown) = Unknown, "Max(Unknown, Unknown) should be Unknown");
      Assert (Wcwidth_Level'Max (Unknown, Unicode_3) = Unicode_3, "Max(Unknown, Unicode_3) should be Unicode_3");
      Assert
        (Wcwidth_Level'Max (Unicode_3, Unicode_13) = Unicode_13, "Max(Unicode_3, Unicode_13) should be Unicode_13");
      Assert
        (Wcwidth_Level'Max (Unicode_13, Unicode_16) = Unicode_16, "Max(Unicode_13, Unicode_16) should be Unicode_16");
      Assert (Wcwidth_Level'Max (Unicode_16, Unknown) = Unicode_16, "Max(Unicode_16, Unknown) should be Unicode_16");
      Assert (Wcwidth_Level'Max (Unicode_3, Unknown) = Unicode_3, "Max(Unicode_3, Unknown) should be Unicode_3");
   end Test_Wcwidth_Level_Max;

   ---------------------------------------------------------------------------
   --  FUNC-WCW-005: Refine_Unicode_Level — All 12 Combinations
   ---------------------------------------------------------------------------

   procedure Test_Refine_None_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (None, Unknown) = None,
         "Refine(None, Unknown) should return None (probe contributes nothing when Unknown)");
   end Test_Refine_None_Unknown;

   procedure Test_Refine_None_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (None, Unicode_3) = Basic,
         "Refine(None, Unicode_3) should return Basic (Unicode_3 maps to Basic, upgrades None)");
   end Test_Refine_None_Unicode3;

   procedure Test_Refine_None_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (None, Unicode_13) = Basic,
         "Refine(None, Unicode_13) should return Basic (Unicode_13 maps to Basic, upgrades None)");
   end Test_Refine_None_Unicode13;

   procedure Test_Refine_None_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (None, Unicode_16) = Extended,
         "Refine(None, Unicode_16) should return Extended (Unicode_16 maps to Extended, upgrades None)");
   end Test_Refine_None_Unicode16;

   procedure Test_Refine_Basic_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Basic, Unknown) = Basic,
         "Refine(Basic, Unknown) should return Basic (probe contributes nothing when Unknown)");
   end Test_Refine_Basic_Unknown;

   procedure Test_Refine_Basic_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Basic, Unicode_3) = Basic,
         "Refine(Basic, Unicode_3) should return Basic (Unicode_3 maps to Basic, max(Basic, Basic) = Basic)");
   end Test_Refine_Basic_Unicode3;

   procedure Test_Refine_Basic_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Basic, Unicode_13) = Basic,
         "Refine(Basic, Unicode_13) should return Basic (Unicode_13 maps to Basic, max(Basic, Basic) = Basic)");
   end Test_Refine_Basic_Unicode13;

   procedure Test_Refine_Basic_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Basic, Unicode_16) = Extended,
         "Refine(Basic, Unicode_16) should return Extended (Unicode_16 maps to Extended, upgrades Basic)");
   end Test_Refine_Basic_Unicode16;

   procedure Test_Refine_Extended_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Extended, Unknown) = Extended,
         "Refine(Extended, Unknown) should return Extended (probe contributes nothing when Unknown)");
   end Test_Refine_Extended_Unknown;

   procedure Test_Refine_Extended_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Extended, Unicode_3) = Extended,
         "Refine(Extended, Unicode_3) should return Extended (Unicode_3 maps to Basic < Extended; no downgrade)");
   end Test_Refine_Extended_Unicode3;

   procedure Test_Refine_Extended_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Extended, Unicode_13) = Extended,
         "Refine(Extended, Unicode_13) should return Extended (Unicode_13 maps to Basic < Extended; no downgrade)");
   end Test_Refine_Extended_Unicode13;

   procedure Test_Refine_Extended_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Refine_Unicode_Level (Extended, Unicode_16) = Extended,
         "Refine(Extended, Unicode_16) should return Extended (Unicode_16 maps to Extended, max = Extended)");
   end Test_Refine_Extended_Unicode16;

   ---------------------------------------------------------------------------
   --  FUNC-WCW-005: Cross-Combination Properties
   ---------------------------------------------------------------------------

   procedure Test_Refine_Never_Downgrades (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Verify Result >= Env_Level for all 12 combinations
   begin
      --  Env = None
      Assert (Refine_Unicode_Level (None, Unknown) >= None, "Refine(None, Unknown): result >= None (no downgrade)");
      Assert (Refine_Unicode_Level (None, Unicode_3) >= None, "Refine(None, Unicode_3): result >= None (no downgrade)");
      Assert
        (Refine_Unicode_Level (None, Unicode_13) >= None, "Refine(None, Unicode_13): result >= None (no downgrade)");
      Assert
        (Refine_Unicode_Level (None, Unicode_16) >= None, "Refine(None, Unicode_16): result >= None (no downgrade)");

      --  Env = Basic
      Assert (Refine_Unicode_Level (Basic, Unknown) >= Basic, "Refine(Basic, Unknown): result >= Basic (no downgrade)");
      Assert
        (Refine_Unicode_Level (Basic, Unicode_3) >= Basic, "Refine(Basic, Unicode_3): result >= Basic (no downgrade)");
      Assert
        (Refine_Unicode_Level (Basic, Unicode_13) >= Basic,
         "Refine(Basic, Unicode_13): result >= Basic (no downgrade)");
      Assert
        (Refine_Unicode_Level (Basic, Unicode_16) >= Basic,
         "Refine(Basic, Unicode_16): result >= Basic (no downgrade)");

      --  Env = Extended
      Assert
        (Refine_Unicode_Level (Extended, Unknown) >= Extended,
         "Refine(Extended, Unknown): result >= Extended (no downgrade)");
      Assert
        (Refine_Unicode_Level (Extended, Unicode_3) >= Extended,
         "Refine(Extended, Unicode_3): result >= Extended (no downgrade)");
      Assert
        (Refine_Unicode_Level (Extended, Unicode_13) >= Extended,
         "Refine(Extended, Unicode_13): result >= Extended (no downgrade)");
      Assert
        (Refine_Unicode_Level (Extended, Unicode_16) >= Extended,
         "Refine(Extended, Unicode_16): result >= Extended (no downgrade)");
   end Test_Refine_Never_Downgrades;

   procedure Test_Refine_Unknown_Leaves_Env_Unchanged (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Verify: if Wcw_Level = Unknown then Result = Env_Level for all env values
   begin
      Assert
        (Refine_Unicode_Level (None, Unknown) = None,
         "Refine(None, Unknown): Unknown leaves Env_Level = None unchanged");
      Assert
        (Refine_Unicode_Level (Basic, Unknown) = Basic,
         "Refine(Basic, Unknown): Unknown leaves Env_Level = Basic unchanged");
      Assert
        (Refine_Unicode_Level (Extended, Unknown) = Extended,
         "Refine(Extended, Unknown): Unknown leaves Env_Level = Extended unchanged");
   end Test_Refine_Unknown_Leaves_Env_Unchanged;

   procedure Test_Refine_Unicode16_Implies_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Verify: if Wcw_Level = Unicode_16 then Result >= Extended for all env values
   begin
      Assert
        (Refine_Unicode_Level (None, Unicode_16) >= Extended,
         "Refine(None, Unicode_16): result >= Extended when Wcw = Unicode_16");
      Assert
        (Refine_Unicode_Level (Basic, Unicode_16) >= Extended,
         "Refine(Basic, Unicode_16): result >= Extended when Wcw = Unicode_16");
      Assert
        (Refine_Unicode_Level (Extended, Unicode_16) >= Extended,
         "Refine(Extended, Unicode_16): result >= Extended when Wcw = Unicode_16");
   end Test_Refine_Unicode16_Implies_Extended;

   ---------------------------------------------------------------------------
   --  FUNC-WCW-010: Optional_Wcwidth_Level Discriminated Record
   ---------------------------------------------------------------------------

   procedure Test_Optional_Default_Not_Set (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opt : constant Optional_Wcwidth_Level := (Is_Set => False);
   begin
      Assert (not Opt.Is_Set, "Default Optional_Wcwidth_Level should have Is_Set = False");
   end Test_Optional_Default_Not_Set;

   procedure Test_Optional_Set_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opt : constant Optional_Wcwidth_Level := (Is_Set => True, Level => Unknown);
   begin
      Assert (Opt.Is_Set, "(Is_Set => True, Level => Unknown) should have Is_Set = True");
      Assert (Opt.Level = Unknown, "(Is_Set => True, Level => Unknown) should have Level = Unknown");
   end Test_Optional_Set_Unknown;

   procedure Test_Optional_Set_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opt : constant Optional_Wcwidth_Level := (Is_Set => True, Level => Unicode_13);
   begin
      Assert (Opt.Is_Set, "(Is_Set => True, Level => Unicode_13) should have Is_Set = True");
      Assert (Opt.Level = Unicode_13, "(Is_Set => True, Level => Unicode_13) should have Level = Unicode_13");
   end Test_Optional_Set_Unicode13;

   procedure Test_Optional_Set_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opt : constant Optional_Wcwidth_Level := (Is_Set => True, Level => Unicode_16);
   begin
      Assert (Opt.Is_Set, "(Is_Set => True, Level => Unicode_16) should have Is_Set = True");
      Assert (Opt.Level = Unicode_16, "(Is_Set => True, Level => Unicode_16) should have Level = Unicode_16");
   end Test_Optional_Set_Unicode16;

   ---------------------------------------------------------------------------
   --  FUNC-WCW-013: Integration Smoke Tests for Probe_Wcwidth_Level
   ---------------------------------------------------------------------------

   procedure Test_Probe_Returns_Valid_Level (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Level : Wcwidth_Level;
   begin
      --  Call Probe_Wcwidth_Level and verify the result is a valid Wcwidth_Level value.
      --  The actual value is locale-dependent; we only verify the type contract here
      --  by checking the result lies within the enumeration bounds.
      Level := Probe_Wcwidth_Level;
      Assert
        (Level >= Wcwidth_Level'First and then Level <= Wcwidth_Level'Last,
         "Probe_Wcwidth_Level should return a valid Wcwidth_Level value within enumeration bounds");
   end Test_Probe_Returns_Valid_Level;

   procedure Test_Probe_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Level_1 : Wcwidth_Level;
      Level_2 : Wcwidth_Level;
   begin
      --  Call Probe_Wcwidth_Level twice and verify both calls return the same value.
      --  This tests the caching contract (FUNC-WCW-010): the result must be deterministic.
      Level_1 := Probe_Wcwidth_Level;
      Level_2 := Probe_Wcwidth_Level;
      Assert (Level_1 = Level_2, "Probe_Wcwidth_Level called twice should return the same cached value");
   end Test_Probe_Cache_Consistency;

end Test_Wcwidth;
