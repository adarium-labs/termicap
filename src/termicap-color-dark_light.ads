-------------------------------------------------------------------------------
--  Termicap.Color.Dark_Light - Dark / Light Theme Classification (SPARK Gold)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  SPARK Gold-provable functions for luminance computation and dark/light
--  terminal background theme classification.
--
--  @description
--  This package provides all the SPARK Gold-provable building blocks for the
--  DARK-LIGHT feature: the Theme_Kind enumeration, the LUMINANCE_THRESHOLD
--  named number, and pure functions that compute ITU-R BT.601 perceived
--  luminance (integer arithmetic), classify an RGB color as dark or light,
--  and expose Boolean convenience predicates.
--
--  All functions carry SPARK Gold-level contracts sufficient for GNATprove to
--  discharge all proof obligations without manual lemmas.  No I/O, no global
--  state, and no exceptions are used in this package.  The I/O boundary is
--  in the child package Termicap.Color.Dark_Light.Detect (SPARK Off).
--
--  The luminance formula is:
--    Y = (299 * R + 587 * G + 114 * B) / 1000
--  Maximum intermediate sum is 255_000, well within Natural on all platforms.
--
--  Requirements Coverage:
--    - @relation(FUNC-DKL-001): Theme_Kind enumeration
--    - @relation(FUNC-DKL-002): Luminance computation function
--    - @relation(FUNC-DKL-003): Classify_Theme function
--    - @relation(FUNC-DKL-004): Is_Dark and Is_Light convenience predicates
--    - @relation(FUNC-DKL-007): SPARK Gold provability boundary

with Termicap.Color.BG_Query;

package Termicap.Color.Dark_Light
  with SPARK_Mode
is

   use Termicap.Color.BG_Query;

   ---------------------------------------------------------------------------
   --  Theme Classification Type (FUNC-DKL-001)
   ---------------------------------------------------------------------------

   --  @summary Two-valued enumeration classifying a terminal background as dark or light.
   --  @description Dark indicates perceived luminance below the midpoint of the 0..255
   --  scale (luminance < 128).  Light indicates luminance at or above the midpoint
   --  (luminance >= 128).  Using an enumeration rather than Boolean makes case
   --  statements self-documenting and enables exhaustiveness checking by GNATprove.
   --  @relation(FUNC-DKL-001): Theme_Kind enumeration
   type Theme_Kind is (Dark, Light);

   ---------------------------------------------------------------------------
   --  Luminance Threshold Constant (FUNC-DKL-003)
   ---------------------------------------------------------------------------

   --  @summary Midpoint threshold on the 0..255 luminance scale.
   --  @description Named number (not a typed constant) so it participates in
   --  static expressions.  Corresponds to 0.5 on the normalised [0.0, 1.0] scale.
   --  Colors with luminance < 128 are Dark; >= 128 are Light.
   LUMINANCE_THRESHOLD : constant := 128;

   ---------------------------------------------------------------------------
   --  Luminance Computation (FUNC-DKL-002)
   ---------------------------------------------------------------------------

   --  @summary Compute the ITU-R BT.601 perceived luminance of an RGB color.
   --  @description Implements the BT.601 formula using scaled integer coefficients:
   --    Y = (299 * R + 587 * G + 114 * B) / 1000
   --  where R, G, B are each in 0..255.  Division is integer division (truncation
   --  toward zero).  Maximum intermediate value is 255_000, which fits in Natural
   --  (>= 2**31 - 1) on all supported platforms; no overflow is possible.
   --  The result is guaranteed to be in 0..255 for any valid RGB input.
   --  @param Color The RGB color value whose luminance is to be computed.
   --  @return Perceived luminance in the range 0..255.
   --  @relation(FUNC-DKL-002): BT.601 integer luminance computation
   function Luminance (Color : RGB) return Natural
   is ((299 * Color.Red + 587 * Color.Green + 114 * Color.Blue) / 1_000)
   with Post => Luminance'Result in 0 .. 255;

   ---------------------------------------------------------------------------
   --  Theme Classification (FUNC-DKL-003)
   ---------------------------------------------------------------------------

   --  @summary Classify an RGB color as Dark or Light using the luminance threshold.
   --  @description Calls Luminance to obtain Y in 0..255, then returns Dark when
   --  Y < LUMINANCE_THRESHOLD (128) and Light otherwise.  The two-branch conditional
   --  is exhaustive over the full range 0..255; GNATprove verifies completeness
   --  by path analysis.  The boundary case Y = 128 is classified as Light,
   --  consistent with the CSS and termenv convention.
   --  @param Color The RGB color value to classify.
   --  @return Dark if luminance < 128, Light if luminance >= 128.
   --  @relation(FUNC-DKL-003): Threshold-based dark/light classification
   function Classify_Theme (Color : RGB) return Theme_Kind
   is (if Luminance (Color) < LUMINANCE_THRESHOLD then Dark else Light);

   ---------------------------------------------------------------------------
   --  Boolean Convenience Predicates (FUNC-DKL-004)
   ---------------------------------------------------------------------------

   --  @summary Return True when the color's perceived luminance is below 128.
   --  @description Expression function delegating entirely to Classify_Theme.
   --  Declared as an expression function in the spec so GNATprove can see the
   --  definition at every call site and discharge the postcondition by rewriting.
   --  @param Color The RGB color value to test.
   --  @return True iff Classify_Theme (Color) = Dark.
   --  @relation(FUNC-DKL-004): Boolean dark predicate
   function Is_Dark (Color : RGB) return Boolean
   is (Classify_Theme (Color) = Dark)
   with Post => Is_Dark'Result = (Classify_Theme (Color) = Dark);

   --  @summary Return True when the color's perceived luminance is at or above 128.
   --  @description Expression function delegating entirely to Classify_Theme.
   --  Declared as an expression function in the spec so GNATprove can see the
   --  definition at every call site and discharge the postcondition by rewriting.
   --  @param Color The RGB color value to test.
   --  @return True iff Classify_Theme (Color) = Light.
   --  @relation(FUNC-DKL-004): Boolean light predicate
   function Is_Light (Color : RGB) return Boolean
   is (Classify_Theme (Color) = Light)
   with Post => Is_Light'Result = (Classify_Theme (Color) = Light);

end Termicap.Color.Dark_Light;
