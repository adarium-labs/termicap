-------------------------------------------------------------------------------
--  Keyboard_Protocol_Demo - Kitty Keyboard Protocol Detection Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Keyboard.IO API for active keyboard protocol
--  detection using the Kitty Keyboard Protocol and XTerm modifyOtherKeys
--  probes.
--
--  @description
--  Shows how to:
--    1. Guard against non-TTY stdin and show graceful degradation.
--    2. Call Detect_Keyboard_Protocol (the primary cached entry point) and
--       interpret the returned Keyboard_Capability record.
--    3. Display the five Kitty_Flags fields when Protocol = Kitty.
--    4. Call Probe_Keyboard_Protocol (the cache-bypass variant) to show that
--       an uncached fresh probe is also available.
--    5. Use the pure SPARK parser Parse_Kitty_Response directly on a
--       hard-coded byte buffer to demonstrate the provable surface.
--
--  Run this program from different terminal contexts:
--    ./keyboard_protocol_demo             -- Kitty: shows full flags
--    TERM=xterm-256color ./keyboard_protocol_demo  -- likely Legacy or XTerm_CSI
--    ./keyboard_protocol_demo < /dev/null -- non-TTY path (stdin redirected)
--
--  Requirements demonstrated:
--    FUNC-KKB-001  Keyboard_Protocol enumeration
--    FUNC-KKB-002  Kitty_Flags record and NO_KITTY_FLAGS constant
--    FUNC-KKB-003  Keyboard_Capability result record and NO_KEYBOARD_CAPABILITY
--    FUNC-KKB-005  Parse_Kitty_Flags (exercised via Parse_Kitty_Response path)
--    FUNC-KKB-006  Parse_Kitty_Response pure SPARK parser
--    FUNC-KKB-009  Full detection cascade (Win32 > Kitty > XTerm > Legacy)
--    FUNC-KKB-011  Non-TTY guard (Detect_Keyboard_Protocol returns Unknown)
--    FUNC-KKB-013  1000 ms per-probe timeout
--    FUNC-KKB-014  No-exception guarantee
--    FUNC-KKB-017  Cached vs. cache-bypass (Probe_Keyboard_Protocol)

with Ada.Text_IO;

with Termicap.TTY;
with Termicap.Keyboard;          use Termicap.Keyboard;
with Termicap.Keyboard.IO;

procedure Keyboard_Protocol_Demo is

   use Ada.Text_IO;


   ---------------------------------------------------------------------------
   --  Helper: map Keyboard_Protocol to a human-readable label.
   ---------------------------------------------------------------------------

   function Protocol_Label (P : Keyboard_Protocol) return String is
   begin
      case P is
         when Unknown   => return "Unknown   (detection not performed or not possible)";
         when Legacy    => return "Legacy    (probed; no enhanced protocol found)";
         when XTerm_CSI => return "XTerm_CSI (XTerm modifyOtherKeys detected)";
         when Kitty     => return "Kitty     (Kitty Keyboard Protocol detected)";
         when Win32     => return "Win32     (Windows Console keyboard)";
      end case;
   end Protocol_Label;


   ---------------------------------------------------------------------------
   --  Helper: print the five Kitty flag bits with short labels.
   ---------------------------------------------------------------------------

   procedure Print_Kitty_Flags (Flags : Kitty_Flags) is

      function B (V : Boolean) return String is
        (if V then "Yes" else "No ");

   begin
      Put_Line ("  Kitty flags:");
      Put_Line ("    Disambiguate_Escape_Codes : " & B (Flags.Disambiguate_Escape_Codes));
      Put_Line ("    Report_Event_Types        : " & B (Flags.Report_Event_Types));
      Put_Line ("    Report_Alternate_Keys     : " & B (Flags.Report_Alternate_Keys));
      Put_Line ("    Report_All_Keys_As_Escape : " & B (Flags.Report_All_Keys_As_Escape));
      Put_Line ("    Report_Associated_Text    : " & B (Flags.Report_Associated_Text));
   end Print_Kitty_Flags;


   ---------------------------------------------------------------------------
   --  Helper: print all fields of a Keyboard_Capability record.
   ---------------------------------------------------------------------------

   procedure Print_Capability (Cap : Keyboard_Capability) is
   begin
      Put_Line ("  Protocol : " & Protocol_Label (Cap.Protocol));
      Put_Line ("  Probed   : " & (if Cap.Probed then "Yes" else "No"));
      if Cap.Protocol = Kitty then
         Print_Kitty_Flags (Cap.Flags);
      end if;
   end Print_Capability;


