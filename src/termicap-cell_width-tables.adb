-------------------------------------------------------------------------------
--  Termicap.Cell_Width.Tables - Binary Search Lookup (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements the binary search over a sorted Width_Table and provides
--  the Get_Table dispatch function.
--
--  @description
--  Cell_Width_In_Table performs O(log N) binary search over a Width_Table
--  sorted by First with non-overlapping ranges.  All proof obligations are
--  discharged by GNATprove at Gold level via loop invariants and the exit
--  guards at the array boundaries.
--
--  Requirements Coverage:
--    - @relation(FUNC-CWM-003): Binary search algorithm
--    - @relation(FUNC-CWM-001): Get_Table table dispatch
--    - @relation(FUNC-CWM-014): SPARK Gold provability

package body Termicap.Cell_Width.Tables
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Table Dispatch (FUNC-CWM-001)
   ---------------------------------------------------------------------------

   function Get_Table (Version : Table_Version) return Width_Table is
   begin
      case Version is
         when Unicode_3  =>
            return TABLE_UNICODE_3;

         when Unicode_13 =>
            return TABLE_UNICODE_13;

         when Unicode_16 =>
            return TABLE_UNICODE_16;
      end case;
   end Get_Table;

   ---------------------------------------------------------------------------
   --  Binary Search Lookup (FUNC-CWM-003, FUNC-CWM-014, FUNC-CWM-015)
   ---------------------------------------------------------------------------

   function Cell_Width_In_Table
     (Codepoint : Unicode_Scalar_Value; Table : Width_Table)
      return Cell_Width_Value
   is
      Low  : Table_Index := Table'First;
      High : Table_Index := Table'Last;
      Mid  : Table_Index;
   begin
      --  Early exit: codepoint beyond all table entries
      if Codepoint > Table (Table'Last).Last then
         return 1;
      end if;

      --  Early exit: codepoint before all table entries
      if Codepoint < Table (Table'First).First then
         return 1;
      end if;

      while Low <= High loop
         pragma
           Loop_Invariant (Low in Table'Range and then High in Table'Range);
         pragma
           Loop_Invariant
             (for all I in Table'First .. Low - 1 =>
                Table (I).Last < Codepoint);
         pragma
           Loop_Invariant
             (for all I in High + 1 .. Table'Last =>
                Table (I).First > Codepoint);
         pragma Loop_Variant (Decreases => High - Low);

         Mid := Low + (High - Low) / 2;

         if Codepoint < Table (Mid).First then
            exit when Mid = Table'First;
            High := Mid - 1;
         elsif Codepoint > Table (Mid).Last then
            exit when Mid = Table'Last;
            Low := Mid + 1;
         else
            --  Codepoint is within [First, Last] -> return stored width
            return Table (Mid).Width;
         end if;
      end loop;

      --  No matching range found: default to narrow (width 1)
      return 1;
   end Cell_Width_In_Table;

end Termicap.Cell_Width.Tables;
