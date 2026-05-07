-------------------------------------------------------------------------------
--  Full_Capabilities_Demo - Full Terminal Capability Snapshot Usage Examples
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Capabilities.Get_Full / Detect_Full API for
--  obtaining a terminal capability snapshot that includes all Tier 4 probes.
--
--  @description
--  Covers four realistic scenarios:
--
--  Scene 1 -- Basic usage (Get_Full):
--    The most common pattern for TUI applications.  Call Get_Full with no
--    arguments to obtain a cached Full_Terminal_Capabilities record.  All base
--    fields (TTY, Color, Size, Unicode, Identity, DA1) plus the five Tier 4
--    fields (XTVERSION, Keyboard, Mouse, Graphics, Clipboard) are printed.
--    Note the higher first-call latency (~6 s worst case) compared to Get.
--
--  Scene 2 -- Per-stream query:
--    Query for Stderr instead of Stdout.  Color detection is stream-specific;
--    all other fields (Keyboard, Mouse, Graphics, Clipboard, XTVERSION) are
--    the same regardless of stream since those probes are stream-independent.
--
--  Scene 3 -- Detect_Full (fresh, uncached):
--    Bypass both caches (the capabilities-level Full_Cache and the sub-
--    detector-level IO caches for Tier 4 probes) to re-detect everything
--    from scratch.  Use after a SIGWINCH resize or when the calling context
--    needs an authoritative fresh snapshot.
--
--  Scene 4 -- TUI application decision logic:
--    Show the canonical guard pattern used by a real TUI application: use
--    the XTVERSION name to confirm the terminal, check Keyboard and Mouse
--    protocol support, gate Sixel rendering on Graphics.Sixel_Supported, and
--    select an appropriate clipboard strategy based on Clipboard.Support.
--
--  Requirements demonstrated:
--    FUNC-KKB-019  Keyboard field lifted from ADR-0021 deferral
--    FUNC-MSE-019  Mouse field lifted from ADR-0026 deferral
--    FUNC-SXL-019  Graphics field lifted from ADR-0028 deferral
--    FUNC-C52-019  Clipboard field lifted from ADR-0031 deferral

with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Termicap.Capabilities;
with Termicap.Clipboard;
with Termicap.Color;
with Termicap.Graphics;
with Termicap.Hyperlinks;
with Termicap.Keyboard;
with Termicap.Mouse;
with Termicap.Terminal_Id;
with Termicap.TTY;
with Termicap.Unicode;
with Termicap.XTVERSION;

