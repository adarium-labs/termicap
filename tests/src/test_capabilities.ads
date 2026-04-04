-------------------------------------------------------------------------------
--  Termicap.Capabilities.Tests - Unit Tests for Termicap.Capabilities
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Terminal_Capabilities record assembly, field
--  population, Downsampling_Available derivation, override integration,
--  re-detection, and record value semantics.
--
--  Requirements Coverage:
--    - @relation(FUNC-CAP-001): Terminal_Capabilities record type and fields
--    - @relation(FUNC-CAP-002): Stream_Kind does not affect Assemble directly
--    - @relation(FUNC-CAP-006): Override state applied to Color field via Detect
--    - @relation(FUNC-CAP-007): TTY fields reflect override state via Detect
--    - @relation(FUNC-CAP-009): Immutability — value semantics of returned record
--    - @relation(FUNC-CAP-012): Downsampling_Available derivation (Color >= Extended_256)
--    - @relation(FUNC-CAP-014): Re-detection on explicit Detect call

with AUnit.Test_Cases;

package Test_Capabilities is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Group 1: Assemble — Downsampling_Available derivation (FUNC-CAP-001, FUNC-CAP-012)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-CAP-012): True_Color => Downsampling_Available = True
   procedure Test_Downsampling_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-012): Extended_256 => Downsampling_Available = True
   procedure Test_Downsampling_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-012): Basic_16 => Downsampling_Available = False
   procedure Test_Downsampling_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-012): None => Downsampling_Available = False
   procedure Test_Downsampling_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 2: Assemble — Record fields populated correctly (FUNC-CAP-001)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-CAP-001): TTY_Stdin field matches parameter
   procedure Test_Fields_TTY_Stdin
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-001): TTY_Stdout field matches parameter
   procedure Test_Fields_TTY_Stdout
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-001): TTY_Stderr field matches parameter
   procedure Test_Fields_TTY_Stderr
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-001): Color field matches parameter
   procedure Test_Fields_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-001): Size field matches parameter
   procedure Test_Fields_Size
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-001): Unicode field matches parameter
   procedure Test_Fields_Unicode
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-001): Identity.Kind field matches parameter
   procedure Test_Fields_Identity_Kind
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 3: Assemble — Stream_Kind does not affect Assemble (FUNC-CAP-002)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-CAP-002): Two Assemble calls with different TTY_Stdout
   --  values produce records with different Color-visible context when
   --  Color = None vs Color = Basic_16
   procedure Test_Different_Tty_Stdout_Different_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-002): Assemble is stream-agnostic — same Color input
   --  produces same Color output regardless of which TTY flag differs
   procedure Test_Assemble_Stream_Agnostic
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 4: Detect — Override integration (FUNC-CAP-006, FUNC-CAP-007)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-CAP-006): Set_Override (Force_True_Color) -> Detect.Color = True_Color
   procedure Test_Override_Force_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-006): Set_Override (Force_None) -> Detect.Color = None
   procedure Test_Override_Force_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-006): Set_Override (Force_Basic) -> Detect.Color = Basic_16
   procedure Test_Override_Force_Basic
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-CAP-006): Set_Override (Force_256) -> Detect.Color = Extended_256
   procedure Test_Override_Force_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 5: Detect — Re-detection (FUNC-CAP-014)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-CAP-014): Two successive Detect calls each produce a record
   procedure Test_Redetection_Produces_Independent_Records
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 6: Record immutability (FUNC-CAP-009)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-CAP-009): Modifying a copy of Terminal_Capabilities does
   --  not change the original (Ada value semantics)
   procedure Test_Record_Value_Semantics
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Capabilities;
