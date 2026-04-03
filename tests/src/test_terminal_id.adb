-------------------------------------------------------------------------------
--  Test_Terminal_Id - Unit Tests for Termicap.Terminal_Id
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Cases;
use AUnit.Test_Cases.Registration;

with Termicap.Terminal_Id; use Termicap.Terminal_Id;
with Termicap.Environment; use Termicap.Environment;

package body Test_Terminal_Id is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Terminal_Id");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  Per-Terminal_Kind tests (FUNC-TID-012)
      Register_Routine
        (T,
         Test_Alacritty'Access,
         "FUNC-TID-012: TERM='alacritty' -> Kind=Alacritty");
      Register_Routine
        (T,
         Test_Apple_Terminal'Access,
         "FUNC-TID-012: TERM_PROGRAM='Apple_Terminal' -> Kind=Apple_Terminal");
      Register_Routine
        (T,
         Test_Dumb'Access,
         "FUNC-TID-012: TERM='dumb' -> Kind=Dumb");
      Register_Routine
        (T,
         Test_Foot'Access,
         "FUNC-TID-012: TERM='foot' -> Kind=Foot");
      Register_Routine
        (T,
         Test_Foot_Extra'Access,
         "FUNC-TID-012: TERM='foot-extra' -> Kind=Foot");
      Register_Routine
        (T,
         Test_Ghostty'Access,
         "FUNC-TID-012: TERM='xterm-ghostty' -> Kind=Ghostty");
      Register_Routine
        (T,
         Test_ITerm2'Access,
         "FUNC-TID-012: TERM_PROGRAM='iTerm.app' -> Kind=ITerm2");
      Register_Routine
        (T,
         Test_JediTerm'Access,
         "FUNC-TID-012: TERMINAL_EMULATOR='JetBrains-JediTerm' -> Kind=JediTerm");
      Register_Routine
        (T,
         Test_Kitty'Access,
         "FUNC-TID-012: TERM='xterm-kitty' -> Kind=Kitty");
      Register_Routine
        (T,
         Test_Konsole'Access,
         "FUNC-TID-012: KONSOLE_VERSION='210401' -> Kind=Konsole");
      Register_Routine
        (T,
         Test_Linux_Console'Access,
         "FUNC-TID-012: TERM='linux' -> Kind=Linux_Console");
      Register_Routine
        (T,
         Test_Mintty'Access,
         "FUNC-TID-012: TERM_PROGRAM='mintty' -> Kind=Mintty");
      Register_Routine
        (T,
         Test_Rxvt'Access,
         "FUNC-TID-012: TERM='rxvt-unicode-256color' -> Kind=Rxvt");
      Register_Routine
        (T,
         Test_Screen'Access,
         "FUNC-TID-012: TERM='screen-256color' -> Kind=Screen");
      Register_Routine
        (T,
         Test_Tmux_Via_Var'Access,
         "FUNC-TID-012: TMUX='/tmp/tmux-1234/default,1234,0' -> Kind=Tmux");
      Register_Routine
        (T,
         Test_Tmux_Via_Term'Access,
         "FUNC-TID-012: TERM='tmux-256color' (no TMUX var) -> Kind=Tmux");
      Register_Routine
        (T,
         Test_VSCode'Access,
         "FUNC-TID-012: TERM_PROGRAM='vscode' -> Kind=VSCode");
      Register_Routine
        (T,
         Test_VTE'Access,
         "FUNC-TID-012: VTE_VERSION='6800' -> Kind=VTE");
      Register_Routine
        (T,
         Test_WezTerm_Via_Program'Access,
         "FUNC-TID-012: TERM_PROGRAM='WezTerm' -> Kind=WezTerm");
      Register_Routine
        (T,
         Test_WezTerm_Via_Term'Access,
         "FUNC-TID-012: TERM='wezterm' -> Kind=WezTerm");
      Register_Routine
        (T,
         Test_Windows_Terminal'Access,
         "FUNC-TID-012: WT_SESSION='some-guid' -> Kind=Windows_Terminal");
      Register_Routine
        (T,
         Test_Xterm'Access,
         "FUNC-TID-012: TERM='xterm-256color' -> Kind=Xterm");

      --  Unknown fallback (FUNC-TID-005)
      Register_Routine
        (T,
         Test_Unknown_All_Absent'Access,
         "FUNC-TID-005: Empty environment -> Kind=Unknown, Is_Multiplexer=False, strings empty");

      --  Priority / shadow-rule tests (FUNC-TID-012)
      Register_Routine
        (T,
         Test_Priority_TERM_PROGRAM_Over_TERM'Access,
         "FUNC-TID-012: TERM_PROGRAM=iTerm.app shadows TERM=xterm-256color -> Kind=ITerm2");
      Register_Routine
        (T,
         Test_Priority_WT_SESSION_Over_TERM'Access,
         "FUNC-TID-012: WT_SESSION present shadows TERM=xterm -> Kind=Windows_Terminal");
      Register_Routine
        (T,
         Test_Priority_TMUX_Over_TERM'Access,
         "FUNC-TID-012: TMUX present shadows TERM=xterm -> Kind=Tmux");
      Register_Routine
        (T,
         Test_Priority_VTE_Over_TERM'Access,
         "FUNC-TID-012: VTE_VERSION present shadows TERM=xterm -> Kind=VTE");

      --  Case-insensitivity (FUNC-TID-010)
      Register_Routine
        (T,
         Test_Case_TERM_PROGRAM_Uppercase'Access,
         "FUNC-TID-010: TERM_PROGRAM='ITERM.APP' -> Kind=ITerm2 (case-insensitive)");
      Register_Routine
        (T,
         Test_Case_TERM_Uppercase'Access,
         "FUNC-TID-010: TERM='XTERM-256COLOR' -> Kind=Xterm (case-insensitive)");

      --  Is_Multiplexer (FUNC-TID-006)
      Register_Routine
        (T,
         Test_Is_Multiplexer_Tmux'Access,
         "FUNC-TID-006: Kind=Tmux -> Is_Multiplexer=True");
      Register_Routine
        (T,
         Test_Is_Multiplexer_Screen'Access,
         "FUNC-TID-006: Kind=Screen -> Is_Multiplexer=True");
      Register_Routine
        (T,
         Test_Not_Multiplexer_Kitty'Access,
         "FUNC-TID-006: Kind=Kitty -> Is_Multiplexer=False");
      Register_Routine
        (T,
         Test_Is_Multiplexer_Independent_Of_Kind'Access,
         "FUNC-TID-006: TERM_PROGRAM=vscode + TMUX -> Kind=VSCode, Is_Multiplexer=True");
      Register_Routine
        (T,
         Test_Is_Multiplexer_Screen_Via_Term_With_Program'Access,
         "FUNC-TID-006: TERM=screen-256color + TERM_PROGRAM=WezTerm -> Kind=WezTerm, Is_Multiplexer=True");

      --  String field tests (FUNC-TID-002, FUNC-TID-008)
      Register_Routine
        (T,
         Test_String_Fields_Populated'Access,
         "FUNC-TID-002/008: String fields populated from TERM_PROGRAM, TERM_PROGRAM_VERSION, TERM");
      Register_Routine
        (T,
         Test_String_Fields_Empty_When_Absent'Access,
         "FUNC-TID-002: Empty environment -> all string fields are empty strings");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  Per-Terminal_Kind Tests (FUNC-TID-012)
   ---------------------------------------------------------------------------

   procedure Test_Alacritty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "alacritty");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Alacritty,
         "TERM='alacritty' should yield Kind=Alacritty");
   end Test_Alacritty;


   procedure Test_Apple_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM_PROGRAM", "Apple_Terminal");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Apple_Terminal,
         "TERM_PROGRAM='Apple_Terminal' should yield Kind=Apple_Terminal");
   end Test_Apple_Terminal;


   procedure Test_Dumb
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "dumb");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Dumb,
         "TERM='dumb' should yield Kind=Dumb");
   end Test_Dumb;


   procedure Test_Foot
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "foot");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Foot,
         "TERM='foot' should yield Kind=Foot");
   end Test_Foot;


   procedure Test_Foot_Extra
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "foot-extra");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Foot,
         "TERM='foot-extra' should yield Kind=Foot");
   end Test_Foot_Extra;


   procedure Test_Ghostty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "xterm-ghostty");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Ghostty,
         "TERM='xterm-ghostty' should yield Kind=Ghostty");
   end Test_Ghostty;


   procedure Test_ITerm2
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM_PROGRAM", "iTerm.app");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = ITerm2,
         "TERM_PROGRAM='iTerm.app' should yield Kind=ITerm2");
   end Test_ITerm2;


   procedure Test_JediTerm
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERMINAL_EMULATOR", "JetBrains-JediTerm");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = JediTerm,
         "TERMINAL_EMULATOR='JetBrains-JediTerm' should yield Kind=JediTerm");
   end Test_JediTerm;


   procedure Test_Kitty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "xterm-kitty");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Kitty,
         "TERM='xterm-kitty' should yield Kind=Kitty");
   end Test_Kitty;


   procedure Test_Konsole
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "KONSOLE_VERSION", "210401");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Konsole,
         "KONSOLE_VERSION='210401' should yield Kind=Konsole");
   end Test_Konsole;


   procedure Test_Linux_Console
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "linux");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Linux_Console,
         "TERM='linux' should yield Kind=Linux_Console");
   end Test_Linux_Console;


   procedure Test_Mintty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM_PROGRAM", "mintty");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Mintty,
         "TERM_PROGRAM='mintty' should yield Kind=Mintty");
   end Test_Mintty;


   procedure Test_Rxvt
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "rxvt-unicode-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Rxvt,
         "TERM='rxvt-unicode-256color' should yield Kind=Rxvt");
   end Test_Rxvt;


   procedure Test_Screen
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "screen-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Screen,
         "TERM='screen-256color' should yield Kind=Screen");
   end Test_Screen;


   procedure Test_Tmux_Via_Var
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TMUX", "/tmp/tmux-1234/default,1234,0");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Tmux,
         "TMUX='/tmp/tmux-1234/default,1234,0' should yield Kind=Tmux");
   end Test_Tmux_Via_Var;


   procedure Test_Tmux_Via_Term
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "tmux-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Tmux,
         "TERM='tmux-256color' (no TMUX var) should yield Kind=Tmux");
   end Test_Tmux_Via_Term;


   procedure Test_VSCode
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM_PROGRAM", "vscode");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = VSCode,
         "TERM_PROGRAM='vscode' should yield Kind=VSCode");
   end Test_VSCode;


   procedure Test_VTE
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "VTE_VERSION", "6800");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = VTE,
         "VTE_VERSION='6800' should yield Kind=VTE");
   end Test_VTE;


   procedure Test_WezTerm_Via_Program
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM_PROGRAM", "WezTerm");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = WezTerm,
         "TERM_PROGRAM='WezTerm' should yield Kind=WezTerm");
   end Test_WezTerm_Via_Program;


   procedure Test_WezTerm_Via_Term
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "wezterm");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = WezTerm,
         "TERM='wezterm' should yield Kind=WezTerm");
   end Test_WezTerm_Via_Term;


   procedure Test_Windows_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "WT_SESSION", "some-guid-1234-5678-abcd-efghijkl");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Windows_Terminal,
         "WT_SESSION present should yield Kind=Windows_Terminal");
   end Test_Windows_Terminal;


   procedure Test_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "xterm-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Xterm,
         "TERM='xterm-256color' should yield Kind=Xterm");
   end Test_Xterm;

   ---------------------------------------------------------------------------
   --  Unknown Fallback Test (FUNC-TID-005)
   ---------------------------------------------------------------------------

   procedure Test_Unknown_All_Absent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  Completely empty environment — no detection variable is present
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Unknown,
         "Empty environment should yield Kind=Unknown");
      Assert
        (not Result.Is_Multiplexer,
         "Empty environment should yield Is_Multiplexer=False");
      Assert
        (Result.Program_Name = Null_Unbounded_String,
         "Empty environment should yield Program_Name as empty string");
      Assert
        (Result.Program_Version = Null_Unbounded_String,
         "Empty environment should yield Program_Version as empty string");
      Assert
        (Result.Term_Value = Null_Unbounded_String,
         "Empty environment should yield Term_Value as empty string");
   end Test_Unknown_All_Absent;

   ---------------------------------------------------------------------------
   --  Priority / Shadow-Rule Tests (FUNC-TID-012)
   ---------------------------------------------------------------------------

   procedure Test_Priority_TERM_PROGRAM_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  TERM_PROGRAM (priority 1) must shadow TERM (priority 7)
      Insert (Env, "TERM_PROGRAM", "iTerm.app");
      Insert (Env, "TERM", "xterm-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = ITerm2,
         "TERM_PROGRAM='iTerm.app' should shadow TERM='xterm-256color', yielding Kind=ITerm2");
   end Test_Priority_TERM_PROGRAM_Over_TERM;


   procedure Test_Priority_WT_SESSION_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  WT_SESSION (priority 3) must shadow TERM (priority 7)
      Insert (Env, "WT_SESSION", "some-guid");
      Insert (Env, "TERM", "xterm");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Windows_Terminal,
         "WT_SESSION present should shadow TERM='xterm', yielding Kind=Windows_Terminal");
   end Test_Priority_WT_SESSION_Over_TERM;


   procedure Test_Priority_TMUX_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  TMUX (priority 6) must shadow TERM=xterm (priority 7)
      Insert (Env, "TMUX", "/tmp/tmux-1000/default,1000,0");
      Insert (Env, "TERM", "xterm");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Tmux,
         "TMUX present should shadow TERM='xterm', yielding Kind=Tmux");
   end Test_Priority_TMUX_Over_TERM;


   procedure Test_Priority_VTE_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  VTE_VERSION (priority 5) must shadow TERM=xterm (priority 7)
      Insert (Env, "VTE_VERSION", "6800");
      Insert (Env, "TERM", "xterm");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = VTE,
         "VTE_VERSION present should shadow TERM='xterm', yielding Kind=VTE");
   end Test_Priority_VTE_Over_TERM;

   ---------------------------------------------------------------------------
   --  Case-Insensitivity Tests (FUNC-TID-010)
   ---------------------------------------------------------------------------

   procedure Test_Case_TERM_PROGRAM_Uppercase
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  Value comparison must be case-insensitive per FUNC-TID-010
      Insert (Env, "TERM_PROGRAM", "ITERM.APP");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = ITerm2,
         "TERM_PROGRAM='ITERM.APP' (uppercase) should yield Kind=ITerm2 (case-insensitive)");
   end Test_Case_TERM_PROGRAM_Uppercase;


   procedure Test_Case_TERM_Uppercase
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  TERM value comparison must be case-insensitive per FUNC-TID-010
      Insert (Env, "TERM", "XTERM-256COLOR");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Xterm,
         "TERM='XTERM-256COLOR' (uppercase) should yield Kind=Xterm (case-insensitive)");
   end Test_Case_TERM_Uppercase;

   ---------------------------------------------------------------------------
   --  Is_Multiplexer Tests (FUNC-TID-006)
   ---------------------------------------------------------------------------

   procedure Test_Is_Multiplexer_Tmux
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TMUX", "/tmp/tmux-1000/default,1000,0");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Tmux,
         "TMUX present should yield Kind=Tmux");
      Assert
        (Result.Is_Multiplexer,
         "Kind=Tmux should yield Is_Multiplexer=True");
   end Test_Is_Multiplexer_Tmux;


   procedure Test_Is_Multiplexer_Screen
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "screen-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Screen,
         "TERM='screen-256color' should yield Kind=Screen");
      Assert
        (Result.Is_Multiplexer,
         "Kind=Screen should yield Is_Multiplexer=True");
   end Test_Is_Multiplexer_Screen;


   procedure Test_Not_Multiplexer_Kitty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      Insert (Env, "TERM", "xterm-kitty");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = Kitty,
         "TERM='xterm-kitty' should yield Kind=Kitty");
      Assert
        (not Result.Is_Multiplexer,
         "Kind=Kitty should yield Is_Multiplexer=False");
   end Test_Not_Multiplexer_Kitty;


   procedure Test_Is_Multiplexer_Independent_Of_Kind
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  TERM_PROGRAM wins the Kind cascade (VSCode), but TMUX is also present.
      --  Is_Multiplexer must be True independently of Kind.
      Insert (Env, "TERM_PROGRAM", "vscode");
      Insert (Env, "TMUX", "/tmp/tmux-1000/default,12345,0");
      Insert (Env, "TERM", "xterm-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = VSCode,
         "TERM_PROGRAM=vscode should yield Kind=VSCode (cascade priority)");
      Assert
        (Result.Is_Multiplexer,
         "TMUX present should yield Is_Multiplexer=True even when Kind/=Tmux");
   end Test_Is_Multiplexer_Independent_Of_Kind;


   procedure Test_Is_Multiplexer_Screen_Via_Term_With_Program
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  TERM_PROGRAM wins Kind (WezTerm), but TERM=screen-256color means
      --  a GNU Screen multiplexer is present.  Is_Multiplexer must be True.
      Insert (Env, "TERM_PROGRAM", "WezTerm");
      Insert (Env, "TERM", "screen-256color");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = WezTerm,
         "TERM_PROGRAM=WezTerm should yield Kind=WezTerm (cascade priority)");
      Assert
        (Result.Is_Multiplexer,
         "TERM='screen-256color' should yield Is_Multiplexer=True even when Kind/=Screen");
   end Test_Is_Multiplexer_Screen_Via_Term_With_Program;

   ---------------------------------------------------------------------------
   --  String Field Tests (FUNC-TID-002, FUNC-TID-008)
   ---------------------------------------------------------------------------

   procedure Test_String_Fields_Populated
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  Verify that Program_Name, Program_Version, and Term_Value are populated
      --  verbatim from the environment, regardless of the Kind determination.
      Insert (Env, "TERM_PROGRAM", "WezTerm");
      Insert (Env, "TERM_PROGRAM_VERSION", "20231203-110809-5046fc22");
      Insert (Env, "TERM", "wezterm");
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Kind = WezTerm,
         "TERM_PROGRAM='WezTerm' + TERM='wezterm' should yield Kind=WezTerm");
      Assert
        (Result.Program_Name = To_Unbounded_String ("WezTerm"),
         "Program_Name should hold the raw TERM_PROGRAM value 'WezTerm'");
      Assert
        (Result.Program_Version = To_Unbounded_String ("20231203-110809-5046fc22"),
         "Program_Version should hold the raw TERM_PROGRAM_VERSION value '20231203-110809-5046fc22'");
      Assert
        (Result.Term_Value = To_Unbounded_String ("wezterm"),
         "Term_Value should hold the raw TERM value 'wezterm'");
   end Test_String_Fields_Populated;


   procedure Test_String_Fields_Empty_When_Absent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env    : Environment := EMPTY_ENVIRONMENT;
      Result : Terminal_Identity;
   begin
      --  When TERM_PROGRAM, TERM_PROGRAM_VERSION, and TERM are all absent,
      --  string fields must be the empty string.
      Result := Detect_Terminal_Identity (Env);
      Assert
        (Result.Program_Name = Null_Unbounded_String,
         "Program_Name should be empty when TERM_PROGRAM is absent");
      Assert
        (Result.Program_Version = Null_Unbounded_String,
         "Program_Version should be empty when TERM_PROGRAM_VERSION is absent");
      Assert
        (Result.Term_Value = Null_Unbounded_String,
         "Term_Value should be empty when TERM is absent");
   end Test_String_Fields_Empty_When_Absent;

end Test_Terminal_Id;
