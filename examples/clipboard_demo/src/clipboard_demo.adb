-------------------------------------------------------------------------------
--  Clipboard_Demo - OSC 52 Clipboard Capability Detection Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates OSC 52 clipboard capability detection via Termicap.Clipboard.IO.
--
--  @description
--  Calls Detect_Clipboard (the primary cached entry point) and prints a
--  human-readable summary of the resulting Clipboard_Capabilities record:
--    - Support level (None / Write_Only / Read_Write)
--    - Detection provenance: Via_DA1, Via_Active_Probe, Via_Env_Heuristic
--    - Whether any active probe was performed (Probed)
--  Also demonstrates Detect_Clipboard_Uncached for callers that need a fresh
--  probe result independent of the process-lifetime cache.
--  Lists the named terminal identifier constants so the reader can see which
--  terminal names drive passive detection (env-var heuristics).
--  Exits with status 0 when Support >= Write_Only (clipboard usable);
--  exits with status 1 otherwise (expected in non-TTY / CI environments).
--
--  Requirements demonstrated:
--    FUNC-C52-001  Clipboard_Support enumeration (None / Write_Only / Read_Write)
--    FUNC-C52-002  Clipboard_Capabilities result record and NO_CLIPBOARD_CAPABILITIES
--    FUNC-C52-005  Named constants for known terminal identifiers
--    FUNC-C52-006  Clipboard inference from DA1 Ps=52
--    FUNC-C52-007  Active OSC 52 read-back probe
--    FUNC-C52-009  Passive env-var heuristics
--    FUNC-C52-010  Combined detection cascade (DA1 -> probe -> env-var)
--    FUNC-C52-012  Pre-condition guards and TTY guards
--    FUNC-C52-013  Non-TTY passive fallback
--    FUNC-C52-015  1000 ms per-session probe timeout
--    FUNC-C52-016  No-exception guarantee
--    FUNC-C52-017  Cached vs. cache-bypass (Detect_Clipboard_Uncached)

with Ada.Command_Line;
with Ada.Text_IO;

with Termicap.Clipboard;
with Termicap.Clipboard.IO;

procedure Clipboard_Demo is

   use Ada.Text_IO;
   use Termicap.Clipboard;

   ---------------------------------------------------------------------------
   --  Helper: map Clipboard_Support to a human-readable label.
   ---------------------------------------------------------------------------

   function Support_Label (S : Clipboard_Support) return String is
   begin
      case S is
         when None       => return "None       (no OSC 52 clipboard access detected)";
         when Write_Only => return "Write_Only (OSC 52 writes accepted; read-back not confirmed)";
         when Read_Write => return "Read_Write (OSC 52 read and write both confirmed)";
      end case;
   end Support_Label;


   ---------------------------------------------------------------------------
   --  Helper: print provenance flags for a Clipboard_Capabilities record.
   ---------------------------------------------------------------------------

   procedure Print_Provenance (Caps : Clipboard_Capabilities) is
   begin
      Put_Line ("Detection provenance:");

      if Caps.Via_DA1 then
         Put_Line ("  Via_DA1:           Yes (DA1 Ps=52 reported clipboard write capability)");
      else
         Put_Line ("  Via_DA1:           No");
      end if;

      if Caps.Via_Active_Probe then
         Put_Line ("  Via_Active_Probe:  Yes (OSC 52 read-back probe returned a valid response)");
      else
         Put_Line ("  Via_Active_Probe:  No");
      end if;

      if Caps.Via_Env_Heuristic then
         Put_Line ("  Via_Env_Heuristic: Yes (env-var heuristic matched; no active probe attempted)");
      else
         Put_Line ("  Via_Env_Heuristic: No");
      end if;
   end Print_Provenance;


   ---------------------------------------------------------------------------
   --  Helper: print Probed metadata with a contextual explanation.
   ---------------------------------------------------------------------------

   procedure Print_Probed (Caps : Clipboard_Capabilities) is
   begin
      if Caps.Probed then
         Put_Line ("Probed:              Yes (at least one active probe session was executed)");
      else
         Put_Line ("Probed:              No");
         if Caps.Via_Env_Heuristic then
            Put_Line ("  (result determined by passive env-var heuristics only)");
         else
            Put_Line ("  (stdin is not a TTY, foreground guard failed, /dev/tty could not");
            Put_Line ("   be opened, or Win32 Console gate suppressed active probing)");
         end if;
      end if;
   end Print_Probed;


   ---------------------------------------------------------------------------
   --  Helper: print all fields of a Clipboard_Capabilities record.
   ---------------------------------------------------------------------------

   procedure Print_Capabilities (Label : String; Caps : Clipboard_Capabilities) is
   begin
      Put_Line (Label);
      Put_Line ("  Support: " & Support_Label (Caps.Support));
      New_Line;
      Print_Provenance (Caps);
      New_Line;
      Print_Probed (Caps);
   end Print_Capabilities;


