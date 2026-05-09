-------------------------------------------------------------------------------
--  Test_OSC_Session_Windows - Windows integration tests for Termicap.OSC
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with Ada.Calendar; use Ada.Calendar;

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.OSC;
with Termicap.DA1;

with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;

package body Test_OSC_Session_Windows is

   use type Win32.BOOL;
   use type Win32.DWORD;
   use type Termicap.OSC.Session_Status;
   use type Termicap.OSC.File_Descriptor;

   --  Defensive wall-clock ceiling for Drain_Input on Windows.  The drain
   --  algorithm is FUNC-OSC-011 bounded to 16 iterations of WaitForSingleObject
   --  with a 0 ms timeout, so the realistic runtime is sub-millisecond.  We
   --  use 200 ms as a generous regression bound that catches obvious bugs
   --  (e.g., calling WaitForSingleObject with INFINITE) without being flaky
   --  under heavy CI load.
   DRAIN_INPUT_BOUND_S : constant Duration := 0.200;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.OSC (Windows console)");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      Register_Routine
        (T,
         Test_Open_Returns_Documented_Status'Access,
         "FUNC-OSC-008: Open returns Session_OK or Session_No_Terminal"
         & " (never Session_Save_Failed / Session_Raw_Failed on healthy host)");
      Register_Routine
        (T,
         Test_DA1_Roundtrip_Sentinel'Access,
         "FUNC-OSC-006/008: DA1 query as Sentinel_Query input returns Resp_Length=0, Timed_Out=False");
      Register_Routine
        (T,
         Test_Finalize_Restores_Console_Mode'Access,
         "FUNC-OSC-008/017: Finalize restores STD_INPUT_HANDLE and STD_OUTPUT_HANDLE console mode");
      Register_Routine
        (T,
         Test_Foreground_Check_Returns_True_With_Handle'Access,
         "FUNC-OSC-019: Is_Foreground_Process returns True on a valid console FD");
      Register_Routine
        (T,
         Test_Drain_Input_Bounded'Access,
         "FUNC-OSC-018: Drain_Input completes within a defensive wall-clock bound");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Local Helpers
   ---------------------------------------------------------------------------

   --  Snapshot the current console mode of a standard handle via GetStdHandle
   --  + GetConsoleMode.  Returns (OK => False) when the handle is not a
   --  console (e.g., redirected to a file or pipe).
   procedure Read_Std_Console_Mode
     (Std_Handle_Id :     Win32.DWORD;
      Mode          : out Win32.DWORD;
      OK            : out Boolean)
   is
      H   : constant Win32.Winnt.HANDLE := Win32.Winbase.GetStdHandle (Std_Handle_Id);
      Tmp : aliased Win32.DWORD := 0;
      Res : Win32.BOOL;
   begin
      Mode := 0;
      OK   := False;
      if H = Win32.Winbase.INVALID_HANDLE_VALUE then
         return;
      end if;
      Res := Win32.Wincon.GetConsoleMode (H, Tmp'Unchecked_Access);
      if Res /= Win32.FALSE then
         Mode := Tmp;
         OK   := True;
      end if;
   end Read_Std_Console_Mode;

   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   procedure Test_Open_Returns_Documented_Status (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Session : Termicap.OSC.Probe_Session;
      Status  : Termicap.OSC.Session_Status;
   begin
      Termicap.OSC.Open (Session, Status);
      --  On a Windows host the only legitimate outcomes are:
      --    Session_OK            — we have a usable console
      --    Session_No_Terminal   — both stdin AND stdout were redirected and
      --                            neither CONIN$/CONOUT$ could be opened.
      Assert
        (Status = Termicap.OSC.Session_OK or else Status = Termicap.OSC.Session_No_Terminal,
         "Open must return Session_OK or Session_No_Terminal on Windows; got an unexpected status");
      --  Save_Failed and Raw_Failed indicate the Phase 6 implementation
      --  regressed.  They MUST NOT happen on a healthy Windows host.
      Assert
        (Status /= Termicap.OSC.Session_Save_Failed,
         "Open must NOT return Session_Save_Failed on a healthy Windows host (FUNC-OSC-017 regression)");
      Assert
        (Status /= Termicap.OSC.Session_Raw_Failed,
         "Open must NOT return Session_Raw_Failed on a healthy Windows host (FUNC-OSC-017 regression)");
      Termicap.OSC.Close (Session);
   end Test_Open_Returns_Documented_Status;

   procedure Test_DA1_Roundtrip_Sentinel (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Session     : Termicap.OSC.Probe_Session;
      Status      : Termicap.OSC.Session_Status;
      Response    : Termicap.OSC.Response_Buffer := [others => 0];
      Resp_Length : Natural := 0;
      Timed_Out   : Boolean := True;
   begin
      Termicap.OSC.Open (Session, Status);
      if Status = Termicap.OSC.Session_OK then
         --  Sending DA1 itself as the query: the appended sentinel (DA1) IS
         --  the response, so the read loop terminates immediately with no
         --  pre-sentinel bytes.  This validates the full Sentinel_Query
         --  pathway end-to-end on Windows: Write_Query, Timed_Read,
         --  parser detection of CSI ? ... c, and the Resp_Length contract.
         Termicap.OSC.Sentinel_Query
           (Session     => Session,
            Query       => Termicap.DA1.DA1_QUERY,
            Response    => Response,
            Resp_Length => Resp_Length,
            Timeout_Ms  => 1_000,
            Timed_Out   => Timed_Out);
         Assert
           (not Timed_Out,
            "Sentinel_Query with DA1 input must NOT time out (the sentinel IS the response)");
         Assert
           (Resp_Length = 0,
            "Sentinel_Query with DA1 input must return Resp_Length = 0 (no pre-sentinel bytes)");
      else
         --  No usable console (e.g., stdin and stdout both redirected).
         --  The probe-dependent assertions cannot run; trivially pass so the
         --  test exits cleanly.
         Assert (True, "Test skipped — Open returned Session_No_Terminal");
      end if;
      Termicap.OSC.Close (Session);
   end Test_DA1_Roundtrip_Sentinel;

   procedure Test_Finalize_Restores_Console_Mode (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      In_Mode_Pre   : Win32.DWORD := 0;
      In_Mode_Post  : Win32.DWORD := 0;
      In_OK_Pre     : Boolean     := False;
      In_OK_Post    : Boolean     := False;
      Out_Mode_Pre  : Win32.DWORD := 0;
      Out_Mode_Post : Win32.DWORD := 0;
      Out_OK_Pre    : Boolean     := False;
      Out_OK_Post   : Boolean     := False;
   begin
      Read_Std_Console_Mode (Win32.Winbase.STD_INPUT_HANDLE,  In_Mode_Pre,  In_OK_Pre);
      Read_Std_Console_Mode (Win32.Winbase.STD_OUTPUT_HANDLE, Out_Mode_Pre, Out_OK_Pre);

      if not In_OK_Pre and then not Out_OK_Pre then
         --  Neither standard handle is a console; cannot exercise the
         --  restore path.  Skip.
         Assert (True, "Test skipped — no console-mode-capable standard handle");
         return;
      end if;

      declare
         Session : Termicap.OSC.Probe_Session;
         Status  : Termicap.OSC.Session_Status;
      begin
         Termicap.OSC.Open (Session, Status);
         if Status /= Termicap.OSC.Session_OK then
            --  Open did not switch to raw mode, so there is nothing to
            --  restore.  Trivially pass.
            Termicap.OSC.Close (Session);
            Assert (True, "Test skipped — Open did not return Session_OK");
            return;
         end if;
         --  Session goes out of scope at the end of this declare block;
         --  Limited_Controlled.Finalize must run unconditionally and restore
         --  both the input and output console modes.
      end;

      Read_Std_Console_Mode (Win32.Winbase.STD_INPUT_HANDLE,  In_Mode_Post,  In_OK_Post);
      Read_Std_Console_Mode (Win32.Winbase.STD_OUTPUT_HANDLE, Out_Mode_Post, Out_OK_Post);

      if In_OK_Pre and then In_OK_Post then
         Assert
           (In_Mode_Pre = In_Mode_Post,
            "STD_INPUT_HANDLE console mode must be restored after Probe_Session finalises"
            & " (FUNC-OSC-017 restore sequence)");
      end if;

      if Out_OK_Pre and then Out_OK_Post then
         Assert
           (Out_Mode_Pre = Out_Mode_Post,
            "STD_OUTPUT_HANDLE console mode must be restored after Probe_Session finalises"
            & " (FUNC-OSC-017 restore sequence)");
      end if;
   end Test_Finalize_Restores_Console_Mode;

   procedure Test_Foreground_Check_Returns_True_With_Handle (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      FD : Termicap.OSC.File_Descriptor;
   begin
      FD := Termicap.OSC.Open_Terminal;
      if FD = Termicap.OSC.INVALID_FD then
         --  No usable console.  Skip cleanly; the foreground check has no
         --  meaning without a backing handle.
         Assert (True, "Test skipped — Open_Terminal returned INVALID_FD");
         return;
      end if;
      --  FUNC-OSC-019: on Windows the foreground check reduces to "did we
      --  acquire a usable console handle?".  Since Open_Terminal succeeded,
      --  the answer must be True.
      Assert
        (Termicap.OSC.Is_Foreground_Process (FD),
         "Is_Foreground_Process must return True for a valid console FD on Windows");
      Termicap.OSC.Close_Terminal (FD);
   end Test_Foreground_Check_Returns_True_With_Handle;

   procedure Test_Drain_Input_Bounded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      FD      : Termicap.OSC.File_Descriptor;
      T_Start : Time;
      Elapsed : Duration;
   begin
      --  Drain_Input takes a raw File_Descriptor (the Session's FD field is
      --  private), so we exercise it via Open_Terminal which returns the
      --  same kind of FD that Probe_Session.Open ultimately uses internally.
      FD := Termicap.OSC.Open_Terminal;
      if FD = Termicap.OSC.INVALID_FD then
         --  No usable console; Drain_Input has no FD to operate on.
         Assert (True, "Test skipped — Open_Terminal returned INVALID_FD");
         return;
      end if;
      T_Start := Clock;
      Termicap.OSC.Drain_Input (FD);
      Elapsed := Clock - T_Start;
      Termicap.OSC.Close_Terminal (FD);
      Assert
        (Elapsed < DRAIN_INPUT_BOUND_S,
         "Drain_Input must complete within the defensive wall-clock bound"
         & " (FUNC-OSC-011 / FUNC-OSC-018 — bounded iteration count)");
   end Test_Drain_Input_Bounded;

end Test_OSC_Session_Windows;
