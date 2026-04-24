-------------------------------------------------------------------------------
--  Termicap.Dimensions - Terminal Dimensions Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with Interfaces.C;

package body Termicap.Dimensions
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  C FFI binding (FUNC-DIM-006)
   ---------------------------------------------------------------------------

   function C_Get_Winsize
     (Fd      : Interfaces.C.int;
      Cols    : access Interfaces.C.unsigned_short;
      Rows    : access Interfaces.C.unsigned_short;
      X_Pixel : access Interfaces.C.unsigned_short;
      Y_Pixel : access Interfaces.C.unsigned_short) return Interfaces.C.int;
   pragma Import (C, C_Get_Winsize, "termicap_get_winsize");

   STDOUT_FD : constant Interfaces.C.int := 1;

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

         --  Overflow check: Accumulator * 10 + Digit must fit in Natural
         if Accumulator > (Positive'Last - Digit) / 10 then
            return 0;
         end if;

         Accumulator := Accumulator * 10 + Digit;
      end loop;

      --  "0" is not a valid Positive
      if Accumulator = 0 then
         return 0;
      end if;

      return Accumulator;
   end Try_Parse_Positive;

   ---------------------------------------------------------------------------
   --  Get_Size (FUNC-DIM-002 through FUNC-DIM-008)
   ---------------------------------------------------------------------------

   function Get_Size (Env : Termicap.Environment.Environment; Is_TTY : Boolean) return Terminal_Size is
      use type Interfaces.C.int;
      use type Interfaces.C.unsigned_short;

      Result : Terminal_Size := (Rows => DEFAULT_ROWS, Columns => DEFAULT_COLUMNS, Pixel_Width => 0, Pixel_Height => 0);
   begin
      --  Step 1: If Is_TTY, attempt ioctl via C wrapper (FUNC-DIM-002)
      if Is_TTY then
         declare
            C_Cols    : aliased Interfaces.C.unsigned_short := 0;
            C_Rows    : aliased Interfaces.C.unsigned_short := 0;
            C_X_Pixel : aliased Interfaces.C.unsigned_short := 0;
            C_Y_Pixel : aliased Interfaces.C.unsigned_short := 0;
            Status    : Interfaces.C.int;
         begin
            Status :=
              C_Get_Winsize
                (Fd      => STDOUT_FD,
                 Cols    => C_Cols'Access,
                 Rows    => C_Rows'Access,
                 X_Pixel => C_X_Pixel'Access,
                 Y_Pixel => C_Y_Pixel'Access);

            if Status = 0 and then C_Cols > 0 and then C_Rows > 0 then
               return
                 (Columns      => Positive (C_Cols),
                  Rows         => Positive (C_Rows),
                  Pixel_Width  => Natural (C_X_Pixel),
                  Pixel_Height => Natural (C_Y_Pixel));
            end if;
         end;
         --  ioctl failed or returned zero dims; fall through to env vars

      end if;

      --  Step 2: Parse COLUMNS from Environment (FUNC-DIM-003)
      if Termicap.Environment.Contains (Env, "COLUMNS") then
         declare
            Parsed : constant Natural := Try_Parse_Positive (Termicap.Environment.Value (Env, "COLUMNS"));
         begin
            if Parsed > 0 then
               Result.Columns := Parsed;
            end if;
         end;
      end if;

      --  Step 3: Parse LINES from Environment (FUNC-DIM-003)
      if Termicap.Environment.Contains (Env, "LINES") then
         declare
            Parsed : constant Natural := Try_Parse_Positive (Termicap.Environment.Value (Env, "LINES"));
         begin
            if Parsed > 0 then
               Result.Rows := Parsed;
            end if;
         end;
      end if;

      --  Step 4: Any dimension not set retains the default (FUNC-DIM-004)
      --  Pixel dimensions remain 0 since env vars don't provide them

      return Result;
   end Get_Size;

end Termicap.Dimensions;
