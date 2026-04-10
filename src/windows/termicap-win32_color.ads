-------------------------------------------------------------------------------
--  Termicap.Win32_Color - Windows Console API Color Level Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows-specific color level detection using the Windows build number and
--  the WT_SESSION environment variable.
--
--  @description
--  Provides two subprograms for Windows color capability detection:
--
--  - Build_To_Color_Level: a pure function mapping an OS build number and a
--    WT_SESSION flag to a Color_Level.  This is the primary testable unit,
--    with SPARK contracts guaranteeing that Basic_16 is never returned
--    (FUNC-WIN-013).
--
--  - Detect_Windows_Color_Level: an impure wrapper that reads the real OS
--    build number via the NT kernel API and consults the supplied environment
--    snapshot for WT_SESSION (FUNC-WIN-007).
--
--  Build number thresholds (FUNC-WIN-008):
--    < 10 586              => None
--    10 586 .. 14 930      => Extended_256
--    >= 14 931             => True_Color
--
--  If WT_SESSION is present and non-empty the result is always True_Color,
--  regardless of the build number (FUNC-WIN-007).
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-007): WT_SESSION environment variable detection
--    - @relation(FUNC-WIN-008): Build number to color level mapping
--    - @relation(FUNC-WIN-013): SPARK contracts on Build_To_Color_Level

with Interfaces;
with Termicap.Color;
with Termicap.Environment;

package Termicap.Win32_Color
  with SPARK_Mode
is

   use type Termicap.Color.Color_Level;

   ---------------------------------------------------------------------------
   --  Build Number Type
   ---------------------------------------------------------------------------

   --  Windows build numbers are unsigned 32-bit integers.
   subtype Build_Number is Interfaces.Unsigned_32;

   ---------------------------------------------------------------------------
   --  Pure Mapping Function (FUNC-WIN-008, FUNC-WIN-013)
   ---------------------------------------------------------------------------

   --  @summary Map a Windows build number and WT_SESSION flag to a color level.
   --  @param Build         The Windows OS build number (from RtlGetVersion).
   --  @param Has_WT_Session True if the WT_SESSION environment variable is
   --                        present and non-empty in the calling environment.
   --  @return The color level:
   --    - True_Color  when Has_WT_Session = True (FUNC-WIN-007 override), or
   --                  when Build >= 14_931 (FUNC-WIN-008).
   --    - Extended_256 when 10_586 <= Build <= 14_930 (FUNC-WIN-008).
   --    - None        when Build < 10_586 (FUNC-WIN-008).
   --  @relation(FUNC-WIN-008): Threshold-based build number mapping
   --  @relation(FUNC-WIN-013): Postcondition guarantees Basic_16 is never returned
   function Build_To_Color_Level
     (Build          : Build_Number;
      Has_WT_Session : Boolean)
      return Termicap.Color.Color_Level
   with
     Global => null,
     Post   =>
        (if Has_WT_Session then
           Build_To_Color_Level'Result = Termicap.Color.True_Color)
        and then Build_To_Color_Level'Result in
           Termicap.Color.None | Termicap.Color.Extended_256
             | Termicap.Color.True_Color;

   ---------------------------------------------------------------------------
   --  Impure Detection Wrapper (FUNC-WIN-007)
   ---------------------------------------------------------------------------

   --  @summary Detect Windows console color level from the live environment.
   --  @param Env  An immutable environment variable snapshot used to check
   --              WT_SESSION (FUNC-WIN-007).
   --  @return The color level derived from the real OS build number and the
   --          WT_SESSION variable in Env.
   --  @relation(FUNC-WIN-007): WT_SESSION variable detection
   function Detect_Windows_Color_Level
     (Env : Termicap.Environment.Environment)
      return Termicap.Color.Color_Level
   with SPARK_Mode => Off;

end Termicap.Win32_Color;
