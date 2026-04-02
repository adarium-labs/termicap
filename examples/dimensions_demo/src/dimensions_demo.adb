-------------------------------------------------------------------------------
--  Dimensions_Demo - Terminal Dimensions Detection Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Dimensions API for terminal size detection.
--
--  @description
--  Shows how to:
--    1. Capture the live process environment via Capture_Current
--    2. Check TTY status for stdout with Is_TTY
--    3. Call Get_Size with the captured environment and TTY flag
--    4. Print the detected terminal dimensions
--    5. Explore how environment overrides (COLUMNS, LINES) affect detection
--
--  Run this program from different shell contexts to see how the result
--  changes:
--    ./dimensions_demo                        -- normal interactive terminal
--    ./dimensions_demo | cat                  -- stdout piped; ioctl may fail
--    COLUMNS=200 LINES=50 ./dimensions_demo   -- env var override

with Ada.Text_IO;

with Termicap.Dimensions;          use Termicap.Dimensions;
with Termicap.Environment;         use Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.TTY;                 use Termicap.TTY;

procedure Dimensions_Demo is

   ---------------------------------------------------------------------------
   --  Helper: print a Terminal_Size value
   ---------------------------------------------------------------------------

   procedure Print_Size (Label : String; Size : Terminal_Size) is
   begin
      Ada.Text_IO.Put_Line ("  " & Label);
      Ada.Text_IO.Put_Line ("    Columns:      " & Size.Columns'Image);
      Ada.Text_IO.Put_Line ("    Rows:         " & Size.Rows'Image);
      Ada.Text_IO.Put_Line ("    Pixel Width:  " & Size.Pixel_Width'Image);
      Ada.Text_IO.Put_Line ("    Pixel Height: " & Size.Pixel_Height'Image);
   end Print_Size;

   ---------------------------------------------------------------------------
   --  Live environment and TTY state
   ---------------------------------------------------------------------------

   Live_Env      : Environment;
   Stdout_Is_TTY : Boolean;

begin

   --  -------------------------------------------------------------------------
   --  Section 1: Capture the live environment and TTY status
   --  -------------------------------------------------------------------------

   Termicap.Environment.Capture.Capture_Current (Live_Env);
   Stdout_Is_TTY := Is_TTY (Stdout);

   Ada.Text_IO.Put_Line ("=== Termicap Terminal Dimensions Example ===");
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 2: Detect and display the live terminal dimensions
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Live Detection ---");

   declare
      Tty_Label : constant String :=
         (if Stdout_Is_TTY then "Yes (interactive terminal)"
          else "No  (piped or redirected)");
   begin
      Ada.Text_IO.Put_Line ("  Stdout is TTY: " & Tty_Label);
   end;

   declare
      Size : constant Terminal_Size := Get_Size (Live_Env, Stdout_Is_TTY);
   begin
      Print_Size ("Detected dimensions:", Size);
   end;

   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 3: Relevant environment variables
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
      Show_Var ("COLUMNS");
      Show_Var ("LINES");
   end;

   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 4: Programmatic scenarios — explore the fallback chain
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Programmatic Scenarios ---");

   --  Scenario A: No env vars, Is_TTY=False -> 80x24 default
   declare
      Empty_Env : constant Environment := EMPTY_ENVIRONMENT;
      Size      : constant Terminal_Size := Get_Size (Empty_Env, Is_TTY => False);
   begin
      Print_Size ("No env vars, not TTY (expect 80x24):", Size);
   end;

   --  Scenario B: COLUMNS and LINES from env vars
   declare
      Custom_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Custom_Env, "COLUMNS", "200");
      Insert (Custom_Env, "LINES", "60");
      declare
         Size : constant Terminal_Size := Get_Size (Custom_Env, Is_TTY => False);
      begin
         Print_Size ("COLUMNS=200, LINES=60 (expect 200x60):", Size);
      end;
   end;

   --  Scenario C: Only COLUMNS set -> partial detection
   declare
      Partial_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Partial_Env, "COLUMNS", "132");
      declare
         Size : constant Terminal_Size := Get_Size (Partial_Env, Is_TTY => False);
      begin
         Print_Size ("COLUMNS=132 only (expect 132x24):", Size);
      end;
   end;

   --  Scenario D: Invalid env var values -> fallback to defaults
   declare
      Invalid_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Invalid_Env, "COLUMNS", "abc");
      Insert (Invalid_Env, "LINES", "-1");
      declare
         Size : constant Terminal_Size := Get_Size (Invalid_Env, Is_TTY => False);
      begin
         Print_Size ("COLUMNS=abc, LINES=-1 (expect 80x24):", Size);
      end;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done. Try running with different COLUMNS/LINES values to");
   Ada.Text_IO.Put_Line ("see how they affect the detected dimensions.");

end Dimensions_Demo;
