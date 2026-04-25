-------------------------------------------------------------------------------
--  Graphics_Demo - Sixel / Kitty Graphics Protocol Detection Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates Sixel and Kitty graphics protocol detection via
--  Termicap.Graphics.IO.
--
--  @description
--  Calls Detect_Graphics (the primary cached entry point) and prints a
--  human-readable summary of the resulting Graphics_Capabilities record:
--    - Sixel_Supported and Kitty_Graphics_Supported flags
--    - Detection provenance: Sixel_Via_DA1 vs. passive heuristics,
--      Kitty_Via_Active_Probe vs. passive env-vars
--    - Whether any active probe was performed (Probed)
--    - Sixel_Color_Registers (number of available color registers, or unknown)
--    - Kitty_Graphics_Version (protocol version, or unknown)
--  Lists the named terminal identifier constants (FUNC-SXL-004) so the reader
--  can see which terminal names drive passive detection.
--  Exits with status 0 when either Sixel or Kitty graphics are supported;
--  exits with status 1 otherwise (expected in non-TTY / CI environments).
--
--  Requirements demonstrated:
--    FUNC-SXL-001  Graphics_Capabilities result record
--    FUNC-SXL-002  Sixel_Color_Registers optional field
--    FUNC-SXL-003  Kitty_Graphics_Version optional field
--    FUNC-SXL-004  Named terminal identifier constants
--    FUNC-SXL-005  Sixel detection via DA1 Has_Capability
--    FUNC-SXL-008  Passive Sixel env-var heuristics
--    FUNC-SXL-009  Passive Kitty env-var heuristics
--    FUNC-SXL-010  Optional Kitty APC active probe
--    FUNC-SXL-012  Detection cascade with guards
--    FUNC-SXL-013  Non-TTY passive fallback
--    FUNC-SXL-016  No-exception guarantee
--    FUNC-SXL-017  One-probe-per-process caching

with Ada.Command_Line;
with Ada.Text_IO;

with Termicap.Graphics;
with Termicap.Graphics.IO;

