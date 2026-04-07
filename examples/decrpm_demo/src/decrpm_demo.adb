-------------------------------------------------------------------------------
--  DECRPM_Demo - DEC Private Mode Query Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.DECRPM.IO API for querying active terminal mode
--  states via the DECRPM protocol (CSI ? Ps $ p / CSI ? Ps ; Pm $ y).
--
--  @description
--  Shows how to:
--    1. Call Detect_Mode for a single mode (MODE_BRACKETED_PASTE) and handle
--       both the success and failure variants of Mode_Query_Result.
--    2. Call Detect_Modes with all six standard modes in a single batch to
--       reduce terminal round-trips, and display the results as a table.
--    3. Count how many modes are actively supported (Set or Permanently_Set)
--       and print a summary line.
--
--  Run this program from different terminal contexts:
--    ./decrpm_demo                    -- most modern terminals respond
--    TERM=dumb ./decrpm_demo          -- typically triggers Query_Timeout
--    Inside tmux: queries are forwarded or wrapped automatically.
--
--  Requirements demonstrated:
--    FUNC-RPM-001  Mode_Id subtype and MODE_* named constants
--    FUNC-RPM-002  Mode_Status enumeration (Set/Reset/Not_Recognized/etc.)
--    FUNC-RPM-003  Mode_Report record (Mode + Status fields)
--    FUNC-RPM-004  Query_Error enumeration and Mode_Query_Result record
--    FUNC-RPM-009  Detect_Mode top-level convenience function
--    FUNC-RPM-011  Detect_Modes batch convenience function and Batch_Query_Result

with Ada.Text_IO;

with Termicap.DECRPM;      use Termicap.DECRPM;
with Termicap.DECRPM.IO;   use Termicap.DECRPM.IO;

procedure DECRPM_Demo is

   ---------------------------------------------------------------------------
   --  Helper: map a Mode_Status to a short human-readable label.
   ---------------------------------------------------------------------------

   function Status_Label (S : Mode_Status) return String is
   begin
      case S is
         when Not_Recognized    => return "Not recognized";
         when Set               => return "Set (enabled)";
         when Reset             => return "Reset (disabled)";
         when Permanently_Set   => return "Permanently set";
         when Permanently_Reset => return "Permanently reset";
      end case;
   end Status_Label;


   ---------------------------------------------------------------------------
   --  Helper: return True when a mode is considered "supported" — i.e. the
   --  terminal implements it (Set, Reset, Permanently_Set, or Permanently_Reset).
   ---------------------------------------------------------------------------

   function Is_Supported (S : Mode_Status) return Boolean is
   begin
      return S /= Not_Recognized;
   end Is_Supported;


   ---------------------------------------------------------------------------
   --  Helper: map a Query_Error to a human-readable message.
   ---------------------------------------------------------------------------

   function Error_Label (E : Query_Error) return String is
   begin
      case E is
         when Not_A_Terminal => return "Not_A_Terminal (no controlling TTY)";
         when Not_Foreground => return "Not_Foreground (process not in foreground group)";
         when Query_Timeout  => return "Query_Timeout (terminal did not respond)";
         when Parse_Failed   => return "Parse_Failed (response could not be parsed)";
      end case;
   end Error_Label;

