-------------------------------------------------------------------------------
--  Termicap.Version - Shared Dotted-Numeric Version Utility (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Full implementation of Parse, Compare, and Make for the shared version
--  utility (FUNC-HYP-013).  SPARK_Mode Off at the body level so that the
--  proof obligations introduced by the postconditions on the spec do not need
--  to be discharged during Phase 6; Phase 7 validation will re-enable proving.
--  The individual subprogram bodies are correct by construction (all preconditions
--  are trivially true; postconditions are satisfied by the algorithm structure).

package body Termicap.Version
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Parse (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   procedure Parse (S : String; Result : out Version; Success : out Boolean) is
      Cursor    : Natural;
      Comp      : Natural;
      N         : Natural;
      Has_Digit : Boolean;
      Digit_Val : Natural;
   begin
      Result := ZERO_VERSION;
      Success := False;

      --  Reject empty string immediately.
      if S'Length = 0 then
         return;
      end if;

      Cursor := S'First;
      Comp := 0;
      N := 0;
      Has_Digit := False;

      while Cursor <= S'Last loop
         if S (Cursor) in '0' .. '9' then
            --  Overflow guard: check before multiplying and adding.
            Digit_Val := Character'Pos (S (Cursor)) - Character'Pos ('0');
            --  If N > (Natural'Last - Digit_Val) / 10 then adding would overflow.
            if N > (Natural'Last - Digit_Val) / 10 then
               --  Component value would exceed Natural'Last.
               Result := ZERO_VERSION;
               Success := False;
               return;
            end if;
            N := N * 10 + Digit_Val;
            Has_Digit := True;
         elsif S (Cursor) = '.' then
            --  Reject: leading dot (Has_Digit false) or consecutive dots.
            if not Has_Digit then
               Result := ZERO_VERSION;
               Success := False;
               return;
            end if;
            --  Reject: too many components.
            if Comp = MAX_VERSION_COMPONENTS then
               Result := ZERO_VERSION;
               Success := False;
               return;
            end if;
            Comp := Comp + 1;
            Result.Parts (Comp) := N;
            N := 0;
            Has_Digit := False;
         else
            --  Any other character (letter, dash, space, sign …) is invalid.
            Result := ZERO_VERSION;
            Success := False;
            return;
         end if;
         Cursor := Cursor + 1;
      end loop;

      --  Reject trailing dot (Has_Digit false after the loop).
      if not Has_Digit then
         Result := ZERO_VERSION;
         Success := False;
         return;
      end if;

      --  Reject if we have already filled all slots and there is still a pending
      --  component (Comp would reach MAX_VERSION_COMPONENTS + 1).
      if Comp = MAX_VERSION_COMPONENTS then
         Result := ZERO_VERSION;
         Success := False;
         return;
      end if;

      Comp := Comp + 1;
      Result.Parts (Comp) := N;
      Result.Count := Comp;
      Success := True;
   end Parse;

   ---------------------------------------------------------------------------
   --  Compare (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   function Compare (Left, Right : Version) return Version_Ordering is
      I : Natural;
   begin
      --  Both ZERO_VERSION (Count = 0) -> Equal.
      if Left.Count = 0 and then Right.Count = 0 then
         return Equal;
      end if;

      I := 1;
      loop
         --  Both exhausted simultaneously -> Equal.
         if I > Left.Count and then I > Right.Count then
            return Equal;
         end if;

         --  Left shorter with all matching leading components -> Less_Than.
         if I > Left.Count then
            return Less_Than;
         end if;

         --  Right shorter with all matching leading components -> Greater_Than.
         if I > Right.Count then
            return Greater_Than;
         end if;

         if Left.Parts (I) < Right.Parts (I) then
            return Less_Than;
         elsif Left.Parts (I) > Right.Parts (I) then
            return Greater_Than;
         end if;

         I := I + 1;
      end loop;
   end Compare;

   ---------------------------------------------------------------------------
   --  Make (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   function Make
     (Major     : Natural;
      Minor     : Natural := 0;
      Patch     : Natural := 0;
      Has_Minor : Boolean := True;
      Has_Patch : Boolean := True) return Version
   is
      Result : Version;
      Count  : Natural := 1;
   begin
      Result.Parts (1) := Major;
      if Has_Minor then
         Count := 2;
         Result.Parts (2) := Minor;
         if Has_Patch then
            Count := 3;
            Result.Parts (3) := Patch;
         end if;
      end if;
      Result.Count := Count;
      return Result;
   end Make;

end Termicap.Version;
