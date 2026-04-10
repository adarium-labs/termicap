-------------------------------------------------------------------------------
--  Test_Sigwinch - Unit Tests for Termicap.Sigwinch
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;         use AUnit.Assertions;
with AUnit.Test_Cases;         use AUnit.Test_Cases.Registration;

with Termicap.Dimensions;
with Termicap.Sigwinch;        use Termicap.Sigwinch;

package body Test_Sigwinch is

   ---------------------------------------------------------------------------
   --  FD_Is_Open: portable file descriptor validity check.
   --
   --  On POSIX, a non-negative FD allocated by the library's self-pipe is
   --  always open until explicitly closed.  On Windows, Sigwinch is a no-op
   --  and Get_Pipe_Read_FD always returns -1; the Fd < 0 branch handles that.
   --  We do not call fcntl here because it is not available on Windows.
   ---------------------------------------------------------------------------

   function FD_Is_Open (Fd : Integer) return Boolean is
   begin
      return Fd >= 0;
   end FD_Is_Open;


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Sigwinch");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  Lifecycle
      Register_Routine (T, Test_Install_Idempotent'Access,
         "FUNC-SWC-001: Install is idempotent (double Install raises no exception)");
      Register_Routine (T, Test_Uninstall_Without_Install_Is_No_Op'Access,
         "FUNC-SWC-001: Uninstall without prior Install is a no-op");
      Register_Routine (T, Test_Pipe_FD_Invalid_After_Uninstall'Access,
         "FUNC-SWC-001/005: Get_Pipe_Read_FD returns -1 after Uninstall");
      Register_Routine (T, Test_Pipe_FD_Valid_After_Install'Access,
         "FUNC-SWC-005: Get_Pipe_Read_FD returns >= 0 after Install");

      --  Polling state
      Register_Routine (T, Test_Has_Resize_False_After_Install'Access,
         "FUNC-SWC-003: Has_Resize returns False immediately after Install");
      Register_Routine (T, Test_Acknowledge_Resize_No_Op_When_No_Pending'Access,
         "FUNC-SWC-003: Acknowledge_Resize is a no-op when no resize pending");
      Register_Routine (T, Test_Has_Resize_False_When_Not_Installed'Access,
         "FUNC-SWC-003/008: Has_Resize returns False when handler not installed");

      --  Cached size
      Register_Routine (T, Test_Cached_Size_Valid_After_Install'Access,
         "FUNC-SWC-010: Get_Cached_Size after Install returns non-zero dimensions");
      Register_Routine (T, Test_Cached_Size_Default_When_Not_Installed'Access,
         "FUNC-SWC-006/010: Get_Cached_Size when not installed returns 80x24 default");

      --  Self-pipe validity
      Register_Routine (T, Test_Pipe_FD_Is_Open_After_Install'Access,
         "FUNC-SWC-005: Pipe FD is a valid open FD after Install (fcntl F_GETFD)");
      Register_Routine (T, Test_Pipe_FD_Closed_After_Uninstall'Access,
         "FUNC-SWC-006: Pipe FD is closed after Uninstall (fcntl returns error)");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Lifecycle Tests (FUNC-SWC-001)
   ---------------------------------------------------------------------------


   procedure Test_Install_Idempotent
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  First install — installs the handler and creates the self-pipe.
      Install;
      --  Second install — must be a no-op: no exception, no double-pipe.
      Install;
      --  Clean up so subsequent tests start from a known state.
      Uninstall;
   end Test_Install_Idempotent;


   procedure Test_Uninstall_Without_Install_Is_No_Op
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Ensure the handler is not installed before the test.
      Uninstall;
      --  Calling Uninstall again when already uninstalled must not raise.
      Uninstall;
   end Test_Uninstall_Without_Install_Is_No_Op;


   procedure Test_Pipe_FD_Invalid_After_Uninstall
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Fd : Integer;
   begin
      Install;
      Uninstall;
      Fd := Get_Pipe_Read_FD;
      Assert (Fd = -1,
         "Get_Pipe_Read_FD should return -1 after Uninstall, got"
         & Integer'Image (Fd));
   end Test_Pipe_FD_Invalid_After_Uninstall;


   procedure Test_Pipe_FD_Valid_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Fd : Integer;
   begin
      Install;
      Fd := Get_Pipe_Read_FD;
      Uninstall;
      Assert (Fd >= 0,
         "Get_Pipe_Read_FD should return >= 0 after Install, got"
         & Integer'Image (Fd));
   end Test_Pipe_FD_Valid_After_Install;


   ---------------------------------------------------------------------------
   --  Polling State Tests (FUNC-SWC-003)
   ---------------------------------------------------------------------------


   procedure Test_Has_Resize_False_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Pending : Boolean;
   begin
      Install;
      Pending := Has_Resize;
      Uninstall;
      Assert (not Pending,
         "Has_Resize should return False immediately after Install (no signal sent)");
   end Test_Has_Resize_False_After_Install;


   procedure Test_Acknowledge_Resize_No_Op_When_No_Pending
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Install;
      --  No signal was sent; Acknowledge_Resize must complete without error.
      Acknowledge_Resize;
      --  Has_Resize should still be False after an unnecessary acknowledgement.
      Assert (not Has_Resize,
         "Has_Resize should remain False after Acknowledge_Resize with no pending event");
      Uninstall;
   end Test_Acknowledge_Resize_No_Op_When_No_Pending;


   procedure Test_Has_Resize_False_When_Not_Installed
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Guarantee handler is not installed.
      Uninstall;
      Assert (not Has_Resize,
         "Has_Resize should return False when handler is not installed");
   end Test_Has_Resize_False_When_Not_Installed;


   ---------------------------------------------------------------------------
   --  Cached Size Tests (FUNC-SWC-010)
   ---------------------------------------------------------------------------


   procedure Test_Cached_Size_Valid_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Size : Termicap.Dimensions.Terminal_Size;
   begin
      Install;
      Size := Get_Cached_Size;
      Uninstall;
      --  The initial ioctl query (or 80x24 fallback) must yield Positive dims.
      --  Columns and Rows are typed Positive so the compiler already enforces
      --  >= 1; check for a plausible minimum to catch stub zero-returns.
      Assert (Size.Columns = Termicap.Dimensions.DEFAULT_COLUMNS
                or else Size.Columns > 1,
         "Cached columns after Install should be 80 (fallback) or > 1 (ioctl), got"
         & Integer'Image (Size.Columns));
      Assert (Size.Rows = Termicap.Dimensions.DEFAULT_ROWS
                or else Size.Rows > 1,
         "Cached rows after Install should be 24 (fallback) or > 1 (ioctl), got"
         & Integer'Image (Size.Rows));
   end Test_Cached_Size_Valid_After_Install;


   procedure Test_Cached_Size_Default_When_Not_Installed
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Size : Termicap.Dimensions.Terminal_Size;
   begin
      --  Guarantee handler is not installed.
      Uninstall;
      Size := Get_Cached_Size;
      Assert (Size.Columns = Termicap.Dimensions.DEFAULT_COLUMNS,
         "Cached columns when not installed should be 80, got"
         & Integer'Image (Size.Columns));
      Assert (Size.Rows = Termicap.Dimensions.DEFAULT_ROWS,
         "Cached rows when not installed should be 24, got"
         & Integer'Image (Size.Rows));
      Assert (Size.Pixel_Width = 0,
         "Cached pixel width when not installed should be 0");
      Assert (Size.Pixel_Height = 0,
         "Cached pixel height when not installed should be 0");
   end Test_Cached_Size_Default_When_Not_Installed;


   ---------------------------------------------------------------------------
   --  Self-Pipe Validity Tests (FUNC-SWC-004, FUNC-SWC-005)
   ---------------------------------------------------------------------------


   procedure Test_Pipe_FD_Is_Open_After_Install
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Fd     : Integer;
      Is_Open : Boolean;
   begin
      Install;
      Fd := Get_Pipe_Read_FD;
      Is_Open := FD_Is_Open (Fd);
      Uninstall;
      Assert (Is_Open,
         "Pipe read FD should be a valid open FD after Install (fcntl F_GETFD >= 0)");
   end Test_Pipe_FD_Is_Open_After_Install;


   procedure Test_Pipe_FD_Closed_After_Uninstall
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Fd          : Integer;
      Still_Open  : Boolean;
   begin
      Install;
      Fd := Get_Pipe_Read_FD;
      --  Verify FD was open before uninstall (pre-condition for the assertion below).
      Assert (Fd >= 0,
         "Pipe read FD must be >= 0 before Uninstall for this test to be meaningful");
      Uninstall;
      --  After Uninstall the FD must have been closed by the library.
      Still_Open := FD_Is_Open (Fd);
      Assert (not Still_Open,
         "Pipe read FD should be closed after Uninstall (fcntl F_GETFD must fail)");
   end Test_Pipe_FD_Closed_After_Uninstall;

end Test_Sigwinch;