begin

   Put_Line ("=== Termicap OSC 52 Clipboard Detection Demo ===");
   New_Line;
   Put_Line ("This demo runs the OSC 52 clipboard capability detection cascade.");
   Put_Line ("The cascade has three phases:");
   Put_Line ("  Phase 1 — DA1 passive probe (Ps=52 -> Write_Only)");
   Put_Line ("  Phase 2 — Active OSC 52 read-back probe (Valid_Response -> Read_Write)");
   Put_Line ("  Phase 3 — Env-var heuristics (TERM_PROGRAM, WT_SESSION, TERM)");
   Put_Line ("Worst-case runtime: ~2 s (1000 ms per probe session, two sessions).");
   New_Line;

   ---------------------------------------------------------------------------
   --  Scenario A — Detect_Clipboard (primary cached API)
   --
   --  This is the recommended entry point for application code.  The first
   --  call runs the full cascade; all subsequent calls in the same process
   --  return the cached result (FUNC-C52-017).
   --  The function never propagates an exception (FUNC-C52-016).
   ---------------------------------------------------------------------------

   Put_Line ("--- Scenario A: Detect_Clipboard (cached) ---");
   New_Line;

   declare
      Caps : constant Clipboard_Capabilities :=
               Termicap.Clipboard.IO.Detect_Clipboard;
   begin
      Print_Capabilities ("Cached result:", Caps);
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Scenario B — Detect_Clipboard_Uncached (cache-bypass)
   --
   --  Runs the full cascade without consulting or updating the cache.
   --  Intended for test harnesses or callers that need a fresh probe result
   --  after a terminal change (FUNC-C52-017 Should clause).
   --  The result will typically match Scenario A on the same terminal.
   ---------------------------------------------------------------------------

   Put_Line ("--- Scenario B: Detect_Clipboard_Uncached (cache-bypass) ---");
   Put_Line ("(may match Scenario A — both probes hit the same terminal)");
   New_Line;

   declare
      Caps : constant Clipboard_Capabilities :=
               Termicap.Clipboard.IO.Detect_Clipboard_Uncached;
   begin
      Print_Capabilities ("Uncached result:", Caps);
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Named terminal identifier constants (FUNC-C52-005)
   --
   --  These constants drive the Phase 3 passive env-var heuristics.  Listing
   --  them here makes the demo self-documenting: readers can see exactly which
   --  terminal names the library recognises without looking at the source.
   ---------------------------------------------------------------------------

   Put_Line ("--- Known OSC 52 capable terminal identifiers (FUNC-C52-005) ---");
   New_Line;
   Put_Line ("TERM_PROGRAM values (Read_Write inference):");
   Put_Line ("  """ & TERM_PROGRAM_WEZTERM & """ — WezTerm (full OSC 52 read and write)");
   Put_Line ("  """ & TERM_PROGRAM_ITERM2  & """ — iTerm2 (OSC 52 read and write via clipboard integration)");
   New_Line;
   Put_Line ("TERM_PROGRAM values (Write_Only inference):");
   Put_Line ("  """ & TERM_PROGRAM_VSCODE & """ — VS Code integrated terminal (OSC 52 write only)");
   New_Line;
   Put_Line ("TERM values:");
   Put_Line ("  """ & TERM_XTERM_KITTY & """ — kitty GPU terminal (full OSC 52 read and write)");
   Put_Line ("  """ & TERM_XTERM & """* — xterm family prefix (Write_Only; allowWindowOps disabled by default)");
   New_Line;
   Put_Line ("Environment variable names used in passive detection:");
   Put_Line ("  """ & ENV_WT_SESSION & """ — Windows Terminal (Write_Only when present and non-empty)");
   Put_Line ("  """ & ENV_TMUX & """ — tmux multiplexer passthrough detection (not a heuristic)");
   Put_Line ("  """ & ENV_STY & """ — GNU screen multiplexer passthrough detection (not a heuristic)");
   New_Line;
   Put_Line ("Per-session probe timeout: " & Natural'Image (CLIPBOARD_PROBE_TIMEOUT_MS) & " ms");
   Put_Line ("  (up to two sessions: DA1 + OSC 52 read-back)");

   New_Line;

   ---------------------------------------------------------------------------
   --  Summary and exit status
   ---------------------------------------------------------------------------

   Put_Line ("--- Summary ---");
   New_Line;

   declare
      Caps : constant Clipboard_Capabilities :=
               Termicap.Clipboard.IO.Detect_Clipboard;
   begin
      if Caps.Support >= Write_Only then
         case Caps.Support is
            when None =>
               --  Cannot reach here given the >= Write_Only guard, but
               --  the compiler needs all cases covered.
               null;
            when Write_Only =>
               Put_Line ("OSC 52 write access is available.");
               Put_Line ("  Use: ESC ] 52 ; c ; <base64-data> BEL to set the clipboard.");
            when Read_Write =>
               Put_Line ("OSC 52 read and write access are both available.");
               Put_Line ("  Use: ESC ] 52 ; c ; <base64-data> BEL to set the clipboard.");
               Put_Line ("  Use: ESC ] 52 ; c ; ? BEL to request the current clipboard content.");
         end case;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      else
         Put_Line ("No OSC 52 clipboard access detected.");
         Put_Line ("(This is expected when running in a non-TTY or CI environment,");
         Put_Line (" or when the terminal does not support OSC 52.)");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end;

   New_Line;
   Put_Line ("Done.");

end Clipboard_Demo;
