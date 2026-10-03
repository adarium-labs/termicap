-------------------------------------------------------------------------------
--  Test_Win32_Cygwin - Unit Tests for Termicap.Win32_Cygwin
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Cases; use AUnit.Test_Cases.Registration;

with Termicap.Win32_Cygwin; use Termicap.Win32_Cygwin;

package body Test_Win32_Cygwin is


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Win32_Cygwin");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  Group 1 — go-isatty Acceptance Vectors (FUNC-CYG-013)
      Register_Routine (T, Test_Empty_String_False'Access,
         "FUNC-CYG-013 V1: """" -> False (fewer than 5 segments)");
      Register_Routine (T, Test_Msys_Single_Dash_False'Access,
         "FUNC-CYG-013 V2: ""\msys-"" -> False (only 2 segments)");
      Register_Routine (T, Test_Cygwin_Five_Dashes_False'Access,
         "FUNC-CYG-013 V3: ""\cygwin-----"" -> False (token[1] empty)");
      Register_Routine (T, Test_Msys_Uppercase_Pty_Token2_False'Access,
         "FUNC-CYG-013 V4: ""\msys-x-PTY5-pty1-from-master"" -> False (token[2]=PTY5 uppercase)");
      Register_Routine (T, Test_Cygwin_Uppercase_Pty_Token2_False'Access,
         "FUNC-CYG-013 V5: ""\cygwin-x-PTY5-from-master"" -> False (token[2]=PTY5 uppercase)");
      Register_Routine (T, Test_Cygwin_Toaster_False'Access,
         "FUNC-CYG-013 V6: ""\cygwin-x-pty2-from-toaster"" -> False (token[4]=toaster)");
      Register_Routine (T, Test_Cygwin_Empty_Session_Id_False'Access,
         "FUNC-CYG-013 V7: ""\cygwin--pty2-from-master"" -> False (token[1] empty)");
      Register_Routine (T, Test_Cygwin_Double_Backslash_False'Access,
         "FUNC-CYG-013 V8: ""\\cygwin-x-pty2-from-master"" -> False (double backslash)");
      Register_Routine (T, Test_Cygwin_Trailing_Dash_True'Access,
         "FUNC-CYG-013 V9: ""\cygwin-x-pty2-from-master-"" -> True (trailing dash ok)");
      Register_Routine (T, Test_Cygwin_From_Master_True'Access,
         "FUNC-CYG-013 V10: ""\cygwin-e022582115c10879-pty4-from-master"" -> True");
      Register_Routine (T, Test_Msys_To_Master_True'Access,
         "FUNC-CYG-013 V11: ""\msys-e022582115c10879-pty4-to-master"" -> True");
      Register_Routine (T, Test_Cygwin_To_Master_True'Access,
         "FUNC-CYG-013 V12: ""\cygwin-e022582115c10879-pty4-to-master"" -> True");
      Register_Routine (T, Test_Device_Named_Pipe_Cygwin_From_Master_True'Access,
         "FUNC-CYG-013 V13: ""\Device\NamedPipe\cygwin-...-pty4-from-master"" -> True");
      Register_Routine (T, Test_Device_Named_Pipe_Msys_To_Master_True'Access,
         "FUNC-CYG-013 V14: ""\Device\NamedPipe\msys-...-pty4-to-master"" -> True");
      Register_Routine (T, Test_No_Leading_Backslash_False'Access,
         "FUNC-CYG-013 V15: ""Device\NamedPipe\cygwin-..."" -> False (no leading backslash)");

      --  Group 2 — Token Rule Boundary Tests (FUNC-CYG-007 through FUNC-CYG-012)
      Register_Routine (T, Test_Token0_Uppercase_C_False'Access,
         "FUNC-CYG-007: ""\Cygwin-x-pty2-from-master"" -> False (uppercase C)");
      Register_Routine (T, Test_Token0_All_Caps_Msys_False'Access,
         "FUNC-CYG-007: ""\MSYS-x-pty2-from-master"" -> False (all caps)");
      Register_Routine (T, Test_Token2_Too_Short_False'Access,
         "FUNC-CYG-009: ""\cygwin-x-pt-from-master"" -> False (token[2] too short)");
      Register_Routine (T, Test_Token3_Uppercase_From_False'Access,
         "FUNC-CYG-010: ""\cygwin-x-pty2-FROM-master"" -> False (uppercase FROM)");
      Register_Routine (T, Test_Token3_Slave_False'Access,
         "FUNC-CYG-010: ""\cygwin-x-pty2-slave-master"" -> False (wrong direction word)");
      Register_Routine (T, Test_Token4_Uppercase_Master_False'Access,
         "FUNC-CYG-011: ""\cygwin-x-pty2-from-MASTER"" -> False (uppercase MASTER)");
      Register_Routine (T, Test_Four_Tokens_False'Access,
         "FUNC-CYG-012: ""\cygwin-x-pty2-from"" -> False (missing token[4])");
      Register_Routine (T, Test_Three_Tokens_False'Access,
         "FUNC-CYG-012: ""\cygwin-x-pty2"" -> False (only 3 tokens)");
      Register_Routine (T, Test_One_Token_False'Access,
         "FUNC-CYG-012: ""\cygwin"" -> False (only 1 token)");
      Register_Routine (T, Test_Empty_Token2_False'Access,
         "FUNC-CYG-009: ""\cygwin-x--from-master"" -> False (empty token[2])");

      --  Group 3 — \Device\NamedPipe prefix variants
      Register_Routine (T, Test_Device_Named_Pipe_Cygwin_To_Master_True'Access,
         "FUNC-CYG-007: ""\Device\NamedPipe\cygwin-abc123-pty0-to-master"" -> True");
      Register_Routine (T, Test_Device_Named_Pipe_Msys_From_Master_True'Access,
         "FUNC-CYG-007: ""\Device\NamedPipe\msys-abc123-pty0-from-master"" -> True");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Group 1 — go-isatty Acceptance Vectors (FUNC-CYG-013)
   ---------------------------------------------------------------------------


   procedure Test_Empty_String_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name (""),
          """" & """" & """ -> Is_Cygwin_Pipe_Name should return False (empty string, <5 segments)");
   end Test_Empty_String_False;


   procedure Test_Msys_Single_Dash_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\msys-"),
          """\msys-"" -> Is_Cygwin_Pipe_Name should return False (only 2 segments)");
   end Test_Msys_Single_Dash_False;


   procedure Test_Cygwin_Five_Dashes_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-----"),
          """\cygwin-----"" -> Is_Cygwin_Pipe_Name should return False (token[1] empty)");
   end Test_Cygwin_Five_Dashes_False;


   procedure Test_Msys_Uppercase_Pty_Token2_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\msys-x-PTY5-pty1-from-master"),
          """\msys-x-PTY5-pty1-from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[2]=""PTY5"" uppercase, fails FUNC-CYG-009)");
   end Test_Msys_Uppercase_Pty_Token2_False;


   procedure Test_Cygwin_Uppercase_Pty_Token2_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-PTY5-from-master"),
          """\cygwin-x-PTY5-from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[2]=""PTY5"" uppercase, fails FUNC-CYG-009)");
   end Test_Cygwin_Uppercase_Pty_Token2_False;


   procedure Test_Cygwin_Toaster_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-pty2-from-toaster"),
          """\cygwin-x-pty2-from-toaster"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[4]=""toaster"", fails FUNC-CYG-011)");
   end Test_Cygwin_Toaster_False;


   procedure Test_Cygwin_Empty_Session_Id_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin--pty2-from-master"),
          """\cygwin--pty2-from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[1] empty, fails FUNC-CYG-008)");
   end Test_Cygwin_Empty_Session_Id_False;


   procedure Test_Cygwin_Double_Backslash_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\\cygwin-x-pty2-from-master"),
          """\\cygwin-x-pty2-from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (double backslash prefix, token[0]=""\\cygwin"", fails FUNC-CYG-007)");
   end Test_Cygwin_Double_Backslash_False;


   procedure Test_Cygwin_Trailing_Dash_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\cygwin-x-pty2-from-master-"),
          """\cygwin-x-pty2-from-master-"" -> Is_Cygwin_Pipe_Name should return True"
          & " (trailing dash produces 6th segment which is ignored per FUNC-CYG-011)");
   end Test_Cygwin_Trailing_Dash_True;


   procedure Test_Cygwin_From_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\cygwin-e022582115c10879-pty4-from-master"),
          """\cygwin-e022582115c10879-pty4-from-master"" -> Is_Cygwin_Pipe_Name should return True");
   end Test_Cygwin_From_Master_True;


   procedure Test_Msys_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\msys-e022582115c10879-pty4-to-master"),
          """\msys-e022582115c10879-pty4-to-master"" -> Is_Cygwin_Pipe_Name should return True");
   end Test_Msys_To_Master_True;


   procedure Test_Cygwin_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\cygwin-e022582115c10879-pty4-to-master"),
          """\cygwin-e022582115c10879-pty4-to-master"" -> Is_Cygwin_Pipe_Name should return True");
   end Test_Cygwin_To_Master_True;


   procedure Test_Device_Named_Pipe_Cygwin_From_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\Device\NamedPipe\cygwin-e022582115c10879-pty4-from-master"),
          """\Device\NamedPipe\cygwin-e022582115c10879-pty4-from-master"""
          & " -> Is_Cygwin_Pipe_Name should return True");
   end Test_Device_Named_Pipe_Cygwin_From_Master_True;


   procedure Test_Device_Named_Pipe_Msys_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\Device\NamedPipe\msys-e022582115c10879-pty4-to-master"),
          """\Device\NamedPipe\msys-e022582115c10879-pty4-to-master"""
          & " -> Is_Cygwin_Pipe_Name should return True");
   end Test_Device_Named_Pipe_Msys_To_Master_True;


   procedure Test_No_Leading_Backslash_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("Device\NamedPipe\cygwin-e022582115c10879-pty4-to-master"),
          """Device\NamedPipe\cygwin-e022582115c10879-pty4-to-master"""
          & " -> Is_Cygwin_Pipe_Name should return False (no leading backslash,"
          & " token[0]=""Device\NamedPipe\cygwin"" not in accepted set, fails FUNC-CYG-007)");
   end Test_No_Leading_Backslash_False;


   ---------------------------------------------------------------------------
   --  Group 2 — Token Rule Boundary Tests (FUNC-CYG-007 through FUNC-CYG-012)
   ---------------------------------------------------------------------------


   procedure Test_Token0_Uppercase_C_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\Cygwin-x-pty2-from-master"),
          """\Cygwin-x-pty2-from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[0]=""\Cygwin"" uppercase C, case-sensitive match fails FUNC-CYG-007)");
   end Test_Token0_Uppercase_C_False;


   procedure Test_Token0_All_Caps_Msys_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\MSYS-x-pty2-from-master"),
          """\MSYS-x-pty2-from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[0]=""\MSYS"" all caps, case-sensitive match fails FUNC-CYG-007)");
   end Test_Token0_All_Caps_Msys_False;


   procedure Test_Token2_Too_Short_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-pt-from-master"),
          """\cygwin-x-pt-from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[2]=""pt"" is only 2 chars, minimum 3 required, fails FUNC-CYG-009)");
   end Test_Token2_Too_Short_False;


   procedure Test_Token3_Uppercase_From_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-pty2-FROM-master"),
          """\cygwin-x-pty2-FROM-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[3]=""FROM"" uppercase, case-sensitive match fails FUNC-CYG-010)");
   end Test_Token3_Uppercase_From_False;


   procedure Test_Token3_Slave_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-pty2-slave-master"),
          """\cygwin-x-pty2-slave-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[3]=""slave"" is not ""from"" or ""to"", fails FUNC-CYG-010)");
   end Test_Token3_Slave_False;


   procedure Test_Token4_Uppercase_Master_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-pty2-from-MASTER"),
          """\cygwin-x-pty2-from-MASTER"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[4]=""MASTER"" uppercase, case-sensitive match fails FUNC-CYG-011)");
   end Test_Token4_Uppercase_Master_False;


   procedure Test_Four_Tokens_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-pty2-from"),
          """\cygwin-x-pty2-from"" -> Is_Cygwin_Pipe_Name should return False"
          & " (only 4 tokens, token[4] missing, fails FUNC-CYG-012)");
   end Test_Four_Tokens_False;


   procedure Test_Three_Tokens_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x-pty2"),
          """\cygwin-x-pty2"" -> Is_Cygwin_Pipe_Name should return False"
          & " (only 3 tokens, fails FUNC-CYG-012)");
   end Test_Three_Tokens_False;


   procedure Test_One_Token_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin"),
          """\cygwin"" -> Is_Cygwin_Pipe_Name should return False"
          & " (only 1 token, fails FUNC-CYG-012)");
   end Test_One_Token_False;


   procedure Test_Empty_Token2_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (not Is_Cygwin_Pipe_Name ("\cygwin-x--from-master"),
          """\cygwin-x--from-master"" -> Is_Cygwin_Pipe_Name should return False"
          & " (token[2] is empty, does not start with ""pty"", fails FUNC-CYG-009)");
   end Test_Empty_Token2_False;


   ---------------------------------------------------------------------------
   --  Group 3 — \Device\NamedPipe Prefix Variants
   ---------------------------------------------------------------------------


   procedure Test_Device_Named_Pipe_Cygwin_To_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\Device\NamedPipe\cygwin-abc123-pty0-to-master"),
          """\Device\NamedPipe\cygwin-abc123-pty0-to-master"""
          & " -> Is_Cygwin_Pipe_Name should return True");
   end Test_Device_Named_Pipe_Cygwin_To_Master_True;


   procedure Test_Device_Named_Pipe_Msys_From_Master_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Is_Cygwin_Pipe_Name ("\Device\NamedPipe\msys-abc123-pty0-from-master"),
          """\Device\NamedPipe\msys-abc123-pty0-from-master"""
          & " -> Is_Cygwin_Pipe_Name should return True");
   end Test_Device_Named_Pipe_Msys_From_Master_True;


end Test_Win32_Cygwin;
