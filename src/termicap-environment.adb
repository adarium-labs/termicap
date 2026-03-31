-------------------------------------------------------------------------------
--  Termicap.Environment - Environment Variable Snapshot (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements pure query and builder operations for the Environment snapshot
--  type using SPARK-compatible formal containers.

package body Termicap.Environment
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Internal helpers: SPARK-compatible lowercase conversion and hashing
   ---------------------------------------------------------------------------

   function To_Lower_Char (C : Character) return Character
   is (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32) else C);

   function To_Lower_String (S : String) return String is
      Result : String := S;
   begin
      for I in Result'Range loop
         Result (I) := To_Lower_Char (Result (I));
      end loop;
      return Result;
   end To_Lower_String;

   ---------------------------------------------------------------------------
   --  Private hash and equality helpers (used by Env_Maps instantiation)
   ---------------------------------------------------------------------------

   function Case_Insensitive_Hash (Key : String) return Hash_Type is
      Lower : constant String := To_Lower_String (Key);
      H     : Hash_Type := 5381;
   begin
      for I in Lower'Range loop
         H := H * 33 + Hash_Type (Character'Pos (Lower (I)));
      end loop;
      return H;
   end Case_Insensitive_Hash;

   function Case_Insensitive_Equal (Left, Right : String) return Boolean is
   begin
      return To_Lower_String (Left) = To_Lower_String (Right);
   end Case_Insensitive_Equal;

   ---------------------------------------------------------------------------
   --  Query Operations (FUNC-ENV-002, FUNC-ENV-003)
   ---------------------------------------------------------------------------

   function Contains (Env : Environment; Name : String) return Boolean is
      Lower_Name : constant String := To_Lower_String (Name);
   begin
      return Env_Maps.Contains (Env.Map, Lower_Name);
   end Contains;

   function Value (Env : Environment; Name : String) return String is
      Lower_Name : constant String := To_Lower_String (Name);
      Cursor     : Env_Maps.Cursor;
   begin
      Cursor := Env_Maps.Find (Env.Map, Lower_Name);
      if Env_Maps.Has_Element (Env.Map, Cursor) then
         return Env_Maps.Element (Env.Map, Cursor);
      else
         return "";
      end if;
   end Value;

   ---------------------------------------------------------------------------
   --  Builder Operations (FUNC-ENV-005)
   ---------------------------------------------------------------------------

   procedure Insert (Env : in out Environment; Name : String; Value : String) is
      Lower_Name : constant String := To_Lower_String (Name);
   begin
      Env_Maps.Include (Env.Map, Lower_Name, Value);
   end Insert;

   ---------------------------------------------------------------------------
   --  Comparison Utilities (FUNC-ENV-006)
   ---------------------------------------------------------------------------

   function Equal_Case_Insensitive (Left : String; Right : String) return Boolean is
   begin
      return To_Lower_String (Left) = To_Lower_String (Right);
   end Equal_Case_Insensitive;

   ---------------------------------------------------------------------------
   --  Multi-Candidate Matching (FUNC-ENV-008)
   ---------------------------------------------------------------------------

   function Value_Matches (Env : Environment; Name : String; Candidates : String_Vector) return Boolean is
   begin
      if not Contains (Env, Name) then
         return False;
      end if;

      declare
         Val : constant String := Value (Env, Name);
      begin
         for I in String_Vectors.First_Index (Candidates) .. String_Vectors.Last_Index (Candidates) loop
            if Equal_Case_Insensitive (Val, String_Vectors.Element (Candidates, I)) then
               return True;
            end if;
         end loop;
      end;

      return False;
   end Value_Matches;

end Termicap.Environment;
