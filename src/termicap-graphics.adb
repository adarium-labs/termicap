-------------------------------------------------------------------------------
--  Termicap.Graphics - Sixel / Kitty Graphics Detection Types (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Body of the pure SPARK function Parse_Kitty_APC_Response.
--  The package body carries pragma SPARK_Mode (On) so that GNATprove can
--  verify absence of runtime errors and the Global => null contract for the
--  parser (mixed SPARK pattern, ADR-0013, FUNC-SXL-018).
--
--  This is a Phase 3 stub: Parse_Kitty_APC_Response contains a minimal
--  correct implementation sufficient for compilation and SPARK proof.
--  The full detection logic lives in Termicap.Graphics.IO bodies (Phase 6).
--
--  Requirements Coverage:
--    - @relation(FUNC-SXL-011): Parse_Kitty_APC_Response body

with Termicap.Version;

package body Termicap.Graphics
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Internal byte constants
   ---------------------------------------------------------------------------

   BYTE_ESC  : constant Byte := 16#1B#;  --  ESC      (0x1B)
   BYTE_USCO : constant Byte := 16#5F#;  --  _        (0x5F, APC introducer byte 2)
   BYTE_G    : constant Byte := Character'Pos ('G');  --  G   (0x47)
   BYTE_BEL  : constant Byte := 16#07#;  --  BEL      (0x07, alternate APC terminator)
   BYTE_BSLS : constant Byte := 16#5C#;  --  \        (0x5C, ST second byte)

   ---------------------------------------------------------------------------
   --  Parse_Kitty_APC_Response (FUNC-SXL-011)
   ---------------------------------------------------------------------------

   function Parse_Kitty_APC_Response (Buffer : Byte_Array; Length : Natural) return APC_Parse_Result is
      --  Minimum APC G frame:  ESC _ G ESC \  = 5 bytes
      MIN_FRAME_LEN : constant := 5;

      Base : constant Positive := Buffer'First;

      --  Return True when the slice [From .. From + Len - 1] contains Needle.
      --  Caller must ensure From + Len - 1 <= Buffer'Last.
      function Contains_Substring (From : Positive; Len : Natural; Needle : String) return Boolean
      with Pre => From >= Base and then From + Len - 1 <= Base + Length - 1 and then Needle'Length > 0;

      function Contains_Substring (From : Positive; Len : Natural; Needle : String) return Boolean is
         N_Len : constant Positive := Needle'Length;
         I     : Positive;
         J     : Natural;
         Match : Boolean;
      begin
         if Len < N_Len then
            return False;
         end if;
         I := From;
         while I <= From + Len - N_Len loop
            Match := True;
            J := 0;
            while J < N_Len loop
               if Buffer (I + J) /= Byte (Character'Pos (Needle (Needle'First + J))) then
                  Match := False;
                  exit;
               end if;
               J := J + 1;
            end loop;
            if Match then
               return True;
            end if;
            I := I + 1;
         end loop;
         return False;
      end Contains_Substring;

      I : Natural;
   begin
      --  Fast-exit: buffer too short to contain even the minimum APC G frame.
      if Length < MIN_FRAME_LEN then
         return Not_Present;
      end if;

      --  Linear scan for APC G introducer: ESC _ G (0x1B 0x5F 0x47).
      I := Base;
      while I <= Base + Length - MIN_FRAME_LEN loop

         --  Look for APC introducer ESC _
         if Buffer (I) = BYTE_ESC and then Buffer (I + 1) = BYTE_USCO then
            --  Check for Kitty graphics identifier 'G'
            if Buffer (I + 2) = BYTE_G then
               --  Found APC G; scan for the terminator (ESC \ or BEL).
               declare
                  Params_Start : constant Positive := I + 3;
                  End_Pos      : Natural := 0;
                  K            : Natural;
               begin
                  K := Params_Start;
                  while K <= Base + Length - 1 loop
                     if Buffer (K) = BYTE_BEL then
                        End_Pos := K;
                        exit;
                     elsif Buffer (K) = BYTE_ESC and then K + 1 <= Base + Length - 1 and then Buffer (K + 1) = BYTE_BSLS
                     then
                        End_Pos := K;
                        exit;
                     end if;
                     K := K + 1;
                  end loop;

                  if End_Pos > 0 then
                     --  Params_Start..End_Pos-1 is the parameter region.
                     declare
                        Params_Len : constant Natural := End_Pos - Params_Start;
                     begin
                        if Params_Len > 0 and then Contains_Substring (Params_Start, Params_Len, "OK") then
                           return OK;
                        elsif Params_Len > 0 and then Contains_Substring (Params_Start, Params_Len, "EINVAL") then
                           return Error;
                        else
                           --  APC G found but contains neither OK nor EINVAL;
                           --  treat as Error (unexpected response).
                           return Error;
                        end if;
                     end;
                  end if;
                  --  Terminator not found before end of buffer; keep scanning.
               end;
            end if;
         end if;

         I := I + 1;
      end loop;

      --  No APC G envelope found.
      return Not_Present;
   end Parse_Kitty_APC_Response;

   ---------------------------------------------------------------------------
   --  Parse_Kitty_Version (FUNC-SXL-003, FUNC-HYP-022)
   ---------------------------------------------------------------------------
   --  Delegates to Termicap.Version.Parse (ADR-0036) and encodes the result
   --  as MAJOR * 10_000 + MINOR * 100 + PATCH.
   --  Returns 0 on any parse failure, preserving the previous "unknown" sentinel.

   function Parse_Kitty_Version (Version_String : String) return Natural is
      V  : Termicap.Version.Version;
      Ok : Boolean;
   begin
      Termicap.Version.Parse (Version_String, V, Ok);
      if not Ok or else V.Count = 0 then
         return 0;
      end if;
      declare
         Major : constant Natural := (if V.Count >= 1 then V.Parts (1) else 0);
         Minor : constant Natural := (if V.Count >= 2 then V.Parts (2) else 0);
         Patch : constant Natural := (if V.Count >= 3 then V.Parts (3) else 0);
      begin
         return Major * 10_000 + Minor * 100 + Patch;
      end;
   end Parse_Kitty_Version;

end Termicap.Graphics;
