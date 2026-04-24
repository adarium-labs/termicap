-------------------------------------------------------------------------------
--  Termicap.DECRPM - DEC Private Mode Query Types and Parsing (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (Off);

package body Termicap.DECRPM is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  DECRPM_Query (FUNC-RPM-005)
   ---------------------------------------------------------------------------

   function DECRPM_Query (Mode : Mode_Id) return Byte_Array is
      --  Maximum: 3-byte prefix + 10 digits + 2-byte suffix = 15 bytes.
      MAX_QUERY_LENGTH : constant := 15;
      Buffer    : Byte_Array (1 .. MAX_QUERY_LENGTH);
      Pos       : Positive := 4;
      Temp      : Natural := Mode;
      Rev_Buf   : Byte_Array (1 .. 10);
      Rev_Count : Natural := 0;
   begin
      --  ESC [ ?
      Buffer (1) := 16#1B#;
      Buffer (2) := 16#5B#;
      Buffer (3) := 16#3F#;

      --  Encode decimal digits.
      if Temp = 0 then
         Buffer (Pos) := Byte (Character'Pos ('0'));
         Pos := Pos + 1;
      else
         --  Extract digits in reverse order.
         while Temp > 0 loop
            Rev_Count := Rev_Count + 1;
            Rev_Buf (Rev_Count) := Byte (Character'Pos ('0') + (Temp mod 10));
            Temp := Temp / 10;
         end loop;
         --  Write digits in forward order.
         for I in reverse 1 .. Rev_Count loop
            Buffer (Pos) := Rev_Buf (I);
            Pos := Pos + 1;
         end loop;
      end if;

      --  $ p suffix.
      Buffer (Pos) := 16#24#;
      Buffer (Pos + 1) := 16#70#;
      return Buffer (1 .. Pos + 1);
   end DECRPM_Query;

   ---------------------------------------------------------------------------
   --  Contains_DECRPM_Response (FUNC-RPM-006)
   ---------------------------------------------------------------------------

   function Contains_DECRPM_Response (Bytes : Byte_Array; Length : Natural) return Boolean is
      I            : Natural;
      Mode_Count   : Natural;
      Status_Count : Natural;
   begin
      --  Minimum valid response: ESC [ ? d ; d $ y = 7 bytes.
      if Length < 7 then
         return False;
      end if;

      --  Check prefix: ESC [ ?
      if Bytes (Bytes'First) /= 16#1B#
        or else Bytes (Bytes'First + 1) /= 16#5B#
        or else Bytes (Bytes'First + 2) /= 16#3F#
      then
         return False;
      end if;

      --  Scan mode number digits from position 4 (index Bytes'First + 3).
      I := Bytes'First + 3;
      Mode_Count := 0;
      while I <= Bytes'First + Length - 1 and then Bytes (I) >= 16#30# and then Bytes (I) <= 16#39# loop
         Mode_Count := Mode_Count + 1;
         I := I + 1;
      end loop;
      if Mode_Count = 0 then
         return False;
      end if;

      --  Check semicolon.
      if I > Bytes'First + Length - 1 or else Bytes (I) /= 16#3B# then
         return False;
      end if;
      I := I + 1;

      --  Scan status digits.
      Status_Count := 0;
      while I <= Bytes'First + Length - 1 and then Bytes (I) >= 16#30# and then Bytes (I) <= 16#39# loop
         Status_Count := Status_Count + 1;
         I := I + 1;
      end loop;
      if Status_Count = 0 then
         return False;
      end if;

      --  Check suffix: $ y
      if I + 1 > Bytes'First + Length - 1 then
         return False;
      end if;
      return Bytes (I) = 16#24# and then Bytes (I + 1) = 16#79#;
   end Contains_DECRPM_Response;

   ---------------------------------------------------------------------------
   --  Parse_DECRPM_Response (FUNC-RPM-007)
   ---------------------------------------------------------------------------

   function Parse_DECRPM_Response (Bytes : Byte_Array; Length : Natural) return Mode_Report is
      Default_Report : constant Mode_Report := (Mode => 0, Status => Not_Recognized);
      I              : Natural;
      Ps             : Natural := 0;
      Pm             : Natural := 0;
      Decoded_Status : Mode_Status;
   begin
      if Length = 0 or else not Contains_DECRPM_Response (Bytes, Length) then
         return Default_Report;
      end if;

      --  Skip ESC [ ? (positions Bytes'First .. Bytes'First + 2).
      I := Bytes'First + 3;

      --  Extract mode number (Ps).
      while I <= Bytes'First + Length - 1 and then Bytes (I) >= 16#30# and then Bytes (I) <= 16#39# loop
         if Ps <= (Natural'Last - 9) / 10 then
            Ps := Ps * 10 + (Natural (Bytes (I)) - 16#30#);
         else
            return Default_Report;
         end if;
         I := I + 1;
      end loop;

      --  Ps = 0 is not a valid DEC private mode.
      if Ps = 0 then
         return Default_Report;
      end if;

      --  Skip semicolon.
      I := I + 1;

      --  Extract status code (Pm).
      while I <= Bytes'First + Length - 1 and then Bytes (I) >= 16#30# and then Bytes (I) <= 16#39# loop
         if Pm <= (Natural'Last - 9) / 10 then
            Pm := Pm * 10 + (Natural (Bytes (I)) - 16#30#);
         else
            return Default_Report;
         end if;
         I := I + 1;
      end loop;

      --  Map Pm to Mode_Status.
      Decoded_Status :=
        (case Pm is
           when 0 => Not_Recognized,
           when 1 => Set,
           when 2 => Reset,
           when 3 => Permanently_Set,
           when 4 => Permanently_Reset,
           when others => Not_Recognized);

      return (Mode => Ps, Status => Decoded_Status);
   end Parse_DECRPM_Response;

end Termicap.DECRPM;