procedure Full_Capabilities_Demo is

   use Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use type Termicap.Keyboard.Keyboard_Protocol;

   ---------------------------------------------------------------------------
   --  Helper: print every field of a Full_Terminal_Capabilities record.
   ---------------------------------------------------------------------------

   procedure Print_Full_Caps
     (Label : String;
      Caps  : Termicap.Capabilities.Full_Terminal_Capabilities)
   is
   begin
      Put_Line ("  [" & Label & "]");

      --  ---- Base fields (same as Terminal_Capabilities) ----

      Put_Line ("  TTY_Stdin              : "
                & Boolean'Image (Caps.TTY_Stdin));
      Put_Line ("  TTY_Stdout             : "
                & Boolean'Image (Caps.TTY_Stdout));
      Put_Line ("  TTY_Stderr             : "
                & Boolean'Image (Caps.TTY_Stderr));
      Put_Line ("  Color                  : "
                & Termicap.Color.Color_Level'Image (Caps.Color));
      Put_Line ("  Size (Cols x Rows)     : "
                & Positive'Image (Caps.Size.Columns)
                & " x"
                & Positive'Image (Caps.Size.Rows));
      Put_Line ("  Unicode                : "
                & Termicap.Unicode.Unicode_Level'Image (Caps.Unicode));
      Put_Line ("  Identity.Kind          : "
                & Termicap.Terminal_Id.Terminal_Kind'Image
                    (Caps.Identity.Kind));
      Put_Line ("  Identity.Is_Multiplexer: "
                & Boolean'Image (Caps.Identity.Is_Multiplexer));
      Put_Line ("  Identity.Program_Name  : """
                & To_String (Caps.Identity.Program_Name) & """");
      Put_Line ("  Downsampling_Available : "
                & Boolean'Image (Caps.Downsampling_Available));

      --  ---- Tier 4: XTVERSION ----

      case Caps.XTVERSION.Status is
         when Termicap.XTVERSION.Success =>
            Put_Line
              ("  XTVERSION.Terminal     : """
               & To_String (Caps.XTVERSION.Terminal_Name)
               & " "
               & To_String (Caps.XTVERSION.Terminal_Version) & """");
         when Termicap.XTVERSION.Timeout =>
            Put_Line ("  XTVERSION              : (no response — timed out)");
         when Termicap.XTVERSION.Parse_Error =>
            Put_Line ("  XTVERSION              : (response received but unparseable)");
      end case;

      --  ---- Tier 4: Keyboard ----

      Put_Line ("  Keyboard.Protocol      : "
                & Termicap.Keyboard.Keyboard_Protocol'Image
                    (Caps.Keyboard.Protocol));
      Put_Line ("  Keyboard.Probed        : "
                & Boolean'Image (Caps.Keyboard.Probed));
      if Caps.Keyboard.Protocol = Termicap.Keyboard.Kitty then
         Put_Line
           ("  Keyboard.Flags.Disambiguate_Escape_Codes : "
            & Boolean'Image
                (Caps.Keyboard.Flags.Disambiguate_Escape_Codes));
         Put_Line
           ("  Keyboard.Flags.Report_Event_Types        : "
            & Boolean'Image (Caps.Keyboard.Flags.Report_Event_Types));
         Put_Line
           ("  Keyboard.Flags.Report_Alternate_Keys     : "
            & Boolean'Image (Caps.Keyboard.Flags.Report_Alternate_Keys));
         Put_Line
           ("  Keyboard.Flags.Report_All_Keys_As_Escape : "
            & Boolean'Image
                (Caps.Keyboard.Flags.Report_All_Keys_As_Escape));
         Put_Line
           ("  Keyboard.Flags.Report_Associated_Text    : "
            & Boolean'Image
                (Caps.Keyboard.Flags.Report_Associated_Text));
      end if;

      --  ---- Tier 4: Mouse ----

      Put_Line ("  Mouse.Best_Encoding    : "
                & Termicap.Mouse.Mouse_Encoding'Image
                    (Caps.Mouse.Best_Encoding));
      Put_Line ("  Mouse.Supports_SGR     : "
                & Boolean'Image (Caps.Mouse.Supports_SGR));
      Put_Line ("  Mouse.Supports_SGR_Pixels : "
                & Boolean'Image (Caps.Mouse.Supports_SGR_Pixels));
      Put_Line ("  Mouse.Probed           : "
                & Boolean'Image (Caps.Mouse.Probed));

      --  ---- Tier 4: Graphics ----

      Put_Line ("  Graphics.Sixel_Supported        : "
                & Boolean'Image (Caps.Graphics.Sixel_Supported));
      Put_Line ("  Graphics.Kitty_Graphics_Supported: "
                & Boolean'Image (Caps.Graphics.Kitty_Graphics_Supported));
      Put_Line ("  Graphics.Sixel_Via_DA1          : "
                & Boolean'Image (Caps.Graphics.Sixel_Via_DA1));
      Put_Line ("  Graphics.Kitty_Via_Active_Probe : "
                & Boolean'Image (Caps.Graphics.Kitty_Via_Active_Probe));
      Put_Line ("  Graphics.Sixel_Color_Registers  : "
                & Natural'Image (Caps.Graphics.Sixel_Color_Registers));

      --  ---- Tier 4: Clipboard ----

      Put_Line ("  Clipboard.Support      : "
                & Termicap.Clipboard.Clipboard_Support'Image
                    (Caps.Clipboard.Support));
      Put_Line ("  Clipboard.Via_DA1      : "
                & Boolean'Image (Caps.Clipboard.Via_DA1));
      Put_Line ("  Clipboard.Via_Active_Probe : "
                & Boolean'Image (Caps.Clipboard.Via_Active_Probe));
      Put_Line ("  Clipboard.Via_Env_Heuristic: "
                & Boolean'Image (Caps.Clipboard.Via_Env_Heuristic));

      --  ---- Tier 4: Hyperlinks (XTVERSION-refined; FUNC-HYP-015) ----

      Put_Line ("  Hyperlinks.Support     : "
                & Termicap.Hyperlinks.Hyperlinks_Support'Image
                    (Caps.Hyperlinks.Support));
      Put_Line ("  Hyperlinks.Provenance  : "
                & Termicap.Hyperlinks.Hyperlinks_Provenance'Image
                    (Caps.Hyperlinks.Provenance));
      Put_Line ("  Hyperlinks.Version_Known: "
                & Boolean'Image (Caps.Hyperlinks.Terminal_Version_Known));
   end Print_Full_Caps;

begin

   Put_Line ("=== Termicap Full Capabilities API Demo ===");
   Put_Line ("(Note: first call runs all Tier 4 probes; may take up to ~6 s");
   Put_Line (" on a non-responsive remote terminal.)");
   New_Line;

   ---------------------------------------------------------------------------
   --  Scene 1 -- Basic usage (Get_Full)
   --
   --  Get_Full is the single-call entry point for TUI applications that need
   --  the complete capability picture.  It caches the result per stream just
   --  like Get, so repeated calls are free.  The Tier 4 probe sub-detectors
   --  (Keyboard.IO, Mouse.IO, Graphics.IO, Clipboard.IO) also cache their
   --  own results internally, so if you mix Get_Full calls with standalone
   --  Detect_Keyboard_Protocol / Detect_Mouse_Protocols calls, the second
   --  call in either direction benefits from the already-populated cache.
   ---------------------------------------------------------------------------

   Put_Line ("--- Scene 1: Basic usage (Get_Full) ---");

   declare
      Caps : constant Termicap.Capabilities.Full_Terminal_Capabilities :=
        Termicap.Capabilities.Get_Full;
   begin
      Print_Full_Caps ("stdout, cached", Caps);
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Scene 2 -- Per-stream query
   --
   --  Pass Stream => Stderr to obtain a Full_Terminal_Capabilities whose Color
   --  and TTY_Stderr fields reflect the stderr stream.  Keyboard, Mouse,
   --  Graphics, Clipboard, and XTVERSION are stream-independent probes and
   --  return identical values regardless of the Stream argument.
   ---------------------------------------------------------------------------

   Put_Line ("--- Scene 2: Per-stream query (stderr) ---");

   declare
      Stderr_Caps : constant Termicap.Capabilities.Full_Terminal_Capabilities :=
        Termicap.Capabilities.Get_Full (Stream => Termicap.TTY.Stderr);
   begin
      Print_Full_Caps ("stderr, cached", Stderr_Caps);
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Scene 3 -- Detect_Full (fresh, uncached)
   --
   --  Detect_Full bypasses both the capabilities-level Full_Cache and the
   --  sub-detector-level IO caches: it calls Probe_Keyboard_Protocol,
   --  Probe_Mouse_Protocols, Detect_Graphics_Uncached, and
   --  Detect_Clipboard_Uncached rather than their cached counterparts.
   --  Use this after SIGWINCH, after an override change, or in test harnesses
   --  that need an authoritative fresh snapshot.
   ---------------------------------------------------------------------------

   Put_Line ("--- Scene 3: Detect_Full (fresh, uncached) ---");

   declare
      Fresh : constant Termicap.Capabilities.Full_Terminal_Capabilities :=
        Termicap.Capabilities.Detect_Full;
   begin
      Print_Full_Caps ("stdout, fresh", Fresh);
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Scene 4 -- TUI application decision logic
   --
   --  Demonstrate the canonical guard pattern for a TUI application that
   --  needs to select its rendering strategy from the full capability picture.
   ---------------------------------------------------------------------------

   Put_Line ("--- Scene 4: TUI application decision logic ---");

   declare
      Caps : constant Termicap.Capabilities.Full_Terminal_Capabilities :=
        Termicap.Capabilities.Get_Full;
   begin
      --  Gate 1: establish the terminal identity via active probe.
      Put ("  Terminal identification : ");
      case Caps.XTVERSION.Status is
         when Termicap.XTVERSION.Success =>
            Put_Line
              (To_String (Caps.XTVERSION.Terminal_Name)
               & " " & To_String (Caps.XTVERSION.Terminal_Version));
         when others =>
            Put_Line
              (Termicap.Terminal_Id.Terminal_Kind'Image
                 (Caps.Identity.Kind)
               & " (passive identification only)");
      end case;

      --  Gate 2: choose keyboard input handling.
      Put ("  Keyboard strategy      : ");
      case Caps.Keyboard.Protocol is
         when Termicap.Keyboard.Kitty =>
            Put_Line ("Kitty Keyboard Protocol -- full key disambiguation available.");
         when Termicap.Keyboard.XTerm_CSI =>
            Put_Line ("XTerm modifyOtherKeys -- enhanced Ctrl/Alt encoding available.");
         when Termicap.Keyboard.Win32 =>
            Put_Line ("Win32 Console API -- platform keyboard input.");
         when Termicap.Keyboard.Legacy =>
            Put_Line ("Legacy VT encoding -- basic ASCII key handling only.");
         when Termicap.Keyboard.Unknown =>
            Put_Line ("Unknown -- could not probe; fall back to raw byte reading.");
      end case;

      --  Gate 3: choose mouse input encoding.
      Put ("  Mouse strategy         : ");
      case Caps.Mouse.Best_Encoding is
         when Termicap.Mouse.SGR_Pixels =>
            Put_Line ("SGR pixel-precision -- sub-cell mouse coordinates available.");
         when Termicap.Mouse.SGR =>
            Put_Line ("SGR decimal -- unlimited coordinate range.");
         when Termicap.Mouse.URXVT =>
            Put_Line ("URXVT decimal -- unlimited coordinate range.");
         when Termicap.Mouse.X10 =>
            Put_Line ("X10 -- basic button tracking; columns limited to 222.");
         when Termicap.Mouse.None =>
            Put_Line ("No mouse support detected.");
         when Termicap.Mouse.Unknown =>
            Put_Line ("Unknown -- could not probe; mouse input disabled.");
      end case;

      --  Gate 4: enable Sixel image rendering only when confirmed.
      Put ("  Sixel rendering        : ");
      if Caps.Graphics.Sixel_Supported then
         if Caps.Graphics.Sixel_Via_DA1 then
            Put_Line
              ("enabled (confirmed via DA1 probe"
               & (if Caps.Graphics.Sixel_Color_Registers > 0
                  then "; " & Natural'Image (Caps.Graphics.Sixel_Color_Registers)
                    & " color registers)"
                  else ")"));
         else
            Put_Line ("enabled (inferred via terminal heuristics).");
         end if;
      else
         Put_Line ("disabled (terminal does not advertise Sixel support).");
      end if;

      --  Gate 5: select clipboard strategy.
      Put ("  Clipboard strategy     : ");
      case Caps.Clipboard.Support is
         when Termicap.Clipboard.Read_Write =>
            Put_Line ("OSC 52 read + write available -- full clipboard integration.");
         when Termicap.Clipboard.Write_Only =>
            Put_Line ("OSC 52 write-only -- can push to clipboard, not read back.");
         when Termicap.Clipboard.None =>
            Put_Line ("No OSC 52 support -- use OS-level clipboard fallback.");
      end case;

      --  Gate 6: choose OSC 8 hyperlink emission strategy (FUNC-HYP-015).
      --  Use the *refined* Hyperlinks classification: it is at least as
      --  confident as the base passive value and may be promoted to Supported
      --  (or demoted to Unsupported) by the XTVERSION minimum-version table.
      Put ("  Hyperlinks strategy    : ");
      case Caps.Hyperlinks.Support is
         when Termicap.Hyperlinks.Supported =>
            Put_Line
              ("emit OSC 8 (XTVERSION-confirmed: "
               & Termicap.Hyperlinks.Hyperlinks_Provenance'Image
                   (Caps.Hyperlinks.Provenance)
               & ").");
         when Termicap.Hyperlinks.Likely_Supported =>
            Put_Line ("emit OSC 8 (heuristic; safe default for known-good emulators).");
         when Termicap.Hyperlinks.Unsupported =>
            Put_Line ("avoid OSC 8 -- terminal does not render the sequence.");
         when Termicap.Hyperlinks.Unknown =>
            Put_Line ("avoid OSC 8 by default; fall back to plain text.");
      end case;
   end;

   New_Line;
   Put_Line ("Done.");

end Full_Capabilities_Demo;
