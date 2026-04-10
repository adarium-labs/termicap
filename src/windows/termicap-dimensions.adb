-------------------------------------------------------------------------------
--  Termicap.Dimensions - Terminal Dimensions Detection (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Windows implementation of terminal dimensions detection using
--  GetConsoleScreenBufferInfo() when Is_TTY is True, with environment
--  variable (COLUMNS/LINES) and default (80x24) fallbacks.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-005): GetConsoleScreenBufferInfo-based dimensions
--    - @relation(FUNC-DIM-003): Environment variable fallback
--    - @relation(FUNC-DIM-004): Default fallback to 80x24

with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;
with Termicap.Win32_VT;

package body Termicap.Dimensions
   with SPARK_Mode => Off
is

   use type Win32.BOOL;
   use type Win32.Winnt.HANDLE;
   use type Win32.SHORT;

   ---------------------------------------------------------------------------
   --  Try_Parse_Positive: parse a string as a Positive, return 0 on failure
   ---------------------------------------------------------------------------

   function Try_Parse_Positive (S : String) return Natural is
      Accumulator : Natural := 0;
      Digit       : Natural;
   begin
      if S'Length = 0 then
         return 0;
      end if;

      for I in S'Range loop
         if S (I) not in '0' .. '9' then
            return 0;
         end if;

         Digit := Character'Pos (S (I)) - Character'Pos ('0');

         if Accumulator > (Positive'Last - Digit) / 10 then
            return 0;
         end if;

         Accumulator := Accumulator * 10 + Digit;
      end loop;

      if Accumulator = 0 then
         return 0;
      end if;

      return Accumulator;
   end Try_Parse_Positive;

   ---------------------------------------------------------------------------
   --  Get_Size (FUNC-WIN-005, FUNC-DIM-003, FUNC-DIM-004)
   ---------------------------------------------------------------------------

   function Get_Size
      (Env    : Termicap.Environment.Environment;
       Is_TTY : Boolean) return Terminal_Size
   is
      Result : Terminal_Size :=
         (Rows         => DEFAULT_ROWS,
          Columns      => DEFAULT_COLUMNS,
          Pixel_Width  => 0,
          Pixel_Height => 0);
   begin
      --  Try the console API when we are running in a TTY (FUNC-WIN-005)
      if Is_TTY then
         declare
            H    : constant Win32.Winnt.HANDLE :=
               Win32.Winbase.GetStdHandle (Win32.Winbase.STD_OUTPUT_HANDLE);
            Info : aliased Win32.Wincon.CONSOLE_SCREEN_BUFFER_INFO;
            Res  : Win32.BOOL;
         begin
            if Termicap.Win32_VT.Is_Valid_Handle (H) then
               Res := Win32.Wincon.GetConsoleScreenBufferInfo
                 (H, Info'Unchecked_Access);

               if Res /= Win32.FALSE then
                  --  Use srWindow (visible console window), not dwSize
                  --  (total screen buffer). This gives the actual terminal
                  --  window size as seen by the user (FUNC-WIN-005).
                  declare
                     Cols : constant Natural :=
                        Natural (Info.srWindow.Right - Info.srWindow.Left) + 1;
                     Rows : constant Natural :=
                        Natural (Info.srWindow.Bottom - Info.srWindow.Top) + 1;
                  begin
                     if Cols > 0 and then Rows > 0 then
                        Result.Columns      := Cols;
                        Result.Rows         := Rows;
                        Result.Pixel_Width  := 0;
                        Result.Pixel_Height := 0;
                        --  Return immediately with the console-derived size
                        return Result;
                     end if;
                  end;
               end if;
            end if;
         end;
      end if;

      --  Environment variable fallback (FUNC-DIM-003)
      if Termicap.Environment.Contains (Env, "COLUMNS") then
         declare
            Parsed : constant Natural :=
               Try_Parse_Positive (Termicap.Environment.Value (Env, "COLUMNS"));
         begin
            if Parsed > 0 then
               Result.Columns := Parsed;
            end if;
         end;
      end if;

      if Termicap.Environment.Contains (Env, "LINES") then
         declare
            Parsed : constant Natural :=
               Try_Parse_Positive (Termicap.Environment.Value (Env, "LINES"));
         begin
            if Parsed > 0 then
               Result.Rows := Parsed;
            end if;
         end;
      end if;

      return Result;
   end Get_Size;

end Termicap.Dimensions;
