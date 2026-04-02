-------------------------------------------------------------------------------
--  Unicode_Demo - Unicode Support Level Detection Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Unicode API for terminal Unicode support detection.
--
--  @description
--  Shows how to:
--    1. Capture the live process environment via Capture_Current
--    2. Check TTY status for stdout with Is_TTY
--    3. Detect the color level so the tool can decide whether to emit ANSI
--       escapes alongside Unicode symbols
--    4. Call Detect_Unicode_Level with the captured environment snapshot
--    5. Select the correct symbol set:
--         Basic / Extended  ->  Unicode glyphs  (checkmark, cross, arrow, bullet)
--         None              ->  ASCII fallbacks ([OK], [FAIL], ->, *)
--    6. Print a brief capability summary line
--
--  Run this program from different shell contexts:
--    ./unicode_demo                       -- normal interactive terminal
--    LANG=C ./unicode_demo                -- ASCII locale; Unicode suppressed
--    LC_ALL=en_US.UTF-8 ./unicode_demo    -- explicit UTF-8 locale
--    TERM=linux ./unicode_demo            -- Linux kernel console; no Unicode

with Ada.Text_IO;

with Termicap.Color;                  use Termicap.Color;
with Termicap.Environment;            use Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.TTY;                    use Termicap.TTY;
with Termicap.Unicode;                use Termicap.Unicode;

procedure Unicode_Demo is

   ---------------------------------------------------------------------------
   --  Symbol set: the two strings a real CLI tool would pick per detection
   ---------------------------------------------------------------------------

   --  Unicode glyphs (Basic / Extended level)
   SYM_OK     : constant String := "  " & Character'Val (16#E2#)
                                         & Character'Val (16#9C#)
                                         & Character'Val (16#93#);   --  UTF-8 U+2713 ✓
   SYM_FAIL   : constant String := "  " & Character'Val (16#E2#)
                                         & Character'Val (16#9C#)
                                         & Character'Val (16#97#);   --  UTF-8 U+2717 ✗
   SYM_ARROW  : constant String := "  " & Character'Val (16#E2#)
                                         & Character'Val (16#86#)
                                         & Character'Val (16#92#);   --  UTF-8 U+2192 →
   SYM_BULLET : constant String := "  " & Character'Val (16#E2#)
                                         & Character'Val (16#80#)
                                         & Character'Val (16#A2#);   --  UTF-8 U+2022 •

   --  ASCII fallbacks (None level)
   ASC_OK     : constant String := "  [OK]  ";
   ASC_FAIL   : constant String := "  [FAIL]";
   ASC_ARROW  : constant String := "  ->    ";
   ASC_BULLET : constant String := "  *     ";

   ---------------------------------------------------------------------------
   --  ANSI escape helpers — only used when color is available
   ---------------------------------------------------------------------------

   ESC   : constant Character := Character'Val (16#1B#);
   RESET : constant String    := ESC & "[0m";

   function Green  return String is (ESC & "[32m");
   function Red    return String is (ESC & "[31m");
   function Yellow return String is (ESC & "[33m");
   function Bold   return String is (ESC & "[1m");

   ---------------------------------------------------------------------------
   --  Helper: render a Unicode_Level value as a human-readable string
   ---------------------------------------------------------------------------

   function Level_Name (Level : Unicode_Level) return String is
   begin
      case Level is
         when None     => return "None (ASCII only)";
         when Basic    => return "Basic (common Unicode glyphs)";
         when Extended => return "Extended (full Unicode / emoji)";
      end case;
   end Level_Name;


   ---------------------------------------------------------------------------
   --  Helper: render a Color_Level value as a short label
   ---------------------------------------------------------------------------

   function Color_Label (Level : Color_Level) return String is
   begin
      case Level is
         when None         => return "None";
         when Basic_16     => return "Basic 16";
         when Extended_256 => return "256 colors";
         when True_Color   => return "TrueColor";
      end case;
   end Color_Label;


   ---------------------------------------------------------------------------
   --  Live environment and detection results
   ---------------------------------------------------------------------------

   Live_Env      : Environment;
   Stdout_Is_TTY : Boolean;
   Uni_Level     : Unicode_Level;
   Clr_Level     : Color_Level;

