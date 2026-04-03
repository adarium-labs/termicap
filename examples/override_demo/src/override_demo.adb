-------------------------------------------------------------------------------
--  Override_Demo - Global Enable/Disable Override Usage Examples
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Override API for process-wide color output
--  override.
--
--  @description
--  Covers three realistic scenarios:
--
--  Scenario A — Standalone CLI flag parsing (no framework):
--    Parse Ada.Command_Line manually for --color=VALUE or --no-color, call
--    Parse_Color_Flag, then call Set_Override.  When no flag is passed the
--    override stays at Auto and normal detection runs.
--
--  Scenario B — Scoped_Override RAII:
--    A subsystem block temporarily forces Force_None (e.g., writing to a log
--    file that must be plain text).  On scope exit — including on exception —
--    the outer override is automatically restored.
--
--  Scenario C — Simple forced level:
--    Set Force_256 unconditionally, observe that Detect_Color_Level returns
--    Extended_256 regardless of the terminal, then restore Auto.
--
--  Requirements demonstrated:
--    FUNC-OVR-001  Override_Mode enumeration
--    FUNC-OVR-002  Set_Override
--    FUNC-OVR-003  Get_Override
--    FUNC-OVR-004  Override interaction with color detection
--    FUNC-OVR-005  Override interaction with TTY detection
--    FUNC-OVR-007  Scoped_Override RAII type
--    FUNC-OVR-011  Reset_Override convenience procedure
--    FUNC-OVR-013  Parse_Color_Flag pure function
--    FUNC-OVR-014  No automatic command-line parsing

with Ada.Command_Line;
with Ada.Text_IO;

with Termicap.Color;               use Termicap.Color;
with Termicap.Environment;         use Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Override;            use Termicap.Override;
with Termicap.TTY;                 use Termicap.TTY;

procedure Override_Demo is

   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   --  Render a Color_Level as a short human-readable string.
   function Level_Name (Level : Color_Level) return String is
   begin
      case Level is
         when None         => return "None (no color)";
         when Basic_16     => return "Basic 16 colors";
         when Extended_256 => return "Extended 256 colors";
         when True_Color   => return "TrueColor (24-bit)";
      end case;
   end Level_Name;

   --  Render an Override_Mode as a short human-readable string.
   function Mode_Name (Mode : Override_Mode) return String is
   begin
      case Mode is
         when Auto            => return "Auto (normal detection)";
         when Force_None      => return "Force_None";
         when Force_Basic     => return "Force_Basic";
         when Force_256       => return "Force_256";
         when Force_True_Color => return "Force_True_Color";
      end case;
   end Mode_Name;

   ---------------------------------------------------------------------------
   --  Live environment snapshot (captured once at startup)
   ---------------------------------------------------------------------------

   Live_Env : Environment;

