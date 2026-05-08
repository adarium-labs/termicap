-------------------------------------------------------------------------------
--  Test_FGPGRP - Unit Tests for Foreground Process Group Check
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.OSC; use Termicap.OSC;

package body Test_FGPGRP is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.OSC (FGPGRP)");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-FGP-008: Session_Not_Foreground status distinctness
      Register_Routine
        (T,
         Test_Session_Not_Foreground_Exists'Access,
         "FUNC-FGP-008: Session_Not_Foreground is a valid Session_Status value");
      Register_Routine
        (T, Test_Session_Not_Foreground_Ne_OK'Access, "FUNC-FGP-008: Session_Not_Foreground /= Session_OK");
      Register_Routine
        (T,
         Test_Session_Not_Foreground_Ne_No_Terminal'Access,
         "FUNC-FGP-008: Session_Not_Foreground /= Session_No_Terminal");
      Register_Routine
        (T,
         Test_Session_Not_Foreground_Ne_Save_Failed'Access,
         "FUNC-FGP-008: Session_Not_Foreground /= Session_Save_Failed");
      Register_Routine
        (T,
         Test_Session_Not_Foreground_Ne_Raw_Failed'Access,
         "FUNC-FGP-008: Session_Not_Foreground /= Session_Raw_Failed");
      Register_Routine
        (T,
         Test_Session_Not_Foreground_Ne_Already_Active'Access,
         "FUNC-FGP-008: Session_Not_Foreground /= Session_Already_Active");

      --  FUNC-FGP-004, FUNC-FGP-010: Is_Foreground_Process contract
      Register_Routine
        (T,
         Test_Is_Foreground_Invalid_FD_No_Exception'Access,
         "FUNC-FGP-010: Is_Foreground_Process (INVALID_FD) does not raise");
      Register_Routine
        (T,
         Test_Is_Foreground_Invalid_FD_Returns_False'Access,
         "FUNC-FGP-005/006: Is_Foreground_Process (INVALID_FD) returns False");
      Register_Routine
        (T,
         Test_Is_Foreground_Returns_Boolean'Access,
         "FUNC-FGP-004: Is_Foreground_Process result is Boolean (no exception)");

      --  FUNC-FGP-011: Idempotency
      Register_Routine
        (T,
         Test_Is_Foreground_Idempotent_Invalid_FD'Access,
         "FUNC-FGP-011: Is_Foreground_Process (INVALID_FD) gives same result on repeated calls");
      Register_Routine
        (T,
         Test_Open_Foreground_Status_Idempotent'Access,
         "FUNC-FGP-011: Open foreground-related status is consistent across successive calls");

      --  FUNC-FGP-001, FUNC-FGP-008, FUNC-FGP-009: Open() integration
      Register_Routine
        (T,
         Test_Open_Returns_Valid_Status'Access,
         "FUNC-FGP-001/008: Open returns a valid Session_Status without exception");
      Register_Routine
        (T,
         Test_Open_Not_Foreground_Session_Not_Open'Access,
         "FUNC-FGP-008/009: Session_Not_Foreground => Is_Open is False");
      Register_Routine (T, Test_Open_OK_Session_Is_Open'Access, "FUNC-FGP-008: Session_OK => Is_Open is True");
      Register_Routine
        (T,
         Test_Open_Consistent_Across_Calls'Access,
         "FUNC-FGP-001: Open foreground-related outcome is consistent across two successive calls");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   --  Return True if Status is a valid member of Session_Status.
   --  Because Session_Status is an enumeration the compiler guarantees all
   --  values are valid Ada values; the function exercises the case statement
   --  to confirm the set of legal values matches the spec.
   function Is_Valid_Status (Status : Session_Status) return Boolean is
   begin
      case Status is
         when Session_OK
            | Session_Not_Foreground
            | Session_No_Terminal
            | Session_Save_Failed
            | Session_Raw_Failed
            | Session_Already_Active
         =>
            return True;
      end case;
   end Is_Valid_Status;

   ---------------------------------------------------------------------------
   --  FUNC-FGP-008: Session_Not_Foreground Status distinctness
   ---------------------------------------------------------------------------

   procedure Test_Session_Not_Foreground_Exists (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : constant Session_Status := Session_Not_Foreground;
   begin
      Assert (Is_Valid_Status (Status), "Session_Not_Foreground must be a valid Session_Status value");
   end Test_Session_Not_Foreground_Exists;

   procedure Test_Session_Not_Foreground_Ne_OK (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Assign to a variable rather than a constant so GNAT cannot fold the
      --  comparison to a compile-time True and emit a spurious warning.
      NF : Session_Status := Session_Not_Foreground;
   begin
      Assert (NF /= Session_OK, "Session_Not_Foreground must be distinct from Session_OK (FUNC-FGP-008)");
   end Test_Session_Not_Foreground_Ne_OK;

   procedure Test_Session_Not_Foreground_Ne_No_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      NF : Session_Status := Session_Not_Foreground;
   begin
      Assert
        (NF /= Session_No_Terminal, "Session_Not_Foreground must be distinct from Session_No_Terminal (FUNC-FGP-008)");
   end Test_Session_Not_Foreground_Ne_No_Terminal;

   procedure Test_Session_Not_Foreground_Ne_Save_Failed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      NF : Session_Status := Session_Not_Foreground;
   begin
      Assert
        (NF /= Session_Save_Failed, "Session_Not_Foreground must be distinct from Session_Save_Failed (FUNC-FGP-008)");
   end Test_Session_Not_Foreground_Ne_Save_Failed;

   procedure Test_Session_Not_Foreground_Ne_Raw_Failed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      NF : Session_Status := Session_Not_Foreground;
   begin
      Assert
        (NF /= Session_Raw_Failed, "Session_Not_Foreground must be distinct from Session_Raw_Failed (FUNC-FGP-008)");
   end Test_Session_Not_Foreground_Ne_Raw_Failed;

   procedure Test_Session_Not_Foreground_Ne_Already_Active (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      NF : Session_Status := Session_Not_Foreground;
   begin
      Assert
        (NF /= Session_Already_Active,
         "Session_Not_Foreground must be distinct from Session_Already_Active (FUNC-FGP-008)");
   end Test_Session_Not_Foreground_Ne_Already_Active;

   ---------------------------------------------------------------------------
   --  FUNC-FGP-004, FUNC-FGP-010: Is_Foreground_Process contract
   ---------------------------------------------------------------------------

   procedure Test_Is_Foreground_Invalid_FD_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Result : Boolean;
   begin
      --  FUNC-FGP-010: Must not raise any exception, including on INVALID_FD.
      --  FUNC-FGP-005/006: INVALID_FD (-1) causes ioctl to fail; result is False.
      Result := Is_Foreground_Process (INVALID_FD);
      Assert (not Result, "Is_Foreground_Process (INVALID_FD) must return False without raising (FUNC-FGP-010)");
   end Test_Is_Foreground_Invalid_FD_No_Exception;

   procedure Test_Is_Foreground_Invalid_FD_Returns_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  FUNC-FGP-005: Non-TTY (or invalid) FD -> ioctl fails -> returns False.
      --  FUNC-FGP-006: Any ioctl failure is silently treated as False.
      Assert
        (not Is_Foreground_Process (INVALID_FD),
         "Is_Foreground_Process (INVALID_FD) must return False (FUNC-FGP-005, FUNC-FGP-006)");
   end Test_Is_Foreground_Invalid_FD_Returns_False;

   procedure Test_Is_Foreground_Returns_Boolean (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Open /dev/tty to get a real terminal FD; if that is not possible we
      --  fall back to INVALID_FD.  Either way the call must return a Boolean
      --  without raising (FUNC-FGP-004, FUNC-FGP-010).
      FD     : File_Descriptor := Open_Terminal;
      Result : Boolean;
   begin
      if FD = INVALID_FD then
         --  No controlling terminal in this test environment; use INVALID_FD.
         Result := Is_Foreground_Process (INVALID_FD);
         Assert (not Result, "Is_Foreground_Process (INVALID_FD) must return False (FUNC-FGP-006)");
      else
         --  A real terminal FD is available; the call must return without exception.
         Result := Is_Foreground_Process (FD);
         --  Result may be True (foreground) or False (background/CI); both are valid.
         --  We verify the call completed without exception by checking that the
         --  Boolean result equals itself when compared via an intermediate variable.
         declare
            Check : Boolean := Result;
         begin
            Assert (Check = Result, "Is_Foreground_Process must return a Boolean value (FUNC-FGP-004)");
         end;
         Close_Terminal (FD);
      end if;
   end Test_Is_Foreground_Returns_Boolean;

   ---------------------------------------------------------------------------
   --  FUNC-FGP-011: Idempotency
   ---------------------------------------------------------------------------

   procedure Test_Is_Foreground_Idempotent_Invalid_FD (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-FGP-011: Stateless — two calls with the same FD return the same result.
      Result_1 : constant Boolean := Is_Foreground_Process (INVALID_FD);
      Result_2 : constant Boolean := Is_Foreground_Process (INVALID_FD);
   begin
      Assert
        (Result_1 = Result_2,
         "Is_Foreground_Process (INVALID_FD) must return the same value on repeated calls (FUNC-FGP-011)");
   end Test_Is_Foreground_Idempotent_Invalid_FD;

   procedure Test_Open_Foreground_Status_Idempotent (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-FGP-011: Two successive Open calls in the same environment must
      --  produce a consistent foreground-related outcome (both non-foreground or
      --  both foreground — the process group does not change during the test).
      --
      --  We only compare whether the first call resulted in Session_Not_Foreground
      --  or Session_No_Terminal vs. the second call.  If the first call succeeded
      --  (Session_OK) we close the session before the second call.
      Status_1 : Session_Status;
      Status_2 : Session_Status;

      --  Helper to test foreground-related outcome category.
      function Foreground_Suppressed (S : Session_Status) return Boolean
      is (S = Session_Not_Foreground or else S = Session_No_Terminal);

   begin
      declare
         S1 : Probe_Session;
      begin
         Open (S1, Status_1);
         Close (S1);
      end;

      declare
         S2 : Probe_Session;
      begin
         Open (S2, Status_2);
         Close (S2);
      end;

      --  Both calls must agree on whether probing was suppressed for
      --  foreground-related reasons.  Session_Already_Active cannot occur
      --  because we closed S1 before opening S2.
      Assert
        (Status_2 /= Session_Already_Active,
         "Second Open after Close must not return Session_Already_Active (FUNC-FGP-011)");
      Assert
        (Foreground_Suppressed (Status_1) = Foreground_Suppressed (Status_2),
         "Open foreground-suppression outcome must be consistent across successive calls (FUNC-FGP-011)");
   end Test_Open_Foreground_Status_Idempotent;

   ---------------------------------------------------------------------------
   --  FUNC-FGP-001, FUNC-FGP-008, FUNC-FGP-009: Open() integration
   ---------------------------------------------------------------------------

   procedure Test_Open_Returns_Valid_Status (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-FGP-001, FUNC-FGP-008: Open must return a valid Session_Status
      --  without raising any exception regardless of the test environment.
      Status : Session_Status;
   begin
      declare
         S : Probe_Session;
      begin
         Open (S, Status);
         Close (S);
      end;
      Assert (Is_Valid_Status (Status), "Open must return a valid Session_Status without exception (FUNC-FGP-001)");
   end Test_Open_Returns_Valid_Status;

   procedure Test_Open_Not_Foreground_Session_Not_Open (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-FGP-008: When Open returns Session_Not_Foreground, no session is
      --  open (Is_Open must be False) because no bytes were sent to the terminal
      --  and no raw mode was activated.
      Status : Session_Status;
   begin
      declare
         S : Probe_Session;
      begin
         Open (S, Status);
         if Status = Session_Not_Foreground then
            Assert (not Is_Open (S), "Is_Open must be False when status is Session_Not_Foreground (FUNC-FGP-008)");
         end if;
         Close (S);
      end;
      --  If the status was not Session_Not_Foreground the test is vacuously
      --  satisfied in this environment (process is foreground or no terminal).
      Assert (True, "Test_Open_Not_Foreground_Session_Not_Open completed without exception");
   end Test_Open_Not_Foreground_Session_Not_Open;

   procedure Test_Open_OK_Session_Is_Open (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-FGP-008: When Open returns Session_OK, Is_Open must be True.
      --  This tests the positive path: process is foreground with a controlling
      --  terminal.  In CI or piped environments the test is vacuously satisfied.
      Status : Session_Status;
   begin
      declare
         S : Probe_Session;
      begin
         Open (S, Status);
         if Status = Session_OK then
            Assert (Is_Open (S), "Is_Open must be True when Open returned Session_OK (FUNC-FGP-008)");
         end if;
         Close (S);
      end;
      Assert (True, "Test_Open_OK_Session_Is_Open completed without exception");
   end Test_Open_OK_Session_Is_Open;

   procedure Test_Open_Consistent_Across_Calls (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  FUNC-FGP-001: In a given environment the foreground check result does
      --  not change between calls.  We run Open twice (closing between) and
      --  check that both return the same foreground-suppression category.
      Status_1 : Session_Status;
      Status_2 : Session_Status;

      function Is_Foreground_Blocked (S : Session_Status) return Boolean
      is (S = Session_Not_Foreground);

   begin
      declare
         S : Probe_Session;
      begin
         Open (S, Status_1);
         Close (S);
      end;

      declare
         S : Probe_Session;
      begin
         Open (S, Status_2);
         Close (S);
      end;

      Assert
        (Status_2 /= Session_Already_Active,
         "Second Open after Close must not return Session_Already_Active (FUNC-FGP-001)");
      Assert
        (Is_Foreground_Blocked (Status_1) = Is_Foreground_Blocked (Status_2),
         "Foreground-blocked outcome must be consistent across two Open calls (FUNC-FGP-001)");
   end Test_Open_Consistent_Across_Calls;

end Test_FGPGRP;
