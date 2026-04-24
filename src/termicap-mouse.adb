-------------------------------------------------------------------------------
--  Termicap.Mouse - Mouse Protocol Detection Types and Parsers (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Bodies of the two pure SPARK functions: Parse_Mouse_DECRPM_Response and
--  Resolve_Best_Encoding.  The package body carries pragma SPARK_Mode (On) so
--  that GNATprove can verify absence of runtime errors and the Global => null
--  contracts for both functions (mixed SPARK pattern, ADR-0013, FUNC-MSE-017).
--
--  Requirements Coverage:
--    - @relation(FUNC-MSE-007): Parse_Mouse_DECRPM_Response body
--    - @relation(FUNC-MSE-008): Resolve_Best_Encoding body

pragma SPARK_Mode (On);

package body Termicap.Mouse
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;
   use type Termicap.DECRPM.Mode_Status;

   ---------------------------------------------------------------------------
   --  Internal byte constants
   ---------------------------------------------------------------------------

   BYTE_ESC   : constant Byte := 16#1B#;  --  ESC  (0x1B)
   BYTE_LBRK  : constant Byte := 16#5B#;  --  '['  (0x5B)
   BYTE_QMARK : constant Byte := 16#3F#;  --  '?'  (0x3F)
   BYTE_SEMI  : constant Byte := 16#3B#;  --  ';'  (0x3B)
   BYTE_DOLL  : constant Byte := 16#24#;  --  '$'  (0x24)
   BYTE_Y     : constant Byte := 16#79#;  --  'y'  (0x79)
   BYTE_ZERO  : constant Byte := 16#30#;  --  '0' = ASCII digit 0 (0x30)
   BYTE_FOUR  : constant Byte := 16#34#;  --  '4' = ASCII digit 4 (0x34)
   BYTE_NINE  : constant Byte := 16#39#;  --  '9' = ASCII digit 9 (0x39)

   ---------------------------------------------------------------------------
   --  Parse_Mouse_DECRPM_Response (FUNC-MSE-007)
   ---------------------------------------------------------------------------

   function Parse_Mouse_DECRPM_Response (Buffer : Byte_Array; Length : Natural) return DECRPM_Parse_Result is
      FAILURE : constant DECRPM_Parse_Result := (Valid => False, Mode => 0, Status => Termicap.DECRPM.Not_Recognized);

      Base : constant Positive := Buffer'First;
      --  All index arithmetic is relative to Buffer'First to handle any
      --  array index base.

      Pos   : Natural;
      Mode  : Termicap.DECRPM.Mode_Id;
      Pm    : Natural;
      Digit : Natural;
   begin
      --  Minimum valid frame: ESC [ ? d ; d $ y = 8 bytes
      if Length < 8 then
         return FAILURE;
      end if;

      --  Check three-byte prefix: ESC [ ?
      if Buffer (Base) /= BYTE_ESC or else Buffer (Base + 1) /= BYTE_LBRK or else Buffer (Base + 2) /= BYTE_QMARK then
         return FAILURE;
      end if;

      --  Decode mode digits (Ps): one or more ASCII decimal digits after '?'
      Pos := Base + 3;
      Mode := 0;

      if Pos > Base + Length - 1 then
         return FAILURE;
      end if;

      if Buffer (Pos) < BYTE_ZERO or else Buffer (Pos) > BYTE_NINE then
         return FAILURE;  --  no digit immediately after '?'

      end if;

      while Pos <= Base + Length - 1 and then Buffer (Pos) >= BYTE_ZERO and then Buffer (Pos) <= BYTE_NINE loop
         Digit := Natural (Buffer (Pos)) - Natural (BYTE_ZERO);
         Mode := Mode * 10 + Digit;
         Pos := Pos + 1;
      end loop;

      --  Must find semicolon ';' after mode digits
      if Pos > Base + Length - 1 or else Buffer (Pos) /= BYTE_SEMI then
         return FAILURE;
      end if;
      Pos := Pos + 1;

      --  Decode status digit (Pm): exactly one ASCII digit in range '0'..'4'
      if Pos > Base + Length - 1 then
         return FAILURE;
      end if;

      if Buffer (Pos) < BYTE_ZERO or else Buffer (Pos) > BYTE_FOUR then
         return FAILURE;
      end if;
      Pm := Natural (Buffer (Pos)) - Natural (BYTE_ZERO);
      Pos := Pos + 1;

      --  Must find '$' 'y' suffix immediately after status digit
      if Pos + 1 > Base + Length - 1 then
         return FAILURE;
      end if;

      if Buffer (Pos) /= BYTE_DOLL or else Buffer (Pos + 1) /= BYTE_Y then
         return FAILURE;
      end if;

      --  Mode 0 is not a valid DEC private mode number; treat as failure
      if Mode = 0 then
         return FAILURE;
      end if;

      --  Map Pm (0..4) to Mode_Status
      declare
         Status : Termicap.DECRPM.Mode_Status;
      begin
         case Pm is
            when 0 =>
               Status := Termicap.DECRPM.Not_Recognized;

            when 1 =>
               Status := Termicap.DECRPM.Set;

            when 2 =>
               Status := Termicap.DECRPM.Reset;

            when 3 =>
               Status := Termicap.DECRPM.Permanently_Set;

            when 4 =>
               Status := Termicap.DECRPM.Permanently_Reset;

            when others =>
               return FAILURE;
               --  Unreachable: Pm was guarded to 0..4 above; the case arm
               --  satisfies SPARK's complete-coverage requirement.
         end case;

         return (Valid => True, Mode => Mode, Status => Status);
      end;
   end Parse_Mouse_DECRPM_Response;

   ---------------------------------------------------------------------------
   --  Resolve_Best_Encoding (FUNC-MSE-008)
   ---------------------------------------------------------------------------

   function Resolve_Best_Encoding (Caps : Mouse_Capabilities) return Mouse_Encoding is
   begin
      --  If no active probe was performed, the encoding is unknown by definition.
      if not Caps.Probed then
         return Unknown;
      end if;

      --  Preference cascade: richest encoding wins (ADR-0023).
      --  Tracking-mode flags (Supports_Button_Event, Supports_Any_Event) are
      --  intentionally ignored — encoding choice is orthogonal to tracking mode.
      if Caps.Supports_SGR_Pixels then
         return SGR_Pixels;
      elsif Caps.Supports_SGR then
         return SGR;
      elsif Caps.Supports_URXVT then
         return URXVT;
      elsif Caps.Supports_X10 then
         return X10;
      else
         return None;
      end if;
   end Resolve_Best_Encoding;

end Termicap.Mouse;
