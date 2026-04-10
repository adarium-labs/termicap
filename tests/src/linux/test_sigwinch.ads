-------------------------------------------------------------------------------
--  Test_Sigwinch - Unit Tests for Termicap.Sigwinch
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the SIGWINCH resize notification lifecycle,
--  polling interface, self-pipe FD validity, and cached dimension retrieval.
--
--  Requirements Coverage:
--    - @relation(FUNC-SWC-001): Signal handler installation and removal
--    - @relation(FUNC-SWC-003): Resize event polling interface
--    - @relation(FUNC-SWC-005): Pipe read FD exposure
--    - @relation(FUNC-SWC-006): Handler cleanup and resource release
--    - @relation(FUNC-SWC-008): Graceful degradation on non-Unix platforms
--    - @relation(FUNC-SWC-010): Current cached dimensions retrieval

with AUnit.Test_Cases;

package Test_Sigwinch is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Lifecycle Tests (FUNC-SWC-001)
   ---------------------------------------------------------------------------

   --  FUNC-SWC-001: Install is idempotent (double Install raises no exception)
   procedure Test_Install_Idempotent
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SWC-001: Uninstall without prior Install is a no-op
   procedure Test_Uninstall_Without_Install_Is_No_Op
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SWC-001, FUNC-SWC-005: Get_Pipe_Read_FD returns -1 after Uninstall
   procedure Test_Pipe_FD_Invalid_After_Uninstall
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SWC-005: Get_Pipe_Read_FD returns >= 0 after Install
   procedure Test_Pipe_FD_Valid_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Polling State Tests (FUNC-SWC-003)
   ---------------------------------------------------------------------------

   --  FUNC-SWC-003: Has_Resize returns False immediately after Install
   procedure Test_Has_Resize_False_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SWC-003: Acknowledge_Resize is a no-op when no resize pending
   procedure Test_Acknowledge_Resize_No_Op_When_No_Pending
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SWC-003, FUNC-SWC-008: Has_Resize returns False when not installed
   procedure Test_Has_Resize_False_When_Not_Installed
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Cached Size Tests (FUNC-SWC-010)
   ---------------------------------------------------------------------------

   --  FUNC-SWC-010: Get_Cached_Size after Install returns non-zero dimensions
   procedure Test_Cached_Size_Valid_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SWC-006, FUNC-SWC-010: Get_Cached_Size when not installed returns
   --  80x24 default
   procedure Test_Cached_Size_Default_When_Not_Installed
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Self-Pipe Validity Tests (FUNC-SWC-004, FUNC-SWC-005)
   ---------------------------------------------------------------------------

   --  FUNC-SWC-005: Pipe FD is a valid open FD after Install (fcntl F_GETFD)
   procedure Test_Pipe_FD_Is_Open_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-SWC-006: Pipe FD is closed after Uninstall (fcntl returns error)
   procedure Test_Pipe_FD_Closed_After_Uninstall
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Sigwinch;
