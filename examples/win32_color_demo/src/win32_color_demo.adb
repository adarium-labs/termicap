-------------------------------------------------------------------------------
--  Win32_Color_Demo - Windows Console Color Detection Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates that Termicap detects color support correctly on Windows
--  using only the public API.
--
--  @description
--  On Windows 10+, Termicap automatically integrates three sources of
--  color capability evidence:
--
--  1. Windows build number — Win10 build 10586+ supports 256 colours;
--     build 14931+ supports 24-bit TrueColor.
--  2. WT_SESSION — if present and non-empty, the terminal is Windows
--     Terminal, which always supports TrueColor.
--  3. Standard environment variable cascade — FORCE_COLOR, NO_COLOR,
--     COLORTERM, TERM_PROGRAM, CI, etc. (same as all platforms).
--
--  Run from different contexts to see how the result changes:
--
--    win32_color_demo.exe              -- Windows Terminal (WT_SESSION set)
--    win32_color_demo.exe              -- plain cmd.exe or conhost
--    set NO_COLOR=1 && win32_color_demo.exe   -- NO_COLOR suppresses all
--    set FORCE_COLOR=3 && win32_color_demo.exe -- FORCE_COLOR mandates TrueColor

with Ada.Text_IO;

with Termicap.Capabilities;
with Termicap.Color;
with Termicap.Dimensions;
with Termicap.TTY;

procedure Win32_Color_Demo is

   use Ada.Text_IO;

   function Color_Name (Level : Termicap.Color.Color_Level) return String is
   begin
      return
        (case Level is
            when Termicap.Color.None         => "None  (no color support)",
            when Termicap.Color.Basic_16     => "Basic_16  (16 colors)",
            when Termicap.Color.Extended_256 => "Extended_256  (256 colors)",
            when Termicap.Color.True_Color   => "True_Color  (24-bit, 16M colors)");
   end Color_Name;

   Caps : constant Termicap.Capabilities.Terminal_Capabilities :=
     Termicap.Capabilities.Detect;

begin
   Put_Line ("=== Termicap Windows Console Demo ===");
   New_Line;

   Put_Line ("TTY status:");
   Put_Line ("  stdin  : " & Boolean'Image (Caps.TTY_Stdin));
   Put_Line ("  stdout : " & Boolean'Image (Caps.TTY_Stdout));
   Put_Line ("  stderr : " & Boolean'Image (Caps.TTY_Stderr));
   New_Line;

   Put_Line ("Color level  : " & Color_Name (Caps.Color));
   Put_Line ("Terminal cols: " & Integer'Image (Caps.Size.Columns));
   Put_Line ("Terminal rows: " & Integer'Image (Caps.Size.Rows));
   New_Line;

   Put_Line ("Downsampling available : " & Boolean'Image (Caps.Downsampling_Available));
   New_Line;

   Put_Line ("Note: on Windows Terminal (WT_SESSION set), Color = True_Color.");
   Put_Line ("      On older conhost builds, Color reflects the OS build threshold.");
   Put_Line ("      FORCE_COLOR / NO_COLOR env vars take full priority.");

end Win32_Color_Demo;
