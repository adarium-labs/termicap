-------------------------------------------------------------------------------
--  Termicap.Downsampling - Color Downsampling Conversions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Converts color values from higher-fidelity levels (TrueColor, 256-color)
--  to the nearest equivalent at a lower fidelity level (256-color, 16-color,
--  or no-color).
--
--  @description
--  Provides pure, SPARK Gold-provable functions for color downsampling.
--  All arithmetic is integer-only over bounded subtypes.  No FFI, no dynamic
--  allocation, no global state, no unbounded loops.
--
--  The package defines the fundamental color value types (Color_Component,
--  RGB, Color_Index_256, Color_Index_16) and a unified return type
--  (Downsampled_Color) as a discriminated record keyed on Color_Level.
--
--  Conversion functions:
--    - Downsample_True_To_256 : RGB -> Color_Index_256  (grayscale-first + cube)
--    - Downsample_True_To_16  : RGB -> Color_Index_16   (redmean nearest-neighbor)
--    - Downsample_256_To_16   : Color_Index_256 -> Color_Index_16
--
--  General dispatch (overloaded on source type):
--    - Downsample (Color : RGB;            Target : Color_Level) return Downsampled_Color
--    - Downsample (Index : Color_Index_256; Target : Color_Level) return Downsampled_Color
--  Note: Color_Index_16 is a subtype of Color_Index_256; pass Color_Index_16 values
--  to the Color_Index_256 overload directly (no separate overload needed or possible).
--
--  Classification:
--    - Color_Level_Of : Downsampled_Color -> Color_Level
--
--  Requirements Coverage:
--    - @relation(FUNC-DSP-001): Color_Component subtype and RGB record
--    - @relation(FUNC-DSP-002): Color_Index_256 subtype
--    - @relation(FUNC-DSP-003): Color_Index_16 subtype
--    - @relation(FUNC-DSP-004): Downsample_True_To_256 function
--    - @relation(FUNC-DSP-005): Downsample_True_To_16 function
--    - @relation(FUNC-DSP-006): Downsample_256_To_16 function
--    - @relation(FUNC-DSP-007): Strip-to-None sentinel via Downsampled_Color
--    - @relation(FUNC-DSP-008): General Downsample dispatch functions
--    - @relation(FUNC-DSP-009): Idempotency postconditions
--    - @relation(FUNC-DSP-010): Monotonicity via Color_Level_Of postcondition
--    - @relation(FUNC-DSP-011): SPARK Gold provability throughout

with Termicap.Color;

package Termicap.Downsampling
  with SPARK_Mode
