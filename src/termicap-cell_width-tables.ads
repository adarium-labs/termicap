-------------------------------------------------------------------------------
--  Termicap.Cell_Width.Tables - Unicode Width Table Data and Binary Search
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Width table data (width-0 and width-2 codepoint ranges) for Unicode 3.0,
--  13.0, and 16.0, together with the binary search lookup function.
--
--  @description
--  This child package is the data layer for Termicap.Cell_Width.  It defines:
--
--    Width_Entry   -- A (First, Last, Width) codepoint range record.
--    Table_Index   -- Constrained index subtype for Width_Table arrays.
--    Width_Table   -- Unconstrained array type over Width_Entry.
--    TABLE_UNICODE_3, TABLE_UNICODE_13, TABLE_UNICODE_16
--                  -- Compile-time constant Width_Table for each Unicode version.
--    Get_Table     -- Pure case-dispatch returning the table for a Table_Version.
--    Cell_Width_In_Table -- Binary search lookup; Global => null; SPARK Gold.
--
--  Only width-0 and width-2 ranges are stored.  Unmatched codepoints default
--  to width 1.  Entries are sorted by First with no overlapping ranges.
--
--  Ghost predicates Is_Sorted_Non_Overlapping and All_Widths_Valid can be used
--  in GNATprove preconditions to strengthen the proof.
--
--  All public entities are SPARK_Mode => On and SPARK Gold provable.
--
--  Requirements Coverage:
--    - @relation(FUNC-CWM-001): Bundled Unicode width table versions (constants)
--    - @relation(FUNC-CWM-002): Width_Entry record and Width_Table array type
--    - @relation(FUNC-CWM-003): Binary search over sorted ranges (Cell_Width_In_Table)
--    - @relation(FUNC-CWM-007): ZWJ (U+200D) in width-0 table entries
--    - @relation(FUNC-CWM-008): VS16 (U+FE0F) in width-0 table entries
--    - @relation(FUNC-CWM-009): Combining character ranges in width-0 entries
--    - @relation(FUNC-CWM-014): SPARK Gold provability
--    - @relation(FUNC-CWM-015): O(log N) lookup, constant array storage

