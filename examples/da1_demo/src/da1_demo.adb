-------------------------------------------------------------------------------
--  Example_DA1 - DA1 Primary Device Attributes Query Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.DA1.IO API for querying the active terminal's
--  Primary Device Attributes (DA1) via the CSI c protocol.
--
--  @description
--  Shows how to:
--    1. Call Detect_DA1 (the primary convenience API) with the default 100 ms
--       timeout to send a CSI c query and obtain a structured DA1_Capabilities
--       record in one step.
--    2. Check the Supported flag to determine whether a DA1 response was
--       received within the timeout.
--    3. Access the VT conformance level using VT_Level_Of when Supported is True.
--    4. Test individual capabilities (Sixel_Graphics, ANSI_Color) using
--       Has_Capability.
--    5. Iterate over all DA1_Capability values to enumerate supported features.
--
--  Run this program from different terminal contexts:
--    ./da1_demo                    -- most terminals respond (100 ms timeout)
--    TERM=dumb ./da1_demo          -- typically triggers a timeout
--    Inside tmux: the query is wrapped for multiplexer passthrough automatically.
--
--  Requirements demonstrated:
--    FUNC-DA1-001  DA1_Capability enumeration (iteration over all values)
--    FUNC-DA1-002  VT_Level enumeration (VT_Level_Of result)
--    FUNC-DA1-003  DA1_Capabilities record (Supported, Level, Flags)
--    FUNC-DA1-005  Has_Capability convenience function
--    FUNC-DA1-006  VT_Level_Of convenience function
--    FUNC-DA1-009  Detect_DA1 top-level convenience function
--    FUNC-DA1-010  Foreground process group guard (transparent via Probe_Session)
--    FUNC-DA1-011  Not-a-TTY guard (transparent via Probe_Session)
--    FUNC-DA1-012  Multiplexer passthrough (transparent via Wrap_For_Passthrough)

with Ada.Text_IO;

with Termicap.DA1;      use Termicap.DA1;
with Termicap.DA1.IO;

procedure Da1_Demo is

   ---------------------------------------------------------------------------
   --  Helper: map a DA1_Capability to a human-readable label.
   ---------------------------------------------------------------------------

   function Capability_Label (Cap : DA1_Capability) return String is
   begin
      case Cap is
         when Printer           => return "Printer port (Ps=2)";
         when ReGIS_Graphics    => return "ReGIS graphics (Ps=3)";
         when Sixel_Graphics    => return "Sixel graphics (Ps=4)";
         when Selective_Erase   => return "Selective erase (Ps=6)";
         when User_Defined_Keys => return "User-defined keys / UDK (Ps=8)";
         when Windowing         => return "Windowing capability (Ps=18)";
         when ANSI_Color        => return "ANSI colour / VT525 (Ps=22)";
         when Rectangular_Editing => return "Rectangular editing (Ps=28)";
         when Clipboard_Access    => return "OSC 52 clipboard access (Ps=52)";
      end case;
   end Capability_Label;

   ---------------------------------------------------------------------------
   --  Helper: map a VT_Level to a human-readable label.
   ---------------------------------------------------------------------------

   function Level_Label (L : VT_Level) return String is
   begin
      case L is
         when Unknown => return "Unknown (no DA1 response or unrecognised Ps)";
         when VT100   => return "VT100 (Ps=1; reserved, rarely sent)";
         when VT200   => return "VT200 (Ps=62)";
         when VT300   => return "VT300 (Ps=63)";
         when VT400   => return "VT400 (Ps=64)";
         when VT500   => return "VT500 (Ps=65)";
      end case;
   end Level_Label;

begin

   Ada.Text_IO.Put_Line ("=== Termicap DA1 Primary Device Attributes Demo ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Call Detect_DA1 with the default 100 ms timeout.
   --
   --  Detect_DA1 is the recommended entry point for most callers.  It:
   --    1. Opens a Probe_Session (which enforces the TTY and foreground-process
   --       guards before any terminal I/O is attempted).
   --    2. Optionally wraps the DA1_QUERY for multiplexer passthrough when
   --       running inside tmux or GNU Screen (FUNC-DA1-012).
   --    3. Sends ESC [ c and accumulates response bytes until a complete DA1
   --       response (ESC [ ? ... c) is detected or the timeout expires.
   --    4. Parses and interprets the response into a DA1_Capabilities record.
   --
   --  When Supported is False, all Flags entries are False and Level is Unknown
   --  by construction of Interpret_DA1 and the DA1_Capabilities default.
   ---------------------------------------------------------------------------

   declare
      Caps : constant DA1_Capabilities :=
        Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => 100);
   begin

      if not Caps.Supported then

         --  The terminal did not respond within the timeout, or the Probe_Session
         --  could not be opened (not a TTY, not foreground process, etc.).
         Ada.Text_IO.Put_Line
           ("No DA1 response received "
            & "(terminal may not support DA1 queries)");
         Ada.Text_IO.New_Line;

      else

         --  A valid DA1 response was received and successfully interpreted.
         --  Print the VT conformance level encoded in the first DA1 parameter.
         Ada.Text_IO.Put_Line
           ("VT conformance level : " & Level_Label (VT_Level_Of (Caps)));
         Ada.Text_IO.New_Line;

         --  Check and print two commonly-used individual capabilities.
         --  Has_Capability guards against Supported = False and is safe to call
         --  unconditionally, but here Caps.Supported is already confirmed True.

         Ada.Text_IO.Put_Line ("--- Key Capabilities ---");

         Ada.Text_IO.Put_Line
           ("Sixel graphics : "
            & (if Has_Capability (Caps, Sixel_Graphics)
               then "Supported"
               else "Not supported"));

         Ada.Text_IO.Put_Line
           ("ANSI colour    : "
            & (if Has_Capability (Caps, ANSI_Color)
               then "Supported"
               else "Not supported"));

         Ada.Text_IO.New_Line;

         --  Iterate over every DA1_Capability value and report its status.
         --  The Capability_Flags array is indexed by DA1_Capability, so a
         --  simple for-loop covers the complete set without any hardcoding.
         Ada.Text_IO.Put_Line ("--- Full Capability Survey ---");

         for Cap in DA1_Capability loop
            Ada.Text_IO.Put_Line
              ((if Has_Capability (Caps, Cap) then "[x] " else "[ ] ")
               & Capability_Label (Cap));
         end loop;

         Ada.Text_IO.New_Line;

      end if;

   end;

   Ada.Text_IO.Put_Line ("Done.");

end Da1_Demo;
