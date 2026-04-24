-------------------------------------------------------------------------------
--  Termicap.Color.BG_Query - Background / Foreground Color Query (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (On);

package body Termicap.Color.BG_Query
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Internal Byte Constants
   ---------------------------------------------------------------------------

   BYTE_r    : constant Byte := 16#72#;  --  'r'
   BYTE_g    : constant Byte := 16#67#;  --  'g'
   BYTE_b    : constant Byte := 16#62#;  --  'b'
   BYTE_a    : constant Byte := 16#61#;  --  'a'
   BYTE_CLON : constant Byte := 16#3A#;  --  ':'
   BYTE_SEMI : constant Byte := 16#3B#;  --  ';'
   BYTE_SLSH : constant Byte := 16#2F#;  --  '/'
   BYTE_ESC  : constant Byte := 16#1B#;  --  ESC
   BYTE_OSC  : constant Byte := 16#5D#;  --  ']'
   BYTE_ST   : constant Byte := 16#5C#;  --  '\'
   BYTE_BEL  : constant Byte := 16#07#;  --  BEL
   BYTE_DIG0 : constant Byte := 16#30#;  --  '0'
   BYTE_DIG9 : constant Byte := 16#39#;  --  '9'
   BYTE_DIG1 : constant Byte := 16#31#;  --  '1'
   BYTE_A_UP : constant Byte := 16#41#;  --  'A' (uppercase)
   BYTE_F_UP : constant Byte := 16#46#;  --  'F' (uppercase)
   BYTE_A_LO : constant Byte := 16#61#;  --  'a' (lowercase)
   BYTE_F_LO : constant Byte := 16#66#;  --  'f' (lowercase)

   --  Sentinel value indicating an invalid hex digit
   INVALID_HEX : constant := 16;

   ---------------------------------------------------------------------------
   --  Internal helper: convert a byte to its hex digit value (0..15)
   --  Returns INVALID_HEX (16) for non-hex bytes.
   ---------------------------------------------------------------------------

   function Hex_Digit_Value (B : Byte) return Natural with Post => Hex_Digit_Value'Result <= INVALID_HEX is
   begin
      if B >= BYTE_DIG0 and then B <= BYTE_DIG9 then
         return Natural (B) - Natural (BYTE_DIG0);
      elsif B >= BYTE_A_UP and then B <= BYTE_F_UP then
         return Natural (B) - Natural (BYTE_A_UP) + 10;
      elsif B >= BYTE_A_LO and then B <= BYTE_F_LO then
         return Natural (B) - Natural (BYTE_A_LO) + 10;
      else
         return INVALID_HEX;
      end if;
   end Hex_Digit_Value;

   ---------------------------------------------------------------------------
   --  Query Sequence Selection (FUNC-BGC-005)
   ---------------------------------------------------------------------------

   function Query_Sequence (Kind : Query_Kind) return Byte_Array is
   begin
      case Kind is
         when Background =>
            return OSC_BG_QUERY;

         when Foreground =>
            return OSC_FG_QUERY;
      end case;
   end Query_Sequence;

   ---------------------------------------------------------------------------
   --  Hex Channel Parsing (FUNC-BGC-009)
   ---------------------------------------------------------------------------

   function Parse_Hex_Channel (Bytes : Byte_Array; Start : Natural; Length : Natural) return Channel_Result is
      --  Use a wider type to accumulate without overflow:
      --  max 4 hex digits = 0xFFFF = 65535, fits in Natural.
      --  But intermediate * 16 for 4 digits could be up to 65535 * 16 before
      --  the last addition, so use a type that can hold 0xFFFF safely.
      subtype Acc_Type is Natural range 0 .. 65_535;

      Acc   : Acc_Type := 0;
      Digit : Natural;
      Value : Natural;
   begin
      --  Precondition guarantees Length in 1 .. MAX_CHANNEL_LENGTH
      --  and Start + Length - 1 <= Bytes'Last

      for I in Start .. Start + Length - 1 loop
         pragma Loop_Invariant (Acc <= 65_535);
         pragma Loop_Invariant (I >= Start);
         pragma Loop_Invariant (I <= Start + Length - 1);

         Digit := Hex_Digit_Value (Bytes (I));
         if Digit = INVALID_HEX then
            return (Success => False);
         end if;

         --  Accumulate: Acc * 16 + Digit
         --  Maximum intermediate: after 3 digits Acc <= 0xFFF = 4095,
         --  then Acc * 16 <= 65520, then + 15 = 65535 which fits in Acc_Type.
         Acc := Acc * 16 + Digit;
      end loop;

      --  Normalize to 8-bit based on length
      case Length is
         when 1 =>
            --  0xF -> 0xFF: multiply by 17 (max: 15 * 17 = 255)
            Value := Acc * 17;

         when 2 =>
            --  0xFF -> 0xFF: use as-is (max: 255)
            Value := Acc;

         when 3 =>
            --  0xFFF -> 0xFF: divide by 16 (max: 4095 / 16 = 255)
            Value := Acc / 16;

         when 4 =>
            --  0xFFFF -> 0xFF: divide by 256, take high byte (max: 65535 / 256 = 255)
            Value := Acc / 256;

         when others =>
            --  Cannot happen given precondition; defensive
            return (Success => False);
      end case;

      if Value > 255 then
         return (Success => False);
      end if;

      return (Success => True, Value => Value);
   end Parse_Hex_Channel;

   ---------------------------------------------------------------------------
   --  RGB Prefix Detection (FUNC-BGC-008)
   ---------------------------------------------------------------------------

   procedure Find_RGB_Prefix (Bytes : Byte_Array; Length : Natural; Offset : out Natural; Found : out Boolean) is
   begin
      Offset := Bytes'First;
      Found := False;

      --  Need at least 4 bytes for "rgb:" and at least 1 byte after the colon
      if Length < 5 then
         return;
      end if;

      --  Scan for "rgb:" (4 bytes: 0x72 0x67 0x62 0x3A)
      --  The sequence must start at or before Bytes'First + Length - 5
      --  so that 4 bytes fit and there is at least 1 byte after the colon.
      for I in Bytes'First .. Bytes'First + Length - 5 loop
         pragma Loop_Invariant (I >= Bytes'First);
         pragma Loop_Invariant (I <= Bytes'First + Length - 5);

         if Bytes (I) = BYTE_r
           and then Bytes (I + 1) = BYTE_g
           and then Bytes (I + 2) = BYTE_b
           and then Bytes (I + 3) = BYTE_CLON
         then
            --  Found "rgb:" — offset points to byte after the colon
            Offset := I + 4;
            Found := True;
            return;
         end if;
      end loop;

      --  Not found with "rgb:"; try "rgba:" (5 bytes)
      --  Need at least 5 bytes for "rgba:" and at least 1 byte after the colon
      if Length < 6 then
         return;
      end if;

      for I in Bytes'First .. Bytes'First + Length - 6 loop
         pragma Loop_Invariant (I >= Bytes'First);
         pragma Loop_Invariant (I <= Bytes'First + Length - 6);

         if Bytes (I) = BYTE_r
           and then Bytes (I + 1) = BYTE_g
           and then Bytes (I + 2) = BYTE_b
           and then Bytes (I + 3) = BYTE_a
           and then Bytes (I + 4) = BYTE_CLON
         then
            --  Found "rgba:" — offset points to byte after the colon
            Offset := I + 5;
            Found := True;
            return;
         end if;
      end loop;
   end Find_RGB_Prefix;

   ---------------------------------------------------------------------------
   --  RGB Channel Splitting (FUNC-BGC-008)
   ---------------------------------------------------------------------------

   procedure Split_RGB_Channels
     (Bytes            : Byte_Array;
      Start            : Natural;
      Length           : Natural;
      Ch_R, Ch_G, Ch_B : out Channel_Slice;
      Success          : out Boolean)
   is
      --  End of the scan range (inclusive), absolute index
      Last : constant Natural := Start + Length - 1;

      --  Positions of the first and second slash (absolute indices), 0 = not found
      Slash1_Pos : Natural := 0;
      Slash2_Pos : Natural := 0;

      --  Length of each channel
      R_Len : Natural;
      G_Len : Natural;
      B_Len : Natural;
   begin
      --  Initialize outputs defensively
      Ch_R := (Start => Start, Length => 1);
      Ch_G := (Start => Start, Length => 1);
      Ch_B := (Start => Start, Length => 1);
      Success := False;

      --  Scan for the first slash
      for I in Start .. Last loop
         pragma Loop_Invariant (I >= Start);
         pragma Loop_Invariant (I <= Last);

         if Bytes (I) = BYTE_SLSH then
            Slash1_Pos := I;
            exit;
         end if;
      end loop;

      if Slash1_Pos = 0 then
         --  No slash found
         return;
      end if;

      --  Scan for the second slash (starting after Slash1_Pos)
      if Slash1_Pos >= Last then
         --  No room for a second slash
         return;
      end if;

      for I in Slash1_Pos + 1 .. Last loop
         pragma Loop_Invariant (I >= Slash1_Pos + 1);
         pragma Loop_Invariant (I <= Last);

         if Bytes (I) = BYTE_SLSH then
            Slash2_Pos := I;
            exit;
         end if;
      end loop;

      if Slash2_Pos = 0 then
         --  Only one slash found
         return;
      end if;

      --  Compute channel lengths
      --  R channel: Start .. Slash1_Pos - 1
      --  G channel: Slash1_Pos + 1 .. Slash2_Pos - 1
      --  B channel: Slash2_Pos + 1 .. Last (or until 3rd slash, whichever is first)

      --  Validate that Slash1_Pos > Start so R length is not zero
      if Slash1_Pos <= Start then
         return;
      end if;

      R_Len := Slash1_Pos - Start;

      --  Validate that Slash2_Pos > Slash1_Pos + 1 so G length is not zero
      if Slash2_Pos <= Slash1_Pos + 1 then
         return;
      end if;

      G_Len := Slash2_Pos - Slash1_Pos - 1;

      --  B channel: from Slash2_Pos + 1 to end (or next slash)
      --  Validate there is at least one byte after Slash2_Pos
      if Slash2_Pos >= Last then
         return;
      end if;

      --  Find end of B channel: scan for 3rd slash (optional)
      declare
         B_Start : constant Natural := Slash2_Pos + 1;
         B_End   : Natural := Last;
      begin
         for I in B_Start .. Last loop
            pragma Loop_Invariant (I >= B_Start);
            pragma Loop_Invariant (I <= Last);

            if Bytes (I) = BYTE_SLSH then
               B_End := I - 1;
               exit;
            end if;
         end loop;

         if B_End < B_Start then
            return;
         end if;

         B_Len := B_End - B_Start + 1;

         --  Validate all channel lengths are in 1 .. MAX_CHANNEL_LENGTH
         if R_Len not in 1 .. MAX_CHANNEL_LENGTH
           or else G_Len not in 1 .. MAX_CHANNEL_LENGTH
           or else B_Len not in 1 .. MAX_CHANNEL_LENGTH
         then
            return;
         end if;

         Ch_R := (Start => Start, Length => R_Len);
         Ch_G := (Start => Slash1_Pos + 1, Length => G_Len);
         Ch_B := (Start => B_Start, Length => B_Len);
         Success := True;
      end;
   end Split_RGB_Channels;

   ---------------------------------------------------------------------------
   --  RGB Response Parsing (FUNC-BGC-007)
   ---------------------------------------------------------------------------

   function Parse_RGB_Response (Bytes : Byte_Array; Length : Natural) return Parse_Result is
      Prefix_Offset    : Natural;
      Prefix_Found     : Boolean;
      Ch_R, Ch_G, Ch_B : Channel_Slice;
      Split_OK         : Boolean;
      R_Result         : Channel_Result;
      G_Result         : Channel_Result;
      B_Result         : Channel_Result;
   begin
      if Length = 0 then
         return (Success => False);
      end if;

      --  Step 1: find "rgb:" or "rgba:" prefix
      Find_RGB_Prefix (Bytes, Length, Prefix_Offset, Prefix_Found);

      if not Prefix_Found then
         return (Success => False);
      end if;

      --  Step 2: compute remaining length after the prefix
      --  Prefix_Offset is the absolute index of the first channel byte.
      --  The scan range is Bytes'First .. Bytes'First + Length - 1.
      --  Remaining bytes: Prefix_Offset .. Bytes'First + Length - 1
      declare
         End_Index  : constant Natural := Bytes'First + Length - 1;
         Rem_Length : Natural;
      begin
         if Prefix_Offset > End_Index then
            return (Success => False);
         end if;

         Rem_Length := End_Index - Prefix_Offset + 1;

         if Rem_Length = 0 then
            return (Success => False);
         end if;

         --  Precondition check for Split_RGB_Channels:
         --  Start >= Bytes'First: Prefix_Offset >= Bytes'First + 4 (from postcondition)
         --  Start + Length - 1 <= Bytes'Last: Prefix_Offset + Rem_Length - 1 = End_Index
         --    = Bytes'First + Length - 1 <= Bytes'Last (from Parse_RGB_Response precondition)

         --  Step 3: split into three channels
         Split_RGB_Channels
           (Bytes   => Bytes,
            Start   => Prefix_Offset,
            Length  => Rem_Length,
            Ch_R    => Ch_R,
            Ch_G    => Ch_G,
            Ch_B    => Ch_B,
            Success => Split_OK);

         if not Split_OK then
            return (Success => False);
         end if;

         --  Steps 4-6: parse each hex channel
         R_Result := Parse_Hex_Channel (Bytes, Ch_R.Start, Ch_R.Length);
         if not R_Result.Success then
            return (Success => False);
         end if;

         G_Result := Parse_Hex_Channel (Bytes, Ch_G.Start, Ch_G.Length);
         if not G_Result.Success then
            return (Success => False);
         end if;

         B_Result := Parse_Hex_Channel (Bytes, Ch_B.Start, Ch_B.Length);
         if not B_Result.Success then
            return (Success => False);
         end if;

         return (Success => True, Color => (Red => R_Result.Value, Green => G_Result.Value, Blue => B_Result.Value));
      end;
   end Parse_RGB_Response;

   ---------------------------------------------------------------------------
   --  OSC Header Stripping (FUNC-BGC-010)
   ---------------------------------------------------------------------------

   function Strip_OSC_Header (Bytes : Byte_Array; Length : Natural; Kind : Query_Kind) return Strip_Result is
      --  Minimum: ESC ] 1 X ; + 1 payload byte = 6 bytes
      MIN_LENGTH : constant := 6;

      Expected_Digit : Byte;
      Payload_Start  : Positive;
      Payload_End    : Natural;
      Payload_Len    : Natural;
   begin
      --  Step 1: need at least 6 bytes
      if Length < MIN_LENGTH then
         return (Success => False);
      end if;

      --  Step 2: verify ESC ] at positions 1 and 2 (Bytes'First and Bytes'First + 1)
      if Bytes (Bytes'First) /= BYTE_ESC or else Bytes (Bytes'First + 1) /= BYTE_OSC then
         return (Success => False);
      end if;

      --  Step 3: determine expected digit at position 4 (Bytes'First + 3)
      case Kind is
         when Background =>
            Expected_Digit := BYTE_DIG1;  --  '1' for OSC 11

         when Foreground =>
            Expected_Digit := BYTE_DIG0;  --  '0' for OSC 10
      end case;

      --  Step 4: verify '1' at position 3 and Expected_Digit at position 4
      --  and ';' at position 5
      if Bytes (Bytes'First + 2) /= BYTE_DIG1
        or else Bytes (Bytes'First + 3) /= Expected_Digit
        or else Bytes (Bytes'First + 4) /= BYTE_SEMI
      then
         return (Success => False);
      end if;

      --  Step 5: payload starts at position 6 (Bytes'First + 5)
      Payload_Start := Bytes'First + 5;

      --  Step 6: scan backwards for terminator
      --  Last byte of the valid range is Bytes'First + Length - 1
      declare
         Last : constant Natural := Bytes'First + Length - 1;
      begin
         Payload_End := Last;

         --  Check for ESC \ (two bytes at end)
         if Length >= 2 and then Bytes (Last - 1) = BYTE_ESC and then Bytes (Last) = BYTE_ST then
            --  Exclude the two terminator bytes
            if Last < 2 then
               return (Success => False);
            end if;
            Payload_End := Last - 2;

         elsif Bytes (Last) = BYTE_BEL then
            --  Exclude the single BEL byte
            Payload_End := Last - 1;
         end if;

         --  Step 7: compute payload length
         if Payload_End < Payload_Start then
            --  Payload_Length would be zero or negative
            return (Success => False);
         end if;

         Payload_Len := Payload_End - Payload_Start + 1;

         if Payload_Len = 0 then
            return (Success => False);
         end if;

         return (Success => True, Offset => Payload_Start, Payload_Length => Payload_Len);
      end;
   end Strip_OSC_Header;

   ---------------------------------------------------------------------------
   --  COLORFGBG Parsing (FUNC-BGC-011)
   ---------------------------------------------------------------------------

   function Parse_Colorfgbg (Value : String) return Colorfgbg_Result is
      FAIL : constant Colorfgbg_Result := (Success => False, Foreground => 0, Background => 0);

      First_Semi : Natural := 0;
      Last_Semi  : Natural := 0;

      FG_Val  : Natural := 0;
      BG_Val  : Natural := 0;
      Has_Dig : Boolean := False;
   begin
      if Value'Length = 0 then
         return FAIL;
      end if;

      --  Step 1: find first semicolon
      for I in Value'First .. Value'Last loop
         pragma Loop_Invariant (I >= Value'First);
         pragma Loop_Invariant (I <= Value'Last);

         if Value (I) = ';' then
            First_Semi := I;
            exit;
         end if;
      end loop;

      if First_Semi = 0 then
         return FAIL;
      end if;

      --  Step 2: find last semicolon (scan forward, keep updating)
      Last_Semi := First_Semi;

      for I in First_Semi + 1 .. Value'Last loop
         pragma Loop_Invariant (I >= First_Semi + 1);
         pragma Loop_Invariant (I <= Value'Last);
         pragma Loop_Invariant (Last_Semi >= First_Semi);
         pragma Loop_Invariant (Last_Semi < I);

         if Value (I) = ';' then
            Last_Semi := I;
         end if;
      end loop;

      --  Step 3: parse FG: Value(Value'First .. First_Semi - 1)
      if First_Semi <= Value'First then
         --  Empty FG field (semicolon is the first character)
         return FAIL;
      end if;

      Has_Dig := False;
      FG_Val := 0;

      for I in Value'First .. First_Semi - 1 loop
         pragma Loop_Invariant (I >= Value'First);
         pragma Loop_Invariant (I <= First_Semi - 1);

         declare
            C : constant Character := Value (I);
         begin
            if C < '0' or else C > '9' then
               return FAIL;
            end if;
            --  Guard against overflow before multiply
            if FG_Val > 1_000 then
               return FAIL;
            end if;
            FG_Val := FG_Val * 10 + (Character'Pos (C) - Character'Pos ('0'));
            Has_Dig := True;
         end;
      end loop;

      if not Has_Dig or else FG_Val > 15 then
         return FAIL;
      end if;

      --  Step 4: parse BG: Value(Last_Semi + 1 .. Value'Last)
      if Last_Semi >= Value'Last then
         --  Empty BG field (semicolon is the last character)
         return FAIL;
      end if;

      Has_Dig := False;
      BG_Val := 0;

      for I in Last_Semi + 1 .. Value'Last loop
         pragma Loop_Invariant (I >= Last_Semi + 1);
         pragma Loop_Invariant (I <= Value'Last);

         declare
            C : constant Character := Value (I);
         begin
            if C < '0' or else C > '9' then
               return FAIL;
            end if;
            if BG_Val > 1_000 then
               return FAIL;
            end if;
            BG_Val := BG_Val * 10 + (Character'Pos (C) - Character'Pos ('0'));
            Has_Dig := True;
         end;
      end loop;

      if not Has_Dig or else BG_Val > 15 then
         return FAIL;
      end if;

      return (Success => True, Foreground => FG_Val, Background => BG_Val);
   end Parse_Colorfgbg;

   ---------------------------------------------------------------------------
   --  ANSI Color Index to RGB (FUNC-BGC-012)
   ---------------------------------------------------------------------------

   function Ansi_To_RGB (Index : ANSI_Index) return RGB is
   begin
      return ANSI_COLOR_TABLE (Index);
   end Ansi_To_RGB;

end Termicap.Color.BG_Query;