begin

   Ada.Text_IO.Put_Line ("=== Termicap DECRPM Private Mode Query Demo ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO A — Single Mode Query with Detect_Mode
   --
   --  Detect_Mode is the recommended entry point for callers that need the
   --  status of exactly one mode.  It sends CSI ? 2004 $ p to the terminal,
   --  waits up to 100 ms, and returns a Mode_Query_Result discriminated record.
   --
   --  The Success discriminant determines which variant is accessible:
   --    Success = True  => Result.Report holds the Mode_Report (mode + status).
   --    Success = False => Result.Error  holds the Query_Error reason.
   --  Accessing the wrong variant raises Constraint_Error by construction.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario A: Single Mode Query (MODE_BRACKETED_PASTE = 2004) ---");

   declare
      Result : constant Mode_Query_Result :=
        Detect_Mode (Mode => MODE_BRACKETED_PASTE, Timeout_Ms => 100);
   begin
      if Result.Success then
         Ada.Text_IO.Put_Line
           ("Mode   : " & Mode_Id'Image (Result.Report.Mode));
         Ada.Text_IO.Put_Line
           ("Status : " & Status_Label (Result.Report.Status));
      else
         Ada.Text_IO.Put_Line
           ("Query failed — " & Error_Label (Result.Error));
      end if;
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO B — Batch Query with Detect_Modes
   --
   --  Detect_Modes opens a single Probe_Session and queries all six standard
   --  modes in sequence, sharing the TTY setup/teardown cost across the batch.
   --  The total timeout (200 ms default) is divided across the six queries.
   --
   --  Individual mode timeouts do not abort the batch: a mode that does not
   --  respond within its per-query slice is reported with Status = Not_Recognized
   --  so that subsequent modes still receive their share of the budget.
   --
   --  The Batch_Query_Result discriminated record mirrors Mode_Query_Result:
   --    Success = True  => Result.Reports(1 .. Result.Count) holds the reports.
   --    Success = False => Result.Error holds the session-open failure reason.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario B: Batch Query (6 standard modes) ---");

   declare
      Modes : Mode_Id_Array := (others => 0);
      Count : constant Positive := 6;
   begin
      --  Populate the first six slots with the standard mode identifiers.
      Modes (1) := MODE_CURSOR_VISIBILITY;
      Modes (2) := MODE_MOUSE_X11;
      Modes (3) := MODE_MOUSE_SGR;
      Modes (4) := MODE_ALT_SCREEN;
      Modes (5) := MODE_BRACKETED_PASTE;
      Modes (6) := MODE_SYNC_OUTPUT;

      declare
         Batch : constant Batch_Query_Result :=
           Detect_Modes (Modes => Modes, Count => Count, Timeout_Ms => 200);
      begin
         if not Batch.Success then
            Ada.Text_IO.Put_Line
              ("Batch query failed — " & Error_Label (Batch.Error));

         else
            --  Print a table header.
            Ada.Text_IO.Put_Line
              ("Mode   Name                    Status");
            Ada.Text_IO.Put_Line
              ("------ ----------------------- -----------------");

            --  Iterate over the first Count reports in input order.
            for I in 1 .. Batch.Count loop
               declare
                  R : constant Mode_Report := Batch.Reports (I);

                  --  Map mode number to a short name for display.
                  Mode_Name : constant String :=
                    (if    R.Mode = MODE_CURSOR_VISIBILITY then "CURSOR_VISIBILITY"
                     elsif R.Mode = MODE_MOUSE_X11         then "MOUSE_X11"
                     elsif R.Mode = MODE_MOUSE_SGR         then "MOUSE_SGR"
                     elsif R.Mode = MODE_ALT_SCREEN        then "ALT_SCREEN"
                     elsif R.Mode = MODE_BRACKETED_PASTE   then "BRACKETED_PASTE"
                     elsif R.Mode = MODE_SYNC_OUTPUT       then "SYNC_OUTPUT"
                     else                                       "Unknown");
               begin
                  Ada.Text_IO.Put_Line
                    (Mode_Id'Image (R.Mode) & "  "
                     & Mode_Name
                     & (if Mode_Name'Length < 23
                        then (1 .. 23 - Mode_Name'Length => ' ')
                        else "")
                     & Status_Label (R.Status));
               end;
            end loop;

            Ada.Text_IO.New_Line;

            --  Compute and print the summary line.
            declare
               Supported_Count : Natural := 0;
            begin
               for I in 1 .. Batch.Count loop
                  if Is_Supported (Batch.Reports (I).Status) then
                     Supported_Count := Supported_Count + 1;
                  end if;
               end loop;

               Ada.Text_IO.Put_Line
                 (Natural'Image (Supported_Count)
                  & " of"
                  & Positive'Image (Batch.Count)
                  & " modes supported");
            end;

         end if;
      end;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done.");

end DECRPM_Demo;
