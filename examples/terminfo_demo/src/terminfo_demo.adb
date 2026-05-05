-------------------------------------------------------------------------------
--  Terminfo_Demo - Terminfo Database Parsing Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Terminfo.IO API for parsing the active terminal's
--  compiled terminfo database entry.
--
--  @description
--  Shows how to:
--    1. Capture the current process environment via Capture_Current.
--    2. Call Parse_Terminfo (the primary entry point) with the captured snapshot
--       to locate, read, and parse the terminfo binary for $TERM.
--    3. Inspect the Terminfo_Result discriminant to distinguish Success from
--       failure, and print the appropriate error code when parsing fails.
--    4. Access the Terminfo_Snapshot fields on success:
--         - Colors     -- value of the `colors` numeric capability
--         - Has_Setaf  -- whether `setaf` (set_a_foreground) is present
--         - Has_Setab  -- whether `setab` (set_a_background) is present
--         - Has_RGB_Flag -- whether the extended `RGB` truecolor flag is set
--         - Has_Tc_Flag  -- whether the extended `Tc` truecolor flag is set
--         - Term_Name  -- primary terminal name from the names section
--
--  Run this program from any terminal:
--    ./terminfo_demo                    -- reads $TERM from the environment
--    TERM=xterm-256color ./terminfo_demo
--    TERM=nonexistent ./terminfo_demo   -- demonstrates Error_File_Not_Found
--    unset TERM && ./terminfo_demo      -- demonstrates Error_No_Term
--
--  Requirements demonstrated:
--    FUNC-TIF-001  Terminfo_Snapshot immutable value record
--    FUNC-TIF-002  Terminfo_Result discriminated result type / Terminfo_Error codes
--    FUNC-TIF-003  TERM variable read from Environment snapshot
--    FUNC-TIF-004  Standard search directory order
--    FUNC-TIF-005  Primary and alternate path construction
--    FUNC-TIF-010  colors numeric capability extraction
--    FUNC-TIF-011  setaf / setab string capability extraction
--    FUNC-TIF-014  RGB and Tc truecolor flag extraction
--    FUNC-TIF-015  Parse_Terminfo top-level entry function
--    FUNC-TIF-016  Immutable value-copy snapshot semantics
--    FUNC-TIF-019  No exception propagation guarantee

with Ada.Command_Line;
with Ada.Text_IO;

with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Terminfo;       use Termicap.Terminfo;
with Termicap.Terminfo.IO;

procedure Terminfo_Demo is

   use Ada.Text_IO;

   ---------------------------------------------------------------------------
   --  Helper: map a Terminfo_Error to a human-readable label.
   ---------------------------------------------------------------------------

   function Error_Label (Err : Terminfo_Error) return String is
   begin
      case Err is
         when Error_No_Term =>
            return "Error_No_Term — $TERM is not set or is empty";
         when Error_File_Not_Found =>
            return "Error_File_Not_Found — no terminfo file found for $TERM";
         when Error_IO_Failure =>
            return "Error_IO_Failure — terminfo file found but could not be read";
         when Error_Invalid_Magic =>
            return "Error_Invalid_Magic — file does not start with a recognised magic number";
         when Error_Header_Corrupt =>
            return "Error_Header_Corrupt — header fields are inconsistent or out of range";
         when Error_File_Too_Large =>
            return "Error_File_Too_Large — file exceeds the maximum accepted size";
         when Error_Encoding =>
            return "Error_Encoding — string capability contains unexpected byte values";
      end case;
   end Error_Label;


   ---------------------------------------------------------------------------
   --  Helper: format the Colors field as a human-readable string.
   ---------------------------------------------------------------------------

   function Colors_Image (Colors : Integer) return String is
   begin
      if Colors = ABSENT_NUMERIC then
         return "absent (not listed in database)";
      elsif Colors = CANCELLED_NUMERIC then
         return "cancelled (explicitly removed in database)";
      else
         return Integer'Image (Colors);
      end if;
   end Colors_Image;


   ---------------------------------------------------------------------------
   --  Main
   ---------------------------------------------------------------------------

   Env    : Termicap.Environment.Environment;
   Result : Terminfo_Result;

