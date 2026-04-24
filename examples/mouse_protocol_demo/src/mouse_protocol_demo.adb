-------------------------------------------------------------------------------
--  Mouse_Protocol_Demo - Usage example for Termicap.Mouse.IO
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates mouse protocol detection via Termicap.Mouse.IO.
--
--  @description
--  Calls Detect_Mouse_Protocols, then prints a human-readable summary of the
--  resulting Mouse_Capabilities record: Best_Encoding, Probed metadata,
--  per-mode Supports_* flags, and platform-specific flags.
--  Exits with status 1 when Best_Encoding = Unknown and no platform flag is
--  set (total detection failure); otherwise exits with status 0.

with Ada.Command_Line;
with Ada.Text_IO;

with Termicap.Mouse;
with Termicap.Mouse.IO;

procedure Mouse_Protocol_Demo is

   use Ada.Text_IO;
   use Termicap.Mouse;

   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   function Bool_Image (Value : Boolean) return String is
     (if Value then "Yes" else "No");

   function Encoding_Image (Enc : Mouse_Encoding) return String is
   begin
      case Enc is
         when Unknown    => return "Unknown";
         when None       => return "None";
         when X10        => return "X10";
         when URXVT      => return "URXVT";
         when SGR        => return "SGR";
         when SGR_Pixels => return "SGR_Pixels";
      end case;
   end Encoding_Image;

   ---------------------------------------------------------------------------
   --  Probe reason when Probed = False
   ---------------------------------------------------------------------------

   procedure Print_Not_Probed_Reason (Caps : Mouse_Capabilities) is
   begin
      if Caps.Win32_Console_Mouse then
         Put_Line ("Not probed — Win32 Console mouse is available.");
      elsif Caps.GPM_Available then
         Put_Line ("Not probed — GPM (Linux console mouse daemon) detected.");
      elsif Caps.Best_Encoding = Unknown then
         Put_Line ("Not probed — stdin is not a TTY, foreground guard failed,");
         Put_Line ("             /dev/tty could not be opened, or probe timed out entirely.");
      else
         Put_Line ("Not probed — result determined without active DECRPM session.");
      end if;
   end Print_Not_Probed_Reason;

   ---------------------------------------------------------------------------
   --  Main
   ---------------------------------------------------------------------------

   Caps : constant Mouse_Capabilities := Termicap.Mouse.IO.Detect_Mouse_Protocols;

begin
   Put_Line ("Termicap - Mouse Protocol Detection Demo");
   Put_Line ("==========================================");
   New_Line;

   Put_Line ("Best encoding:   " & Encoding_Image (Caps.Best_Encoding));

   if Caps.Probed then
      Put_Line ("Probed:          True (active DECRPM session executed)");
   else
      Put      ("Probed:          False — ");
      Print_Not_Probed_Reason (Caps);
   end if;

   New_Line;
   Put_Line ("Supports:");
   Put_Line ("  X10 (mode 1000):           " & Bool_Image (Caps.Supports_X10));
   Put_Line ("  Button Event (mode 1002):  " & Bool_Image (Caps.Supports_Button_Event));
   Put_Line ("  Any Event (mode 1003):     " & Bool_Image (Caps.Supports_Any_Event));
   Put_Line ("  URXVT (mode 1015):         " & Bool_Image (Caps.Supports_URXVT));
   Put_Line ("  SGR (mode 1006):           " & Bool_Image (Caps.Supports_SGR));
   Put_Line ("  SGR Pixels (mode 1016):    " & Bool_Image (Caps.Supports_SGR_Pixels));

   New_Line;
   Put_Line ("Platform flags:");
   Put_Line ("  Win32 Console Mouse:       " & Bool_Image (Caps.Win32_Console_Mouse));
   Put_Line ("  GPM Available:             " & Bool_Image (Caps.GPM_Available));

   --  Exit status: 1 when total failure (Unknown encoding, no platform flags).
   if Caps.Best_Encoding = Unknown
      and then not Caps.Win32_Console_Mouse
      and then not Caps.GPM_Available
   then
      New_Line;
      Put_Line ("(Detection failed completely — no mouse capability determined.)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   end if;

end Mouse_Protocol_Demo;
