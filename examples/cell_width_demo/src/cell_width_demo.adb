-------------------------------------------------------------------------------
--  Cell_Width_Demo - Usage example for Termicap.Cell_Width
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates cell width measurement using precomputed Unicode width tables.
--
--  @description
--  This program showcases the typical caller patterns for the CELL-WIDTH feature:
--
--    1. Basic lookup: query the display column width of individual codepoints
--       covering all four width categories (ASCII, CJK wide, combining, control).
--    2. Version-specific lookup: use the two-argument Cell_Width overload with
--       an explicit Table_Version to pin the Unicode version used for lookup.
--    3. Active version query: read the version selected at process elaboration
--       time from the UNICODE_VERSION environment variable.
--    4. Practical string width: compute the display column count of a short
--       UTF-32 string by summing individual Cell_Width results.
--    5. Special characters: demonstrate ZWJ (U+200D), VS16 (U+FE0F), and
--       representative combining marks (Combining Diacritical Marks block).
--
--  Width semantics:
--    0  --  Combining marks, format characters, control characters
--    1  --  Narrow: ASCII printable, Latin, Greek, Cyrillic, most symbols
--    2  --  Wide / fullwidth: CJK ideographs, fullwidth forms, many emoji
--
--  Set the UNICODE_VERSION environment variable to "3", "13", or "16" before
--  running to select a specific table version.  The default is Unicode 16.0.

with Ada.Text_IO;
with Ada.Integer_Text_IO;

with Termicap.Cell_Width;

