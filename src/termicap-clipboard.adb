-------------------------------------------------------------------------------
--  Termicap.Clipboard - OSC 52 Clipboard Detection Types (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Implementation of Parse_OSC52_Response (FUNC-C52-008).  The function scans
--  a raw byte buffer for an OSC 52 response envelope of the form:
--    ESC ] 52 ; <selection> ; <base64-or-empty> BEL
--    or: ESC ] 52 ; <selection> ; <base64-or-empty> ESC \
--  and classifies the result as Valid_Response, Not_Present, or Malformed.
--
--  The package body carries pragma SPARK_Mode (On) so that GNATprove can
--  verify absence of runtime errors and the Global => null contract for the
--  parser (mixed SPARK pattern, ADR-0013, FUNC-C52-018).
--
--  Requirements Coverage:
--    - @relation(FUNC-C52-008): Parse_OSC52_Response body

pragma SPARK_Mode (On);

package body Termicap.Clipboard
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Parse_OSC52_Response (FUNC-C52-008)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-C52-008): OSC 52 response parser (SPARK Silver)
   function Parse_OSC52_Response (Buffer : Byte_Array; Length : Natural) return OSC52_Parse_Result is
      --  Minimum OSC 52 response: ESC ] 52 ; c ; BEL = 8 bytes.
      --  We need at least 5 bytes to see ESC ] 5 2 ; before scanning.
      MIN_SCAN_LEN : constant := 5;

      Base : constant Positive := Buffer'First;
      Last : constant Natural := Base + Length - 1;

      I : Natural;
      J : Natural;

      --  Byte constants for the OSC 52 introducer.
      BYTE_ESC       : constant Byte := 16#1B#;  --  ESC  (0x1B)
      BYTE_OSC       : constant Byte := 16#5D#;  --  ]    (0x5D, OSC introducer)
      BYTE_5         : constant Byte := Character'Pos ('5');
      BYTE_2         : constant Byte := Character'Pos ('2');
      BYTE_SEMICOLON : constant Byte := Character'Pos (';');
      BYTE_BEL       : constant Byte := 16#07#;  --  BEL  (0x07)
      BYTE_BSLS      : constant Byte := 16#5C#;  --  \    (0x5C, ST second byte)

      Semicolons : Natural;
   begin
      --  Fast-exit: buffer too short to contain any meaningful OSC 52 pattern.
      if Length < MIN_SCAN_LEN then
         return Not_Present;
      end if;

      --  Linear scan for OSC 52 introducer: ESC ] 5 2 (0x1B 0x5D 0x35 0x32).
      I := Base;
      while I <= Last - (MIN_SCAN_LEN - 1) loop

         if Buffer (I)     = BYTE_ESC
           and then Buffer (I + 1) = BYTE_OSC
           and then Buffer (I + 2) = BYTE_5
           and then Buffer (I + 3) = BYTE_2
         then
            --  Found OSC 52 introducer at I.  Now scan for the terminator.
            --  Expect: ; <selection> ; <payload> <terminator>
            --  Count semicolons; require >= 2 before terminator.
            Semicolons := 0;
            J := I + 4;

            while J <= Last loop
               if Buffer (J) = BYTE_SEMICOLON then
                  Semicolons := Semicolons + 1;
               end if;

               --  BEL terminator
               if Buffer (J) = BYTE_BEL then
                  if Semicolons >= 2 then
                     return Valid_Response;
                  else
                     return Malformed;
                  end if;
               end if;

               --  ST terminator: ESC \ (0x1B 0x5C)
               if Buffer (J) = BYTE_ESC and then J + 1 <= Last and then Buffer (J + 1) = BYTE_BSLS then
                  if Semicolons >= 2 then
                     return Valid_Response;
                  else
                     return Malformed;
                  end if;
               end if;

               J := J + 1;
            end loop;

            --  Reached end of valid region without a terminator.
            return Malformed;
         end if;

         I := I + 1;
      end loop;

      --  No OSC 52 introducer found.
      return Not_Present;
   end Parse_OSC52_Response;

end Termicap.Clipboard;
