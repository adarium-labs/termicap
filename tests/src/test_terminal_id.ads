-------------------------------------------------------------------------------
--  Test_Terminal_Id - Unit Tests for Termicap.Terminal_Id
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Terminal_Kind enumeration, Terminal_Identity
--  record, and the full Detect_Terminal_Identity 7-step priority cascade.
--
--  Requirements Coverage:
--    - @relation(FUNC-TID-001): Terminal_Kind enumeration type
--    - @relation(FUNC-TID-002): Terminal_Identity record type
--    - @relation(FUNC-TID-004): Environment variable reading order and priority
--    - @relation(FUNC-TID-005): Unknown fallback postcondition
--    - @relation(FUNC-TID-006): Is_Multiplexer derivation rule
--    - @relation(FUNC-TID-008): Version string representation strategy
--    - @relation(FUNC-TID-010): Case-insensitive string comparison
--    - @relation(FUNC-TID-012): Unit testability of each classification rule

with AUnit.Test_Cases;

package Test_Terminal_Id is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Per-Terminal_Kind Tests (FUNC-TID-012)
   ---------------------------------------------------------------------------

   --  FUNC-TID-012: TERM=alacritty -> Kind=Alacritty
   procedure Test_Alacritty
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM_PROGRAM=Apple_Terminal -> Kind=Apple_Terminal
   procedure Test_Apple_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=dumb -> Kind=Dumb
   procedure Test_Dumb
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=foot -> Kind=Foot
   procedure Test_Foot
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=foot-extra -> Kind=Foot
   procedure Test_Foot_Extra
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=xterm-ghostty -> Kind=Ghostty
   procedure Test_Ghostty
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM_PROGRAM=iTerm.app -> Kind=ITerm2
   procedure Test_ITerm2
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERMINAL_EMULATOR=JetBrains-JediTerm -> Kind=JediTerm
   procedure Test_JediTerm
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=xterm-kitty -> Kind=Kitty
   procedure Test_Kitty
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: KONSOLE_VERSION=210401 -> Kind=Konsole
   procedure Test_Konsole
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=linux -> Kind=Linux_Console
   procedure Test_Linux_Console
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM_PROGRAM=mintty -> Kind=Mintty
   procedure Test_Mintty
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=rxvt-unicode-256color -> Kind=Rxvt
   procedure Test_Rxvt
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=screen-256color -> Kind=Screen
   procedure Test_Screen
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TMUX=/tmp/tmux-1234/default,1234,0 -> Kind=Tmux
   procedure Test_Tmux_Via_Var
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=tmux-256color (no TMUX var) -> Kind=Tmux
   procedure Test_Tmux_Via_Term
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM_PROGRAM=vscode -> Kind=VSCode
   procedure Test_VSCode
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: VTE_VERSION=6800 -> Kind=VTE
   procedure Test_VTE
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM_PROGRAM=WezTerm -> Kind=WezTerm
   procedure Test_WezTerm_Via_Program
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=wezterm -> Kind=WezTerm
   procedure Test_WezTerm_Via_Term
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: WT_SESSION=some-guid -> Kind=Windows_Terminal
   procedure Test_Windows_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TERM=xterm-256color -> Kind=Xterm
   procedure Test_Xterm
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Unknown Fallback Test (FUNC-TID-005)
   ---------------------------------------------------------------------------

   --  FUNC-TID-005: Empty environment -> Kind=Unknown, Is_Multiplexer=False, strings=""
   procedure Test_Unknown_All_Absent
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Priority / Shadow-Rule Tests (FUNC-TID-012)
   ---------------------------------------------------------------------------

   --  FUNC-TID-012: TERM_PROGRAM=iTerm.app + TERM=xterm-256color -> Kind=ITerm2
   procedure Test_Priority_TERM_PROGRAM_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: WT_SESSION=guid + TERM=xterm -> Kind=Windows_Terminal
   procedure Test_Priority_WT_SESSION_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: TMUX=... + TERM=xterm -> Kind=Tmux
   procedure Test_Priority_TMUX_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-012: VTE_VERSION=6800 + TERM=xterm -> Kind=VTE
   procedure Test_Priority_VTE_Over_TERM
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Case-Insensitivity Tests (FUNC-TID-010)
   ---------------------------------------------------------------------------

   --  FUNC-TID-010: TERM_PROGRAM=ITERM.APP -> Kind=ITerm2
   procedure Test_Case_TERM_PROGRAM_Uppercase
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-010: TERM=XTERM-256COLOR -> Kind=Xterm
   procedure Test_Case_TERM_Uppercase
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Is_Multiplexer Tests (FUNC-TID-006)
   ---------------------------------------------------------------------------

   --  FUNC-TID-006: Kind=Tmux -> Is_Multiplexer=True
   procedure Test_Is_Multiplexer_Tmux
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-006: Kind=Screen -> Is_Multiplexer=True
   procedure Test_Is_Multiplexer_Screen
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-006: Kind=Kitty -> Is_Multiplexer=False
   procedure Test_Not_Multiplexer_Kitty
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-006: TERM_PROGRAM=vscode + TMUX present -> Kind=VSCode, Is_Multiplexer=True
   procedure Test_Is_Multiplexer_Independent_Of_Kind
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-006: TERM=screen-256color + TERM_PROGRAM=WezTerm -> Kind=WezTerm, Is_Multiplexer=True
   procedure Test_Is_Multiplexer_Screen_Via_Term_With_Program
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  String Field Tests (FUNC-TID-002, FUNC-TID-008)
   ---------------------------------------------------------------------------

   --  FUNC-TID-002/008: TERM_PROGRAM=WezTerm, TERM_PROGRAM_VERSION=20231203, TERM=wezterm
   procedure Test_String_Fields_Populated
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TID-002: Empty environment -> all string fields = ""
   procedure Test_String_Fields_Empty_When_Absent
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Terminal_Id;
