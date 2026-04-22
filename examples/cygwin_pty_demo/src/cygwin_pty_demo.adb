-------------------------------------------------------------------------------
--  Cygwin_Pty_Demo - Cygwin / MSYS2 PTY Detection Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates that Is_TTY correctly handles Cygwin and MSYS2 PTY handles.
--
--  @description
--  On Windows, a Cygwin or MSYS2 shell connects standard streams to named
--  pipes rather than console objects.  Win32.Wincon.GetConsoleMode therefore
--  returns FALSE for those handles, causing a naive TTY check to report False.
--
--  Termicap.TTY.Is_TTY compensates by also inspecting the pipe name against
--  the Cygwin/MSYS2 pattern before returning False for a non-console handle
--  (FUNC-CYG-015).  When run inside mintty, Cygwin bash, or MSYS2 bash,
--  stdout is reported as a TTY without any change to the calling API.

with Ada.Text_IO;
with Termicap.TTY;
with Termicap.Capabilities;
with Termicap.Color;

procedure Cygwin_Pty_Demo is

   use Ada.Text_IO;

   Caps : constant Termicap.Capabilities.Terminal_Capabilities :=
            Termicap.Capabilities.Get;

begin
   Put_Line ("=== Termicap Cygwin / MSYS2 PTY Demo ===");
   New_Line;

   Put_Line ("TTY status (via Termicap.TTY.Is_TTY):");
   Put_Line ("  stdin  : " & Boolean'Image (Termicap.TTY.Is_TTY (Termicap.TTY.Stdin)));
   Put_Line ("  stdout : " & Boolean'Image (Termicap.TTY.Is_TTY (Termicap.TTY.Stdout)));
   Put_Line ("  stderr : " & Boolean'Image (Termicap.TTY.Is_TTY (Termicap.TTY.Stderr)));
   New_Line;

   Put_Line ("Detected capabilities:");
   Put_Line ("  TTY_Stdout : " & Boolean'Image (Caps.TTY_Stdout));
   Put_Line ("  Color      : " & Termicap.Color.Color_Level'Image (Caps.Color));
   New_Line;

   Put_Line ("Note: in a Cygwin/MSYS2 shell (mintty, git-bash, MSYS2 bash)");
   Put_Line ("      Is_TTY should be TRUE even though GetConsoleMode returns");
   Put_Line ("      FALSE for named-pipe PTY handles.  In a plain cmd.exe or");
   Put_Line ("      PowerShell window the result depends on the console mode.");

end Cygwin_Pty_Demo;
