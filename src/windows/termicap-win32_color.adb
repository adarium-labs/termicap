-------------------------------------------------------------------------------
--  Termicap.Win32_Color - Windows Console API Color Level Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements Windows-specific color level detection.
--
--  @description
--  Build_To_Color_Level is a pure function: it maps the Windows OS build number
--  and a WT_SESSION flag to a Color_Level using the threshold constants defined
--  in FUNC-WIN-008.
--
--  Detect_Windows_Color_Level is an impure wrapper that reads the real build
--  number from the NT kernel and delegates to Build_To_Color_Level.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-007): WT_SESSION environment variable detection
--    - @relation(FUNC-WIN-008): Build number to color level mapping
--    - @relation(FUNC-WIN-013): SPARK postcondition on Build_To_Color_Level

with Termicap.Win32_Ntdll;

package body Termicap.Win32_Color
  with SPARK_Mode => Off
is

   use type Build_Number;  --  make >=, <=, <, > visible for Interfaces.Unsigned_32

   ---------------------------------------------------------------------------
   --  Build Number Thresholds (FUNC-WIN-008)
   ---------------------------------------------------------------------------

   --  Minimum build number for Extended_256 (Windows 10 Anniversary Update).
   BUILD_256_MIN : constant Build_Number := 10_586;

   --  Minimum build number for True_Color (Windows 10 Creators Update).
   BUILD_TRUE_MIN : constant Build_Number := 14_931;

   ---------------------------------------------------------------------------
   --  Build_To_Color_Level (FUNC-WIN-008, FUNC-WIN-013)
   ---------------------------------------------------------------------------

   function Build_To_Color_Level
     (Build          : Build_Number;
      Has_WT_Session : Boolean)
      return Termicap.Color.Color_Level
   is
      use Termicap.Color;
   begin
      --  WT_SESSION present and non-empty indicates Windows Terminal, which
      --  always supports True Color regardless of the OS build number
      --  (FUNC-WIN-007 override).
      if Has_WT_Session then
         return True_Color;
      end if;

      --  Threshold-based mapping (FUNC-WIN-008)
      if Build >= BUILD_TRUE_MIN then
         return True_Color;
      elsif Build >= BUILD_256_MIN then
         return Extended_256;
      else
         return None;
      end if;
   end Build_To_Color_Level;

   ---------------------------------------------------------------------------
   --  Detect_Windows_Color_Level (FUNC-WIN-007)
   ---------------------------------------------------------------------------

   function Detect_Windows_Color_Level
     (Env : Termicap.Environment.Environment)
      return Termicap.Color.Color_Level
   is
      Build          : Build_Number;
      Has_WT_Session : Boolean;
   begin
      --  Check WT_SESSION in the provided environment snapshot (FUNC-WIN-007).
      --  The variable is present and non-empty when running inside Windows Terminal.
      Has_WT_Session :=
         Termicap.Environment.Contains (Env, "WT_SESSION")
         and then Termicap.Environment.Value (Env, "WT_SESSION") /= "";

      --  Obtain the real Windows build number via dynamic ntdll loading (FUNC-WIN-006).
      Build := Termicap.Win32_Ntdll.Get_Build_Number;

      return Build_To_Color_Level (Build, Has_WT_Session);
   end Detect_Windows_Color_Level;

end Termicap.Win32_Color;