procedure Graphics_Demo is

   use Ada.Text_IO;
   use Termicap.Graphics;

   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   function Bool_Image (Value : Boolean) return String is
     (if Value then "Yes" else "No");


   ---------------------------------------------------------------------------
   --  Print provenance details for Sixel detection
   ---------------------------------------------------------------------------

   procedure Print_Sixel_Provenance (Caps : Graphics_Capabilities) is
   begin
      if not Caps.Sixel_Supported then
         Put_Line ("  Sixel provenance:    N/A (not supported)");
         return;
      end if;

      if Caps.Sixel_Via_DA1 then
         Put_Line ("  Sixel provenance:    Active DA1 probe (Ps=4 confirmed)");
      else
         Put_Line ("  Sixel provenance:    Passive heuristics (TERM / TERM_PROGRAM / XTVERSION)");
      end if;
   end Print_Sixel_Provenance;


   ---------------------------------------------------------------------------
   --  Print provenance details for Kitty graphics detection
   ---------------------------------------------------------------------------

   procedure Print_Kitty_Provenance (Caps : Graphics_Capabilities) is
   begin
      if not Caps.Kitty_Graphics_Supported then
         Put_Line ("  Kitty provenance:    N/A (not supported)");
         return;
      end if;

      if Caps.Kitty_Via_Active_Probe then
         Put_Line ("  Kitty provenance:    Active APC probe (ESC _ G response OK)");
      else
         Put_Line ("  Kitty provenance:    Passive env-var heuristics");
         Put_Line ("                       (KITTY_WINDOW_ID, TERM=xterm-kitty, or TERM_PROGRAM=WezTerm)");
      end if;
   end Print_Kitty_Provenance;


   ---------------------------------------------------------------------------
   --  Print the Sixel_Color_Registers optional sub-field
   ---------------------------------------------------------------------------

   procedure Print_Color_Registers (Caps : Graphics_Capabilities) is
   begin
      if Caps.Sixel_Color_Registers = 0 then
         Put_Line ("  Sixel color registers: unknown");
      else
         Put_Line ("  Sixel color registers: " & Natural'Image (Caps.Sixel_Color_Registers));
      end if;
   end Print_Color_Registers;


   ---------------------------------------------------------------------------
   --  Print the Kitty_Graphics_Version optional sub-field
   ---------------------------------------------------------------------------

   procedure Print_Kitty_Version (Caps : Graphics_Capabilities) is
   begin
      if Caps.Kitty_Graphics_Version = 0 then
         Put_Line ("  Kitty graphics version: unknown");
      else
         Put_Line ("  Kitty graphics version: " & Natural'Image (Caps.Kitty_Graphics_Version));
      end if;
   end Print_Kitty_Version;


   ---------------------------------------------------------------------------
   --  Main
   ---------------------------------------------------------------------------

   Caps : constant Graphics_Capabilities := Termicap.Graphics.IO.Detect_Graphics;

begin
   Put_Line ("Termicap - Sixel / Kitty Graphics Protocol Detection Demo");
   Put_Line ("==========================================================");
   New_Line;

   ---------------------------------------------------------------------------
   --  Primary result flags
   ---------------------------------------------------------------------------

   Put_Line ("Graphics support:");
   Put_Line ("  Sixel graphics:        " & Bool_Image (Caps.Sixel_Supported));
   Put_Line ("  Kitty graphics:        " & Bool_Image (Caps.Kitty_Graphics_Supported));

   New_Line;

   ---------------------------------------------------------------------------
   --  Detection provenance
   ---------------------------------------------------------------------------

   Put_Line ("Detection provenance:");
   Print_Sixel_Provenance (Caps);
   Print_Kitty_Provenance (Caps);

   New_Line;

   ---------------------------------------------------------------------------
   --  Probe metadata
   ---------------------------------------------------------------------------

   if Caps.Probed then
      Put_Line ("Probed:                Yes (at least one active probe was executed)");
   else
      Put_Line ("Probed:                No");
      Put_Line ("  (result determined by passive env-var heuristics only, or");
      Put_Line ("   stdin is not a TTY / foreground guard failed / Win32 Console gate)");
   end if;

   New_Line;

   ---------------------------------------------------------------------------
   --  Optional sub-fields (FUNC-SXL-002, FUNC-SXL-003)
   ---------------------------------------------------------------------------

   Put_Line ("Optional sub-fields:");
   Print_Color_Registers (Caps);
   Print_Kitty_Version (Caps);

   New_Line;

   ---------------------------------------------------------------------------
   --  Named terminal identifier constants (FUNC-SXL-004)
   --
   --  These constants drive the passive detection heuristics.  Listing them
   --  here makes the demo self-documenting: readers can see exactly which
   --  terminal names the library recognises without looking at the source.
   ---------------------------------------------------------------------------

   Put_Line ("Known graphics-capable terminal identifiers (FUNC-SXL-004):");
   Put_Line ("  TERM values with known Sixel support:");
   Put_Line ("    """ & TERM_XTERM_KITTY & """ (xterm-kitty — Sixel + Kitty protocol)");
   Put_Line ("    """ & TERM_FOOT        & """ (foot — Sixel via DA1 Ps=4)");
   Put_Line ("    """ & TERM_FOOT_EXTRA  & """ (foot-extra — same as foot)");
   Put_Line ("    """ & TERM_XTERM       & """* (xterm prefix — Sixel when --enable-sixel compiled in)");
   Put_Line ("    """ & TERM_MLTERM      & """ (mlterm — native Sixel support)");
   Put_Line ("    """ & TERM_YAFT        & """ (yaft — framebuffer Sixel support)");
   New_Line;
   Put_Line ("  TERM_PROGRAM values with known Sixel or Kitty support:");
   Put_Line ("    """ & TERM_PROGRAM_WEZTERM & """ (WezTerm — Sixel + Kitty protocol)");
   Put_Line ("    """ & TERM_PROGRAM_ITERM2  & """ (iTerm2 — Sixel via iTerm2 image protocol)");
   New_Line;
   Put_Line ("  Kitty passive detection env-var:");
   Put_Line ("    """ & ENV_KITTY_WINDOW_ID & """ (set by kitty for every managed window)");
   New_Line;
   Put_Line ("  XTVERSION name tokens (case-insensitive substring match):");
   Put_Line ("    """ & XTVERSION_NAME_KITTY   & """ (kitty terminal XTVERSION token)");
   Put_Line ("    """ & XTVERSION_NAME_WEZTERM & """ (WezTerm XTVERSION token)");

   New_Line;

   ---------------------------------------------------------------------------
   --  Summary and exit status
   ---------------------------------------------------------------------------

   Put_Line ("Summary:");
   if Caps.Sixel_Supported or else Caps.Kitty_Graphics_Supported then
      if Caps.Sixel_Supported and then Caps.Kitty_Graphics_Supported then
         Put_Line ("  Both Sixel and Kitty graphics protocols are supported.");
      elsif Caps.Sixel_Supported then
         Put_Line ("  Sixel graphics is supported.");
      else
         Put_Line ("  Kitty graphics protocol is supported.");
      end if;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Put_Line ("  No graphics protocol detected.");
      Put_Line ("  (This is expected when running in a non-TTY or CI environment.)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

   New_Line;
   Put_Line ("Done.");

end Graphics_Demo;
