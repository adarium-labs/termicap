-------------------------------------------------------------------------------
--  Hyperlink_Demo - OSC 8 Hyperlink Support Detection Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates two-tier OSC 8 hyperlink support detection via
--  Termicap.Hyperlinks and Termicap.Hyperlinks + XTVERSION refinement.
--
--  @description
--  Shows how to:
--    1. Capture a live environment snapshot (Termicap.Environment.Capture).
--    2. Run passive terminal identification (Termicap.Terminal_Id).
--    3. Classify OSC 8 hyperlink support passively via
--       Termicap.Hyperlinks.Classify_Hyperlinks_Support (SPARK Silver, pure).
--    4. Run an active XTVERSION probe (Termicap.XTVERSION.IO.Query_And_Identify,
--       100 ms timeout) to confirm or refute the passive classification.
--    5. Refine the passive result with
--       Termicap.Hyperlinks.Refine_With_XTVERSION.
--    6. Print a one-line user-facing recommendation.
--    7. Optionally emit a live OSC 8 hyperlink sequence so the user can
--       visually confirm rendering (only when Support is Supported or
--       Likely_Supported).
--
--  Expected output on terminals without stub bodies:
--    Support / Provenance / Version_Known fields will read "Unknown / Default / False"
--    until Phase 6 implements the package bodies.  That is intentional: this
--    demo verifies the API surface, not the detection logic.
--
--  Requirements demonstrated:
--    FUNC-HYP-001  Hyperlinks_Support enumeration
--    FUNC-HYP-002  Hyperlinks_Result flat record
--    FUNC-HYP-003  Hyperlinks_Provenance enumeration
--    FUNC-HYP-007  Classify_Hyperlinks_Support pure SPARK function
--    FUNC-HYP-008  No global state in passive function
--    FUNC-HYP-011  Refine_With_XTVERSION signature
--    FUNC-HYP-012  Complete state-transition table

with Ada.Command_Line;
with Ada.Text_IO;

with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Terminal_Id;
with Termicap.Hyperlinks;
with Termicap.XTVERSION;
with Termicap.XTVERSION.IO;

procedure Hyperlink_Demo is

   use Ada.Text_IO;
   use Termicap.Hyperlinks;

   ---------------------------------------------------------------------------
   --  Helper: render a Hyperlinks_Support value as a fixed-width label
   ---------------------------------------------------------------------------

   function Support_Image (S : Hyperlinks_Support) return String is
   begin
      case S is
         when Unsupported      => return "Unsupported";
         when Likely_Supported => return "Likely_Supported";
         when Supported        => return "Supported";
         when Unknown          => return "Unknown";
      end case;
   end Support_Image;


   ---------------------------------------------------------------------------
   --  Helper: render a Hyperlinks_Provenance value as a label
   ---------------------------------------------------------------------------

   function Provenance_Image (P : Hyperlinks_Provenance) return String is
   begin
      case P is
         when Default              => return "Default";
         when Env_Excluded         => return "Env_Excluded";
         when Env_Known_Good       => return "Env_Known_Good";
         when Env_Unknown          => return "Env_Unknown";
         when XTVERSION_Confirmed  => return "XTVERSION_Confirmed";
         when XTVERSION_Rejected   => return "XTVERSION_Rejected";
         when XTVERSION_Unresolved => return "XTVERSION_Unresolved";
      end case;
   end Provenance_Image;


   ---------------------------------------------------------------------------
   --  Helper: print a Hyperlinks_Result record with fixed-width labels
   ---------------------------------------------------------------------------

   procedure Print_Result (Label : String; R : Hyperlinks_Result) is
   begin
      Put_Line ("  [" & Label & "]");
      Put_Line ("  Support           : " & Support_Image (R.Support));
      Put_Line ("  Provenance        : " & Provenance_Image (R.Provenance));
      Put_Line ("  Version_Known     : " & (if R.Terminal_Version_Known then "True" else "False"));
   end Print_Result;


   ---------------------------------------------------------------------------
   --  Helper: one-line recommendation based on a Hyperlinks_Result
   ---------------------------------------------------------------------------

   function Recommendation (R : Hyperlinks_Result) return String is
   begin
      case R.Support is
         when Supported        => return "SAFE TO USE";
         when Likely_Supported => return "ASSUMED SAFE";
         when Unsupported      => return "AVOID";
         when Unknown          => return "UNKNOWN — fall back to plain text";
      end case;
   end Recommendation;


   ---------------------------------------------------------------------------
   --  Declarations
   ---------------------------------------------------------------------------

   Live_Env : Termicap.Environment.Environment;

