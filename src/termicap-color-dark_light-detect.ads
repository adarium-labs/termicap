-------------------------------------------------------------------------------
--  Termicap.Color.Dark_Light.Detect - High-Level Theme Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  High-level function combining background color detection with dark/light
--  theme classification into a single call.
--
--  @description
--  This package provides Detect_Theme, which wraps Detect_Background_Color
--  (Termicap.Color.Detection) and Classify_Theme (Termicap.Color.Dark_Light)
--  into a single convenience function returning a discriminated Theme_Result.
--
--  The function executes the following algorithm:
--    1. Clamp Timeout_Ms to at most MAX_TIMEOUT_MS (30_000 ms).
--    2. Call Detect_Background_Color with the clamped timeout.
--    3. If detection succeeds: classify the color and return
--       Theme_Result'(Success => True, Theme => <classified>, Color => <detected>).
--    4. If detection fails: return
--       Theme_Result'(Success => False, Error => <detect error>).
--
--  This package is SPARK_Mode Off because Detect_Theme calls
--  Detect_Background_Color, which manages Ada.Finalization controlled types
--  and performs terminal I/O.  The classification logic it invokes is
--  individually proved at Gold level in Termicap.Color.Dark_Light.
--
--  Requirements Coverage:
--    - @relation(FUNC-DKL-005): Detect_Theme combined detection + classification
--    - @relation(FUNC-DKL-006): Theme_Result discriminated record
--    - @relation(FUNC-DKL-007): SPARK Off boundary for I/O-dependent wrapper

pragma SPARK_Mode (Off);

with Termicap.Color.BG_Query;
with Termicap.Color.Detection;

package Termicap.Color.Dark_Light.Detect is

   use Termicap.Color.Detection;

   ---------------------------------------------------------------------------
   --  Timeout Constant
   ---------------------------------------------------------------------------

   --  @summary Maximum allowed timeout for the underlying OSC query.
   --  @description Timeout_Ms is clamped to this value before being passed to
   --  Detect_Background_Color, consistent with the timeout policy in FUNC-BGC-015.
   MAX_TIMEOUT_MS : constant := 30_000;

   ---------------------------------------------------------------------------
   --  Detection Result Type (FUNC-DKL-006)
   ---------------------------------------------------------------------------

   --  @summary Result of a combined background color detection and theme classification.
   --  @description Discriminated record following the Termicap Result pattern.
   --  When Success is True, Theme holds the classified dark/light value and Color
   --  holds the raw RGB value that was detected and used as classification input.
   --  When Success is False, Error identifies why detection failed.
   --  The default discriminant False ensures uninitialized values are always in
   --  the failure state, preventing accidental use of an uninitialized Theme field.
   --  @relation(FUNC-DKL-006): Theme_Result discriminated record
   type Theme_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Theme : Dark_Light.Theme_Kind;
            Color : BG_Query.RGB;
         when False =>
            Error : Detection.Detect_Error;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Theme Detection (FUNC-DKL-005)
   ---------------------------------------------------------------------------

   --  @summary Detect the terminal background theme (dark or light) in one call.
   --  @description Combines OSC 11 background color detection with BT.601 luminance
   --  classification.  Timeout_Ms is clamped to MAX_TIMEOUT_MS before being passed
   --  to Detect_Background_Color.  Does not raise an exception on any path.
   --  Returns Theme_Result'(Success => True, Theme => Dark | Light, Color => <RGB>)
   --  on success, or Theme_Result'(Success => False, Error => <Detect_Error>) when
   --  both the OSC query and the COLORFGBG fallback fail.
   --  @param Timeout_Ms Millisecond timeout for the underlying OSC query (default 1000).
   --  @return Theme_Result with Theme and Color on success, Error otherwise.
   --  @relation(FUNC-DKL-005): Combined background detection and theme classification
   function Detect_Theme
     (Timeout_Ms : Natural := 1_000) return Theme_Result;

end Termicap.Color.Dark_Light.Detect;