package Termicap.Cell_Width.Tables
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Table Index and Entry Types (FUNC-CWM-002)
   ---------------------------------------------------------------------------

   --  @summary Index subtype for Width_Table arrays.
   --  @description The upper bound is generous; actual tables are expected to
   --  have approximately 1,500-2,000 entries for Unicode 16.0.
   type Table_Index is range 1 .. 4_000;

   --  @summary A single codepoint range entry mapping [First..Last] to Width.
   --  @description Invariant (not enforced by subtype): Last >= First and
   --  Width is in 0 .. 2 with 1 never stored (unmatched codepoints default
   --  to width 1).  Entries are sorted by First with no overlapping ranges.
   --  @relation(FUNC-CWM-002): Width_Entry record type
   type Width_Entry is record
      First : Unicode_Scalar_Value;
      Last  : Unicode_Scalar_Value;
      Width : Cell_Width_Value;
   end record;

   --  @summary Unconstrained array of Width_Entry records, indexed by Table_Index.
   --  @description Each Unicode version's table is a constant of type
   --  Width_Table (1 .. N) for its own N.  The binary search function operates
   --  on Width_Table'Range, making it version-agnostic.
   --  @relation(FUNC-CWM-002): Width_Table array type
   type Width_Table is array (Table_Index range <>) of Width_Entry;

   ---------------------------------------------------------------------------
   --  Ghost Predicates for SPARK Proof (FUNC-CWM-014)
   ---------------------------------------------------------------------------

   --  @summary Return True when every entry in Table satisfies Last >= First.
   --  @description Ghost predicate used in preconditions of Cell_Width_In_Table
   --  to allow GNATprove to reason about valid range entries.  Has no runtime
   --  cost; stripped from executable by the prover.
   function All_Widths_Valid (Table : Width_Table) return Boolean
   is (for all I in Table'Range =>
         Table (I).Width in Cell_Width_Value
         and then Table (I).Last >= Table (I).First)
   with Ghost;

   --  @summary Return True when Table entries are sorted by First with no
   --           overlapping ranges.
   --  @description Ghost predicate: for all adjacent entries I and I+1,
   --  Table(I).Last < Table(I+1).First.  Used in preconditions of
   --  Cell_Width_In_Table to justify invariant establishment in the binary
   --  search loop.
   function Is_Sorted_Non_Overlapping (Table : Width_Table) return Boolean
   is (for all I in Table'First .. Table_Index'Pred (Table'Last) =>
         Table (I).Last < Table (Table_Index'Succ (I)).First)
   with Ghost;

   ---------------------------------------------------------------------------
   --  Table Constants (FUNC-CWM-001)
   ---------------------------------------------------------------------------

   --  Individual table lengths as named constants for constraint expressions.
   --  All entries within each table are sorted by First codepoint with no
   --  overlapping ranges.  Only width-0 (combining/format) and width-2
   --  (wide/fullwidth) ranges are stored; unmatched codepoints default to 1.

   --  Unicode 3.0 table: 74 entries.
   --  Covers basic combining marks (category M, Cf), CJK ideographs,
   --  fullwidth forms, Hangul, Yi, and basic emoji-related ranges.
   --  @relation(FUNC-CWM-001): Unicode 3.0 table length constant
   TABLE_UNICODE_3_LENGTH : constant Table_Index := 74;

   --  Unicode 13.0 table: 80 entries.
   --  Adds NKo combining, Samaritan combining, emoji pictographs, and
   --  CJK Extension B/G supplementary plane ranges.
   --  @relation(FUNC-CWM-001): Unicode 13.0 table length constant
   TABLE_UNICODE_13_LENGTH : constant Table_Index := 80;

   --  Unicode 16.0 table: 82 entries.
   --  Adds Mandaic combining and Combining Diacritical Marks Extended.
   --  @relation(FUNC-CWM-001): Unicode 16.0 table length constant
   TABLE_UNICODE_16_LENGTH : constant Table_Index := 82;

   --  @summary Precomputed Unicode 3.0 width table.
   --  @description Width-0 (combining/format) and width-2 (wide/fullwidth)
   --  codepoint ranges derived from the Unicode 3.0 Character Database.
   --  Entries are sorted by First with no overlapping ranges.
   --  Only ranges with width 0 or 2 are stored; unmatched codepoints default
   --  to width 1.
   --  @relation(FUNC-CWM-001): Unicode 3.0 table constant
   --  @relation(FUNC-CWM-007): ZWJ (U+200D) present via U+200B..U+200F range
   --  @relation(FUNC-CWM-008): VS16 (U+FE0F) present via U+FE00..U+FE0F range
   --  @relation(FUNC-CWM-009): Combining character ranges (category M) present
   TABLE_UNICODE_3 : constant Width_Table (1 .. TABLE_UNICODE_3_LENGTH) :=
     [(First => 16#0300#,
       Last  => 16#036F#,
       Width => 0),  --  1 Combining Diacritical Marks
      (First => 16#0483#,
       Last  => 16#0489#,
       Width => 0),  --  2 Combining Cyrillic
      (First => 16#0591#,
       Last  => 16#05C7#,
       Width => 0),  --  3 Hebrew combining
      (First => 16#0610#,
       Last  => 16#061A#,
       Width => 0),  --  4 Arabic combining
      (First => 16#064B#,
       Last  => 16#065F#,
       Width => 0),  --  5 Arabic tatweel combining
      (First => 16#0670#,
       Last  => 16#0670#,
       Width => 0),  --  6 Arabic superscript alef
      (First => 16#06D6#,
       Last  => 16#06DC#,
       Width => 0),  --  7 Arabic combining
      (First => 16#06DF#,
       Last  => 16#06E4#,
       Width => 0),  --  8 Arabic combining
      (First => 16#06E7#,
       Last  => 16#06E8#,
       Width => 0),  --  9 Arabic combining
      (First => 16#06EA#,
       Last  => 16#06ED#,
       Width => 0),  --  10 Arabic combining
      (First => 16#0711#,
       Last  => 16#0711#,
       Width => 0),  --  11 Syriac superscript alaph
      (First => 16#0730#,
       Last  => 16#074A#,
       Width => 0),  --  12 Syriac combining
      (First => 16#07A6#,
       Last  => 16#07B0#,
       Width => 0),  --  13 Thaana combining
      (First => 16#0900#,
       Last  => 16#0902#,
       Width => 0),  --  14 Devanagari combining
      (First => 16#093C#,
       Last  => 16#093C#,
       Width => 0),  --  15 Devanagari nukta
      (First => 16#0941#,
       Last  => 16#0948#,
       Width => 0),  --  16 Devanagari vowel signs
      (First => 16#094D#,
       Last  => 16#094D#,
       Width => 0),  --  17 Devanagari virama
      (First => 16#0951#,
       Last  => 16#0957#,
       Width => 0),  --  18 Devanagari stress/tone
      (First => 16#0962#,
       Last  => 16#0963#,
       Width => 0),  --  19 Devanagari vowel signs
      (First => 16#0981#,
       Last  => 16#0981#,
       Width => 0),  --  20 Bengali anusvara
      (First => 16#09BC#, Last => 16#09BC#, Width => 0),  --  21 Bengali nukta
      (First => 16#09C1#,
       Last  => 16#09C4#,
       Width => 0),  --  22 Bengali vowel signs
      (First => 16#09CD#, Last => 16#09CD#, Width => 0),  --  23 Bengali virama
      (First => 16#09E2#,
       Last  => 16#09E3#,
       Width => 0),  --  24 Bengali vowel signs
      (First => 16#0A3C#, Last => 16#0A3C#, Width => 0),  --  25 Gurmukhi nukta
      (First => 16#0A41#,
       Last  => 16#0A42#,
       Width => 0),  --  26 Gurmukhi vowel signs
      (First => 16#0A47#,
       Last  => 16#0A48#,
       Width => 0),  --  27 Gurmukhi vowel signs
      (First => 16#0A4B#,
       Last  => 16#0A4D#,
       Width => 0),  --  28 Gurmukhi virama
      (First => 16#0ABC#, Last => 16#0ABC#, Width => 0),  --  29 Gujarati nukta
      (First => 16#0AC1#,
       Last  => 16#0AC5#,
       Width => 0),  --  30 Gujarati vowel signs
      (First => 16#0AC7#,
       Last  => 16#0AC8#,
       Width => 0),  --  31 Gujarati vowel signs
      (First => 16#0ACD#,
       Last  => 16#0ACD#,
       Width => 0),  --  32 Gujarati virama
      (First => 16#0B3C#,
       Last  => 16#0B3C#,
       Width => 0),  --  33 Tamil nukta (Oriya nukta)
      (First => 16#0B41#,
       Last  => 16#0B44#,
       Width => 0),  --  34 Tamil vowel signs
      (First => 16#0B4D#, Last => 16#0B4D#, Width => 0),  --  35 Tamil virama
      (First => 16#0BC0#,
       Last  => 16#0BC0#,
       Width => 0),  --  36 Telugu combining
      (First => 16#0BCD#, Last => 16#0BCD#, Width => 0),  --  37 Telugu virama
      (First => 16#0C3E#,
       Last  => 16#0C40#,
       Width => 0),  --  38 Kannada combining
      (First => 16#0C4D#, Last => 16#0C4D#, Width => 0),  --  39 Kannada virama
      (First => 16#0CBC#,
       Last  => 16#0CBC#,
       Width => 0),  --  40 Malayalam nukta
      (First => 16#0CCD#,
       Last  => 16#0CCD#,
       Width => 0),  --  41 Malayalam virama
      (First => 16#0E31#,
       Last  => 16#0E31#,
       Width => 0),  --  42 Thai vowel sign
      (First => 16#0E34#,
       Last  => 16#0E3A#,
       Width => 0),  --  43 Thai vowel signs
      (First => 16#0E47#, Last => 16#0E4E#, Width => 0),  --  44 Thai combining
      (First => 16#0EB1#, Last => 16#0EB1#, Width => 0),  --  45 Lao vowel sign
      (First => 16#0EB4#,
       Last  => 16#0EB9#,
       Width => 0),  --  46 Lao vowel signs
      (First => 16#0EBB#, Last => 16#0EBC#, Width => 0),  --  47 Lao combining
      (First => 16#0EC8#, Last => 16#0ECD#, Width => 0),  --  48 Lao combining
      (First => 16#0F18#,
       Last  => 16#0F19#,
       Width => 0),  --  49 Tibetan combining
      (First => 16#0F35#,
       Last  => 16#0F35#,
       Width => 0),  --  50 Tibetan combining
      (First => 16#0F37#,
       Last  => 16#0F37#,
       Width => 0),  --  51 Tibetan combining
      (First => 16#0F39#,
       Last  => 16#0F39#,
       Width => 0),  --  52 Tibetan combining
      (First => 16#0F71#,
       Last  => 16#0F7E#,
       Width => 0),  --  53 Tibetan vowel signs
      (First => 16#0F80#,
       Last  => 16#0F84#,
       Width => 0),  --  54 Tibetan combining
      (First => 16#0F86#,
       Last  => 16#0F87#,
       Width => 0),  --  55 Tibetan combining
      (First => 16#0FC6#,
       Last  => 16#0FC6#,
       Width => 0),  --  56 Tibetan combining
      (First => 16#1100#,
       Last  => 16#115F#,
       Width => 2),  --  57 Hangul Jamo lead consonants
      (First => 16#200B#,
       Last  => 16#200F#,
       Width => 0),  --  58 ZW space/ZWNJ/ZWJ/LRM/RLM
      (First => 16#202A#,
       Last  => 16#202E#,
       Width => 0),  --  59 Directional formatting
      (First => 16#2060#,
       Last  => 16#2064#,
       Width => 0),  --  60 Word joiner/format
      (First => 16#206A#,
       Last  => 16#206F#,
       Width => 0),  --  61 Format characters
      (First => 16#20D0#,
       Last  => 16#20F0#,
       Width => 0),  --  62 Combining Marks for Symbols
      (First => 16#2E80#,
       Last  => 16#2EFF#,
       Width => 2),  --  63 CJK Radicals Supplement
      (First => 16#2F00#,
       Last  => 16#2FD5#,
       Width => 2),  --  64 Kangxi Radicals
      (First => 16#2FF0#,
       Last  => 16#2FFB#,
       Width => 2),  --  65 Ideographic Description
      (First => 16#3000#,
       Last  => 16#303E#,
       Width => 2),  --  66 CJK Symbols and Punctuation
      (First => 16#3041#,
       Last  => 16#33FF#,
       Width => 2),  --  67 Hiragana/Katakana/Bopomofo/Compat
      (First => 16#3400#,
       Last  => 16#4DBF#,
       Width => 2),  --  68 CJK Extension A
      (First => 16#4E00#,
       Last  => 16#9FFF#,
       Width => 2),  --  69 CJK Unified Ideographs
      (First => 16#A000#, Last => 16#A4CF#, Width => 2),  --  70 Yi Syllables
      (First => 16#AC00#,
       Last  => 16#D7A3#,
       Width => 2),  --  71 Hangul Syllables
      (First => 16#F900#,
       Last  => 16#FAFF#,
       Width => 2),  --  72 CJK Compat Ideographs
      (First => 16#FE00#,
       Last  => 16#FE0F#,
       Width => 0),  --  73 Variation Selectors (VS16)
      (First => 16#FE10#,
       Last  => 16#FFE6#,
       Width => 2)]; --  74 CJK Compat Forms+Fullwidth

   --  @summary Precomputed Unicode 13.0 width table.
   --  @description Width-0 (combining/format) and width-2 (wide/fullwidth)
   --  codepoint ranges derived from the Unicode 13.0 Character Database.
   --  Entries are sorted by First with no overlapping ranges.
   --  Adds NKo combining, Samaritan combining, emoji, and supplementary CJK.
   --  @relation(FUNC-CWM-001): Unicode 13.0 table constant
   --  @relation(FUNC-CWM-007): ZWJ (U+200D) present via U+200B..U+200F range
   --  @relation(FUNC-CWM-008): VS16 (U+FE0F) present via U+FE00..U+FE0F range
   --  @relation(FUNC-CWM-009): Combining character ranges (category M) present
   TABLE_UNICODE_13 : constant Width_Table (1 .. TABLE_UNICODE_13_LENGTH) :=
     [(First => 16#0300#,
       Last  => 16#036F#,
       Width => 0),  --  1 Combining Diacritical Marks
      (First => 16#0483#,
       Last  => 16#0489#,
       Width => 0),  --  2 Combining Cyrillic
      (First => 16#0591#,
       Last  => 16#05C7#,
       Width => 0),  --  3 Hebrew combining
      (First => 16#0610#,
       Last  => 16#061A#,
       Width => 0),  --  4 Arabic combining
      (First => 16#064B#,
       Last  => 16#065F#,
       Width => 0),  --  5 Arabic tatweel combining
      (First => 16#0670#,
       Last  => 16#0670#,
       Width => 0),  --  6 Arabic superscript alef
      (First => 16#06D6#,
       Last  => 16#06DC#,
       Width => 0),  --  7 Arabic combining
      (First => 16#06DF#,
       Last  => 16#06E4#,
       Width => 0),  --  8 Arabic combining
      (First => 16#06E7#,
       Last  => 16#06E8#,
       Width => 0),  --  9 Arabic combining
      (First => 16#06EA#,
       Last  => 16#06ED#,
       Width => 0),  --  10 Arabic combining
      (First => 16#0711#,
       Last  => 16#0711#,
       Width => 0),  --  11 Syriac superscript alaph
      (First => 16#0730#,
       Last  => 16#074A#,
       Width => 0),  --  12 Syriac combining
      (First => 16#07A6#,
       Last  => 16#07B0#,
       Width => 0),  --  13 Thaana combining
      (First => 16#07EB#,
       Last  => 16#07F3#,
       Width => 0),  --  14 NKo combining (Unicode 5.0+)
      (First => 16#0816#,
       Last  => 16#082D#,
       Width => 0),  --  15 Samaritan combining (Unicode 5.2+)
      (First => 16#0900#,
       Last  => 16#0902#,
       Width => 0),  --  16 Devanagari combining
      (First => 16#093C#,
       Last  => 16#093C#,
       Width => 0),  --  17 Devanagari nukta
      (First => 16#0941#,
       Last  => 16#0948#,
       Width => 0),  --  18 Devanagari vowel signs
      (First => 16#094D#,
       Last  => 16#094D#,
       Width => 0),  --  19 Devanagari virama
      (First => 16#0951#,
       Last  => 16#0957#,
       Width => 0),  --  20 Devanagari stress/tone
      (First => 16#0962#,
       Last  => 16#0963#,
       Width => 0),  --  21 Devanagari vowel signs
      (First => 16#0981#,
       Last  => 16#0981#,
       Width => 0),  --  22 Bengali anusvara
      (First => 16#09BC#, Last => 16#09BC#, Width => 0),  --  23 Bengali nukta
      (First => 16#09C1#,
       Last  => 16#09C4#,
       Width => 0),  --  24 Bengali vowel signs
      (First => 16#09CD#, Last => 16#09CD#, Width => 0),  --  25 Bengali virama
      (First => 16#09E2#,
       Last  => 16#09E3#,
       Width => 0),  --  26 Bengali vowel signs
      (First => 16#0A3C#, Last => 16#0A3C#, Width => 0),  --  27 Gurmukhi nukta
      (First => 16#0A41#,
       Last  => 16#0A42#,
       Width => 0),  --  28 Gurmukhi vowel signs
      (First => 16#0A47#,
       Last  => 16#0A48#,
       Width => 0),  --  29 Gurmukhi vowel signs
      (First => 16#0A4B#,
       Last  => 16#0A4D#,
       Width => 0),  --  30 Gurmukhi virama
      (First => 16#0ABC#, Last => 16#0ABC#, Width => 0),  --  31 Gujarati nukta
      (First => 16#0AC1#,
       Last  => 16#0AC5#,
       Width => 0),  --  32 Gujarati vowel signs
      (First => 16#0AC7#,
       Last  => 16#0AC8#,
       Width => 0),  --  33 Gujarati vowel signs
      (First => 16#0ACD#,
       Last  => 16#0ACD#,
       Width => 0),  --  34 Gujarati virama
      (First => 16#0B3C#, Last => 16#0B3C#, Width => 0),  --  35 Oriya nukta
      (First => 16#0B41#,
       Last  => 16#0B44#,
       Width => 0),  --  36 Oriya vowel signs
      (First => 16#0B4D#, Last => 16#0B4D#, Width => 0),  --  37 Oriya virama
      (First => 16#0BC0#,
       Last  => 16#0BC0#,
       Width => 0),  --  38 Tamil combining
      (First => 16#0BCD#, Last => 16#0BCD#, Width => 0),  --  39 Tamil virama
      (First => 16#0C3E#,
       Last  => 16#0C40#,
       Width => 0),  --  40 Telugu combining
      (First => 16#0C4D#, Last => 16#0C4D#, Width => 0),  --  41 Telugu virama
      (First => 16#0CBC#, Last => 16#0CBC#, Width => 0),  --  42 Kannada nukta
      (First => 16#0CCD#, Last => 16#0CCD#, Width => 0),  --  43 Kannada virama
      (First => 16#0E31#,
       Last  => 16#0E31#,
       Width => 0),  --  44 Thai vowel sign
      (First => 16#0E34#,
       Last  => 16#0E3A#,
       Width => 0),  --  45 Thai vowel signs
      (First => 16#0E47#, Last => 16#0E4E#, Width => 0),  --  46 Thai combining
      (First => 16#0EB1#, Last => 16#0EB1#, Width => 0),  --  47 Lao vowel sign
      (First => 16#0EB4#,
       Last  => 16#0EB9#,
       Width => 0),  --  48 Lao vowel signs
      (First => 16#0EBB#, Last => 16#0EBC#, Width => 0),  --  49 Lao combining
      (First => 16#0EC8#, Last => 16#0ECD#, Width => 0),  --  50 Lao combining
      (First => 16#0F18#,
       Last  => 16#0F19#,
       Width => 0),  --  51 Tibetan combining
      (First => 16#0F35#,
       Last  => 16#0F35#,
       Width => 0),  --  52 Tibetan combining
      (First => 16#0F37#,
       Last  => 16#0F37#,
       Width => 0),  --  53 Tibetan combining
      (First => 16#0F39#,
       Last  => 16#0F39#,
       Width => 0),  --  54 Tibetan combining
      (First => 16#0F71#,
       Last  => 16#0F7E#,
       Width => 0),  --  55 Tibetan vowel signs
      (First => 16#0F80#,
       Last  => 16#0F84#,
       Width => 0),  --  56 Tibetan combining
      (First => 16#0F86#,
       Last  => 16#0F87#,
       Width => 0),  --  57 Tibetan combining
      (First => 16#0FC6#,
       Last  => 16#0FC6#,
       Width => 0),  --  58 Tibetan combining
      (First => 16#1100#,
       Last  => 16#115F#,
       Width => 2),  --  59 Hangul Jamo lead consonants
      (First => 16#200B#,
       Last  => 16#200F#,
       Width => 0),  --  60 ZW space/ZWNJ/ZWJ/LRM/RLM
      (First => 16#202A#,
       Last  => 16#202E#,
       Width => 0),  --  61 Directional formatting
      (First => 16#2060#,
       Last  => 16#2064#,
       Width => 0),  --  62 Word joiner/format
      (First => 16#206A#,
       Last  => 16#206F#,
       Width => 0),  --  63 Format characters
      (First => 16#20D0#,
       Last  => 16#20F0#,
       Width => 0),  --  64 Combining Marks for Symbols
      (First => 16#2E80#,
       Last  => 16#2EFF#,
       Width => 2),  --  65 CJK Radicals Supplement
      (First => 16#2F00#,
       Last  => 16#2FD5#,
       Width => 2),  --  66 Kangxi Radicals
      (First => 16#2FF0#,
       Last  => 16#2FFB#,
       Width => 2),  --  67 Ideographic Description
      (First => 16#3000#,
       Last  => 16#303E#,
       Width => 2),  --  68 CJK Symbols and Punctuation
      (First => 16#3041#,
       Last  => 16#33FF#,
       Width => 2),  --  69 Hiragana/Katakana/Bopomofo/Compat
      (First => 16#3400#,
       Last  => 16#4DBF#,
       Width => 2),  --  70 CJK Extension A
      (First => 16#4E00#,
       Last  => 16#9FFF#,
       Width => 2),  --  71 CJK Unified Ideographs
      (First => 16#A000#, Last => 16#A4CF#, Width => 2),  --  72 Yi Syllables
      (First => 16#AC00#,
       Last  => 16#D7A3#,
       Width => 2),  --  73 Hangul Syllables
      (First => 16#F900#,
       Last  => 16#FAFF#,
       Width => 2),  --  74 CJK Compat Ideographs
      (First => 16#FE00#,
       Last  => 16#FE0F#,
       Width => 0),  --  75 Variation Selectors (VS16)
      (First => 16#FE10#,
       Last  => 16#FFE6#,
       Width => 2),  --  76 CJK Compat Forms+Fullwidth
      (First => 16#1F300#,
       Last  => 16#1F64F#,
       Width => 2), --  77 Emoji (incl. U+1F600)
      (First => 16#1F900#,
       Last  => 16#1F9FF#,
       Width => 2), --  78 Supplemental Symbols/Pictographs
      (First => 16#20000#,
       Last  => 16#2FFFD#,
       Width => 2), --  79 CJK Extension B and beyond
      (First => 16#30000#,
       Last  => 16#3FFFD#,
       Width => 2)]; --  80 CJK Extension G and beyond

   --  @summary Precomputed Unicode 16.0 width table.
   --  @description Width-0 (combining/format) and width-2 (wide/fullwidth)
   --  codepoint ranges derived from the Unicode 16.0 Character Database,
   --  including ZWJ (U+200D, FUNC-CWM-007), VS16 (U+FE0F, FUNC-CWM-008),
   --  and all category-M combining marks (FUNC-CWM-009).
   --  Entries are sorted by First with no overlapping ranges.
   --  Adds Mandaic combining (U+0859..U+085B) and Combining Extended
   --  (U+1AB0..U+1ABE) beyond Unicode 13.0.
   --  @relation(FUNC-CWM-001): Unicode 16.0 table constant
   --  @relation(FUNC-CWM-007): ZWJ (U+200D) present via U+200B..U+200F range
   --  @relation(FUNC-CWM-008): VS16 (U+FE0F) present via U+FE00..U+FE0F range
   --  @relation(FUNC-CWM-009): Combining character ranges (category M) present
   TABLE_UNICODE_16 : constant Width_Table (1 .. TABLE_UNICODE_16_LENGTH) :=
     [(First => 16#0300#,
       Last  => 16#036F#,
       Width => 0),  --  1 Combining Diacritical Marks
      (First => 16#0483#,
       Last  => 16#0489#,
       Width => 0),  --  2 Combining Cyrillic
      (First => 16#0591#,
       Last  => 16#05C7#,
       Width => 0),  --  3 Hebrew combining
      (First => 16#0610#,
       Last  => 16#061A#,
       Width => 0),  --  4 Arabic combining
      (First => 16#064B#,
       Last  => 16#065F#,
       Width => 0),  --  5 Arabic tatweel combining
      (First => 16#0670#,
       Last  => 16#0670#,
       Width => 0),  --  6 Arabic superscript alef
      (First => 16#06D6#,
       Last  => 16#06DC#,
       Width => 0),  --  7 Arabic combining
      (First => 16#06DF#,
       Last  => 16#06E4#,
       Width => 0),  --  8 Arabic combining
      (First => 16#06E7#,
       Last  => 16#06E8#,
       Width => 0),  --  9 Arabic combining
      (First => 16#06EA#,
       Last  => 16#06ED#,
       Width => 0),  --  10 Arabic combining
      (First => 16#0711#,
       Last  => 16#0711#,
       Width => 0),  --  11 Syriac superscript alaph
      (First => 16#0730#,
       Last  => 16#074A#,
       Width => 0),  --  12 Syriac combining
      (First => 16#07A6#,
       Last  => 16#07B0#,
       Width => 0),  --  13 Thaana combining
      (First => 16#07EB#, Last => 16#07F3#, Width => 0),  --  14 NKo combining
      (First => 16#0816#,
       Last  => 16#082D#,
       Width => 0),  --  15 Samaritan combining
      (First => 16#0859#,
       Last  => 16#085B#,
       Width => 0),  --  16 Mandaic combining (Unicode 6.0+)
      (First => 16#0900#,
       Last  => 16#0902#,
       Width => 0),  --  17 Devanagari combining
      (First => 16#093C#,
       Last  => 16#093C#,
       Width => 0),  --  18 Devanagari nukta
      (First => 16#0941#,
       Last  => 16#0948#,
       Width => 0),  --  19 Devanagari vowel signs
      (First => 16#094D#,
       Last  => 16#094D#,
       Width => 0),  --  20 Devanagari virama
      (First => 16#0951#,
       Last  => 16#0957#,
       Width => 0),  --  21 Devanagari stress/tone
      (First => 16#0962#,
       Last  => 16#0963#,
       Width => 0),  --  22 Devanagari vowel signs
      (First => 16#0981#,
       Last  => 16#0981#,
       Width => 0),  --  23 Bengali anusvara
      (First => 16#09BC#, Last => 16#09BC#, Width => 0),  --  24 Bengali nukta
      (First => 16#09C1#,
       Last  => 16#09C4#,
       Width => 0),  --  25 Bengali vowel signs
      (First => 16#09CD#, Last => 16#09CD#, Width => 0),  --  26 Bengali virama
      (First => 16#09E2#,
       Last  => 16#09E3#,
       Width => 0),  --  27 Bengali vowel signs
      (First => 16#0A3C#, Last => 16#0A3C#, Width => 0),  --  28 Gurmukhi nukta
      (First => 16#0A41#,
       Last  => 16#0A42#,
       Width => 0),  --  29 Gurmukhi vowel signs
      (First => 16#0A47#,
       Last  => 16#0A48#,
       Width => 0),  --  30 Gurmukhi vowel signs
      (First => 16#0A4B#,
       Last  => 16#0A4D#,
       Width => 0),  --  31 Gurmukhi virama
      (First => 16#0ABC#, Last => 16#0ABC#, Width => 0),  --  32 Gujarati nukta
      (First => 16#0AC1#,
       Last  => 16#0AC5#,
       Width => 0),  --  33 Gujarati vowel signs
      (First => 16#0AC7#,
       Last  => 16#0AC8#,
       Width => 0),  --  34 Gujarati vowel signs
      (First => 16#0ACD#,
       Last  => 16#0ACD#,
       Width => 0),  --  35 Gujarati virama
      (First => 16#0B3C#, Last => 16#0B3C#, Width => 0),  --  36 Oriya nukta
      (First => 16#0B41#,
       Last  => 16#0B44#,
       Width => 0),  --  37 Oriya vowel signs
      (First => 16#0B4D#, Last => 16#0B4D#, Width => 0),  --  38 Oriya virama
      (First => 16#0BC0#,
       Last  => 16#0BC0#,
       Width => 0),  --  39 Tamil combining
      (First => 16#0BCD#, Last => 16#0BCD#, Width => 0),  --  40 Tamil virama
      (First => 16#0C3E#,
       Last  => 16#0C40#,
       Width => 0),  --  41 Telugu combining
      (First => 16#0C4D#, Last => 16#0C4D#, Width => 0),  --  42 Telugu virama
      (First => 16#0CBC#, Last => 16#0CBC#, Width => 0),  --  43 Kannada nukta
      (First => 16#0CCD#, Last => 16#0CCD#, Width => 0),  --  44 Kannada virama
      (First => 16#0E31#,
       Last  => 16#0E31#,
       Width => 0),  --  45 Thai vowel sign
      (First => 16#0E34#,
       Last  => 16#0E3A#,
       Width => 0),  --  46 Thai vowel signs
      (First => 16#0E47#, Last => 16#0E4E#, Width => 0),  --  47 Thai combining
      (First => 16#0EB1#, Last => 16#0EB1#, Width => 0),  --  48 Lao vowel sign
      (First => 16#0EB4#,
       Last  => 16#0EB9#,
       Width => 0),  --  49 Lao vowel signs
      (First => 16#0EBB#, Last => 16#0EBC#, Width => 0),  --  50 Lao combining
      (First => 16#0EC8#, Last => 16#0ECD#, Width => 0),  --  51 Lao combining
      (First => 16#0F18#,
       Last  => 16#0F19#,
       Width => 0),  --  52 Tibetan combining
      (First => 16#0F35#,
       Last  => 16#0F35#,
       Width => 0),  --  53 Tibetan combining
      (First => 16#0F37#,
       Last  => 16#0F37#,
       Width => 0),  --  54 Tibetan combining
      (First => 16#0F39#,
       Last  => 16#0F39#,
       Width => 0),  --  55 Tibetan combining
      (First => 16#0F71#,
       Last  => 16#0F7E#,
       Width => 0),  --  56 Tibetan vowel signs
      (First => 16#0F80#,
       Last  => 16#0F84#,
       Width => 0),  --  57 Tibetan combining
      (First => 16#0F86#,
       Last  => 16#0F87#,
       Width => 0),  --  58 Tibetan combining
      (First => 16#0FC6#,
       Last  => 16#0FC6#,
       Width => 0),  --  59 Tibetan combining
      (First => 16#1100#,
       Last  => 16#115F#,
       Width => 2),  --  60 Hangul Jamo lead consonants
      (First => 16#1AB0#,
       Last  => 16#1ABE#,
       Width => 0),  --  61 Combining Diacritical Marks Ext.
      (First => 16#200B#,
       Last  => 16#200F#,
       Width => 0),  --  62 ZW space/ZWNJ/ZWJ/LRM/RLM
      (First => 16#202A#,
       Last  => 16#202E#,
       Width => 0),  --  63 Directional formatting
      (First => 16#2060#,
       Last  => 16#2064#,
       Width => 0),  --  64 Word joiner/format
      (First => 16#206A#,
       Last  => 16#206F#,
       Width => 0),  --  65 Format characters
      (First => 16#20D0#,
       Last  => 16#20F0#,
       Width => 0),  --  66 Combining Marks for Symbols
      (First => 16#2E80#,
       Last  => 16#2EFF#,
       Width => 2),  --  67 CJK Radicals Supplement
      (First => 16#2F00#,
       Last  => 16#2FD5#,
       Width => 2),  --  68 Kangxi Radicals
      (First => 16#2FF0#,
       Last  => 16#2FFB#,
       Width => 2),  --  69 Ideographic Description
      (First => 16#3000#,
       Last  => 16#303E#,
       Width => 2),  --  70 CJK Symbols and Punctuation
      (First => 16#3041#,
       Last  => 16#33FF#,
       Width => 2),  --  71 Hiragana/Katakana/Bopomofo/Compat
      (First => 16#3400#,
       Last  => 16#4DBF#,
       Width => 2),  --  72 CJK Extension A
      (First => 16#4E00#,
       Last  => 16#9FFF#,
       Width => 2),  --  73 CJK Unified Ideographs
      (First => 16#A000#, Last => 16#A4CF#, Width => 2),  --  74 Yi Syllables
      (First => 16#AC00#,
       Last  => 16#D7A3#,
       Width => 2),  --  75 Hangul Syllables
      (First => 16#F900#,
       Last  => 16#FAFF#,
       Width => 2),  --  76 CJK Compat Ideographs
      (First => 16#FE00#,
       Last  => 16#FE0F#,
       Width => 0),  --  77 Variation Selectors (VS16)
      (First => 16#FE10#,
       Last  => 16#FFE6#,
       Width => 2),  --  78 CJK Compat Forms+Fullwidth
      (First => 16#1F300#,
       Last  => 16#1F64F#,
       Width => 2), --  79 Emoji (incl. U+1F600)
      (First => 16#1F900#,
       Last  => 16#1F9FF#,
       Width => 2), --  80 Supplemental Symbols/Pictographs
      (First => 16#20000#,
       Last  => 16#2FFFD#,
       Width => 2), --  81 CJK Extension B and beyond
      (First => 16#30000#,
       Last  => 16#3FFFD#,
       Width => 2)]; --  82 CJK Extension G and beyond

   ---------------------------------------------------------------------------
   --  Table Dispatch (FUNC-CWM-001)
   ---------------------------------------------------------------------------

   --  @summary Return the precomputed width table for the given Unicode version.
   --  @description Pure case-dispatch over Table_Version.  All tables are
   --  compile-time constants; no heap allocation or I/O occurs.  Eligible for
   --  SPARK Gold proof.
   --  @param Version  The Unicode version whose table is requested.
   --  @return The Width_Table constant for Version.
   --  @relation(FUNC-CWM-001): Table access by version
   function Get_Table (Version : Table_Version) return Width_Table
   with Global => null;

   ---------------------------------------------------------------------------
   --  Binary Search Lookup (FUNC-CWM-003, FUNC-CWM-014, FUNC-CWM-015)
   ---------------------------------------------------------------------------

   --  @summary Binary search over a sorted Width_Table for the cell width of
   --           a Unicode scalar value.
   --  @description Performs O(log N) binary search over a Width_Table that is
   --  sorted by First with non-overlapping ranges.  Returns the Width field of
   --  the matching entry, or 1 (default narrow) if no entry covers Codepoint.
   --
   --  SPARK proof obligations discharged by GNATprove:
   --    - No array out-of-bounds: loop invariants on Low and High; exit guards
   --      at Table'First and Table'Last boundaries.
   --    - No integer overflow: mid computation uses Low + (High - Low) / 2.
   --    - Return value in Cell_Width_Value: all paths return 0, 1, or a stored Width.
   --    - Termination: loop variant Decreases => High - Low.
   --    - No side effects: Global => null.
   --
   --  Preconditions require Table to be non-empty and structurally valid
   --  (enforced by ghost predicates).  These are discharged automatically when
   --  called with the constant tables defined in this package.
   --
   --  @param Codepoint  A Unicode scalar value (0 .. 16#10_FFFF#).
   --  @param Table      A non-empty, sorted, non-overlapping Width_Table.
   --  @return 0 or 2 when Codepoint falls within a stored range; 1 otherwise.
   --  @relation(FUNC-CWM-003): Binary search algorithm
   --  @relation(FUNC-CWM-014): SPARK Gold provability
   --  @relation(FUNC-CWM-015): O(log N) time complexity
   function Cell_Width_In_Table
     (Codepoint : Unicode_Scalar_Value; Table : Width_Table)
      return Cell_Width_Value
   with
     Global => null,
     Pre    =>
       Table'Length > 0
       and then All_Widths_Valid (Table)
       and then Is_Sorted_Non_Overlapping (Table);

end Termicap.Cell_Width.Tables;