is

   use type Termicap.Color.Color_Level;

   ---------------------------------------------------------------------------
   --  Primitive Color Types (FUNC-DSP-001, FUNC-DSP-002, FUNC-DSP-003)
   ---------------------------------------------------------------------------

   --  @summary One 8-bit sRGB channel value.
   --  @description Constraining to 0 .. 255 lets the SPARK prover discharge
   --  overflow obligations in cube-index and distance calculations without
   --  manual lemmas.
   --  @relation(FUNC-DSP-001): Color_Component subtype
   subtype Color_Component is Natural range 0 .. 255;

   --  @summary A 24-bit sRGB color value.
   --  @description Plain record; no invariant constrains the relationship
   --  between components.  Usable as a function parameter and return type
   --  without dynamic allocation.
   --  @relation(FUNC-DSP-001): RGB record type
   type RGB is record
      Red   : Color_Component;
      Green : Color_Component;
      Blue  : Color_Component;
   end record;

   --  @summary Index into the xterm 256-color palette (0 .. 255).
   --  @description Partition: 0-15 = ANSI 16 colors; 16-231 = 6x6x6 cube;
   --  232-255 = 24-step grayscale ramp.
   --  @relation(FUNC-DSP-002): Color_Index_256 subtype
   subtype Color_Index_256 is Natural range 0 .. 255;

   --  @summary Index into the 16 standard ANSI colors (0 .. 15).
   --  @description Derived from Color_Index_256: any Color_Index_16 value is
   --  directly assignable to Color_Index_256 without conversion.
   --  @relation(FUNC-DSP-003): Color_Index_16 subtype
   subtype Color_Index_16 is Color_Index_256 range 0 .. 15;

   ---------------------------------------------------------------------------
   --  Unified Return Type (FUNC-DSP-007, FUNC-DSP-008)
   ---------------------------------------------------------------------------

   --  @summary Discriminated record holding a downsampled color at any level.
   --  @description The discriminant Level identifies which variant is active:
   --    None         -- no color data; means "emit no color escape sequence"
   --    Basic_16     -- Index_16  : Color_Index_16
   --    Extended_256 -- Index_256 : Color_Index_256
   --    True_Color   -- RGB_Value : RGB
   --  The mutable default (Level => None) allows unconstrained stack allocation.
   --  Callers dispatch on the discriminant in a case statement to extract
   --  the appropriate value.
   --  @relation(FUNC-DSP-007): No-color variant (Level => None)
   --  @relation(FUNC-DSP-008): Return type for general Downsample functions
   type Downsampled_Color
     (Level : Termicap.Color.Color_Level := Termicap.Color.Color_Level'First)
   is record
      case Level is
         when Termicap.Color.None =>
            null;

         when Termicap.Color.Basic_16 =>
            Index_16 : Color_Index_16;

         when Termicap.Color.Extended_256 =>
            Index_256 : Color_Index_256;

         when Termicap.Color.True_Color =>
            RGB_Value : RGB;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Primitive Conversion Functions (FUNC-DSP-004, FUNC-DSP-005, FUNC-DSP-006)
   ---------------------------------------------------------------------------

   --  @summary Map an RGB value to the nearest xterm 256-color palette entry.
   --  @description Uses a grayscale-first check (ramp indices 232-255), then
   --  falls back to 6x6x6 cube quantization (indices 16-231).  The result is
   --  always in 16 .. 255; the ANSI 16-color sub-range (0-15) is never
   --  returned.
   --  @param Color The 24-bit sRGB input color.
   --  @return A 256-color palette index in the range 16 .. 255.
   --  @relation(FUNC-DSP-004): TrueColor to 256-color conversion
   function Downsample_True_To_256 (Color : RGB) return Color_Index_256
   with Global => null, Post => Downsample_True_To_256'Result in 16 .. 255;

   --  @summary Map an RGB value to the nearest of the 16 standard ANSI colors.
   --  @description Uses the integer redmean weighted Euclidean distance against
   --  the canonical ANSI palette.  Ties are broken in favor of the lower index.
   --  @param Color The 24-bit sRGB input color.
   --  @return An ANSI color index in 0 .. 15.
   --  @relation(FUNC-DSP-005): TrueColor to 16-color conversion
   function Downsample_True_To_16 (Color : RGB) return Color_Index_16
   with Global => null;

   --  @summary Map a 256-color palette index to the nearest ANSI 16-color index.
   --  @description Indices 0-15 are returned directly (pass-through).  Indices
   --  16-231 are reconstructed to RGB via the cube formula, then passed to
   --  Downsample_True_To_16.  Indices 232-255 are reconstructed via the
   --  grayscale ramp formula, then passed to Downsample_True_To_16.
   --  @param Index A 256-color palette index.
   --  @return An ANSI color index in 0 .. 15.
   --  @relation(FUNC-DSP-006): 256-color to 16-color conversion
   function Downsample_256_To_16
     (Index : Color_Index_256) return Color_Index_16
   with Global => null;

   ---------------------------------------------------------------------------
   --  General Dispatch Functions (FUNC-DSP-008, FUNC-DSP-009, FUNC-DSP-010)
   ---------------------------------------------------------------------------

   --  @summary Downsample a TrueColor RGB value to the given target level.
   --  @description Dispatches to the appropriate conversion:
   --    Target = True_Color   -> identity (RGB preserved)
   --    Target = Extended_256 -> Downsample_True_To_256
   --    Target = Basic_16     -> Downsample_True_To_16
   --    Target = None         -> no-color result
   --  Idempotency: when Target >= True_Color the result carries the original RGB.
   --  Monotonicity: Color_Level_Of (result) <= Target.
   --  @param Color  The 24-bit sRGB source color.
   --  @param Target The desired output color level.
   --  @return A Downsampled_Color discriminated by the effective output level.
   --  @relation(FUNC-DSP-008): General dispatch for RGB source
   --  @relation(FUNC-DSP-009): Idempotency postcondition for TrueColor source
   --  @relation(FUNC-DSP-010): Monotonicity postcondition
   function Downsample
     (Color : RGB; Target : Termicap.Color.Color_Level)
      return Downsampled_Color
   with
     Global => null,
     Post   =>
       --  Idempotency / identity: TrueColor source at TrueColor target
       (if Target >= Termicap.Color.True_Color
        then
          Downsample'Result.Level = Termicap.Color.True_Color
          and then Downsample'Result.RGB_Value.Red = Color.Red
          and then Downsample'Result.RGB_Value.Green = Color.Green
          and then Downsample'Result.RGB_Value.Blue = Color.Blue)
       --  Strip-to-None
       and then (if Target = Termicap.Color.None
                 then Downsample'Result.Level = Termicap.Color.None)
       --  Monotonicity: result level never exceeds target
       and then Color_Level_Of (Downsample'Result)
                <= Termicap.Color.Color_Level'Min
                     (Termicap.Color.True_Color, Target);

   --  @summary Downsample a 256-color palette index to the given target level.
   --  @description Dispatches to the appropriate conversion:
   --    Target >= Extended_256 -> identity (index preserved as Extended_256)
   --    Target = Basic_16      -> Downsample_256_To_16
   --    Target = None          -> no-color result
   --  Idempotency: when Target >= Extended_256 the result carries the original index.
   --  Monotonicity: Color_Level_Of (result) <= Color_Level'Min (Extended_256, Target).
   --  @param Index  A 256-color palette index.
   --  @param Target The desired output color level.
   --  @return A Downsampled_Color discriminated by the effective output level.
   --  @relation(FUNC-DSP-008): General dispatch for 256-color source
   --  @relation(FUNC-DSP-009): Idempotency postcondition for Extended_256 source
   --  @relation(FUNC-DSP-010): Monotonicity postcondition
   function Downsample
     (Index : Color_Index_256; Target : Termicap.Color.Color_Level)
      return Downsampled_Color
   with
     Global => null,
     Post   =>
       --  Idempotency / identity: Extended_256 source at Extended_256 (or higher) target
       (if Target >= Termicap.Color.Extended_256
        then
          Downsample'Result.Level = Termicap.Color.Extended_256
          and then Downsample'Result.Index_256 = Index)
       --  Strip-to-None
       and then (if Target = Termicap.Color.None
                 then Downsample'Result.Level = Termicap.Color.None)
       --  Monotonicity: result level never exceeds min(Extended_256, Target)
       and then Color_Level_Of (Downsample'Result)
                <= Termicap.Color.Color_Level'Min
                     (Termicap.Color.Extended_256, Target);

   ---------------------------------------------------------------------------
   --  Classification (FUNC-DSP-010)
   ---------------------------------------------------------------------------

   --  @summary Return the Color_Level of a Downsampled_Color value.
   --  @description Trivial discriminant accessor used in monotonicity contracts
   --  and by callers that need to inspect the level of a downsampled result
   --  before extracting the variant.
   --  @param D A Downsampled_Color value.
   --  @return The Color_Level discriminant of D.
   --  @relation(FUNC-DSP-010): Color_Level_Of for monotonicity verification
   function Color_Level_Of
     (D : Downsampled_Color) return Termicap.Color.Color_Level
   with Global => null, Post => Color_Level_Of'Result = D.Level;

end Termicap.Downsampling;
