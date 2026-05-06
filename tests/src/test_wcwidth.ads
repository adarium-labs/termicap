-------------------------------------------------------------------------------
--  Test_Wcwidth - Unit Tests for Termicap.Wcwidth
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK types, constants, and functions
--  in Termicap.Wcwidth: Wcwidth_Level enumeration, Optional_Wcwidth_Level
--  discriminated record, sentinel codepoint constants, Refine_Unicode_Level
--  integration function, and Probe_Wcwidth_Level smoke tests.
--
--  All Refine_Unicode_Level tests are fully deterministic (no C FFI required).
--  Probe_Wcwidth_Level tests are smoke tests that verify the return type
--  contract and caching behaviour without controlling locale state.
--
--  Requirements Coverage:
--    - @relation(FUNC-WCW-002): Sentinel codepoint constants (3 vectors)
--    - @relation(FUNC-WCW-004): Wcwidth_Level enumeration ordering (5 vectors)
--    - @relation(FUNC-WCW-005): Refine_Unicode_Level — all 12 combinations
--    - @relation(FUNC-WCW-010): Optional_Wcwidth_Level discriminated record (4 vectors)
--    - @relation(FUNC-WCW-013): Integration smoke tests — Probe_Wcwidth_Level (2 vectors)

with AUnit.Test_Cases;

package Test_Wcwidth is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-WCW-002: Sentinel Codepoint Constants
   ---------------------------------------------------------------------------

   --  FUNC-WCW-002: WCW_SENTINEL_UNI3 = 16#28FF#
   procedure Test_Sentinel_Uni3_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-002: WCW_SENTINEL_UNI13 = 16#1FB38#
   procedure Test_Sentinel_Uni13_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-002: WCW_SENTINEL_UNI16 = 16#1CD00#
   procedure Test_Sentinel_Uni16_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-002: sentinel codepoints are mutually distinct and in expected numeric relationship
   procedure Test_Sentinels_Ordered (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WCW-004: Wcwidth_Level Enumeration Ordering
   ---------------------------------------------------------------------------

   --  FUNC-WCW-004: Unknown is Wcwidth_Level'First (lowest level)
   procedure Test_Wcwidth_Level_Unknown_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-004: Unicode_16 is Wcwidth_Level'Last (highest level)
   procedure Test_Wcwidth_Level_Unicode16_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-004: ordering Unknown < Unicode_3 < Unicode_13 < Unicode_16
   procedure Test_Wcwidth_Level_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-004: Wcwidth_Level'Max returns the higher of two levels
   procedure Test_Wcwidth_Level_Max (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WCW-005: Refine_Unicode_Level — All 12 Combinations
   ---------------------------------------------------------------------------

   --  Env=None, Wcw=Unknown -> None (no upgrade)
   procedure Test_Refine_None_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=None, Wcw=Unicode_3 -> Basic (upgrade None to Basic)
   procedure Test_Refine_None_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=None, Wcw=Unicode_13 -> Basic (upgrade None to Basic)
   procedure Test_Refine_None_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=None, Wcw=Unicode_16 -> Extended (upgrade None to Extended)
   procedure Test_Refine_None_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Basic, Wcw=Unknown -> Basic (no upgrade)
   procedure Test_Refine_Basic_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Basic, Wcw=Unicode_3 -> Basic (probe maps to Basic; no change)
   procedure Test_Refine_Basic_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Basic, Wcw=Unicode_13 -> Basic (probe maps to Basic; no change)
   procedure Test_Refine_Basic_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Basic, Wcw=Unicode_16 -> Extended (upgrade Basic to Extended)
   procedure Test_Refine_Basic_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Extended, Wcw=Unknown -> Extended (no upgrade)
   procedure Test_Refine_Extended_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Extended, Wcw=Unicode_3 -> Extended (probe < Extended; no downgrade)
   procedure Test_Refine_Extended_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Extended, Wcw=Unicode_13 -> Extended (probe < Extended; no downgrade)
   procedure Test_Refine_Extended_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Env=Extended, Wcw=Unicode_16 -> Extended (probe maps to Extended; no change)
   procedure Test_Refine_Extended_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WCW-005: Properties Verified Across All 12 Combinations
   ---------------------------------------------------------------------------

   --  FUNC-WCW-005: Result >= Env_Level for all 12 combinations (probe never downgrades)
   procedure Test_Refine_Never_Downgrades (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-005: If Wcw_Level = Unknown then Result = Env_Level (no change)
   procedure Test_Refine_Unknown_Leaves_Env_Unchanged (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-005: If Wcw_Level = Unicode_16 then Result >= Extended
   procedure Test_Refine_Unicode16_Implies_Extended (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WCW-010: Optional_Wcwidth_Level Discriminated Record
   ---------------------------------------------------------------------------

   --  FUNC-WCW-010: default (Is_Set => False) construction
   procedure Test_Optional_Default_Not_Set (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-010: (Is_Set => True, Level => Unknown) has Is_Set = True
   procedure Test_Optional_Set_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-010: (Is_Set => True, Level => Unicode_13) has correct Level
   procedure Test_Optional_Set_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-010: (Is_Set => True, Level => Unicode_16) has correct Level
   procedure Test_Optional_Set_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-WCW-013: Integration Smoke Tests for Probe_Wcwidth_Level
   ---------------------------------------------------------------------------

   --  FUNC-WCW-013: Probe_Wcwidth_Level returns a valid Wcwidth_Level
   procedure Test_Probe_Returns_Valid_Level (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WCW-013: Calling Probe_Wcwidth_Level twice returns the same value (caching)
   procedure Test_Probe_Cache_Consistency (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Wcwidth;