begin

   --  Capture the live OS environment once.  Everything downstream is pure.
   Termicap.Environment.Capture.Capture_Current (Live_Env);

   Ada.Text_IO.Put_Line ("=== Termicap Override API Demo ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO A — Manual CLI flag parsing (FUNC-OVR-013, FUNC-OVR-014)
   --
   --  The library never reads Ada.Command_Line itself (FUNC-OVR-014).
   --  The application is responsible for parsing arguments and calling
   --  Set_Override with the result of Parse_Color_Flag.
   --
   --  Accepted flags (case-insensitive value):
   --    --color=never | --color=false | --color=off | --color=0
   --    --color=true  | --color=1     | --color=16
   --    --color=2     | --color=256
   --    --color=always | --color=truecolor | --color=16m | --color=3
   --    --color=auto
   --    --no-color   (bare flag, no value — treated as Force_None)
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario A: CLI flag parsing ---");

   declare
      --  Walk Ada.Command_Line looking for a recognised flag.
      --  The library stays passive; only the application touches Command_Line.
      Requested_Mode : Override_Mode := Auto;
      Found_Flag     : Boolean       := False;
   begin
      for I in 1 .. Ada.Command_Line.Argument_Count loop
         declare
            Arg : constant String := Ada.Command_Line.Argument (I);
         begin
            --  Bare --no-color flag maps directly to Force_None.
            if Arg = "--no-color" then
               Requested_Mode := Force_None;
               Found_Flag     := True;

            --  --color=VALUE: strip the prefix and parse the value.
            elsif Arg'Length > 8
               and then Arg (Arg'First .. Arg'First + 7) = "--color="
            then
               declare
                  Value : constant String :=
                     Arg (Arg'First + 8 .. Arg'Last);
               begin
                  --  Parse_Color_Flag is pure: no side effects, no global
                  --  reads (FUNC-OVR-013).  Unrecognised values return Auto.
                  Requested_Mode := Parse_Color_Flag (Value);
                  Found_Flag     := True;
               end;
            end if;
         end;
      end loop;

      if Found_Flag then
         --  Install the user's choice as the process-wide override.
         Set_Override (Requested_Mode);
         Ada.Text_IO.Put_Line
            ("CLI flag found — override set to: " & Mode_Name (Requested_Mode));
      else
         --  No --color flag was passed; override stays at Auto (the default).
         --  Normal detection logic will run when Detect_Color_Level is called.
         Ada.Text_IO.Put_Line
            ("No --color flag given — override is: "
             & Mode_Name (Get_Override));
      end if;
   end;

   --  Show current detection result under whatever override is now active.
   declare
      Stdout_Is_TTY : constant Boolean    := Is_TTY (Stdout);
      Level         : constant Color_Level :=
         Detect_Color_Level (Live_Env, Stdout_Is_TTY);
   begin
      Ada.Text_IO.Put_Line
         ("Detect_Color_Level result: " & Level_Name (Level));
      Ada.Text_IO.Put_Line
         ("Is_TTY (Stdout):           " & Boolean'Image (Stdout_Is_TTY));
   end;

   --  Reset to Auto so subsequent scenarios start from a clean state.
   Reset_Override;
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO B — Scoped_Override RAII (FUNC-OVR-007, FUNC-OVR-008)
   --
   --  The outer context uses Force_True_Color (e.g., a rich terminal UI).
   --  A nested subsystem must write to a plain-text log: it temporarily
   --  installs Force_None.  When the block exits — even via an exception —
   --  Scoped_Override.Finalize restores Force_True_Color automatically.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario B: Scoped_Override RAII ---");

   --  Establish the outer override.
   Set_Override (Force_True_Color);
   Ada.Text_IO.Put_Line
      ("Outer override installed: " & Mode_Name (Get_Override));

   declare
      --  Guard saves Force_True_Color and installs Force_None.
      --  Finalize will restore Force_True_Color when this block exits.
      Guard : Scoped_Override (Mode => Force_None);
   begin
      Ada.Text_IO.Put_Line
         ("Inside scoped block, override is: " & Mode_Name (Get_Override));

      --  Confirm that color detection respects the local Force_None override
      --  (FUNC-OVR-004): result must be None regardless of environment.
      declare
         Level : constant Color_Level :=
            Detect_Color_Level (Live_Env, True);
      begin
         Ada.Text_IO.Put_Line
            ("Detect_Color_Level inside block: " & Level_Name (Level));
         --  Expected: None (no color)
      end;

      --  Confirm TTY detection returns False under Force_None (FUNC-OVR-005).
      Ada.Text_IO.Put_Line
         ("Is_TTY (Stdout) inside block:    "
          & Boolean'Image (Is_TTY (Stdout)));
      --  Expected: False

      --  Guard.Finalize runs here on block exit, restoring Force_True_Color.
   end;

   Ada.Text_IO.Put_Line
      ("After scoped block, override restored to: "
       & Mode_Name (Get_Override));
   --  Expected: Force_True_Color

   Reset_Override;
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO C — Simple forced level (FUNC-OVR-002, FUNC-OVR-003,
   --               FUNC-OVR-004, FUNC-OVR-005)
   --
   --  Unconditionally force 256-color mode.  Detect_Color_Level must return
   --  Extended_256 and Is_TTY must return True, regardless of the actual
   --  terminal or environment.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario C: Simple forced level ---");

   --  Before: override is Auto; detection reads the real environment.
   Ada.Text_IO.Put_Line
      ("Before Set_Override — mode:  " & Mode_Name (Get_Override));
   declare
      Level_Before : constant Color_Level :=
         Detect_Color_Level (Live_Env, Is_TTY (Stdout));
   begin
      Ada.Text_IO.Put_Line
         ("Before Set_Override — color: " & Level_Name (Level_Before));
   end;

   --  Install Force_256.
   Set_Override (Force_256);
   Ada.Text_IO.Put_Line
      ("After  Set_Override — mode:  " & Mode_Name (Get_Override));

   --  Detect_Color_Level must now return Extended_256 regardless of Env or
   --  TTY (FUNC-OVR-004).  Pass False for Is_TTY to prove TTY is irrelevant.
   declare
      Level_Forced : constant Color_Level :=
         Detect_Color_Level (EMPTY_ENVIRONMENT, False);
   begin
      Ada.Text_IO.Put_Line
         ("After  Set_Override — color: " & Level_Name (Level_Forced));
      --  Expected: Extended 256 colors
   end;

   --  Is_TTY must return True for any stream under a Force_* override
   --  (FUNC-OVR-005).
   Ada.Text_IO.Put_Line
      ("Is_TTY (Stdout) under Force_256: "
       & Boolean'Image (Is_TTY (Stdout)));
   --  Expected: True

   --  Restore to Auto so the process ends in a clean state.
   Reset_Override;
   Ada.Text_IO.Put_Line
      ("After Reset_Override — mode: " & Mode_Name (Get_Override));
   --  Expected: Auto (normal detection)

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done.  Try passing --color=always, --color=never,");
   Ada.Text_IO.Put_Line ("--color=256, or --no-color on the command line.");

end Override_Demo;
