-------------------------------------------------------------------------------
--  Termicap.Sigwinch - SIGWINCH Resize Notification (Windows Stub Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows no-op stub for SIGWINCH.  SIGWINCH is a POSIX signal that does not
--  exist on Windows; all operations are safe no-ops.
--
--  Requirements Coverage:
--    - @relation(FUNC-SWC-008): Graceful degradation on non-Unix platforms

pragma SPARK_Mode (Off);

package body Termicap.Sigwinch is

   procedure Install (Terminal_FD : Integer := 1) is
      pragma Unreferenced (Terminal_FD);
   begin
      null;  --  No SIGWINCH on Windows; graceful no-op (FUNC-SWC-008)
   end Install;

   procedure Uninstall is
   begin
      null;  --  No-op on Windows
   end Uninstall;

   function Has_Resize return Boolean is
   begin
      return False;  --  Never any resize events on Windows via SIGWINCH
   end Has_Resize;

   procedure Acknowledge_Resize is
   begin
      null;  --  No-op on Windows
   end Acknowledge_Resize;

   function Get_Pipe_Read_FD return Integer is
   begin
      return -1;  --  No self-pipe on Windows (FUNC-SWC-008)
   end Get_Pipe_Read_FD;

   function Get_Cached_Size return Termicap.Dimensions.Terminal_Size is
   begin
      return (Rows         => Termicap.Dimensions.DEFAULT_ROWS,
              Columns      => Termicap.Dimensions.DEFAULT_COLUMNS,
              Pixel_Width  => 0,
              Pixel_Height => 0);
   end Get_Cached_Size;

end Termicap.Sigwinch;
