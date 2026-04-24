-------------------------------------------------------------------------------
--  Termicap.XTVERSION - Terminal Identification via XTVERSION (Active)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (On);

package body Termicap.XTVERSION
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Internal Byte Constants
   ---------------------------------------------------------------------------

   BYTE_ESC    : constant Byte := 16#1B#;  --  ESC
   BYTE_DCS_P  : constant Byte := 16#50#;  --  P (DCS introducer second byte)
   BYTE_GT     : constant Byte := 16#3E#;  --  >
   BYTE_PIPE   : constant Byte := 16#7C#;  --  |
   BYTE_ST     : constant Byte := 16#5C#;  --  \ (ST second byte)
   BYTE_BEL    : constant Byte := 16#07#;  --  BEL
   BYTE_LPAREN : constant Byte := 16#28#;  --  (
   BYTE_RPAREN : constant Byte := 16#29#;  --  )
   BYTE_SPACE  : constant Byte := 16#20#;  --  space

   ---------------------------------------------------------------------------
   --  Internal helper: convert a Byte_Array slice to an Ada String
   ---------------------------------------------------------------------------

   function Bytes_To_String (Bytes : Byte_Array; Offset : Positive; Length : Natural) return String
   with Pre => Length > 0 and then Offset >= Bytes'First and then Offset + Length - 1 <= Bytes'Last
   is
      Result : String (1 .. Length);
   begin
      for I in 0 .. Length - 1 loop
         pragma Loop_Invariant (I <= Length - 1);
         Result (I + 1) := Character'Val (Natural (Bytes (Offset + I)));
      end loop;
      return Result;
   end Bytes_To_String;

   ---------------------------------------------------------------------------
   --  DCS Response Recognition (FUNC-XTV-003)
   ---------------------------------------------------------------------------

   function Contains_XTVERSION_Response (Bytes : Byte_Array; Length : Natural) return Boolean is
      First : constant Positive := Bytes'First;
   begin
      --  Minimum valid: 4-byte prefix + 1 payload byte + 1 BEL = 6 bytes
      if Length < 6 then
         return False;
      end if;

      --  Check 4-byte prefix: ESC P > |
      if Bytes (First) /= BYTE_ESC
        or else Bytes (First + 1) /= BYTE_DCS_P
        or else Bytes (First + 2) /= BYTE_GT
        or else Bytes (First + 3) /= BYTE_PIPE
      then
         return False;
      end if;

      --  Scan for ST terminator (ESC \) or BEL starting from First + 5.
      --  First + 4 is the first payload byte; we need at least one before the
      --  terminator, so the scan starts at First + 5.
      for I in First + 5 .. First + Length - 1 loop
         pragma Loop_Invariant (I >= First + 5);
         pragma Loop_Invariant (I <= First + Length - 1);

         if Bytes (I) = BYTE_BEL then
            --  BEL terminator found; at least one payload byte precedes it
            return True;
         elsif I >= First + 6 and then Bytes (I - 1) = BYTE_ESC and then Bytes (I) = BYTE_ST then
            --  ESC \ terminator found; payload byte at First+4 exists
            return True;
         end if;
      end loop;

      return False;
   end Contains_XTVERSION_Response;

   ---------------------------------------------------------------------------
   --  Payload Extraction (FUNC-XTV-004)
   ---------------------------------------------------------------------------

   function Extract_XTV_Payload (Bytes : Byte_Array; Length : Natural) return Payload_Slice is
      First         : constant Positive := Bytes'First;
      Payload_Start : constant Positive := First + 4;
      Last          : constant Positive := First + Length - 1;
      Payload_End   : Natural;
   begin
      --  Find the terminator from the end
      if Bytes (Last) = BYTE_BEL then
         --  BEL: exclude 1 byte
         Payload_End := Last - 1;
      elsif Last >= First + 1 and then Bytes (Last - 1) = BYTE_ESC and then Bytes (Last) = BYTE_ST then
         --  ESC \: exclude 2 bytes
         Payload_End := Last - 2;
      else
         --  Unreachable given precondition (Contains_XTVERSION_Response = True)
         Payload_End := Last;
      end if;

      return (Offset => Payload_Start, Length => Payload_End - Payload_Start + 1);
   end Extract_XTV_Payload;

   ---------------------------------------------------------------------------
   --  Payload Tokenisation (FUNC-XTV-005)
   ---------------------------------------------------------------------------

   function Split_XTV_Payload (Bytes : Byte_Array; Offset : Positive; Length : Natural) return Token_Pair is
      use Ada.Strings.Unbounded;

      Last : constant Natural := Offset + Length - 1;
   begin
      --  Step 1: scan for '(' (Format B: name(version))
      for I in Offset .. Last loop
         pragma Loop_Invariant (I >= Offset);
         pragma Loop_Invariant (I <= Last);

         if Bytes (I) = BYTE_LPAREN then
            --  Found '(': Name = Bytes(Offset .. I-1)
            declare
               Name_Len    : constant Natural := I - Offset;
               Name_Str    : constant String :=
                 (if Name_Len > 0 then Bytes_To_String (Bytes, Offset, Name_Len) else "");
               Version_End : Natural := Last;
            begin
               --  Find closing ')' after '('
               for J in I + 1 .. Last loop
                  pragma Loop_Invariant (J >= I + 1);
                  pragma Loop_Invariant (J <= Last);

                  if Bytes (J) = BYTE_RPAREN then
                     Version_End := J - 1;
                     exit;
                  end if;
               end loop;

               --  Version = Bytes(I+1 .. Version_End)
               declare
                  V_Start     : constant Natural := I + 1;
                  V_Length    : constant Natural := (if Version_End >= V_Start then Version_End - V_Start + 1 else 0);
                  Version_Str : constant String :=
                    (if V_Length > 0 then Bytes_To_String (Bytes, V_Start, V_Length) else "");
               begin
                  return (Name => To_Unbounded_String (Name_Str), Version => To_Unbounded_String (Version_Str));
               end;
            end;
         end if;
      end loop;

      --  Step 2: scan for space (Format A: name version)
      for I in Offset .. Last loop
         pragma Loop_Invariant (I >= Offset);
         pragma Loop_Invariant (I <= Last);

         if Bytes (I) = BYTE_SPACE then
            --  Found space: Name = Bytes(Offset .. I-1), Version = Bytes(I+1 .. Last)
            declare
               Name_Len    : constant Natural := I - Offset;
               Name_Str    : constant String :=
                 (if Name_Len > 0 then Bytes_To_String (Bytes, Offset, Name_Len) else "");
               V_Start     : constant Natural := I + 1;
               V_Length    : constant Natural := (if V_Start <= Last then Last - V_Start + 1 else 0);
               Version_Str : constant String :=
                 (if V_Length > 0 then Bytes_To_String (Bytes, V_Start, V_Length) else "");
            begin
               return (Name => To_Unbounded_String (Name_Str), Version => To_Unbounded_String (Version_Str));
            end;
         end if;
      end loop;

      --  Step 3: no delimiter — entire payload is the name
      return (Name => To_Unbounded_String (Bytes_To_String (Bytes, Offset, Length)), Version => Null_Unbounded_String);
   end Split_XTV_Payload;

   ---------------------------------------------------------------------------
   --  Top-Level Parse Function (FUNC-XTV-006)
   ---------------------------------------------------------------------------

   function Parse_XTVERSION_Response (Bytes : Byte_Array; Length : Natural) return XTVERSION_Result is
   begin
      --  Step 1: reject empty input
      if Length = 0 then
         return (Status => Parse_Error);
      end if;

      --  Step 2: check for valid DCS XTVERSION envelope
      if not Contains_XTVERSION_Response (Bytes, Length) then
         return (Status => Parse_Error);
      end if;

      --  Step 3: extract payload slice
      declare
         Slice : constant Payload_Slice := Extract_XTV_Payload (Bytes, Length);
      begin
         --  Step 4: tokenise name and version from payload
         declare
            Tokens : constant Token_Pair := Split_XTV_Payload (Bytes, Slice.Offset, Slice.Length);
         begin
            --  Step 5: reject empty name
            if Ada.Strings.Unbounded.Length (Tokens.Name) = 0 then
               return (Status => Parse_Error);
            end if;

            --  Step 6: success
            return (Status => Success, Terminal_Name => Tokens.Name, Terminal_Version => Tokens.Version);
         end;
      end;
   end Parse_XTVERSION_Response;

end Termicap.XTVERSION;
