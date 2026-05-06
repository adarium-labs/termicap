-------------------------------------------------------------------------------
--  Test_FGPGRP - Unit Tests for Foreground Process Group Check
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the foreground process group check feature
--  (FUNC-FGP-001 through FUNC-FGP-013) as exercised via the public API of
--  Termicap.OSC.
--
--  @description
--  Because Is_Foreground_Process is a public function in Termicap.OSC, tests
--  exercise it both directly (type and contract tests) and indirectly through
--  the Open procedure which embeds the foreground guard as its first step.
--
--  Requirements Coverage:
--    - @relation(FUNC-FGP-001): Background process contamination guard
--    - @relation(FUNC-FGP-004): Is_Foreground_Process operation contract
--    - @relation(FUNC-FGP-005): Non-TTY case returns False
--    - @relation(FUNC-FGP-006): ioctl failure treated as not foreground
--    - @relation(FUNC-FGP-008): Open returns Session_Not_Foreground when not foreground
--    - @relation(FUNC-FGP-009): Foreground check uses /dev/tty FD
--    - @relation(FUNC-FGP-010): No exception propagation from foreground check
--    - @relation(FUNC-FGP-011): Stateless and idempotent check

with AUnit.Test_Cases;

package Test_FGPGRP is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-FGP-008: Session_Not_Foreground Status
   ---------------------------------------------------------------------------

   --  FUNC-FGP-008: Session_Not_Foreground is a distinct Session_Status value
   procedure Test_Session_Not_Foreground_Exists (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-008: Session_Not_Foreground is distinct from Session_OK
   procedure Test_Session_Not_Foreground_Ne_OK (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-008: Session_Not_Foreground is distinct from Session_No_Terminal
   procedure Test_Session_Not_Foreground_Ne_No_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-008: Session_Not_Foreground is distinct from Session_Save_Failed
   procedure Test_Session_Not_Foreground_Ne_Save_Failed (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-008: Session_Not_Foreground is distinct from Session_Raw_Failed
   procedure Test_Session_Not_Foreground_Ne_Raw_Failed (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-008: Session_Not_Foreground is distinct from Session_Already_Active
   procedure Test_Session_Not_Foreground_Ne_Already_Active (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-FGP-004, FUNC-FGP-010: Is_Foreground_Process contract
   ---------------------------------------------------------------------------

   --  FUNC-FGP-010: Is_Foreground_Process with INVALID_FD does not raise an exception
   procedure Test_Is_Foreground_Invalid_FD_No_Exception (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-005, FUNC-FGP-006: Is_Foreground_Process with INVALID_FD returns False
   procedure Test_Is_Foreground_Invalid_FD_Returns_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-010: Is_Foreground_Process returns a Boolean (does not raise)
   procedure Test_Is_Foreground_Returns_Boolean (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-FGP-011: Idempotency and statelesness
   ---------------------------------------------------------------------------

   --  FUNC-FGP-011: Two successive calls with INVALID_FD return the same result
   procedure Test_Is_Foreground_Idempotent_Invalid_FD (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-011: Two successive Open calls both produce the same foreground-related outcome
   procedure Test_Open_Foreground_Status_Idempotent (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-FGP-001, FUNC-FGP-008, FUNC-FGP-009: Open() integration
   ---------------------------------------------------------------------------

   --  FUNC-FGP-001, FUNC-FGP-008: Open returns a valid Session_Status (no exception)
   procedure Test_Open_Returns_Valid_Status (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-008, FUNC-FGP-009: When Open returns Session_Not_Foreground, session is not open
   procedure Test_Open_Not_Foreground_Session_Not_Open (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-008: When Open returns Session_OK, session is open and safe to use
   procedure Test_Open_OK_Session_Is_Open (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-FGP-001: Open called twice while background: both return non-OK (no bytes sent)
   procedure Test_Open_Consistent_Across_Calls (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_FGPGRP;
