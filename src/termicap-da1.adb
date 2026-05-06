-------------------------------------------------------------------------------
--  Termicap.DA1 - Primary Device Attributes Capability Types and Interpretation (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Implementation of Interpret_DA1 (FUNC-DA1-004).  The function converts a
--  parsed DA1_Params record into a structured DA1_Capabilities value by decoding
--  the VT conformance level from the first parameter and scanning the remaining
--  parameters for known capability flags.
--
--  Requirements Coverage:
--    - @relation(FUNC-DA1-004): Interpret_DA1 pure SPARK function

package body Termicap.DA1
  with SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Interpret_DA1 (FUNC-DA1-004)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-DA1-004): Interpret_DA1 pure SPARK function
   function Interpret_DA1 (Params : Termicap.OSC.Parsing.DA1_Params) return DA1_Capabilities is
      Result : DA1_Capabilities := (Supported => False, Level => Unknown, Flags => [others => False]);
   begin
      --  Step 1: Empty response -> return unsupported default.
      if Params.Count = 0 then
         return Result;
      end if;

      --  Step 2: A non-empty response means the terminal responded.
      Result.Supported := True;

      --  Step 3: Decode first parameter as VT conformance level.
      Result.Level :=
        (case Params.Values (1) is
           when 62 => VT200,
           when 63 => VT300,
           when 64 => VT400,
           when 65 => VT500,
           when others => Unknown);

      --  Step 4: Scan remaining parameters for capability flags.
      for I in 2 .. Params.Count loop
         case Params.Values (I) is
            when 2 =>
               Result.Flags (Printer) := True;

            when 3 =>
               Result.Flags (ReGIS_Graphics) := True;

            when 4 =>
               Result.Flags (Sixel_Graphics) := True;

            when 6 =>
               Result.Flags (Selective_Erase) := True;

            when 8 =>
               Result.Flags (User_Defined_Keys) := True;

            when 18 =>
               Result.Flags (Windowing) := True;

            when 22 =>
               Result.Flags (ANSI_Color) := True;

            when 28 =>
               Result.Flags (Rectangular_Editing) := True;

            when 52 =>
               Result.Flags (Clipboard_Access) := True;  --  OSC 52 clipboard (FUNC-C52-003)

            when others =>
               null;  --  Silently ignore unrecognised Ps values.
         end case;
      end loop;

      --  Step 5: Return the populated record.
      return Result;
   end Interpret_DA1;

end Termicap.DA1;