begin
   Put_Line ("=== Termicap Terminfo Database Parsing Demo ===");
   New_Line;

   ---------------------------------------------------------------------------
   --  Step 1: Capture the current process environment.
   --
   --  Capture_Current reads all live environment variables into an immutable
   --  Environment snapshot.  All downstream detection logic, including
   --  Parse_Terminfo, operates on this snapshot rather than calling getenv(3)
   --  repeatedly, which ensures consistent results throughout the program.
   ---------------------------------------------------------------------------

   Termicap.Environment.Capture.Capture_Current (Env);

   ---------------------------------------------------------------------------
   --  Step 2: Call Parse_Terminfo.
   --
   --  Parse_Terminfo executes the complete pipeline:
   --    1. Reads $TERM from the environment snapshot.
   --    2. Searches candidate directories in standard order:
   --         $TERMINFO, $TERMINFO_DIRS entries, $HOME/.terminfo,
   --         /usr/share/terminfo, /etc/terminfo, /lib/terminfo.
   --    3. For each directory, tries the Primary path (T[0]/T) then the
   --       Alternate path (HH/T) where HH is the two-digit hex of T[0].
   --    4. Reads and binary-parses the first file found.
   --    5. Returns a Terminfo_Result carrying either a Terminfo_Snapshot or
   --       one of the Terminfo_Error codes.
   --
   --  No Ada exception is ever propagated from Parse_Terminfo (FUNC-TIF-019).
   ---------------------------------------------------------------------------

   Result := Termicap.Terminfo.IO.Parse_Terminfo (Env);

   ---------------------------------------------------------------------------
   --  Step 3: Inspect the result discriminant.
   ---------------------------------------------------------------------------

   if not Result.Success then

      --  Parsing failed.  Print the error code and a human-readable label.
      --  Error_File_Not_Found is advisory (FUNC-TIF-020): it simply means no
      --  terminfo database entry was found for $TERM, which is common in
      --  minimal containers and CI environments.
      Put_Line ("Terminfo parse failed:");
      Put_Line ("  Error code : " & Terminfo_Error'Image (Result.Error));
      Put_Line ("  Details    : " & Error_Label (Result.Error));
      New_Line;

      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

   else

      --  A terminfo entry was found and successfully parsed.
      declare
         Snap : constant Terminfo_Snapshot := Result.Snapshot;
      begin

         -----------------------------------------------------------------------
         --  Print the primary terminal name extracted from the names section.
         --  Term_Name.Data holds the raw characters; Term_Name.Length is the
         --  number of significant characters (text before the first '|' separator
         --  in the names section, NUL-terminated in the binary).
         -----------------------------------------------------------------------

         Put_Line ("Terminal name  : "
                   & Snap.Term_Name.Data (1 .. Snap.Term_Name.Length));

         New_Line;

         -----------------------------------------------------------------------
         --  Print the colors count (standard ncurses `colors` capability,
         --  index 13 in the numeric section).
         -----------------------------------------------------------------------

         Put_Line ("Colors count   : " & Colors_Image (Snap.Colors));

         New_Line;

         -----------------------------------------------------------------------
         --  Print setaf / setab availability.
         --
         --  setaf (set_a_foreground, index 359) and setab (set_a_background,
         --  index 360) are the ANSI-compatible foreground/background colour
         --  setting sequences.  Their presence is a reliable indicator that the
         --  terminal supports at least 8 colours.
         -----------------------------------------------------------------------

         Put_Line ("--- ANSI Colour Sequences ---");

         Put_Line ("setaf available: "
                   & (if Snap.Has_Setaf then "Yes" else "No"));

         Put_Line ("setab available: "
                   & (if Snap.Has_Setab then "Yes" else "No"));

         New_Line;

         -----------------------------------------------------------------------
         --  Print the truecolor extension flags.
         --
         --  RGB  -- extended boolean/numeric capability "RGB":
         --          present and set when the terminal supports 24-bit direct
         --          colour via the r/g/b parameter model (uncommon).
         --
         --  Tc   -- extended string capability "Tc" (tmux convention):
         --          present when tmux or a tmux-aware terminal exports this
         --          flag to indicate it will pass through truecolor sequences
         --          to the outer terminal.  Widely used in practice.
         --
         --  Either flag being True is sufficient to conclude that the terminal
         --  (or the outermost multiplexer) supports 24-bit truecolor output.
         -----------------------------------------------------------------------

         Put_Line ("--- Truecolor Extension Flags ---");

         Put_Line ("RGB flag (extended): "
                   & (if Snap.Has_RGB_Flag then "Set" else "Not set"));

         Put_Line ("Tc  flag (extended): "
                   & (if Snap.Has_Tc_Flag  then "Set" else "Not set"));

         New_Line;

         -----------------------------------------------------------------------
         --  Print a brief colour-depth summary derived from the snapshot fields.
         -----------------------------------------------------------------------

         Put_Line ("--- Colour Depth Summary ---");

         if Snap.Has_RGB_Flag or else Snap.Has_Tc_Flag then
            Put_Line ("Inferred depth : TrueColor (24-bit) — RGB or Tc flag detected");
         elsif Snap.Colors >= 256 then
            Put_Line ("Inferred depth : 256 colours (colors >= 256)");
         elsif Snap.Colors >= 8 and then (Snap.Has_Setaf or else Snap.Has_Setab) then
            Put_Line ("Inferred depth : 16 colours (colors >= 8, setaf/setab present)");
         elsif Snap.Colors > 0 then
            Put_Line ("Inferred depth : " & Integer'Image (Snap.Colors) & " colours");
         else
            Put_Line ("Inferred depth : No colour (colors absent, cancelled, or zero)");
         end if;

         New_Line;

         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      end;

   end if;

   Put_Line ("Done.");

end Terminfo_Demo;
