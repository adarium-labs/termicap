-------------------------------------------------------------------------------
--  Termicap.Color.Detection - High-Level Background / Foreground Color Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  High-level functions for detecting the terminal background and foreground
--  color via OSC 10/11 query with COLORFGBG environment variable fallback.
--
--  @description
--  This package provides the two top-level detection functions that implement
--  the two-level cascade defined in FUNC-BGC-013 and FUNC-BGC-014:
--
--    1. Send an OSC 11 (background) or OSC 10 (foreground) query via
--       Query_Color (Termicap.Color.BG_Query.IO).
--    2. If the query succeeds, strip the OSC header and parse the X11 rgb:
--       response via Strip_OSC_Header and Parse_RGB_Response.
--    3. If the query fails or the parse fails, read the COLORFGBG environment
--       variable and parse it via Parse_Colorfgbg and Ansi_To_RGB.
--    4. If both steps fail, return a Detection_Result with Success => False
--       and an appropriate Detect_Error value.
--
--  Both functions clamp Timeout_Ms to a maximum of 30,000 ms to prevent
--  accidental indefinite blocking.  When Timeout_Ms = 0, the OSC query is
--  skipped entirely and the function proceeds directly to the COLORFGBG
--  fallback.
--
--  This package is SPARK_Mode Off because both functions call Query_Color,
--  which manages an Ada.Finalization controlled type (Probe_Session).
--  The parsing and lookup operations they invoke are individually provable
--  in Termicap.Color.BG_Query (SPARK On).
--
--  Requirements Coverage:
--    - @relation(FUNC-BGC-013): Detect_Background_Color with COLORFGBG fallback
--    - @relation(FUNC-BGC-014): Detect_Foreground_Color with COLORFGBG fallback
--    - @relation(FUNC-BGC-015): Timeout clamping and zero-timeout fast path

pragma SPARK_Mode (Off);

with Termicap.Color.BG_Query;

package Termicap.Color.Detection is

   ---------------------------------------------------------------------------
   --  Error Type (FUNC-BGC-013)
   ---------------------------------------------------------------------------

   --  @summary Identifies the specific failure in the color detection cascade.
   --  @description Each value corresponds to a distinct failure condition:
   --    Not_A_Terminal   -- Probe_Session could not open /dev/tty.
   --    Not_Foreground   -- Process is not in the terminal foreground group.
   --    Query_Timeout    -- Sentinel_Query did not receive a DA1 response in time.
   --    Parse_Failed     -- OSC response was received but could not be parsed.
   --    No_Fallback      -- COLORFGBG is absent or could not be parsed.
   --  @relation(FUNC-BGC-013): Detect_Error enumeration
   type Detect_Error is (Not_A_Terminal, Not_Foreground, Query_Timeout, Parse_Failed, No_Fallback);

   ---------------------------------------------------------------------------
   --  Detection Result Type
   ---------------------------------------------------------------------------

   --  @summary Result of a background or foreground color detection attempt.
   --  @description Discriminated record following the same pattern as
   --  BG_Query.Parse_Result.  When Success is True, Color holds the detected
   --  RGB value.  When Success is False, Error identifies the failure reason.
   --  Callers must check the Success discriminant before accessing either field.
   type Detection_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Color : BG_Query.RGB;

         when False =>
            Error : Detect_Error;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Background Color Detection (FUNC-BGC-013)
   ---------------------------------------------------------------------------

   --  @summary Detect the terminal background color.
   --  @description Attempts OSC 11 query first.  Falls back to COLORFGBG
   --  environment variable parsing if the query times out or the response
   --  cannot be parsed.  Timeout_Ms is clamped to 30,000 ms.  When
   --  Timeout_Ms = 0, skips the OSC query and proceeds directly to COLORFGBG.
   --  Returns Detection_Result'(Success => False, Error => No_Fallback) when
   --  both steps fail, leaving the decision to substitute a default to the caller.
   --  Does not raise an exception.
   --  @param Timeout_Ms Millisecond timeout for the OSC query (default 1000).
   --  @return Detection_Result with Color when successful, Error otherwise.
   --  @relation(FUNC-BGC-013): Background color detection cascade
   --  @relation(FUNC-BGC-015): Timeout clamping
   function Detect_Background_Color (Timeout_Ms : Natural := 1_000) return Detection_Result;

   ---------------------------------------------------------------------------
   --  Foreground Color Detection (FUNC-BGC-014)
   ---------------------------------------------------------------------------

   --  @summary Detect the terminal foreground color.
   --  @description Attempts OSC 10 query first.  Falls back to COLORFGBG
   --  environment variable parsing if the query times out or the response
   --  cannot be parsed.  Timeout_Ms is clamped to 30,000 ms.  When
   --  Timeout_Ms = 0, skips the OSC query and proceeds directly to COLORFGBG.
   --  Returns Detection_Result'(Success => False, Error => No_Fallback) when
   --  both steps fail, leaving the decision to substitute a default to the caller.
   --  Does not raise an exception.
   --  @param Timeout_Ms Millisecond timeout for the OSC query (default 1000).
   --  @return Detection_Result with Color when successful, Error otherwise.
   --  @relation(FUNC-BGC-014): Foreground color detection cascade
   --  @relation(FUNC-BGC-015): Timeout clamping
   function Detect_Foreground_Color (Timeout_Ms : Natural := 1_000) return Detection_Result;

end Termicap.Color.Detection;
