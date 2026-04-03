-------------------------------------------------------------------------------
--  Terminal_Id_Demo - Terminal Identification Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Terminal_Id API for passive terminal
--  identification.
--
--  @description
--  Shows how to:
--    1. Capture the live process environment via Capture_Current
--    2. Call Detect_Terminal_Identity with the immutable environment snapshot
--    3. Inspect the returned Terminal_Identity record fields:
--         Kind            -- enumeration classifying the terminal
--         Is_Multiplexer  -- True when running inside tmux or GNU Screen
--         Program_Name    -- raw TERM_PROGRAM value (or "")
--         Program_Version -- raw TERM_PROGRAM_VERSION value (or "")
--         Term_Value      -- raw TERM value (or "")
--    4. Branch on Kind using a case statement with an others fallback
--
--  Run this program from different shell contexts to see how the result
--  changes:
--    ./terminal_id_demo                    -- normal interactive terminal
--    TERM_PROGRAM=iTerm.app ./terminal_id_demo  -- simulate iTerm2
--    TMUX=/tmp/tmux-1000/default,12345,0 ./terminal_id_demo  -- inside tmux
--    TERM=screen ./terminal_id_demo        -- GNU Screen

with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Termicap.Environment;            use Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Terminal_Id;            use Termicap.Terminal_Id;

procedure Terminal_Id_Demo is

   ---------------------------------------------------------------------------
   --  Helper: render an Unbounded_String, substituting a placeholder when
   --  the value is the empty string (variable absent or unset).
   ---------------------------------------------------------------------------

   function Display (S : Ada.Strings.Unbounded.Unbounded_String) return String
   is
      Raw : constant String := Ada.Strings.Unbounded.To_String (S);
   begin
      if Raw = "" then
         return "(not set)";
      else
         return Raw;
      end if;
   end Display;


   ---------------------------------------------------------------------------
   --  Helper: map Terminal_Kind to a human-readable description.
   --  The case statement follows the style guide recommendation: an others
   --  branch makes the code robust against future enumeration extensions.
   ---------------------------------------------------------------------------

   function Kind_Name (K : Terminal_Kind) return String is
   begin
      case K is
         when Unknown          => return "Unknown (no recognised signal found)";
         when Alacritty        => return "Alacritty";
         when Apple_Terminal   => return "Apple Terminal";
         when Dumb             => return "Dumb terminal (no capability declared)";
         when Foot             => return "Foot";
         when Ghostty          => return "Ghostty";
         when ITerm2           => return "iTerm2";
         when JediTerm         => return "JediTerm (JetBrains)";
         when Kitty            => return "Kitty";
         when Konsole          => return "Konsole (KDE)";
         when Linux_Console    => return "Linux kernel console";
         when Mintty           => return "Mintty (Cygwin/MSYS2)";
         when Rxvt             => return "rxvt / urxvt";
         when Screen           => return "GNU Screen (multiplexer)";
         when Tmux             => return "tmux (multiplexer)";
         when VSCode           => return "VS Code integrated terminal";
         when VTE              => return "VTE-based terminal (GNOME Terminal, etc.)";
         when WarpTerminal     => return "Warp Terminal";
         when WezTerm          => return "WezTerm";
         when Windows_Terminal => return "Windows Terminal";
         when Xterm            => return "xterm or xterm-compatible";
         when others           =>
            --  Future Terminal_Kind values added in later releases land here.
            --  Returning an informative string keeps the program functional.
            return "Unrecognised terminal (update Kind_Name for new values)";
      end case;
   end Kind_Name;


   ---------------------------------------------------------------------------
   --  Live environment snapshot — populated once via the OS-interaction
   --  boundary, then passed to pure SPARK detection logic.
   ---------------------------------------------------------------------------

   Live_Env : Environment;
   Identity : Terminal_Identity;

