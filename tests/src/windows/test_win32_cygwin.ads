-------------------------------------------------------------------------------
--  Test_Win32_Cygwin - Unit Tests for Termicap.Win32_Cygwin
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Is_Cygwin_Pipe_Name — the pure SPARK predicate
--  that validates a decoded pipe name against the Cygwin / MSYS2 grammar.
--
--  Test groups:
--    Group 1 — The 14 go-isatty acceptance vectors (FUNC-CYG-013)
--    Group 2 — Token rule boundary tests (FUNC-CYG-007 through FUNC-CYG-012)
--    Group 3 — \Device\NamedPipe prefix variants
--
--  Requirements Coverage:
--    - @relation(FUNC-CYG-006): Is_Cygwin_Pipe_Name public SPARK function
--    - @relation(FUNC-CYG-007): token[0] prefix validation
--    - @relation(FUNC-CYG-008): token[1] non-empty validation
--    - @relation(FUNC-CYG-009): token[2] starts with lowercase "pty"
--    - @relation(FUNC-CYG-010): token[3] is exactly "from" or "to"
--    - @relation(FUNC-CYG-011): token[4] is exactly "master"
--    - @relation(FUNC-CYG-012): minimum 5 '-'-delimited segments
--    - @relation(FUNC-CYG-013): 14 acceptance test vectors from go-isatty

with AUnit.Test_Cases;

package Test_Win32_Cygwin is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Group 1 — go-isatty Acceptance Vectors (FUNC-CYG-013)
   ---------------------------------------------------------------------------

   --  Vector 1: "" -> False (FUNC-CYG-012: fewer than 5 segments)
   procedure Test_Empty_String_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 2: "\msys-" -> False (FUNC-CYG-012: only 2 segments)
   procedure Test_Msys_Single_Dash_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 3: "\cygwin-----" -> False (FUNC-CYG-008: token[1] empty)
   procedure Test_Cygwin_Five_Dashes_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 4: "\msys-x-PTY5-pty1-from-master" -> False (FUNC-CYG-009: token[2]="PTY5" uppercase)
   procedure Test_Msys_Uppercase_Pty_Token2_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 5: "\cygwin-x-PTY5-from-master" -> False (FUNC-CYG-009: token[2]="PTY5" uppercase)
   procedure Test_Cygwin_Uppercase_Pty_Token2_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 6: "\cygwin-x-pty2-from-toaster" -> False (FUNC-CYG-011: token[4]="toaster")
   procedure Test_Cygwin_Toaster_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 7: "\cygwin--pty2-from-master" -> False (FUNC-CYG-008: token[1] empty)
   procedure Test_Cygwin_Empty_Session_Id_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 8: "\\cygwin-x-pty2-from-master" -> False (FUNC-CYG-007: double backslash prefix)
   procedure Test_Cygwin_Double_Backslash_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 9: "\cygwin-x-pty2-from-master-" -> True (trailing dash, extra segment ignored)
   procedure Test_Cygwin_Trailing_Dash_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 10: "\cygwin-e022582115c10879-pty4-from-master" -> True
   procedure Test_Cygwin_From_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 11: "\msys-e022582115c10879-pty4-to-master" -> True
   procedure Test_Msys_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 12: "\cygwin-e022582115c10879-pty4-to-master" -> True
   procedure Test_Cygwin_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 13: "\Device\NamedPipe\cygwin-e022582115c10879-pty4-from-master" -> True
   procedure Test_Device_Named_Pipe_Cygwin_From_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 14: "\Device\NamedPipe\msys-e022582115c10879-pty4-to-master" -> True
   procedure Test_Device_Named_Pipe_Msys_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Vector 15: "Device\NamedPipe\cygwin-e022582115c10879-pty4-to-master" -> False
   --  (no leading backslash; token[0]="Device\NamedPipe\cygwin" fails FUNC-CYG-007)
   procedure Test_No_Leading_Backslash_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 2 — Token Rule Boundary Tests (FUNC-CYG-007 through FUNC-CYG-012)
   ---------------------------------------------------------------------------

   --  FUNC-CYG-007: token[0] case sensitive — uppercase C in "Cygwin" -> False
   procedure Test_Token0_Uppercase_C_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-007: token[0] case sensitive — all-caps "MSYS" -> False
   procedure Test_Token0_All_Caps_Msys_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-009: token[2] minimum length — "pt" (only 2 chars) -> False
   procedure Test_Token2_Too_Short_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-010: token[3] invalid — "FROM" (uppercase) -> False
   procedure Test_Token3_Uppercase_From_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-010: token[3] invalid — "slave" (wrong direction word) -> False
   procedure Test_Token3_Slave_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-011: token[4] case — "MASTER" (uppercase) -> False
   procedure Test_Token4_Uppercase_Master_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-012: exactly 4 tokens (missing token[4]) -> False
   procedure Test_Four_Tokens_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-012: exactly 3 tokens -> False
   procedure Test_Three_Tokens_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-012: exactly 1 token (just "\cygwin") -> False
   procedure Test_One_Token_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CYG-009: empty token[2] (consecutive dashes) does not start with "pty" -> False
   procedure Test_Empty_Token2_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 3 — \Device\NamedPipe Prefix Variants
   ---------------------------------------------------------------------------

   --  "\Device\NamedPipe\cygwin-abc123-pty0-to-master" -> True
   procedure Test_Device_Named_Pipe_Cygwin_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "\Device\NamedPipe\msys-abc123-pty0-from-master" -> True
   procedure Test_Device_Named_Pipe_Msys_From_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Win32_Cygwin;
