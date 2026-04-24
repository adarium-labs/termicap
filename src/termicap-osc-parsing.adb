-------------------------------------------------------------------------------
--  Termicap.OSC.Parsing - Pure SPARK DA1 Parsing and Passthrough Wrapping (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK implementations of DA1 response detection, parsing, and
--  multiplexer passthrough wrapping.
--
--  @description
--  All functions operate on Byte_Array slices bounded by a Length parameter.
--  No heap allocation occurs.  Loop bounds are explicit for SPARK Silver proof.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-006): Contains_DA1_Response, DA1_Response_Start
--    - @relation(FUNC-OSC-010): Parse_DA1_Response
--    - @relation(FUNC-OSC-014): Wrap_For_Passthrough
--    - @relation(FUNC-OSC-015): SPARK Silver boundary

pragma SPARK_Mode (On);

with Interfaces.C;

package body Termicap.OSC.Parsing
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Byte Constants
   ---------------------------------------------------------------------------

   ESC_BYTE : constant Byte := 16#1B#;  --  ESC
   CSI_L    : constant Byte := 16#5B#;  --  '['
   QUEST    : constant Byte := 16#3F#;  --  '?'
   TERM_C   : constant Byte := 16#63#;  --  'c'   DA1 terminator
   SEMI     : constant Byte := 16#3B#;  --  ';'
   DIG_0    : constant Byte := 16#30#;  --  '0'
   DIG_9    : constant Byte := 16#39#;  --  '9'

   ---------------------------------------------------------------------------
   --  Internal helpers
   ---------------------------------------------------------------------------

   --  Return True when B is an ASCII decimal digit byte.
   function Is_Digit (B : Byte) return Boolean
   is (B >= DIG_0 and then B <= DIG_9)
   with Inline;

   --  Return True when B is a digit or semicolon (valid inside DA1 params).
   function Is_Param_Byte (B : Byte) return Boolean
   is ((B >= DIG_0 and then B <= DIG_9) or else B = SEMI)
   with Inline;

   ---------------------------------------------------------------------------
   --  DA1 Sentinel Detection (FUNC-OSC-006)
   ---------------------------------------------------------------------------

   function Contains_DA1_Response (Bytes : Byte_Array; Length : Natural) return Boolean is
      --  We scan for the pattern: ESC [ ? <params>* c
      --  State machine: 0=idle, 1=saw ESC, 2=saw ESC [, 3=saw ESC [ ?,
      --                 4=saw ESC [ ? <params>+ or ESC [ ? c

      State : Natural := 0;
   begin
      if Length = 0 then
         return False;
      end if;

      for I in Bytes'First .. Bytes'First + (Length - 1) loop
         pragma Loop_Invariant (State <= 4);
         pragma Loop_Invariant (I >= Bytes'First);
         pragma Loop_Invariant (I <= Bytes'First + (Length - 1));

         declare
            B : constant Byte := Bytes (I);
         begin
            case State is
               when 0 =>
                  if B = ESC_BYTE then
                     State := 1;
                  end if;

               when 1 =>
                  if B = CSI_L then
                     State := 2;
                  elsif B = ESC_BYTE then
                     State := 1;  --  new ESC, reset to state 1
                  else
                     State := 0;
                  end if;

               when 2 =>
                  if B = QUEST then
                     State := 3;
                  elsif B = ESC_BYTE then
                     State := 1;
                  else
                     State := 0;
                  end if;

               when 3 =>
                  --  After ESC [ ? we accept zero or more param bytes then c
                  if B = TERM_C then
                     return True;
                  elsif Is_Param_Byte (B) then
                     State := 3;  --  remain in param-scan state
                  elsif B = ESC_BYTE then
                     State := 1;  --  new potential ESC sequence
                  else
                     State := 0;
                  end if;

               when others =>
                  State := 0;
            end case;
         end;
      end loop;

      return False;
   end Contains_DA1_Response;

   function DA1_Response_Start (Bytes : Byte_Array; Length : Natural) return Natural is
      State   : Natural := 0;
      ESC_Pos : Natural := 0;  --  position of current candidate ESC byte
   begin
      if Length = 0 then
         return Length;
      end if;

      for I in Bytes'First .. Bytes'First + (Length - 1) loop
         pragma Loop_Invariant (State <= 4);
         pragma Loop_Invariant (I >= Bytes'First);
         pragma Loop_Invariant (I <= Bytes'First + (Length - 1));

         declare
            B   : constant Byte := Bytes (I);
            --  Convert array index to 1-based position within the Length slice
            Pos : constant Natural := I - Bytes'First + 1;
         begin
            case State is
               when 0 =>
                  if B = ESC_BYTE then
                     State := 1;
                     ESC_Pos := Pos;
                  end if;

               when 1 =>
                  if B = CSI_L then
                     State := 2;
                  elsif B = ESC_BYTE then
                     State := 1;
                     ESC_Pos := Pos;
                  else
                     State := 0;
                  end if;

               when 2 =>
                  if B = QUEST then
                     State := 3;
                  elsif B = ESC_BYTE then
                     State := 1;
                     ESC_Pos := Pos;
                  else
                     State := 0;
                  end if;

               when 3 =>
                  if B = TERM_C then
                     return ESC_Pos;
                  elsif Is_Param_Byte (B) then
                     State := 3;
                  elsif B = ESC_BYTE then
                     State := 1;
                     ESC_Pos := Pos;
                  else
                     State := 0;
                  end if;

               when others =>
                  State := 0;
            end case;
         end;
      end loop;

      return Length;
   end DA1_Response_Start;

   ---------------------------------------------------------------------------
   --  DA1 Response Parsing (FUNC-OSC-010)
   ---------------------------------------------------------------------------

   function Parse_DA1_Response (Bytes : Byte_Array; Length : Natural) return DA1_Params is
      Result      : DA1_Params := (Count => 0, Values => [others => 0]);
      Current_Val : Natural := 0;
      In_Params   : Boolean := False;
      Has_Digit   : Boolean := False;
   begin
      --  Must have at least 4 bytes: ESC [ ? c
      if Length < 4 then
         return Result;
      end if;

      --  Verify the required prefix: ESC [ ?
      if Bytes (Bytes'First) /= ESC_BYTE
        or else Bytes (Bytes'First + 1) /= CSI_L
        or else Bytes (Bytes'First + 2) /= QUEST
      then
         return Result;
      end if;

      --  Verify the required suffix: c at position Length (1-based)
      if Bytes (Bytes'First + (Length - 1)) /= TERM_C then
         return Result;
      end if;

      --  Parse the parameter bytes between ? (exclusive) and c (exclusive)
      In_Params := True;

      for I in Bytes'First + 3 .. Bytes'First + (Length - 2) loop
         pragma Loop_Invariant (Result.Count <= MAX_DA1_PARAMS);
         pragma Loop_Invariant (I >= Bytes'First + 3);
         pragma Loop_Invariant (I <= Bytes'First + (Length - 2));

         declare
            B : constant Byte := Bytes (I);
         begin
            if Is_Digit (B) then
               --  Accumulate decimal digit; guard against overflow
               if Current_Val <= 214_748_364 then
                  Current_Val := Current_Val * 10 + (Natural (B) - Natural (DIG_0));
               end if;
               Has_Digit := True;
            elsif B = SEMI then
               --  Semicolon: commit current parameter
               if Has_Digit and then Result.Count < MAX_DA1_PARAMS then
                  Result.Count := Result.Count + 1;
                  Result.Values (Result.Count) := Current_Val;
               elsif Result.Count < MAX_DA1_PARAMS and then not Has_Digit then
                  --  Empty segment (;;) contributes a 0 parameter
                  Result.Count := Result.Count + 1;
                  Result.Values (Result.Count) := 0;
               end if;
               Current_Val := 0;
               Has_Digit := False;
            else
               --  Unexpected byte in parameter area: fail
               In_Params := False;
               exit;
            end if;
         end;
      end loop;

      --  Commit the final parameter (before the 'c' terminator)
      if In_Params then
         if Has_Digit and then Result.Count < MAX_DA1_PARAMS then
            Result.Count := Result.Count + 1;
            Result.Values (Result.Count) := Current_Val;
         elsif not Has_Digit and then Length = 4 then
            --  ESC [ ? c with no params: Count stays 0, which is correct
            null;
         end if;
      end if;

      return Result;
   end Parse_DA1_Response;

   ---------------------------------------------------------------------------
   --  Multiplexer Passthrough Wrapping (FUNC-OSC-014)
   ---------------------------------------------------------------------------

   --  Tmux DCS passthrough prefix: ESC P t m u x ; ESC  (8 bytes)
   TMUX_PREFIX : constant Byte_Array (1 .. 8) := [16#1B#, 16#50#, 16#74#, 16#6D#, 16#75#, 16#78#, 16#3B#, 16#1B#];

   --  Screen DCS passthrough prefix: ESC P  (2 bytes)
   SCREEN_PREFIX : constant Byte_Array (1 .. 2) := [16#1B#, 16#50#];

   --  String terminator suffix: ESC \  (2 bytes)
   ST_SUFFIX : constant Byte_Array (1 .. 2) := [16#1B#, 16#5C#];

   function Wrap_For_Passthrough (Query : Byte_Array; Passthrough : Passthrough_Mode) return Byte_Array is
   begin
      case Passthrough is
         when No_Passthrough =>
            return Query;

         when Tmux_Passthrough =>
            --  Result: TMUX_PREFIX & Query & ST_SUFFIX
            --  Total length = 8 + Query'Length + 2
            declare
               Result : Byte_Array (1 .. TMUX_PREFIX'Length + Query'Length + ST_SUFFIX'Length);
               Pos    : Positive := 1;
            begin
               for I in TMUX_PREFIX'Range loop
                  pragma Loop_Invariant (Pos = I);
                  Result (Pos) := TMUX_PREFIX (I);
                  Pos := Pos + 1;
               end loop;

               for I in Query'Range loop
                  pragma Loop_Invariant (Pos = TMUX_PREFIX'Length + (I - Query'First) + 1);
                  Result (Pos) := Query (I);
                  Pos := Pos + 1;
               end loop;

               for I in ST_SUFFIX'Range loop
                  pragma Loop_Invariant (Pos = TMUX_PREFIX'Length + Query'Length + (I - ST_SUFFIX'First) + 1);
                  Result (Pos) := ST_SUFFIX (I);
                  Pos := Pos + 1;
               end loop;

               return Result;
            end;

         when Screen_Passthrough =>
            --  Result: SCREEN_PREFIX & Query & ST_SUFFIX
            --  Total length = 2 + Query'Length + 2
            declare
               Result : Byte_Array (1 .. SCREEN_PREFIX'Length + Query'Length + ST_SUFFIX'Length);
               Pos    : Positive := 1;
            begin
               for I in SCREEN_PREFIX'Range loop
                  pragma Loop_Invariant (Pos = I);
                  Result (Pos) := SCREEN_PREFIX (I);
                  Pos := Pos + 1;
               end loop;

               for I in Query'Range loop
                  pragma Loop_Invariant (Pos = SCREEN_PREFIX'Length + (I - Query'First) + 1);
                  Result (Pos) := Query (I);
                  Pos := Pos + 1;
               end loop;

               for I in ST_SUFFIX'Range loop
                  pragma Loop_Invariant (Pos = SCREEN_PREFIX'Length + Query'Length + (I - ST_SUFFIX'First) + 1);
                  Result (Pos) := ST_SUFFIX (I);
                  Pos := Pos + 1;
               end loop;

               return Result;
            end;
      end case;
   end Wrap_For_Passthrough;

end Termicap.OSC.Parsing;
