-------------------------------------------------------------------------------
--  Termicap.Environment - Environment Variable Snapshot
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Immutable snapshot of environment variable bindings with SPARK-provable
--  query operations.
--
--  @description
--  Provides a concrete type Environment that stores a snapshot of environment
--  variable bindings. Once captured, the snapshot is immutable and all query
--  operations are pure functions with Global => null contracts (SPARK Silver).
--
--  Keys are case-normalised (lowercased) at insertion time so that lookups are
--  case-insensitive.  Values are stored verbatim.
--
--  The presence/value distinction required for NO_COLOR compliance is modelled
--  by the map itself: a key that is set to the empty string has an entry in the
--  map, whereas an absent variable has no entry at all.  Callers must use
--  Contains to distinguish these two cases.
--
--  Requirements Coverage:
--    - @relation(FUNC-ENV-001): Environment snapshot type
--    - @relation(FUNC-ENV-002): Environment variable existence check
--    - @relation(FUNC-ENV-003): Environment variable value retrieval
--    - @relation(FUNC-ENV-005): Programmatic environment construction for testing
--    - @relation(FUNC-ENV-006): Case-insensitive value comparison
--    - @relation(FUNC-ENV-007): SPARK Silver provability for query functions
--    - @relation(FUNC-ENV-008): Multi-candidate value matching

with SPARK.Containers.Formal.Unbounded_Hashed_Maps;
with SPARK.Containers.Formal.Unbounded_Vectors;
with SPARK.Containers.Types; use SPARK.Containers.Types;

package Termicap.Environment
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Types (FUNC-ENV-001)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-ENV-001): Immutable environment snapshot type.
   type Environment is private;

   --  @relation(FUNC-ENV-005): Empty environment for programmatic construction.
   EMPTY_ENVIRONMENT : constant Environment;

   ---------------------------------------------------------------------------
   --  Query Operations (FUNC-ENV-002, FUNC-ENV-003, FUNC-ENV-007)
   ---------------------------------------------------------------------------

   --  @summary Check whether an environment variable is present in a snapshot.
   --  @param Env  The environment snapshot to query.
   --  @param Name The variable name (case-insensitive).
   --  @return True if the variable is present in the snapshot, even if its
   --          value is the empty string.
   --  @relation(FUNC-ENV-002): Presence check — required for NO_COLOR compliance
   function Contains (Env : Environment; Name : String) return Boolean
   with Global => null;

   --  @summary Retrieve the value of an environment variable.
   --  @param Env  The environment snapshot to query.
   --  @param Name The variable name (case-insensitive).
   --  @return The variable's value, or "" if the variable is not present.
   --  @relation(FUNC-ENV-003): Value retrieval with safe empty-string default
   function Value (Env : Environment; Name : String) return String
   with Global => null;

   ---------------------------------------------------------------------------
   --  Builder Operations (FUNC-ENV-005)
   ---------------------------------------------------------------------------

   --  @summary Add or replace a variable binding in an environment snapshot.
   --  @param Env   The environment snapshot to modify.
   --  @param Name  The variable name (stored in lowercased form).
   --  @param Value The variable value (stored verbatim).
   --  @relation(FUNC-ENV-005): Programmatic construction for unit testing
   procedure Insert (Env : in out Environment; Name : String; Value : String)
   with Global => null;

   ---------------------------------------------------------------------------
   --  Comparison Utilities (FUNC-ENV-006)
   ---------------------------------------------------------------------------

   --  @summary Case-insensitive equality comparison for environment variable
   --           values.
   --  @param Left  First string operand.
   --  @param Right Second string operand.
   --  @return True if Left and Right are equal when both are lowercased.
   --  @relation(FUNC-ENV-006): Required for COLORTERM / TERM value comparisons
   function Equal_Case_Insensitive (Left : String; Right : String) return Boolean
   with Global => null;

   ---------------------------------------------------------------------------
   --  Multi-Candidate Matching (FUNC-ENV-008)
   ---------------------------------------------------------------------------

   --  String_Vectors provides a SPARK-compatible container for variable-length
   --  lists of String values used by Value_Matches.
   --  With Ada 2022 aggregate syntax callers may write:
   --    Value_Matches (Env, "TERM", ["xterm", "rxvt", "linux"])
   package String_Vectors is new
     SPARK.Containers.Formal.Unbounded_Vectors (Index_Type => Positive, Element_Type => String);

   subtype String_Vector is String_Vectors.Vector;

   --  @summary Check whether an environment variable's value matches any of a
   --           set of candidate strings (case-insensitive comparison).
   --  @param Env        The environment snapshot.
   --  @param Name       The variable name (case-insensitive).
   --  @param Candidates Vector of candidate values to match against.
   --  @return True if the variable is present and its value matches at least
   --          one element of Candidates under case-insensitive comparison.
   --          Returns False when the variable is absent.
   --  @relation(FUNC-ENV-008): Multi-candidate value matching for TERM detection
   function Value_Matches (Env : Environment; Name : String; Candidates : String_Vector) return Boolean
   with Global => null;

private

   ---------------------------------------------------------------------------
   --  Private: helper functions for case-insensitive hash and equality
   ---------------------------------------------------------------------------

   --  These helper specifications are visible to the private part and body.
   --  They operate on the lowercased form of the key so that the map stores
   --  and retrieves keys in a normalised representation.

   function Case_Insensitive_Hash (Key : String) return Hash_Type
   with Global => null;

   function Case_Insensitive_Equal (Left, Right : String) return Boolean
   with Global => null;

   ---------------------------------------------------------------------------
   --  Private: internal map instantiation
   ---------------------------------------------------------------------------

   package Env_Maps is new
     SPARK.Containers.Formal.Unbounded_Hashed_Maps
       (Key_Type        => String,
        Element_Type    => String,
        Hash            => Case_Insensitive_Hash,
        Equivalent_Keys => Case_Insensitive_Equal);

   ---------------------------------------------------------------------------
   --  Private: Environment type completion (FUNC-ENV-001)
   ---------------------------------------------------------------------------

   type Environment is record
      Map : Env_Maps.Map;
   end record;

   EMPTY_ENVIRONMENT : constant Environment := (Map => Env_Maps.Empty_Map);

end Termicap.Environment;
