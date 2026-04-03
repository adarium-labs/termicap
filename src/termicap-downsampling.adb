-------------------------------------------------------------------------------
--  Termicap.Downsampling - Color Downsampling Conversions (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements pure integer-only color downsampling algorithms.
--
--  @description
--  All arithmetic is over bounded subtypes.  No FFI, no dynamic allocation,
--  no global state, no unbounded loops.  SPARK Gold target throughout.

package body Termicap.Downsampling
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Body-local constants and helpers
   ---------------------------------------------------------------------------

   --  Cube levels: the 6 representative values of the xterm 6x6x6 colour cube.
   --  Index 0 => 0, Index 1 => 95, ..., Index 5 => 255.
   CUBE_LEVELS : constant array (0 .. 5) of Color_Component :=
     [0 => 0, 1 => 95, 2 => 135, 3 => 175, 4 => 215, 5 => 255];

   --  Canonical ANSI 16-colour RGB palette (indices 0 .. 15).
   ANSI_16_PALETTE : constant array (Color_Index_16) of RGB :=
     [0  => (Red => 0, Green => 0, Blue => 0),
      --  Black
      1  => (Red => 170, Green => 0, Blue => 0),
      --  Red
      2  => (Red => 0, Green => 170, Blue => 0),
      --  Green
      3  => (Red => 170, Green => 170, Blue => 0),
      --  Yellow
      4  => (Red => 0, Green => 0, Blue => 170),
      --  Blue
      5  => (Red => 170, Green => 0, Blue => 170),
      --  Magenta
      6  => (Red => 0, Green => 170, Blue => 170),
      --  Cyan
      7  => (Red => 170, Green => 170, Blue => 170),
      --  White
      8  => (Red => 85, Green => 85, Blue => 85),
      --  Bright Black
      9  => (Red => 255, Green => 85, Blue => 85),
      --  Bright Red
      10 => (Red => 85, Green => 255, Blue => 85),
      --  Bright Green
      11 => (Red => 255, Green => 255, Blue => 85),
      --  Bright Yellow
      12 => (Red => 85, Green => 85, Blue => 255),
      --  Bright Blue
      13 => (Red => 255, Green => 85, Blue => 255),
      --  Bright Magenta
      14 => (Red => 85, Green => 255, Blue => 255),
      --  Bright Cyan
      15 => (Red => 255, Green => 255, Blue => 255)];  --  Bright White

   --  Map a single colour channel value to its nearest xterm cube index (0..5).
   function Cube_Index (C : Color_Component) return Natural
   with Global => null, Post => Cube_Index'Result in 0 .. 5;

   function Cube_Index (C : Color_Component) return Natural is
   begin
      if C < 48 then
         return 0;
      elsif C < 115 then
         return 1;
      elsif C < 155 then
         return 2;
      elsif C < 195 then
         return 3;
      elsif C < 235 then
         return 4;
      else
         return 5;
      end if;
   end Cube_Index;

   --  Reconstruct the channel value for cube index I (0..5).
   function Cube_Level (I : Natural) return Color_Component
   with
     Global => null,
     Pre    => I in 0 .. 5,
     Post   => Cube_Level'Result = CUBE_LEVELS (I);

   function Cube_Level (I : Natural) return Color_Component is
   begin
      return CUBE_LEVELS (I);
   end Cube_Level;

   ---------------------------------------------------------------------------
   --  Primitive Conversion Functions
   ---------------------------------------------------------------------------

   function Downsample_True_To_256 (Color : RGB) return Color_Index_256 is

      --  Subtypes for intermediate arithmetic used in the grayscale check.
      subtype Gray_Index_Range is Natural range 0 .. 23;

      R : constant Color_Component := Color.Red;
      G : constant Color_Component := Color.Green;
      B : constant Color_Component := Color.Blue;

      Gray_Idx : Gray_Index_Range;
      Ramp_Val : Color_Component;

      RI, GI, BI : Natural;

   begin
      --  Step 1: Grayscale check
      --  The 24-step ramp has entries Ramp(i) = 8 + 10*i for i in 0..23,
      --  giving {8, 18, 28, ..., 238}.  We compute the candidate index from
      --  the Red channel and then verify all channels are within 4 of the
      --  ramp value.

      if R < 8 then
         Gray_Idx := 0;
      elsif R > 238 then
         Gray_Idx := 23;
      else
         Gray_Idx := (R - 8) / 10;
      end if;

      Ramp_Val := Color_Component (8 + 10 * Gray_Idx);

      if abs (Integer (R) - Integer (Ramp_Val)) <= 4
        and then abs (Integer (G) - Integer (Ramp_Val)) <= 4
        and then abs (Integer (B) - Integer (Ramp_Val)) <= 4
      then
         return 232 + Gray_Idx;
      end if;

      --  Step 2: Cube quantization
      --  Map each channel to the nearest of {0,95,135,175,215,255}.
      --  The resulting palette index is 16 + 36*RI + 6*GI + BI.
      --  Range proof: max = 16 + 36*5 + 6*5 + 5 = 231; min = 16.

      RI := Cube_Index (R);
      GI := Cube_Index (G);
      BI := Cube_Index (B);

      return 16 + 36 * RI + 6 * GI + BI;
   end Downsample_True_To_256;

   function Downsample_True_To_16 (Color : RGB) return Color_Index_16 is

      --  Subtypes constraining intermediate arithmetic so the SPARK prover can
      --  discharge overflow obligations without manual lemmas.
      subtype Channel_Diff is Integer range -255 .. 255;
      subtype Squared_Diff is Natural range 0 .. 65_025;
      --  Max R/B term: 767 * 65_025 = 49_844_175; max G term: 1024 * 65_025 = 66_585_600
      subtype Dist_Term is Natural range 0 .. 66_585_600;
      --  Max total: 49_844_175 + 66_585_600 + 49_844_175 = 166_013_950
      subtype Scaled_Distance is Natural range 0 .. 166_333_950;

      Best_Index : Color_Index_16 := 0;
      Best_Dist  : Scaled_Distance := Scaled_Distance'Last;

      R_Mean                 : Natural;
      DR, DG, DB             : Channel_Diff;
      DR2, DG2, DB2          : Squared_Diff;
      Term_R, Term_G, Term_B : Dist_Term;
      Dist                   : Scaled_Distance;

   begin
      for I in Color_Index_16 loop
         R_Mean :=
           (Natural (Color.Red) + Natural (ANSI_16_PALETTE (I).Red)) / 2;

         DR := Integer (Color.Red) - Integer (ANSI_16_PALETTE (I).Red);
         DG := Integer (Color.Green) - Integer (ANSI_16_PALETTE (I).Green);
         DB := Integer (Color.Blue) - Integer (ANSI_16_PALETTE (I).Blue);

         DR2 := DR * DR;
         DG2 := DG * DG;
         DB2 := DB * DB;

         Term_R := (512 + R_Mean) * DR2;
         Term_G := 1024 * DG2;
         Term_B := (767 - R_Mean) * DB2;

         Dist := Term_R + Term_G + Term_B;

         if Dist < Best_Dist then
            Best_Dist := Dist;
            Best_Index := I;
         end if;
      end loop;

      return Best_Index;
   end Downsample_True_To_16;

   function Downsample_256_To_16
     (Index : Color_Index_256) return Color_Index_16
   is
      I          : Natural;
      RI, GI, BI : Natural range 0 .. 5;
      G          : Color_Component;
   begin
      if Index in Color_Index_16 then
         --  Branch 1: 0..15 Ã¢ÂÂ pass-through directly.
         return Index;

      elsif Index in 16 .. 231 then
         --  Branch 2: 6x6x6 colour cube Ã¢ÂÂ reconstruct RGB and delegate.
         I := Index - 16;
         RI := I / 36;
         GI := (I / 6) mod 6;
         BI := I mod 6;
         return
           Downsample_True_To_16
             ((Red   => Cube_Level (RI),
               Green => Cube_Level (GI),
               Blue  => Cube_Level (BI)));

      else
         --  Branch 3: 232..255 grayscale ramp Ã¢ÂÂ reconstruct gray and delegate.
         G := Color_Component (8 + 10 * (Index - 232));
         return Downsample_True_To_16 ((Red => G, Green => G, Blue => G));
      end if;
   end Downsample_256_To_16;

   ---------------------------------------------------------------------------
   --  General Dispatch Functions
   ---------------------------------------------------------------------------

   function Downsample
     (Color : RGB; Target : Termicap.Color.Color_Level)
      return Downsampled_Color is
   begin
      case Target is
         when Termicap.Color.True_Color   =>
            return (Level => Termicap.Color.True_Color, RGB_Value => Color);

         when Termicap.Color.Extended_256 =>
            return
              (Level     => Termicap.Color.Extended_256,
               Index_256 => Downsample_True_To_256 (Color));

         when Termicap.Color.Basic_16     =>
            return
              (Level    => Termicap.Color.Basic_16,
               Index_16 => Downsample_True_To_16 (Color));

         when Termicap.Color.None         =>
            return (Level => Termicap.Color.None);
      end case;
   end Downsample;

   function Downsample
     (Index : Color_Index_256; Target : Termicap.Color.Color_Level)
      return Downsampled_Color is
   begin
      case Target is
         when Termicap.Color.True_Color | Termicap.Color.Extended_256 =>
            return (Level => Termicap.Color.Extended_256, Index_256 => Index);

         when Termicap.Color.Basic_16                                 =>
            return
              (Level    => Termicap.Color.Basic_16,
               Index_16 => Downsample_256_To_16 (Index));

         when Termicap.Color.None                                     =>
            return (Level => Termicap.Color.None);
      end case;
   end Downsample;

   ---------------------------------------------------------------------------
   --  Classification
   ---------------------------------------------------------------------------

   function Color_Level_Of
     (D : Downsampled_Color) return Termicap.Color.Color_Level is
   begin
      return D.Level;
   end Color_Level_Of;

end Termicap.Downsampling;