begin

   --  -------------------------------------------------------------------------
   --  Section 1: Capture the live environment and run detection
   --
   --  Capture_Current is the sole OS-interaction point.  Everything downstream
   --  is a pure, SPARK-annotated function operating on the immutable snapshot.
   --  -------------------------------------------------------------------------

   Termicap.Environment.Capture.Capture_Current (Live_Env);
   Identity := Detect_Terminal_Identity (Live_Env);

   Ada.Text_IO.Put_Line ("=== Termicap Terminal Identification Example ===");
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 2: Print each Terminal_Identity field
   --
   --  Kind            -- the primary classification result
   --  Is_Multiplexer  -- derived flag; True for Tmux and Screen
   --  Program_Name    -- raw TERM_PROGRAM environment variable value
   --  Program_Version -- raw TERM_PROGRAM_VERSION environment variable value
   --  Term_Value      -- raw TERM environment variable value
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Detected Terminal Identity ---");

   Ada.Text_IO.Put_Line
      ("Kind            : " & Kind_Name (Identity.Kind));

   Ada.Text_IO.Put_Line
      ("Is_Multiplexer  : " & (if Identity.Is_Multiplexer then "Yes" else "No"));

   Ada.Text_IO.Put_Line
      ("Program_Name    : " & Display (Identity.Program_Name));

   Ada.Text_IO.Put_Line
      ("Program_Version : " & Display (Identity.Program_Version));

   Ada.Text_IO.Put_Line
      ("Term_Value      : " & Display (Identity.Term_Value));

   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 3: Recommended pattern — case statement on Kind
   --
   --  Always include an others branch.  The Terminal_Id spec explicitly states
   --  that callers must use others to remain compatible with future enumeration
   --  extensions (FUNC-TID-001).
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Programmatic Dispatch on Kind ---");

   case Identity.Kind is

      when Tmux | Screen =>
         --  Is_Multiplexer will also be True for these values.
         Ada.Text_IO.Put_Line
            ("Running inside a terminal multiplexer (" &
             Kind_Name (Identity.Kind) & ").");
         Ada.Text_IO.Put_Line
            ("Consider disabling mouse reporting or adjusting escape timing.");

      when VSCode =>
         Ada.Text_IO.Put_Line
            ("Running inside VS Code's integrated terminal.");
         Ada.Text_IO.Put_Line
            ("Hyperlink OSC 8 sequences are supported; sixel graphics are not.");

      when ITerm2 | Kitty | WezTerm | Ghostty =>
         Ada.Text_IO.Put_Line
            ("Running inside a feature-rich GPU-accelerated terminal: " &
             Kind_Name (Identity.Kind) & ".");
         Ada.Text_IO.Put_Line
            ("Inline image protocols, hyperlinks, and TrueColor are available.");

      when Konsole | VTE =>
         Ada.Text_IO.Put_Line
            ("Running inside a GTK/Qt terminal emulator: " &
             Kind_Name (Identity.Kind) & ".");
         Ada.Text_IO.Put_Line
            ("TrueColor and hyperlinks are typically available.");

      when Dumb =>
         Ada.Text_IO.Put_Line
            ("Terminal is declared dumb; suppress all formatting and escapes.");

      when Unknown =>
         Ada.Text_IO.Put_Line
            ("Terminal could not be identified; using safe defaults.");

      when others =>
         --  Handles any Terminal_Kind value not listed above, including values
         --  added in future releases of the library.
         Ada.Text_IO.Put_Line
            ("Terminal identified as: " & Kind_Name (Identity.Kind) & ".");

   end case;

   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 4: Relevant environment variables — show what drove the result
   --
   --  Display each variable that Detect_Terminal_Identity inspects so the
   --  user can understand which signal triggered the classification.
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
      --  Variables inspected in priority order by Detect_Terminal_Identity:
      Show_Var ("TERM_PROGRAM");
      Show_Var ("TERM_PROGRAM_VERSION");
      Show_Var ("TERMINAL_EMULATOR");
      Show_Var ("WT_SESSION");
      Show_Var ("KONSOLE_VERSION");
      Show_Var ("VTE_VERSION");
      Show_Var ("TMUX");
      Show_Var ("TERM");
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line
      ("Done. Set TERM_PROGRAM, TMUX, or TERM to simulate a different terminal.");

end Terminal_Id_Demo;