begin

   --  -------------------------------------------------------------------------
   --  Section 1: Capture the live environment once
   --
   --  Capture_Current is the sole OS-interaction point.  All detection
   --  functions downstream are pure SPARK functions operating on the snapshot.
   --  -------------------------------------------------------------------------

   Termicap.Environment.Capture.Capture_Current (Live_Env);
   Stdout_Is_TTY := Is_TTY (Stdout);

   Uni_Level := Detect_Unicode_Level (Live_Env);
   Clr_Level := Detect_Color_Level (Live_Env, Stdout_Is_TTY);

   --  -------------------------------------------------------------------------
   --  Section 2: Capability summary header
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("=== Termicap Unicode Detection Example ===");
   Ada.Text_IO.New_Line;

   Ada.Text_IO.Put_Line
      ("Stdout TTY : " &
       (if Stdout_Is_TTY then "yes (interactive terminal)"
        else "no  (piped or redirected)"));

   Ada.Text_IO.Put_Line ("Unicode    : " & Level_Name (Uni_Level));
   Ada.Text_IO.Put_Line ("Color      : " & Color_Label (Clr_Level));

   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 3: Demonstrate symbol selection
   --
   --  A real CLI tool would call Detect_Unicode_Level once at startup and pick
   --  its entire symbol table from the result.  Here we show each symbol
   --  alongside its ASCII fallback so the output is self-explanatory.
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Symbol selection ---");

   declare
      Use_Unicode : constant Boolean := Uni_Level /= None;
      Use_Color   : constant Boolean := Clr_Level /= None;

      --  Wrap text in green/red ANSI only when the terminal supports color.
      function Ok_Text   (S : String) return String is
         (if Use_Color then Green & S & RESET else S);
      function Fail_Text (S : String) return String is
         (if Use_Color then Red & S & RESET else S);
      function Info_Text (S : String) return String is
         (if Use_Color then Yellow & S & RESET else S);
      function Bold_Text (S : String) return String is
         (if Use_Color then Bold & S & RESET else S);

      Ok_Sym     : constant String := (if Use_Unicode then SYM_OK     else ASC_OK);
      Fail_Sym   : constant String := (if Use_Unicode then SYM_FAIL   else ASC_FAIL);
      Arrow_Sym  : constant String := (if Use_Unicode then SYM_ARROW  else ASC_ARROW);
      Bullet_Sym : constant String := (if Use_Unicode then SYM_BULLET else ASC_BULLET);
   begin
      Ada.Text_IO.Put_Line
         (Ok_Sym & " " & Ok_Text   ("Build succeeded"));
      Ada.Text_IO.Put_Line
         (Fail_Sym & " " & Fail_Text ("Test failed: expected 42, got 0"));
      Ada.Text_IO.Put_Line
         (Arrow_Sym & " " & Info_Text ("Deploying to production"));
      Ada.Text_IO.Put_Line
         (Bullet_Sym & " " & Bold_Text ("Step 1 of 3: compile"));
      Ada.Text_IO.Put_Line
         (Bullet_Sym & " Step 2 of 3: link");
      Ada.Text_IO.Put_Line
         (Bullet_Sym & " Step 3 of 3: package");
   end;

   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 4: Relevant environment variables
   --
   --  Display the variables that drive Unicode detection so the user can see
   --  exactly what influenced the result.
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Relevant environment variables ---");

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
      Show_Var ("LC_ALL");
      Show_Var ("LC_CTYPE");
      Show_Var ("LANG");
      Show_Var ("TERM");
      Show_Var ("TERM_PROGRAM");
      Show_Var ("TERMINAL_EMULATOR");
      Show_Var ("WT_SESSION");
      Show_Var ("GITHUB_ACTIONS");
      Show_Var ("GITEA_ACTIONS");
      Show_Var ("CIRCLECI");
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line
      ("Try: LANG=C ./unicode_demo          (disables Unicode)");
   Ada.Text_IO.Put_Line
      ("     LC_ALL=en_US.UTF-8 ./unicode_demo  (enables Unicode)");
   Ada.Text_IO.Put_Line
      ("     TERM=linux ./unicode_demo       (Linux console; no Unicode)");

end Unicode_Demo;
