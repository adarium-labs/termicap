-------------------------------------------------------------------------------
--  Termicap.Version - Shared Dotted-Numeric Version Utility
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Shared utility package for parsing and comparing dotted-numeric version
--  strings (e.g. "0.50.0", "3.1.0", "357").
--
--  @description
--  Provides a fixed-size, allocation-free Version record suitable for SPARK
--  Silver verification, plus Parse, Compare, and Make helpers.
--
--  The parser accepts only non-negative integer components separated by dots
--  (no pre-release tags, no build metadata).  Any other input causes Parse to
--  return False.  Up to MAX_VERSION_COMPONENTS (8) components are accepted;
--  a version with more components is rejected.
--
--  The comparator uses lexicographic component ordering with the rule that a
--  shorter prefix that matches all its components is Less_Than the longer
--  version (e.g. "0.50" < "0.50.0").  This is documented as FUNC-HYP-013
--  comparison rule 2.
--
--  Requirements Coverage:
--    - @relation(FUNC-HYP-013): Version type, Parse, Compare, Version_Ordering

package Termicap.Version
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Capacity Constant (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Maximum number of version components supported by Parse.
   --  @description Sufficient for every version in the known-good table
   --  (the longest observed is "1.72.0" — 3 components).  Bounded at 8 to
   --  keep the Version record stack-allocatable and SPARK-provable.
   --  @relation(FUNC-HYP-013): Bounded version-component array
   MAX_VERSION_COMPONENTS : constant := 8;

   ---------------------------------------------------------------------------
   --  Index and Component Array Types (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Index subtype for version component arrays.
   --  @description Used as both the loop variable and array index in Parse
   --  and Compare.  The range 1 .. MAX_VERSION_COMPONENTS bounds all loops
   --  for SPARK Silver provability.
   subtype Component_Index is Positive range 1 .. MAX_VERSION_COMPONENTS;

   --  @summary Fixed-size array of version components (non-negative integers).
   --  @description Indexed by Component_Index.  Elements at indices greater
   --  than Count are zero and are not considered by Compare.
   type Component_Array is array (Component_Index) of Natural;

   ---------------------------------------------------------------------------
   --  Version Record (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Bounded, allocation-free representation of a dotted-numeric version.
   --  @description Count holds the number of valid components (0 when the version
   --  is uninitialised or ZERO_VERSION).  Parts holds the component values at
   --  indices 1 .. Count; elements beyond Count are zero.
   --  @relation(FUNC-HYP-013): Version record type
   type Version is record
      Count : Natural := 0;
      Parts : Component_Array := [others => 0];
   end record;

   ---------------------------------------------------------------------------
   --  Sentinel Constants (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Canonical zero / uninitialised version value.
   --  @description Used as the initial value of Result in Parse on failure, and
   --  as the "floor" entry for emulators that support hyperlinks in any version.
   --  @relation(FUNC-HYP-013): ZERO_VERSION constant
   ZERO_VERSION : constant Version := (Count => 0, Parts => [others => 0]);

   ---------------------------------------------------------------------------
   --  Version_Ordering Enumeration (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Three-way comparison result.
   --  @description Less_Than, Equal, and Greater_Than correspond to the standard
   --  lexicographic ordering of two Version values.
   --  @relation(FUNC-HYP-013): Version_Ordering enumeration
   type Version_Ordering is (Less_Than, Equal, Greater_Than);

   ---------------------------------------------------------------------------
   --  Parse Function (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Parse a dotted-numeric version string into a Version record.
   --  @description Accepts strings of the form "N" or "N.N" or "N.N.N..." where
   --  each N is a sequence of one or more ASCII decimal digits (0-9) and
   --  1 <= component count <= MAX_VERSION_COMPONENTS.
   --
   --  Returns True and populates Result when the input is valid.
   --  Returns False and sets Result to ZERO_VERSION when the input is malformed
   --  (empty string, leading dot, trailing dot, consecutive dots, non-digit
   --  character, integer overflow, or more than MAX_VERSION_COMPONENTS parts).
   --
   --  The function is total (never raises) and has no global state access.
   --
   --  @param S       The input version string.
   --  @param Result  Populated with the parsed version on success; ZERO_VERSION
   --                 on failure.
   --  @param Success Set to True when S is a valid dotted-numeric version;
   --                 False otherwise.
   --  @relation(FUNC-HYP-013): Version parsing
   --
   --  Note: declared as a procedure rather than a function returning Boolean
   --  because SPARK 2014 prohibits "out" mode parameters in functions [E0015].
   procedure Parse (S : String; Result : out Version; Success : out Boolean)
   with
     SPARK_Mode => On,
     Global => null,
     Post => (if Success then Result.Count >= 1 and then Result.Count <= MAX_VERSION_COMPONENTS else Result.Count = 0);

   ---------------------------------------------------------------------------
   --  Compare Function (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Lexicographic component-wise comparison of two Version values.
   --  @description Compares Left and Right component by component.  When one
   --  version has fewer components than the other and all compared components
   --  are equal, the shorter version is Less_Than the longer (FUNC-HYP-013
   --  comparison rule 2).  A single-component version (e.g. "357") is handled
   --  identically to multi-component versions (rule 3).
   --
   --  The function is total, never raises, and has no global state access.
   --
   --  @param Left  First version operand.
   --  @param Right Second version operand.
   --  @return Less_Than, Equal, or Greater_Than.
   --  @relation(FUNC-HYP-013): Version comparison
   function Compare (Left, Right : Version) return Version_Ordering
   with
     SPARK_Mode => On,
     Global => null,
     Post =>
       (if Left.Count = 0 and then Right.Count = 0 then Compare'Result = Equal)
       and then (if Compare'Result = Equal then Compare (Left => Right, Right => Left) = Equal)
       and then (if Compare'Result = Less_Than then Compare (Left => Right, Right => Left) = Greater_Than)
       and then (if Compare'Result = Greater_Than then Compare (Left => Right, Right => Left) = Less_Than);

   ---------------------------------------------------------------------------
   --  Make Constructor (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  @summary Construct a Version from explicit component values (1–3 components).
   --  @description Convenience constructor for test code and known-good table entries
   --  that avoids string parsing.  Major, Minor, and Patch default to 0; passing only
   --  Major yields a single-component version (Count = 1), passing Major and Minor
   --  yields Count = 2, and passing all three yields Count = 3.
   --
   --  The Has_Minor and Has_Patch flags drive the Count calculation.  When
   --  Has_Minor is False, Minor and Patch are ignored even if non-zero.
   --
   --  @param Major     First (required) component.
   --  @param Minor     Second component (used only when Has_Minor = True).
   --  @param Patch     Third component (used only when Has_Patch = True).
   --  @param Has_Minor Include the Minor component in the result (default True).
   --  @param Has_Patch Include the Patch component in the result (default True).
   --  @return Version with Count = 1, 2, or 3 depending on the Has_* flags.
   --  @relation(FUNC-HYP-013): Version construction helper
   function Make
     (Major     : Natural;
      Minor     : Natural := 0;
      Patch     : Natural := 0;
      Has_Minor : Boolean := True;
      Has_Patch : Boolean := True) return Version
   with
     SPARK_Mode => On,
     Global => null,
     Post => Make'Result.Count >= 1 and then Make'Result.Count <= 3 and then Make'Result.Parts (1) = Major;

end Termicap.Version;
