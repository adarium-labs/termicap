-------------------------------------------------------------------------------
--  Color_Demo - Color Level Detection Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Color API for terminal color level detection.
--
--  @description
--  Shows how to:
--    1. Capture the live process environment via Capture_Current
--    2. Check TTY status for stdout with Is_TTY
--    3. Call Detect_Color_Level with the captured environment and TTY flag
--    4. Print the detected color level in a human-readable form
--    5. Explore how environment overrides (NO_COLOR, FORCE_COLOR, COLORTERM,
--       TERM_PROGRAM, CI) steer the 11-step detection cascade
--
--  Run this program from different shell contexts to see how the result
--  changes:
--    ./color_demo                    -- normal interactive terminal
--    ./color_demo | cat              -- stdout piped; TTY gate fires
--    NO_COLOR=1 ./color_demo         -- NO_COLOR suppresses all color
--    FORCE_COLOR=3 ./color_demo      -- FORCE_COLOR mandates TrueColor
--    COLORTERM=truecolor ./color_demo -- COLORTERM hints TrueColor

with Ada.Text_IO;

with Termicap.Color;                  use Termicap.Color;
with Termicap.Environment;            use Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.TTY;                    use Termicap.TTY;

procedure Color_Demo is

   ---------------------------------------------------------------------------
   --  Helper: render a Color_Level value as a human-readable string
   ---------------------------------------------------------------------------

   function Level_Name (Level : Color_Level) return String is
   begin
      case Level is
         when None          => return "None (no color support)";
         when Basic_16      => return "Basic 16 colors";
         when Extended_256  => return "Extended 256 colors";
         when True_Color    => return "TrueColor (24-bit)";
      end case;
   end Level_Name;


   ---------------------------------------------------------------------------
   --  Helper: print a Color_Level detection result with an explanatory label
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  Helper: return an ANSI escape sequence that colors the text with a
   --  distinguishable hue appropriate to the given level.
   --
   --  None         -> no escape (plain text)
   --  Basic_16     -> ESC[1;33m  (bold yellow -- ANSI 16 palette)
   --  Extended_256 -> ESC[38;5;117m (a mid-blue from the 256 palette)
   --  True_Color   -> ESC[38;2;170;221;170m  (#AADDAA -- soft mint green)
   ---------------------------------------------------------------------------

   ESC   : constant Character := Character'Val (16#1B#);
   RESET : constant String := ESC & "[0m";

   function Color_Start (Level : Color_Level) return String is
   begin
      case Level is
         when None         => return "";
         when Basic_16     => return ESC & "[1;33m";
         when Extended_256 => return ESC & "[38;5;117m";
         when True_Color   => return ESC & "[38;2;170;221;170m";
      end case;
   end Color_Start;

   function Color_End (Level : Color_Level) return String is
   begin
      case Level is
         when None   => return "";
         when others => return RESET;
      end case;
   end Color_End;

   procedure Print_Detection
      (Label   : String;
       Env     : Environment;
       Is_Tty  : Boolean)
   is
      LABEL_WIDTH : constant := 40;
      Padded      : String (1 .. LABEL_WIDTH) := (others => ' ');
      Len         : constant Natural :=
         Natural'Min (Label'Length, LABEL_WIDTH - 2);
      Level       : constant Color_Level :=
         Detect_Color_Level (Env, Is_Tty);
      Sample      : constant String := " ████ ";
   begin
      Padded (1 .. Len) := Label (Label'First .. Label'First + Len - 1);
      Padded (Len + 1)  := ':';

      Ada.Text_IO.Put (Padded);
      Ada.Text_IO.Put (" " & Level_Name (Level));
      Ada.Text_IO.Put_Line (Color_Start (Level) & Sample & Color_End (Level));
   end Print_Detection;


   ---------------------------------------------------------------------------
   --  Live environment and TTY state
   ---------------------------------------------------------------------------

   Live_Env      : Environment;
   Stdout_Is_TTY : Boolean;

begin

   --  -------------------------------------------------------------------------
   --  Section 1: Capture the live environment and TTY status
   --
   --  Capture_Current is the sole OS-interaction point; everything downstream
   --  is a pure SPARK function operating on the immutable snapshot.
   --  -------------------------------------------------------------------------

   Termicap.Environment.Capture.Capture_Current (Live_Env);
   Stdout_Is_TTY := Is_TTY (Stdout);

   Ada.Text_IO.Put_Line ("=== Termicap Color Level Detection Example ===");
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 2: Detect and display the live color level
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Live Environment ---");

   declare
      Tty_Label : constant String :=
         (if Stdout_Is_TTY then "Yes (interactive terminal)"
          else "No  (piped or redirected)");
   begin
      Ada.Text_IO.Put_Line ("Stdout is TTY:                 " & Tty_Label);
   end;

   Print_Detection ("Detected color level", Live_Env, Stdout_Is_TTY);
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 3: Key environment variables that influence detection
   --
   --  Display whichever variables are present so the user can see what drove
   --  the decision.
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Relevant Environment Variables ---");

   declare
      procedure Show_Var (Name : String) is
      begin
         if Contains (Live_Env, Name) then
            declare
               V : constant String := Value (Live_Env, Name);
            begin
               if V = "" then
                  Ada.Text_IO.Put_Line ("  " & Name & " = (empty)");
               else
                  Ada.Text_IO.Put_Line ("  " & Name & " = " & V);
               end if;
            end;
         else
            Ada.Text_IO.Put_Line ("  " & Name & " = (not set)");
         end if;
      end Show_Var;
   begin
      Show_Var ("NO_COLOR");
      Show_Var ("FORCE_COLOR");
      Show_Var ("CLICOLOR_FORCE");
      Show_Var ("CLICOLOR");
      Show_Var ("COLORTERM");
      Show_Var ("TERM");
      Show_Var ("TERM_PROGRAM");
      Show_Var ("CI");
   end;

   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 4: Programmatic scenarios — explore the detection cascade
   --
   --  Each scenario builds an Environment from EMPTY_ENVIRONMENT and calls
   --  Detect_Color_Level directly.  This is the recommended pattern for unit
   --  tests: deterministic, no OS calls, fully reproducible.
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Programmatic Scenarios (TTY = True) ---");

   --  Scenario A: NO_COLOR present (even with an empty value) disables all
   --  color regardless of any other variable.  The spec requires presence
   --  checking (Contains), not value checking.
   declare
      No_Color_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (No_Color_Env, "NO_COLOR", "");
      Insert (No_Color_Env, "COLORTERM", "truecolor");   -- would normally give TrueColor
      Print_Detection ("NO_COLOR= (empty), COLORTERM=truecolor", No_Color_Env, True);
   end;

   --  Scenario B: FORCE_COLOR=1 requests at least Basic_16 color even when
   --  stdout is not a TTY.
   declare
      Force_16_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Force_16_Env, "FORCE_COLOR", "1");
      Print_Detection ("FORCE_COLOR=1 (not a TTY)", Force_16_Env, False);
   end;

   --  Scenario C: FORCE_COLOR=2 requests Extended_256 colors.
   declare
      Force_256_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Force_256_Env, "FORCE_COLOR", "2");
      Print_Detection ("FORCE_COLOR=2 (not a TTY)", Force_256_Env, False);
   end;

   --  Scenario D: FORCE_COLOR=3 requests TrueColor.
   declare
      Force_Tc_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Force_Tc_Env, "FORCE_COLOR", "3");
      Print_Detection ("FORCE_COLOR=3 (not a TTY)", Force_Tc_Env, False);
   end;

   --  Scenario E: COLORTERM=truecolor is the standard signal that a terminal
   --  supports 24-bit color.  Requires TTY = True to take effect.
   declare
      Colorterm_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Colorterm_Env, "COLORTERM", "truecolor");
      Print_Detection ("COLORTERM=truecolor (TTY)", Colorterm_Env, True);
   end;

   --  Scenario F: COLORTERM=24bit is an alternative spelling for TrueColor.
   declare
      Colorterm_24_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Colorterm_24_Env, "COLORTERM", "24bit");
      Print_Detection ("COLORTERM=24bit (TTY)", Colorterm_24_Env, True);
   end;

   --  Scenario G: TERM=xterm-256color indicates 256-color support.
   declare
      Term_256_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Term_256_Env, "TERM", "xterm-256color");
      Print_Detection ("TERM=xterm-256color (TTY)", Term_256_Env, True);
   end;

   --  Scenario H: TERM=dumb explicitly opts out of color.  The TTY gate fires
   --  before any color negotiation.
   declare
      Dumb_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Dumb_Env, "TERM", "dumb");
      Print_Detection ("TERM=dumb (TTY)", Dumb_Env, True);
   end;

   --  Scenario I: CI variable present — most CI environments support Basic_16.
   declare
      Ci_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Ci_Env, "CI", "true");
      Print_Detection ("CI=true (TTY)", Ci_Env, True);
   end;

   --  Scenario J: stdout is NOT a TTY and no FORCE_COLOR — color is suppressed
   --  by the TTY gate even though COLORTERM is set.
   declare
      Piped_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Piped_Env, "COLORTERM", "truecolor");
      Print_Detection ("COLORTERM=truecolor (not a TTY)", Piped_Env, False);
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done. Try running with different environment variables to");
   Ada.Text_IO.Put_Line ("see how they affect the detected color level.");

end Color_Demo;
