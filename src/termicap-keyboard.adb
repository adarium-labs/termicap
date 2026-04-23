-------------------------------------------------------------------------------
--  Termicap.Keyboard - Kitty Keyboard Protocol Detection Types and Parsers (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Bodies of the three pure SPARK parser functions.  The package body carries
--  pragma SPARK_Mode (On) so GNATprove can verify absence of runtime errors
--  and the Global => null contracts for all three parsers (ADR-0013, FUNC-KKB-018).
--
--  Requirements Coverage:
--    - @relation(FUNC-KKB-005): Parse_Kitty_Flags body
--    - @relation(FUNC-KKB-006): Parse_Kitty_Response body
--    - @relation(FUNC-KKB-008): Parse_XTerm_Keyboard_Response body

pragma SPARK_Mode (On);

package body Termicap.Keyboard
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Internal byte constants (used across parser bodies)
   ---------------------------------------------------------------------------

   BYTE_ESC  : constant Byte := 16#1B#;  --  ESC  (0x1B)
   BYTE_CSI  : constant Byte := 16#5B#;  --  '['  (0x5B), CSI introducer
   BYTE_QUES : constant Byte := 16#3F#;  --  '?'  (0x3F)
   BYTE_U    : constant Byte := 16#75#;  --  'u'  (0x75), Kitty terminator
   BYTE_M    : constant Byte := 16#6D#;  --  'm'  (0x6D), XTerm terminator
   BYTE_SEMI : constant Byte := 16#3B#;  --  ';'  (0x3B), XTerm separator
   BYTE_FOUR : constant Byte := 16#34#;  --  '4'  (0x34), XTerm private mode
   BYTE_D0   : constant Byte := 16#30#;  --  '0'  (0x30), ASCII digit 0
   BYTE_D9   : constant Byte := 16#39#;  --  '9'  (0x39), ASCII digit 9

   ---------------------------------------------------------------------------
   --  Parse_Kitty_Flags (FUNC-KKB-005)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-KKB-005): Kitty flags bit-field parser (SPARK Silver)
   function Parse_Kitty_Flags (Flags_Int : Natural) return Kitty_Flags is
   begin
      --  Decompose Flags_Int into five low-order bits using integer arithmetic.
      --  Division by 2**N followed by mod 2 isolates each bit position.
      --  Bits 5 and above are ignored by construction; Natural arithmetic
      --  never raises Constraint_Error on a non-negative operand.
      return
        (Disambiguate_Escape_Codes => (Flags_Int / 1) mod 2 = 1,
         Report_Event_Types        => (Flags_Int / 2) mod 2 = 1,
         Report_Alternate_Keys     => (Flags_Int / 4) mod 2 = 1,
         Report_All_Keys_As_Escape => (Flags_Int / 8) mod 2 = 1,
         Report_Associated_Text    => (Flags_Int / 16) mod 2 = 1);
   end Parse_Kitty_Flags;

   ---------------------------------------------------------------------------
   --  Parse_Kitty_Response (FUNC-KKB-006)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-KKB-006): Kitty response byte sequence parser (SPARK Silver)
   function Parse_Kitty_Response (Buffer : Byte_Array; Length : Natural) return Parse_Result is
      First     : constant Positive := Buffer'First;
      Flags_Int : Natural := 0;
   begin
      --  Step 1: Minimum length check.  A real Kitty response always includes
      --  at least one flag digit (ESC [ ? 0 u is 5 bytes for flags=0), so we
      --  reject any response shorter than 5 bytes.  The bare form ESC [ ? u
      --  (4 bytes) is NOT accepted: it was shown in field testing to produce
      --  false Kitty classifications on terminals that partially echo or leak
      --  probe bytes into the pre-sentinel region.  Per the upstream Kitty
      --  Keyboard Protocol specification, even a "no flags pushed" reply
      --  carries the explicit '0' digit, so requiring a digit loses no real
      --  Kitty-terminal responses.
      if Length < 5 then
         return (Valid => False, Flags_Int => 0);
      end if;

      --  Step 2: Header check — bytes 1..3 must be ESC, '[', '?'.
      if Buffer (First) /= BYTE_ESC or else Buffer (First + 1) /= BYTE_CSI or else Buffer (First + 2) /= BYTE_QUES then
         return (Valid => False, Flags_Int => 0);
      end if;

      --  Step 3: Terminator check — last byte must be 'u'.
      if Buffer (First + Length - 1) /= BYTE_U then
         return (Valid => False, Flags_Int => 0);
      end if;

      --  Step 4: Digit accumulation.
      --  Range is Buffer (First + 3 .. First + Length - 2).
      --  With Length >= 5 the range contains at least one byte; every byte
      --  in it must be an ASCII decimal digit.
      for I in First + 3 .. First + Length - 2 loop
         pragma Loop_Invariant (Flags_Int <= Natural'Last / 10 - 9);
         pragma Loop_Invariant (I in First + 3 .. First + Length - 2);

         if Buffer (I) < BYTE_D0 or else Buffer (I) > BYTE_D9 then
            --  Non-digit byte: malformed response.
            return (Valid => False, Flags_Int => 0);
         end if;

         --  Guard against overflow (astronomically unlikely but enforced).
         if Flags_Int > (Natural'Last - 9) / 10 then
            return (Valid => False, Flags_Int => 0);
         end if;

         Flags_Int := Flags_Int * 10 + Natural (Buffer (I)) - Natural (BYTE_D0);
      end loop;

      return (Valid => True, Flags_Int => Flags_Int);
   end Parse_Kitty_Response;

   ---------------------------------------------------------------------------
   --  Parse_XTerm_Keyboard_Response (FUNC-KKB-008)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-KKB-008): XTerm modifyOtherKeys response parser (SPARK Silver)
   function Parse_XTerm_Keyboard_Response (Buffer : Byte_Array; Length : Natural) return Boolean is
      First     : constant Positive := Buffer'First;
      Has_Digit : Boolean := False;
   begin
      --  Step 1: Minimum length check.  ESC [ ? 4 ; <digit> m is 7 bytes.
      if Length < 7 then
         return False;
      end if;

      --  Step 2: Header check — bytes 1..5 must be ESC, '[', '?', '4', ';'.
      if Buffer (First) /= BYTE_ESC
        or else Buffer (First + 1) /= BYTE_CSI
        or else Buffer (First + 2) /= BYTE_QUES
        or else Buffer (First + 3) /= BYTE_FOUR
        or else Buffer (First + 4) /= BYTE_SEMI
      then
         return False;
      end if;

      --  Step 3: Terminator check — last byte must be 'm'.
      if Buffer (First + Length - 1) /= BYTE_M then
         return False;
      end if;

      --  Step 4: Digit scan — Buffer (First + 5 .. First + Length - 2).
      --  Must be non-empty and all bytes must be ASCII decimal digits.
      for I in First + 5 .. First + Length - 2 loop
         pragma Loop_Invariant (I in First + 5 .. First + Length - 2);

         if Buffer (I) < BYTE_D0 or else Buffer (I) > BYTE_D9 then
            return False;
         end if;
         Has_Digit := True;
      end loop;

      --  The digit range First+5 .. First+Length-2 is non-empty iff Length >= 7,
      --  which is already guaranteed by step 1.  But Has_Digit is set inside the
      --  loop; when Length = 7 the range has exactly one element so Has_Digit
      --  becomes True.  For safety we keep the explicit check.
      return Has_Digit;
   end Parse_XTerm_Keyboard_Response;

end Termicap.Keyboard;
