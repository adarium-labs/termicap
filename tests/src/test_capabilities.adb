-------------------------------------------------------------------------------
--  Test_Capabilities - Unit Tests for Termicap.Capabilities
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;  use AUnit.Assertions;
with AUnit.Test_Cases;  use AUnit.Test_Cases.Registration;

with Ada.Strings.Unbounded;

with Termicap.Capabilities; use Termicap.Capabilities;
with Termicap.Color;
with Termicap.DA1;
with Termicap.Dimensions;
with Termicap.Override;    use Termicap.Override;
with Termicap.Terminal_Id;
with Termicap.TTY;
with Termicap.Unicode;

--  Bring equality operators into scope for comparison expressions.
use type Termicap.Color.Color_Level;
use type Termicap.Unicode.Unicode_Level;
use type Termicap.Terminal_Id.Terminal_Kind;

package body Test_Capabilities is

   ---------------------------------------------------------------------------
   --  Helpers - default values for sub-detector result types
   ---------------------------------------------------------------------------

   --  Default Terminal_Size (80x24, no pixel info) used across tests.
   Default_Size : constant Termicap.Dimensions.Terminal_Size :=
     (Rows         => 24,
      Columns      => 80,
      Pixel_Width  => 0,
      Pixel_Height => 0);

   --  Default Unicode level - None (most conservative).
   Default_Unicode : constant Termicap.Unicode.Unicode_Level :=
     Termicap.Unicode.None;

   --  Default Terminal_Identity - Unknown, all string fields empty, not a
   --  multiplexer.  Constructed from the record aggregate directly.
   Default_Identity : constant Termicap.Terminal_Id.Terminal_Identity :=
     (Kind            => Termicap.Terminal_Id.Unknown,
      Program_Name    => Ada.Strings.Unbounded.Null_Unbounded_String,
      Program_Version => Ada.Strings.Unbounded.Null_Unbounded_String,
      Term_Value      => Ada.Strings.Unbounded.Null_Unbounded_String,
      Is_Multiplexer  => False);

   --  Default DA1_Capabilities - no DA1 response received.
   Default_DA1 : constant Termicap.DA1.DA1_Capabilities :=
     (Supported => False,
      Level     => Termicap.DA1.Unknown,
      Flags     => [others => False]);


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Capabilities");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  Group 1 - Downsampling_Available derivation
      Register_Routine (T, Test_Downsampling_True_Color'Access,
         "FUNC-CAP-012: Assemble - True_Color => Downsampling_Available = True");
      Register_Routine (T, Test_Downsampling_Extended_256'Access,
         "FUNC-CAP-012: Assemble - Extended_256 => Downsampling_Available = True");
      Register_Routine (T, Test_Downsampling_Basic_16'Access,
         "FUNC-CAP-012: Assemble - Basic_16 => Downsampling_Available = False");
      Register_Routine (T, Test_Downsampling_None'Access,
         "FUNC-CAP-012: Assemble - None => Downsampling_Available = False");

      --  Group 2 - Record fields populated correctly
      Register_Routine (T, Test_Fields_TTY_Stdin'Access,
         "FUNC-CAP-001: Assemble - TTY_Stdin field matches input parameter");
      Register_Routine (T, Test_Fields_TTY_Stdout'Access,
         "FUNC-CAP-001: Assemble - TTY_Stdout field matches input parameter");
      Register_Routine (T, Test_Fields_TTY_Stderr'Access,
         "FUNC-CAP-001: Assemble - TTY_Stderr field matches input parameter");
      Register_Routine (T, Test_Fields_Color'Access,
         "FUNC-CAP-001: Assemble - Color field matches input parameter");
      Register_Routine (T, Test_Fields_Size'Access,
         "FUNC-CAP-001: Assemble - Size fields match input parameter");
      Register_Routine (T, Test_Fields_Unicode'Access,
         "FUNC-CAP-001: Assemble - Unicode field matches input parameter");
      Register_Routine (T, Test_Fields_Identity_Kind'Access,
         "FUNC-CAP-001: Assemble - Identity.Kind field matches input parameter");

      --  Group 3 - Stream_Kind does not affect Assemble
      Register_Routine (T, Test_Different_Tty_Stdout_Different_Color'Access,
         "FUNC-CAP-002: Assemble - different TTY_Stdout yields different Color contexts");
      Register_Routine (T, Test_Assemble_Stream_Agnostic'Access,
         "FUNC-CAP-002: Assemble - same Color input produces same Color output");

      --  Group 4 - Detect / Override integration
      Register_Routine (T, Test_Override_Force_True_Color'Access,
         "FUNC-CAP-006: Detect - Force_True_Color => Color = True_Color");
      Register_Routine (T, Test_Override_Force_None'Access,
         "FUNC-CAP-006/007: Detect - Force_None => Color = None");
      Register_Routine (T, Test_Override_Force_Basic'Access,
         "FUNC-CAP-006: Detect - Force_Basic => Color = Basic_16");
      Register_Routine (T, Test_Override_Force_256'Access,
         "FUNC-CAP-006: Detect - Force_256 => Color = Extended_256");

      --  Group 5 - Re-detection
      Register_Routine (T, Test_Redetection_Produces_Independent_Records'Access,
         "FUNC-CAP-014: Two successive Detect calls each return independently computed records");

      --  Group 6 - Record immutability
      Register_Routine (T, Test_Record_Value_Semantics'Access,
         "FUNC-CAP-009: Modifying a copy does not affect the original (value semantics)");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Group 1: Assemble - Downsampling_Available derivation
   ---------------------------------------------------------------------------


   procedure Test_Downsampling_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.True_Color,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps.Downsampling_Available,
         "True_Color should set Downsampling_Available = True");
   end Test_Downsampling_True_Color;


   procedure Test_Downsampling_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.Extended_256,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps.Downsampling_Available,
         "Extended_256 should set Downsampling_Available = True");
   end Test_Downsampling_Extended_256;


   procedure Test_Downsampling_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.Basic_16,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (not Caps.Downsampling_Available,
         "Basic_16 should set Downsampling_Available = False");
   end Test_Downsampling_Basic_16;


   procedure Test_Downsampling_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => False,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (not Caps.Downsampling_Available,
         "Color = None should set Downsampling_Available = False");
   end Test_Downsampling_None;


   ---------------------------------------------------------------------------
   --  Group 2: Assemble - Record fields populated correctly
   ---------------------------------------------------------------------------


   procedure Test_Fields_TTY_Stdin
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps_True : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => True,
           TTY_Stdout => False,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
      Caps_False : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => False,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps_True.TTY_Stdin,
         "TTY_Stdin should be True when passed True");
      Assert
        (not Caps_False.TTY_Stdin,
         "TTY_Stdin should be False when passed False");
   end Test_Fields_TTY_Stdin;


   procedure Test_Fields_TTY_Stdout
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps_True : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
      Caps_False : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => False,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps_True.TTY_Stdout,
         "TTY_Stdout should be True when passed True");
      Assert
        (not Caps_False.TTY_Stdout,
         "TTY_Stdout should be False when passed False");
   end Test_Fields_TTY_Stdout;


   procedure Test_Fields_TTY_Stderr
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps_True : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => False,
           TTY_Stderr => True,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
      Caps_False : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => False,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps_True.TTY_Stderr,
         "TTY_Stderr should be True when passed True");
      Assert
        (not Caps_False.TTY_Stderr,
         "TTY_Stderr should be False when passed False");
   end Test_Fields_TTY_Stderr;


   procedure Test_Fields_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.Extended_256,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps.Color = Termicap.Color.Extended_256,
         "Color field should match the Color parameter passed to Assemble");
   end Test_Fields_Color;


   procedure Test_Fields_Size
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Custom_Size : constant Termicap.Dimensions.Terminal_Size :=
        (Rows         => 50,
         Columns      => 132,
         Pixel_Width  => 1320,
         Pixel_Height => 800);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Custom_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps.Size.Rows = 50,
         "Size.Rows should match the Rows passed to Assemble");
      Assert
        (Caps.Size.Columns = 132,
         "Size.Columns should match the Columns passed to Assemble");
      Assert
        (Caps.Size.Pixel_Width = 1320,
         "Size.Pixel_Width should match the Pixel_Width passed to Assemble");
      Assert
        (Caps.Size.Pixel_Height = 800,
         "Size.Pixel_Height should match the Pixel_Height passed to Assemble");
   end Test_Fields_Size;


   procedure Test_Fields_Unicode
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Termicap.Unicode.Extended,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps.Unicode = Termicap.Unicode.Extended,
         "Unicode field should match the Unicode parameter passed to Assemble");
   end Test_Fields_Unicode;


   procedure Test_Fields_Identity_Kind
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Xterm_Identity : constant Termicap.Terminal_Id.Terminal_Identity :=
        (Kind            => Termicap.Terminal_Id.Xterm,
         Program_Name    => Ada.Strings.Unbounded.Null_Unbounded_String,
         Program_Version => Ada.Strings.Unbounded.Null_Unbounded_String,
         Term_Value      => Ada.Strings.Unbounded.To_Unbounded_String ("xterm-256color"),
         Is_Multiplexer  => False);
      Caps : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.Extended_256,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Xterm_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps.Identity.Kind = Termicap.Terminal_Id.Xterm,
         "Identity.Kind should match the Identity parameter passed to Assemble");
   end Test_Fields_Identity_Kind;


   ---------------------------------------------------------------------------
   --  Group 3: Assemble - Stream_Kind does not affect Assemble
   ---------------------------------------------------------------------------


   procedure Test_Different_Tty_Stdout_Different_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  When TTY_Stdout = True we pass Color = Basic_16; when False we pass
      --  Color = None.  Assemble is stream-agnostic: the TTY flag in the call
      --  is just the pre-computed boolean; it does not recompute the Color field.
      Caps_Tty : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.Basic_16,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
      Caps_No_Tty : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => False,
           TTY_Stderr => False,
           Color      => Termicap.Color.None,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps_Tty.Color /= Caps_No_Tty.Color,
         "Two Assemble calls with different Color inputs should produce different Color fields");
      Assert
        (Caps_Tty.TTY_Stdout /= Caps_No_Tty.TTY_Stdout,
         "Two Assemble calls with different TTY_Stdout inputs should produce different TTY_Stdout fields");
   end Test_Different_Tty_Stdout_Different_Color;


   procedure Test_Assemble_Stream_Agnostic
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Assemble with identical Color but different TTY_Stderr values.
      --  The Color field must be the same in both results (Assemble does not
      --  recompute anything; it stores exactly what is passed).
      Caps_A : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => False,
           Color      => Termicap.Color.True_Color,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
      Caps_B : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => False,
           TTY_Stdout => True,
           TTY_Stderr => True,
           Color      => Termicap.Color.True_Color,
           Size       => Default_Size,
           Unicode    => Default_Unicode,
           Identity   => Default_Identity,
           DA1        => Default_DA1);
   begin
      Assert
        (Caps_A.Color = Caps_B.Color,
         "Assemble is stream-agnostic: same Color input yields same Color output");
      Assert
        (Caps_A.Downsampling_Available = Caps_B.Downsampling_Available,
         "Assemble is stream-agnostic: Downsampling_Available depends only on Color");
   end Test_Assemble_Stream_Agnostic;


   ---------------------------------------------------------------------------
   --  Group 4: Detect - Override integration
   ---------------------------------------------------------------------------


   procedure Test_Override_Force_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : Terminal_Capabilities;
   begin
      Set_Override (Force_True_Color);
      begin
         Caps := Detect (Stream => Termicap.TTY.Stdout);
      exception
         when others =>
            Reset_Override;
            raise;
      end;
      Reset_Override;
      Assert
        (Caps.Color = Termicap.Color.True_Color,
         "Force_True_Color override should make Detect return Color = True_Color");
   end Test_Override_Force_True_Color;


   procedure Test_Override_Force_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : Terminal_Capabilities;
   begin
      Set_Override (Force_None);
      begin
         Caps := Detect (Stream => Termicap.TTY.Stdout);
      exception
         when others =>
            Reset_Override;
            raise;
      end;
      Reset_Override;
      Assert
        (Caps.Color = Termicap.Color.None,
         "Force_None override should make Detect return Color = None");
   end Test_Override_Force_None;


   procedure Test_Override_Force_Basic
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : Terminal_Capabilities;
   begin
      Set_Override (Force_Basic);
      begin
         Caps := Detect (Stream => Termicap.TTY.Stdout);
      exception
         when others =>
            Reset_Override;
            raise;
      end;
      Reset_Override;
      Assert
        (Caps.Color = Termicap.Color.Basic_16,
         "Force_Basic override should make Detect return Color = Basic_16");
   end Test_Override_Force_Basic;


   procedure Test_Override_Force_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caps : Terminal_Capabilities;
   begin
      Set_Override (Force_256);
      begin
         Caps := Detect (Stream => Termicap.TTY.Stdout);
      exception
         when others =>
            Reset_Override;
            raise;
      end;
      Reset_Override;
      Assert
        (Caps.Color = Termicap.Color.Extended_256,
         "Force_256 override should make Detect return Color = Extended_256");
   end Test_Override_Force_256;


   ---------------------------------------------------------------------------
   --  Group 5: Detect - Re-detection
   ---------------------------------------------------------------------------


   procedure Test_Redetection_Produces_Independent_Records
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Install a consistent override so Color is deterministic in CI.
      Caps_1 : Terminal_Capabilities;
      Caps_2 : Terminal_Capabilities;
   begin
      Set_Override (Force_Basic);
      begin
         Caps_1 := Detect (Stream => Termicap.TTY.Stdout);
         Caps_2 := Detect (Stream => Termicap.TTY.Stdout);
      exception
         when others =>
            Reset_Override;
            raise;
      end;
      Reset_Override;
      --  Both results should have the same Color when the same override is active.
      Assert
        (Caps_1.Color = Caps_2.Color,
         "Two successive Detect calls with the same override should return the same Color");
      --  Both records are independent value-type copies.
      --  Size fields reflect the real terminal state identically.
      Assert
        (Caps_1.Size.Rows = Caps_2.Size.Rows,
         "Two successive Detect calls should return records with equal Size.Rows");
      Assert
        (Caps_1.Size.Columns = Caps_2.Size.Columns,
         "Two successive Detect calls should return records with equal Size.Columns");
   end Test_Redetection_Produces_Independent_Records;


   ---------------------------------------------------------------------------
   --  Group 6: Record immutability
   ---------------------------------------------------------------------------


   procedure Test_Record_Value_Semantics
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Construct an original record via Assemble.
      Original : constant Terminal_Capabilities :=
        Assemble
          (TTY_Stdin  => True,
           TTY_Stdout => True,
           TTY_Stderr => True,
           Color      => Termicap.Color.True_Color,
           Size       => Default_Size,
           Unicode    => Termicap.Unicode.Extended,
           Identity   => Default_Identity,
           DA1        => Default_DA1);

      --  Make a mutable copy and modify several fields.
      Copy : Terminal_Capabilities := Original;
   begin
      --  Mutate the copy.
      Copy.TTY_Stdin  := False;
      Copy.TTY_Stdout := False;
      Copy.TTY_Stderr := False;
      Copy.Color      := Termicap.Color.None;
      Copy.Unicode    := Termicap.Unicode.None;

      --  The original must be completely unchanged (value semantics).
      Assert
        (Original.TTY_Stdin,
         "Original.TTY_Stdin should be unaffected by mutation of a copy");
      Assert
        (Original.TTY_Stdout,
         "Original.TTY_Stdout should be unaffected by mutation of a copy");
      Assert
        (Original.TTY_Stderr,
         "Original.TTY_Stderr should be unaffected by mutation of a copy");
      Assert
        (Original.Color = Termicap.Color.True_Color,
         "Original.Color should be unaffected by mutation of a copy");
      Assert
        (Original.Unicode = Termicap.Unicode.Extended,
         "Original.Unicode should be unaffected by mutation of a copy");
      Assert
        (Original.Downsampling_Available,
         "Original.Downsampling_Available should be unaffected by mutation of a copy");

      --  Confirm the copy does actually hold the mutated values.
      Assert
        (not Copy.TTY_Stdin,
         "Copy.TTY_Stdin should reflect the mutation");
      Assert
        (Copy.Color = Termicap.Color.None,
         "Copy.Color should reflect the mutation");
   end Test_Record_Value_Semantics;

end Test_Capabilities;
