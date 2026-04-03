-------------------------------------------------------------------------------
--  Downsampling_Demo - Color Downsampling Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Downsampling API for converting colors to lower
--  fidelity levels, with live terminal color swatches when supported.
--
--  @description
--  Shows how to:
--    1. Convert a TrueColor RGB value to a 256-color palette index
--    2. Convert a TrueColor RGB value directly to a 16-color ANSI index
--    3. Use the general Downsample dispatch function keyed on Color_Level
--    4. Inspect the Downsampled_Color discriminated record with a case statement
--    5. Handle the None (strip-to-no-color) case cleanly
--    6. Pass a Color_Index_16 through Downsample_256_To_16 (pass-through)
--
--  Color swatches are rendered next to each color when the terminal supports
--  them.  The detected Color_Level governs which escape sequence is emitted:
--  TrueColor uses ESC[48;2;R;G;Bm, 256-color uses ESC[48;5;Nm, and 16-color
--  uses ESC[48m / ESC[108m for bright variants.  None suppresses all swatches.

with Ada.Text_IO;
with Ada.Integer_Text_IO;

with Termicap.Color;                 use Termicap.Color;
with Termicap.Downsampling;          use Termicap.Downsampling;
with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.TTY;

procedure Downsampling_Demo is

   ---------------------------------------------------------------------------
   --  Terminal capability detection (run once at startup)
   ---------------------------------------------------------------------------

   Env            : Termicap.Environment.Environment;
   Stdout_Is_TTY  : Boolean;
   Terminal_Level : Color_Level;

   ---------------------------------------------------------------------------
   --  Helper: human-readable Color_Level label
   ---------------------------------------------------------------------------

   function Level_Name (Level : Color_Level) return String is
   begin
      case Level is
         when None         => return "None (no color)";
         when Basic_16     => return "Basic_16";
         when Extended_256 => return "Extended_256";
         when True_Color   => return "True_Color";
      end case;
   end Level_Name;

   ---------------------------------------------------------------------------
   --  Helper: print a Color_Index_256 with a fixed-width label
   ---------------------------------------------------------------------------

   procedure Show_Index (Label : String; Index : Color_Index_256) is
   begin
      Ada.Text_IO.Put ("  " & Label & ": ");
      Ada.Integer_Text_IO.Put (Index, Width => 3);
      Ada.Text_IO.New_Line;
   end Show_Index;

   ---------------------------------------------------------------------------
   --  Helper: describe a Downsampled_Color as a one-liner
   ---------------------------------------------------------------------------

   function Describe (D : Downsampled_Color) return String is
   begin
      case D.Level is
         when None =>
            return "no color (None)";
         when Basic_16 =>
            return "ANSI 16-color index" & D.Index_16'Image;
         when Extended_256 =>
            return "256-color index" & D.Index_256'Image;
         when True_Color =>
            return "TrueColor RGB ("
               & D.RGB_Value.Red'Image & ","
               & D.RGB_Value.Green'Image & ","
               & D.RGB_Value.Blue'Image & " )";
      end case;
   end Describe;

   ---------------------------------------------------------------------------
   --  Helper: emit a colored background swatch for an RGB value.
   --
   --  Downsamples the color to Terminal_Level and emits the appropriate ANSI
   --  background escape, two block characters, then a reset.  Does nothing
   --  when Terminal_Level = None (no color support / NO_COLOR).
   --
   --  Background escape codes used:
   --    True_Color   : ESC[48;2;R;G;Bm
   --    Extended_256 : ESC[48;5;Nm
   --    Basic_16     : ESC[4Nm  (indices 0-7 -> 40-47)
   --                   ESC[10Nm (indices 8-15 -> 100-107, bright)
   --    None         : (nothing emitted)
   ---------------------------------------------------------------------------

   procedure Put_Swatch (Color : RGB) is
      ESC   : constant Character := Character'Val (27);
      Reset : constant String    := ESC & "[0m";
   begin
      if Terminal_Level = None then
         return;
      end if;

      declare
         D : constant Downsampled_Color := Downsample (Color, Terminal_Level);
      begin
         case D.Level is
            when None =>
               null;

            when True_Color =>
               Ada.Text_IO.Put
                  (ESC & "[48;2;"
                   & D.RGB_Value.Red'Image (D.RGB_Value.Red'Image'First + 1
                                            .. D.RGB_Value.Red'Image'Last)
                   & ";"
                   & D.RGB_Value.Green'Image (D.RGB_Value.Green'Image'First + 1
                                              .. D.RGB_Value.Green'Image'Last)
                   & ";"
                   & D.RGB_Value.Blue'Image (D.RGB_Value.Blue'Image'First + 1
                                             .. D.RGB_Value.Blue'Image'Last)
                   & "m  " & Reset);

            when Extended_256 =>
               declare
                  Idx_Str : constant String := D.Index_256'Image;
               begin
                  Ada.Text_IO.Put
                     (ESC & "[48;5;"
                      & Idx_Str (Idx_Str'First + 1 .. Idx_Str'Last)
                      & "m  " & Reset);
               end;

            when Basic_16 =>
               --  Indices 0-7: background codes 40-47
               --  Indices 8-15: bright background codes 100-107
               declare
                  Code : constant Natural :=
                     (if D.Index_16 < 8
                      then 40 + Natural (D.Index_16)
                      else 100 + Natural (D.Index_16) - 8);
                  Code_Str : constant String := Code'Image;
               begin
                  Ada.Text_IO.Put
                     (ESC & "["
                      & Code_Str (Code_Str'First + 1 .. Code_Str'Last)
                      & "m  " & Reset);
               end;
         end case;
      end;
   end Put_Swatch;

   ---------------------------------------------------------------------------
   --  Helper: print a swatch + label for a named color
   ---------------------------------------------------------------------------

   procedure Show_Color (Name : String; Color : RGB) is
   begin
      Ada.Text_IO.Put ("  ");
      Put_Swatch (Color);
      Ada.Text_IO.Put_Line
         (" " & Name
          & "  RGB(" & Color.Red'Image & ","
          & Color.Green'Image & ","
          & Color.Blue'Image & " )");
   end Show_Color;

begin

   --  Capture environment and detect terminal color level once.
   Termicap.Environment.Capture.Capture_Current (Env);
   Stdout_Is_TTY  := Termicap.TTY.Is_TTY (Termicap.TTY.Stdout);
   Terminal_Level := Detect_Color_Level (Env, Stdout_Is_TTY);

   Ada.Text_IO.Put_Line ("=== Termicap Color Downsampling Example ===");
   Ada.Text_IO.Put_Line ("  Terminal color level: " & Level_Name (Terminal_Level));
   Ada.Text_IO.New_Line;

   --  ---------------------------------------------------------------------------
   --  Section 1: Basic primitive conversions with live swatches
   --  ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Section 1: Primitive Conversions ---");

   declare
      type Named_Color is record
         Name  : access constant String;
         Value : RGB;
      end record;

      Red_S     : aliased constant String := "Red      ";
      Orange_S  : aliased constant String := "Orange   ";
      Yellow_S  : aliased constant String := "Yellow   ";
      Green_S   : aliased constant String := "Green    ";
      Cyan_S    : aliased constant String := "Cyan     ";
      Blue_S    : aliased constant String := "Blue     ";
      Magenta_S : aliased constant String := "Magenta  ";
      White_S   : aliased constant String := "White    ";
      Gray_S    : aliased constant String := "Gray     ";
      Black_S   : aliased constant String := "Black    ";

      Palette : constant array (1 .. 10) of Named_Color :=
         ((Red_S'Access,     (255,   0,   0)),
          (Orange_S'Access,  (255, 128,   0)),
          (Yellow_S'Access,  (255, 255,   0)),
          (Green_S'Access,   (  0, 200,   0)),
          (Cyan_S'Access,    (  0, 200, 200)),
          (Blue_S'Access,    (  0,   0, 255)),
          (Magenta_S'Access, (200,   0, 200)),
          (White_S'Access,   (255, 255, 255)),
          (Gray_S'Access,    (128, 128, 128)),
          (Black_S'Access,   (  0,   0,   0)));
   begin
      for C of Palette loop
         declare
            Idx_256 : constant Color_Index_256 := Downsample_True_To_256 (C.Value);
            Idx_16  : constant Color_Index_16  := Downsample_True_To_16  (C.Value);
         begin
            Ada.Text_IO.Put ("  ");
            Put_Swatch (C.Value);
            Ada.Text_IO.Put (" " & C.Name.all);
            Ada.Text_IO.Put ("  ->256:");
            Ada.Integer_Text_IO.Put (Idx_256, Width => 3);
            Ada.Text_IO.Put ("  ->16:");
            Ada.Integer_Text_IO.Put (Idx_16, Width => 2);
            Ada.Text_IO.New_Line;
         end;
      end loop;
   end;

   Ada.Text_IO.New_Line;

   --  ---------------------------------------------------------------------------
   --  Section 2: General dispatch on Color_Level (RGB source)
   --  ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Section 2: General Dispatch on Color_Level (RGB source) ---");

   declare
      Crimson : constant RGB := (Red => 220, Green => 20, Blue => 60);
   begin
      Ada.Text_IO.Put ("  Source: ");
      Put_Swatch (Crimson);
      Ada.Text_IO.Put_Line (" Crimson (R=220 G=20 B=60)");
      Ada.Text_IO.New_Line;

      for Target in Color_Level loop
         declare
            Result : constant Downsampled_Color := Downsample (Crimson, Target);
         begin
            Ada.Text_IO.Put ("  Target=" & Level_Name (Target));
            Ada.Text_IO.Put (" -> " & Describe (Result));
            --  Show what the downsampled color actually looks like on this terminal
            if Result.Level /= None then
               Ada.Text_IO.Put ("  ");
               case Result.Level is
                  when None => null;
                  when True_Color =>
                     Put_Swatch (Result.RGB_Value);
                  when Extended_256 =>
                     --  Reconstruct approximate RGB for swatch from palette index
                     --  (just pass the original color downsampled to this level)
                     Put_Swatch (Crimson);
                  when Basic_16 =>
                     Put_Swatch (Crimson);
               end case;
            end if;
            Ada.Text_IO.New_Line;
         end;
      end loop;
   end;

   Ada.Text_IO.New_Line;

   --  ---------------------------------------------------------------------------
   --  Section 3: Case statement on Downsampled_Color
   --  ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Section 3: Case Statement on Downsampled_Color ---");

   declare
      Teal   : constant RGB             := (Red => 0, Green => 128, Blue => 128);
      Result : constant Downsampled_Color := Downsample (Teal, Extended_256);
   begin
      Ada.Text_IO.Put ("  Source: ");
      Put_Swatch (Teal);
      Ada.Text_IO.Put_Line (" Teal (R=0 G=128 B=128)");

      case Result.Level is
         when None =>
            Ada.Text_IO.Put_Line ("  Terminal has no color support; omit escape sequence.");
         when Basic_16 =>
            Ada.Text_IO.Put ("  Emit ANSI 16-color escape for index");
            Ada.Integer_Text_IO.Put (Result.Index_16, Width => 3);
            Ada.Text_IO.New_Line;
         when Extended_256 =>
            Ada.Text_IO.Put ("  Emit 256-color escape: ESC[38;5;");
            Ada.Integer_Text_IO.Put (Result.Index_256, Width => 1);
            Ada.Text_IO.Put_Line ("m");
         when True_Color =>
            Ada.Text_IO.Put_Line
               ("  Emit TrueColor escape: ESC[38;2;"
                & Result.RGB_Value.Red'Image   & ";"
                & Result.RGB_Value.Green'Image & ";"
                & Result.RGB_Value.Blue'Image  & "m");
      end case;
   end;

   Ada.Text_IO.New_Line;

   --  ---------------------------------------------------------------------------
   --  Section 4: Strip-to-None
   --  ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Section 4: Strip-to-None ---");

   declare
      Purple   : constant RGB             := (Red => 128, Green => 0, Blue => 128);
      Stripped : constant Downsampled_Color := Downsample (Purple, None);
   begin
      Ada.Text_IO.Put ("  Source: ");
      Put_Swatch (Purple);
      Ada.Text_IO.Put_Line (" Purple (R=128 G=0 B=128)");
      Ada.Text_IO.Put_Line ("  Target: None  ->  " & Describe (Stripped));
      if Stripped.Level = None then
         Ada.Text_IO.Put_Line
            ("  No escape sequence emitted (correct for NO_COLOR environments).");
      end if;
   end;

   Ada.Text_IO.New_Line;

   --  ---------------------------------------------------------------------------
   --  Section 5: 256-color -> 16-color and pass-through
   --  ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Section 5: 256-to-16 Conversion and Pass-through ---");

   declare
      Bright_Red_16  : constant Color_Index_16  := 9;
      Cube_Color_256 : constant Color_Index_256 := 196;
      Gray_256       : constant Color_Index_256 := 240;

      Passthrough : constant Color_Index_16 := Downsample_256_To_16 (Bright_Red_16);
      From_Cube   : constant Color_Index_16 := Downsample_256_To_16 (Cube_Color_256);
      From_Gray   : constant Color_Index_16 := Downsample_256_To_16 (Gray_256);
   begin
      Show_Index ("256[ 9] bright red (pass-through) -> 16-color", Passthrough);
      Show_Index ("256[196] cube pure red            -> 16-color", From_Cube);
      Show_Index ("256[240] grayscale ramp           -> 16-color", From_Gray);
      Ada.Text_IO.Put_Line
         ("  Pass-through check: 9 ->" & Passthrough'Image
          & (if Passthrough = Bright_Red_16 then "  (correct)" else "  (UNEXPECTED)"));
   end;

   Ada.Text_IO.New_Line;

   --  ---------------------------------------------------------------------------
   --  Section 6: General dispatch (Color_Index_256 source)
   --  ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Section 6: General Dispatch (256-color source) ---");

   declare
      Palette_Color : constant Color_Index_256 := 202;  -- orange-red in cube
   begin
      for Target in Color_Level loop
         declare
            Result : constant Downsampled_Color := Downsample (Palette_Color, Target);
         begin
            Ada.Text_IO.Put_Line
               ("  256[202], Target=" & Level_Name (Target)
                & " -> " & Describe (Result));
         end;
      end loop;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done.");

end Downsampling_Demo;
