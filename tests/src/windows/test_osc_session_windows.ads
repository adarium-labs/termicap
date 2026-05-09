-------------------------------------------------------------------------------
--  Test_OSC_Session_Windows - Windows integration tests for Termicap.OSC
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the Windows console adaptation of the
--  Termicap.OSC probe-session lifecycle (FUNC-OSC-008 amended) and the
--  individual Windows-specific helpers introduced by FUNC-OSC-016/017/018/019.
--
--  These tests run only on Windows hosts and rely on the test binary being
--  invoked under a real console (the existing test runner satisfies this).
--  When stdin and stdout are both redirected, the tests gracefully skip the
--  probe-driven assertions while still exercising the no-terminal path.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-008): Probe session lifecycle on Windows
--    - @relation(FUNC-OSC-016): Console handle acquisition (GetStdHandle / CONIN$ / CONOUT$)
--    - @relation(FUNC-OSC-017): Console mode save / raw / restore
--    - @relation(FUNC-OSC-018): WaitForSingleObject + ReadFile timed read
--    - @relation(FUNC-OSC-019): Foreground check on Windows

with AUnit.Test_Cases;

package Test_OSC_Session_Windows is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-008: Probe Session Open/Close Lifecycle
   ---------------------------------------------------------------------------

   --  FUNC-OSC-008: Open returns Session_OK or Session_No_Terminal; never
   --  Session_Save_Failed or Session_Raw_Failed on a healthy Windows host.
   procedure Test_Open_Returns_Documented_Status (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-008/006: A DA1 query under Sentinel_Query terminates
   --  immediately because the response IS the sentinel; Resp_Length = 0
   --  and Timed_Out = False.
   procedure Test_DA1_Roundtrip_Sentinel (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-008/017: Finalize unconditionally restores the saved console
   --  mode for both STD_INPUT_HANDLE and STD_OUTPUT_HANDLE.
   procedure Test_Finalize_Restores_Console_Mode (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-019: Foreground Check on Windows
   ---------------------------------------------------------------------------

   --  FUNC-OSC-019: Is_Foreground_Process returns True on a valid handle
   --  obtained from Open_Terminal under a real console.
   procedure Test_Foreground_Check_Returns_True_With_Handle (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-018: Bounded Timed Read / Drain
   ---------------------------------------------------------------------------

   --  FUNC-OSC-018: Drain_Input completes within a reasonable wall-clock
   --  bound (defensive ceiling).
   procedure Test_Drain_Input_Bounded (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_OSC_Session_Windows;