begin

   Put_Line ("=== Termicap Kitty Keyboard Protocol Detection Demo ===");
   New_Line;
   Put_Line ("This demo sends two escape-sequence probes to stdin/stdout to");
   Put_Line ("detect whether the terminal speaks the Kitty Keyboard Protocol");
   Put_Line ("(CSI ? u) or XTerm modifyOtherKeys (CSI ? 4 m).");
   Put_Line ("Worst-case runtime: ~2 s (1000 ms per probe, two probes).");
   New_Line;

   ---------------------------------------------------------------------------
   --  Step 1 — Non-TTY guard
   --
   --  Detect_Keyboard_Protocol handles a non-TTY stdin gracefully (it returns
   --  NO_KEYBOARD_CAPABILITY without hanging), but we print an informational
   --  message so the user understands what they are seeing when stdin is
   --  redirected.  We call the function regardless so the output always shows
   --  the full result path.
   ---------------------------------------------------------------------------

   if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdin) then
      Put_Line ("Note: stdin is not a TTY (redirected or piped).");
      Put_Line ("      Detect_Keyboard_Protocol will return NO_KEYBOARD_CAPABILITY.");
      New_Line;
   end if;

   ---------------------------------------------------------------------------
   --  Scenario A — Detect_Keyboard_Protocol (primary cached API)
   --
   --  This is the recommended entry point for application code.  The first
   --  call runs the Win32 > Kitty > XTerm > Legacy cascade; all subsequent
   --  calls in the same process return the cached result (FUNC-KKB-017).
   --  The function never propagates an exception (FUNC-KKB-014).
   ---------------------------------------------------------------------------

   Put_Line ("--- Scenario A: Detect_Keyboard_Protocol (cached) ---");
   New_Line;

   declare
      Cap : constant Keyboard_Capability :=
              Termicap.Keyboard.IO.Detect_Keyboard_Protocol;
   begin
      Print_Capability (Cap);
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Scenario B — Probe_Keyboard_Protocol (cache-bypass)
   --
   --  Runs the full cascade without consulting or updating the cache.
   --  Intended for test harnesses or for callers that need a fresh result
   --  after a terminal change (FUNC-KKB-017 Should clause).  The result may
   --  match Scenario A on the same terminal; this is expected and normal.
   ---------------------------------------------------------------------------

   Put_Line ("--- Scenario B: Probe_Keyboard_Protocol (cache-bypass) ---");
   Put_Line ("(may match Scenario A — both probes hit the same terminal)");
   New_Line;

   declare
      Cap : constant Keyboard_Capability :=
              Termicap.Keyboard.IO.Probe_Keyboard_Protocol;
   begin
      Print_Capability (Cap);
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Scenario C — Parse_Kitty_Response (pure SPARK parser)
   --
   --  Demonstrates the directly-usable SPARK-provable surface.  Client code
   --  can call Parse_Kitty_Response and Parse_Kitty_Flags on any byte buffer
   --  without going through the I/O layer (useful for test stubs, offline
   --  analysis, or logging captured terminal output).
   --
   --  Hard-coded sample: "ESC [ ? 2 8 u" (flags = 28 = bits 2+3+4, i.e.
   --  Report_Alternate_Keys + Report_All_Keys_As_Escape + Report_Associated_Text).
   ---------------------------------------------------------------------------

   Put_Line ("--- Scenario C: Parse_Kitty_Response pure SPARK parser ---");
   Put_Line ("(hard-coded buffer: ESC [ ? 2 8 u  =>  flags integer = 28)");
   New_Line;

   declare
      --  ESC  [     ?     2     8     u
      Sample : constant Byte_Array :=
                 [16#1B#, 16#5B#, 16#3F#, 16#32#, 16#38#, 16#75#];

      Result : constant Parse_Result :=
                 Parse_Kitty_Response
                   (Buffer => Sample,
                    Length => Sample'Length);
   begin
      Put_Line ("  Parse_Kitty_Response result:");
      Put_Line ("    Valid     : " & (if Result.Valid then "True" else "False"));
      Put_Line ("    Flags_Int : " & Natural'Image (Result.Flags_Int));

      if Result.Valid then
         declare
            Flags : constant Kitty_Flags := Parse_Kitty_Flags (Result.Flags_Int);
         begin
            Put_Line ("  Parse_Kitty_Flags result (Flags_Int =" & Natural'Image (Result.Flags_Int) & "):");
            Print_Kitty_Flags (Flags);
         end;
      else
         Put_Line ("  (parse failed — expected Valid = True for this hard-coded sample)");
      end if;
   end;

   New_Line;

   ---------------------------------------------------------------------------
   --  Summary
   ---------------------------------------------------------------------------

   Put_Line ("--- Summary ---");
   New_Line;
   Put_Line ("On a Kitty terminal:");
   Put_Line ("  Protocol = Kitty, Probed = Yes, Flags show the active bits.");
   New_Line;
   Put_Line ("On a plain xterm:");
   Put_Line ("  Protocol = XTerm_CSI (if modifyOtherKeys active) or Legacy,");
   Put_Line ("  Probed = Yes, Flags all False.");
   New_Line;
   Put_Line ("On a non-TTY (stdin redirected):");
   Put_Line ("  Protocol = Unknown, Probed = No  (NO_KEYBOARD_CAPABILITY).");
   New_Line;
   Put_Line ("Done.");

end Keyboard_Protocol_Demo;