begin

   --  Capture the live process environment once.
   Termicap.Environment.Capture.Capture_Current (Live_Env);

   Put_Line ("Termicap - OSC 8 Hyperlink Support Detection Demo");
   Put_Line ("==================================================");
   New_Line;

   ---------------------------------------------------------------------------
   --  STEP 1 — Passive terminal identification
   ---------------------------------------------------------------------------

   Put_Line ("Step 1: Passive Terminal Identification");
   Put_Line ("---------------------------------------");

   declare
      Identity : constant Termicap.Terminal_Id.Terminal_Identity :=
        Termicap.Terminal_Id.Detect_Terminal_Identity (Live_Env);
   begin
      Put_Line ("  Terminal kind     : "
                & Termicap.Terminal_Id.Terminal_Kind'Image (Identity.Kind));
      Put_Line ("  Is multiplexer    : "
                & (if Identity.Is_Multiplexer then "True" else "False"));
      New_Line;

      ---------------------------------------------------------------------------
      --  STEP 2 — Passive hyperlink classification (SPARK Silver, pure)
      ---------------------------------------------------------------------------

      Put_Line ("Step 2: Passive Hyperlink Classification (Classify_Hyperlinks_Support)");
      Put_Line ("------------------------------------------------------------------------");

      declare
         Passive : constant Hyperlinks_Result :=
           Classify_Hyperlinks_Support
             (Env      => Live_Env,
              Identity => Identity);
      begin
         Print_Result ("Passive", Passive);
         New_Line;

         ---------------------------------------------------------------------------
         --  STEP 3 — Active XTVERSION probe (100 ms timeout)
         ---------------------------------------------------------------------------

         Put_Line ("Step 3: Active XTVERSION Probe (100 ms timeout)");
         Put_Line ("------------------------------------------------");

         declare
            XTV : constant Termicap.XTVERSION.XTVERSION_Result :=
              Termicap.XTVERSION.IO.Query_And_Identify (Timeout_Ms => 100);
         begin
            case XTV.Status is
               when Termicap.XTVERSION.Success =>
                  Put_Line ("  XTVERSION status  : Success");
               when Termicap.XTVERSION.Timeout =>
                  Put_Line ("  XTVERSION status  : Timeout");
               when Termicap.XTVERSION.Parse_Error =>
                  Put_Line ("  XTVERSION status  : Parse_Error");
            end case;
            New_Line;

            -----------------------------------------------------------------------
            --  STEP 4 — XTVERSION refinement
            -----------------------------------------------------------------------

            Put_Line ("Step 4: XTVERSION Refinement (Refine_With_XTVERSION)");
            Put_Line ("------------------------------------------------------");

            declare
               Refined : constant Hyperlinks_Result :=
                 Refine_With_XTVERSION
                   (Passive => Passive,
                    XTV     => XTV);
            begin
               Print_Result ("Refined", Refined);
               New_Line;

               -----------------------------------------------------------------
               --  STEP 5 — One-line recommendation
               -----------------------------------------------------------------

               Put_Line ("Recommendation:");
               Put_Line ("  OSC 8 hyperlinks: " & Recommendation (Refined));
               New_Line;

               -----------------------------------------------------------------
               --  STEP 6 — Optional live OSC 8 sequence (visual confirmation)
               --
               --  Emit a real hyperlink only when support is confirmed or
               --  likely.  The sequence is:
               --    ESC ] 8 ; ; <url> ESC \   <- open link
               --    <link text>
               --    ESC ] 8 ; ; ESC \         <- close link
               --
               --  Put (not Put_Line) is used for the escape parts to keep the
               --  entire sequence on one line without spurious newlines inside
               --  the OSC envelope.
               -----------------------------------------------------------------

               if Refined.Support = Supported
                  or else Refined.Support = Likely_Supported
               then
                  Put_Line ("Live OSC 8 hyperlink (visual check — click the link below):");
                  Put (ASCII.ESC & "]8;;"
                       & "https://github.com/Heziode/termicap"
                       & ASCII.ESC & "\");
                  Put ("Termicap on GitHub");
                  Put (ASCII.ESC & "]8;;" & ASCII.ESC & "\");
                  New_Line;
                  New_Line;
               end if;

               -----------------------------------------------------------------
               --  Exit status: 0 when hyperlinks are usable, 1 otherwise.
               -----------------------------------------------------------------

               if Refined.Support = Supported
                  or else Refined.Support = Likely_Supported
               then
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               else
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;

            end;
         end;
      end;
   end;

   Put_Line ("Done.");

end Hyperlink_Demo;