procedure Cell_Width_Demo is

   package IO     renames Ada.Text_IO;
   package Int_IO renames Ada.Integer_Text_IO;

   --  Convenient aliases from Termicap.Cell_Width
   subtype CSV is Termicap.Cell_Width.Unicode_Scalar_Value;
   subtype CWV is Termicap.Cell_Width.Cell_Width_Value;

   use type Termicap.Cell_Width.Table_Version;

   ---------------------------------------------------------------------------
   --  Helper: print a codepoint in Ada hex literal notation (16#XXXX#).
   ---------------------------------------------------------------------------

   procedure Put_Hex (Value : CSV) is
   begin
      Int_IO.Put (Item  => Value,
                  Width => 0,
                  Base  => 16);
   end Put_Hex;

   ---------------------------------------------------------------------------
   --  Helper: print the width value as a right-aligned single digit.
   ---------------------------------------------------------------------------

   procedure Put_Width (W : CWV) is
   begin
      Int_IO.Put (Item  => W,
                  Width => 1,
                  Base  => 10);
   end Put_Width;

   ---------------------------------------------------------------------------
   --  Helper: human-readable label for a Table_Version value.
   ---------------------------------------------------------------------------

   function Version_Image
     (V : Termicap.Cell_Width.Table_Version) return String
   is
   begin
      case V is
         when Termicap.Cell_Width.Unicode_3  => return "Unicode_3  (Unicode 3.0)";
         when Termicap.Cell_Width.Unicode_13 => return "Unicode_13 (Unicode 13.0)";
         when Termicap.Cell_Width.Unicode_16 => return "Unicode_16 (Unicode 16.0)";
      end case;
   end Version_Image;

   ---------------------------------------------------------------------------
   --  Helper: print one codepoint row with its single-arg Cell_Width result.
   ---------------------------------------------------------------------------

   procedure Print_Row (Label     : String;
                        Codepoint : CSV;
                        Comment   : String) is
      W : constant CWV :=
            Termicap.Cell_Width.Cell_Width (Codepoint);
   begin
      IO.Put ("  ");
      IO.Put (Label);
      IO.Put (" (");
      Put_Hex (Codepoint);
      IO.Put (")  width = ");
      Put_Width (W);
      IO.Put ("   -- ");
      IO.Put_Line (Comment);
   end Print_Row;

   ---------------------------------------------------------------------------
   --  A small fixed UTF-32 string used for the practical width demo.
   --  "A" (U+0041) + CJK ideograph (U+4E00) + combining grave (U+0300) +
   --  "!" (U+0021).
   --  Expected total display width = 1 + 2 + 0 + 1 = 4 columns.
   ---------------------------------------------------------------------------

   type UTF32_String is array (Positive range <>) of CSV;

   Sample_String : constant UTF32_String :=
     [16#0041#,   --  LATIN CAPITAL LETTER A              -> width 1
      16#4E00#,   --  CJK UNIFIED IDEOGRAPH-4E00 (yi)     -> width 2
      16#0300#,   --  COMBINING GRAVE ACCENT               -> width 0
      16#0021#];  --  EXCLAMATION MARK                     -> width 1

begin

   IO.Put_Line ("=== Termicap.Cell_Width Demo ===");
   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 1: Active version query (FUNC-CWM-005, FUNC-CWM-006)
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Section 1: Active Version Query ---");
   IO.Put_Line ("The active version is determined once at elaboration time by");
   IO.Put_Line ("reading the UNICODE_VERSION environment variable.");
   IO.Put_Line ("Recognised values: ""3"", ""3.0"", ""13"", ""13.0"", ""16"", ""16.0"".");
   IO.Put_Line ("Unrecognised / absent -> default to Table_Version'Last (Unicode_16).");
   IO.New_Line;

   IO.Put ("  Active_Version = ");
   IO.Put_Line (Version_Image (Termicap.Cell_Width.Active_Version));
   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 2: Basic cell width lookup (FUNC-CWM-010, FUNC-CWM-011,
   --             FUNC-CWM-012)
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Section 2: Basic Cell Width Lookup (active table version) ---");
   IO.Put_Line ("Cell_Width (Codepoint) uses the active table version.");
   IO.New_Line;

   --  ASCII printable fast path (FUNC-CWM-010): no table access required.
   IO.Put_Line ("  ASCII printable fast path (U+0020..U+007E -> 1):");
   Print_Row ("SPACE 'A' '~'     SPACE",   16#0020#, "SPACE                 [ASCII fast path]");
   Print_Row ("SPACE 'A' '~'     A    ",   16#0041#, "LATIN CAPITAL LETTER A [ASCII fast path]");
   Print_Row ("SPACE 'A' '~'     ~    ",   16#007E#, "TILDE                  [ASCII fast path]");
   IO.New_Line;

   --  Control characters (FUNC-CWM-011): C0, DEL, C1 all return 0.
   IO.Put_Line ("  Control characters (C0, DEL, C1 -> 0):");
   Print_Row ("NUL              ", 16#0000#, "C0 control: NUL");
   Print_Row ("LF               ", 16#000A#, "C0 control: LINE FEED");
   Print_Row ("DEL              ", 16#007F#, "DEL (U+007F)");
   Print_Row ("PAD (C1)         ", 16#0080#, "C1 control: PADDING CHARACTER");
   Print_Row ("APC (C1)         ", 16#009F#, "C1 control: APPLICATION PROGRAM COMMAND");
   IO.New_Line;

   --  Wide / fullwidth (table lookup, width 2).
   IO.Put_Line ("  Wide / fullwidth characters (table lookup -> 2):");
   Print_Row ("CJK 4E00         ", 16#4E00#, "CJK UNIFIED IDEOGRAPH-4E00 (yi)");
   Print_Row ("CJK 9FFF         ", 16#9FFF#, "CJK UNIFIED IDEOGRAPH-9FFF");
   Print_Row ("FULLWIDTH !      ", 16#FF01#, "FULLWIDTH EXCLAMATION MARK");
   Print_Row ("GRINNING FACE    ", 16#1F600#, "GRINNING FACE emoji");
   IO.New_Line;

   --  Narrow non-ASCII (table lookup, not in any stored range -> 1).
   IO.Put_Line ("  Narrow non-ASCII characters (default -> 1):");
   Print_Row ("e with acute     ", 16#00E9#, "LATIN SMALL LETTER E WITH ACUTE");
   Print_Row ("Greek alpha      ", 16#03B1#, "GREEK SMALL LETTER ALPHA");
   Print_Row ("Maximum scalar   ", 16#10_FFFF#, "U+10FFFF (highest Unicode scalar value)");
   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 3: Special characters — ZWJ, VS16, combining marks
   --             (FUNC-CWM-007, FUNC-CWM-008, FUNC-CWM-009)
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Section 3: Special Characters ---");
   IO.Put_Line ("ZWJ, VS16, and combining marks are stored as width-0 table entries.");
   IO.New_Line;

   --  ZWJ (FUNC-CWM-007)
   Print_Row ("ZWJ U+200D       ", 16#200D#,
              "ZERO WIDTH JOINER - used to join emoji sequences [FUNC-CWM-007]");

   --  VS16 / Variation Selector-16 (FUNC-CWM-008)
   Print_Row ("VS16 U+FE0F      ", 16#FE0F#,
              "VARIATION SELECTOR-16 - forces emoji presentation [FUNC-CWM-008]");

   --  Combining Diacritical Marks block (FUNC-CWM-009)
   Print_Row ("COMBINING GRAVE  ", 16#0300#,
              "COMBINING GRAVE ACCENT (first entry of block U+0300..U+036F) [FUNC-CWM-009]");
   Print_Row ("COMBINING CEDILLA", 16#0327#,
              "COMBINING CEDILLA (mid-block combining mark) [FUNC-CWM-009]");
   Print_Row ("COMBINING TILDE  ", 16#036F#,
              "COMBINING LATIN SMALL LETTER X (last entry of block) [FUNC-CWM-009]");

   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 4: Version-specific lookup (FUNC-CWM-003, FUNC-CWM-012)
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Section 4: Version-Specific Lookup ---");
   IO.Put_Line ("Cell_Width (Codepoint, Version) uses an explicit table version.");
   IO.Put_Line ("This is useful to pin measurements to a specific Unicode release,");
   IO.Put_Line ("or when integrating with Termicap.Wcwidth.Probe_Wcwidth_Level.");
   IO.New_Line;

   --  Query the same codepoint under all three bundled table versions.
   declare
      Cp : constant CSV := 16#4E00#;  --  CJK UNIFIED IDEOGRAPH-4E00
   begin
      IO.Put_Line ("  CJK UNIFIED IDEOGRAPH-4E00 (U+4E00) across all table versions:");
      for V in Termicap.Cell_Width.Table_Version loop
         declare
            W : constant CWV := Termicap.Cell_Width.Cell_Width (Cp, V);
         begin
            IO.Put ("    ");
            IO.Put (Version_Image (V));
            IO.Put ("  -> width = ");
            Put_Width (W);
            IO.New_Line;
         end;
      end loop;
      IO.New_Line;
   end;

   --  Show that fast-path codepoints return the same result regardless of version.
   declare
      Ascii_A : constant CSV := 16#0041#;  --  'A'
   begin
      IO.Put_Line ("  ASCII 'A' (U+0041) is in the fast path — version makes no difference:");
      for V in Termicap.Cell_Width.Table_Version loop
         declare
            W : constant CWV := Termicap.Cell_Width.Cell_Width (Ascii_A, V);
         begin
            IO.Put ("    ");
            IO.Put (Version_Image (V));
            IO.Put ("  -> width = ");
            Put_Width (W);
            IO.New_Line;
         end;
      end loop;
      IO.New_Line;
   end;

   ---------------------------------------------------------------------------
   --  Section 5: Practical use case — display width of a short string
   --             (FUNC-CWM-012)
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Section 5: Display Width of a String ---");
   IO.Put_Line ("Sum Cell_Width over each codepoint to compute total display columns.");
   IO.Put_Line ("Sample string: U+0041 (A) + U+4E00 (CJK) + U+0300 (combining) + U+0021 (!)");
   IO.Put_Line ("Expected column total: 1 + 2 + 0 + 1 = 4");
   IO.New_Line;

   declare
      Total_Width : Natural := 0;
   begin
      IO.Put_Line ("  Codepoint-by-codepoint breakdown:");
      for I in Sample_String'Range loop
         declare
            Cp : constant CSV := Sample_String (I);
            W  : constant CWV := Termicap.Cell_Width.Cell_Width (Cp);
         begin
            IO.Put ("    [");
            Int_IO.Put (Item => I, Width => 1, Base => 10);
            IO.Put ("] ");
            Put_Hex (Cp);
            IO.Put ("  width = ");
            Put_Width (W);
            IO.New_Line;
            Total_Width := Total_Width + W;
         end;
      end loop;

      IO.New_Line;
      IO.Put ("  Total display width = ");
      Int_IO.Put (Item => Total_Width, Width => 1, Base => 10);
      IO.Put_Line (" columns");
   end;

   IO.New_Line;
   IO.Put_Line ("=== Demo complete ===");

end Cell_Width_Demo;
