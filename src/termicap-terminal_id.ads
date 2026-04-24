-------------------------------------------------------------------------------
--  Termicap.Terminal_Id - Terminal Identification (Passive)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Identifies the terminal emulator or multiplexer hosting the current
--  session by inspecting environment variables passively.
--
--  @description
--  Provides a pure, SPARK-annotated function that classifies the active
--  terminal into a Terminal_Kind enumeration value and returns a
--  Terminal_Identity record containing the classification, raw environment
--  variable strings, and a derived Is_Multiplexer flag.
--
--  Detection reads seven environment variables in strict priority order
--  (TERM_PROGRAM, TERMINAL_EMULATOR, WT_SESSION, KONSOLE_VERSION,
--  VTE_VERSION, TMUX, TERM) and performs all string comparisons
--  case-insensitively.  No OS calls are made and no global state is read.
--
--  Requirements Coverage:
--    - @relation(FUNC-TID-001): Terminal_Kind enumeration type
--    - @relation(FUNC-TID-002): Terminal_Identity record type
--    - @relation(FUNC-TID-003): Detect_Terminal_Identity function signature
--    - @relation(FUNC-TID-005): Unknown fallback postcondition
--    - @relation(FUNC-TID-006): Is_Multiplexer derivation rule
--    - @relation(FUNC-TID-007): SPARK Silver provability
--    - @relation(FUNC-TID-011): Multiplexer_Kind subtype

with Ada.Strings.Unbounded;
with Termicap.Environment;

package Termicap.Terminal_Id
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Terminal Kind Enumeration (FUNC-TID-001)
   ---------------------------------------------------------------------------

   --  @summary Classification of the active terminal emulator or multiplexer.
   --  @description Each value corresponds to a terminal identified passively
   --  from environment variables.  Unknown means no recognised signal was
   --  found; Dumb means the environment explicitly declared no capability.
   --  Callers performing exhaustive case analysis shall include an others
   --  branch to remain compatible with future enumeration extensions.
   --  @relation(FUNC-TID-001): Terminal_Kind enumeration
   type Terminal_Kind is
     (Unknown,
      Alacritty,
      Apple_Terminal,
      Dumb,
      Foot,
      Ghostty,
      ITerm2,
      JediTerm,
      Kitty,
      Konsole,
      Linux_Console,
      Mintty,
      Rxvt,
      Screen,
      Tmux,
      VSCode,
      VTE,
      WarpTerminal,
      WezTerm,
      Windows_Terminal,
      Xterm);

   ---------------------------------------------------------------------------
   --  Multiplexer Subset Subtype (FUNC-TID-011)
   ---------------------------------------------------------------------------

   --  @summary Subtype of Terminal_Kind restricted to terminal multiplexers.
   --  @description Usable in membership tests and case alternatives.  Adding
   --  a new multiplexer in a future version requires only updating this
   --  predicate and the Is_Multiplexer postcondition.
   --  @relation(FUNC-TID-011): Multiplexer_Kind subtype
   subtype Multiplexer_Kind is Terminal_Kind with Static_Predicate => Multiplexer_Kind in Tmux | Screen;

   ---------------------------------------------------------------------------
   --  Terminal Identity Record (FUNC-TID-002)
   ---------------------------------------------------------------------------

   --  @summary Aggregated result of passive terminal identification.
   --  @description All fields are read-only after construction; the record
   --  exposes no mutable state.  String fields hold raw environment variable
   --  values (verbatim, unmodified); absent variables yield the empty string.
   --  @relation(FUNC-TID-002): Terminal_Identity record type
   type Terminal_Identity is record
      --  Classified terminal or multiplexer; Unknown if unrecognised.
      Kind            : Terminal_Kind;
      --  Raw value of TERM_PROGRAM, or "" if absent.
      Program_Name    : Ada.Strings.Unbounded.Unbounded_String;
      --  Raw value of TERM_PROGRAM_VERSION, or "" if absent.
      Program_Version : Ada.Strings.Unbounded.Unbounded_String;
      --  Raw value of TERM, or "" if absent.
      Term_Value      : Ada.Strings.Unbounded.Unbounded_String;
      --  True when TMUX is present in the environment, or TERM starts with
      --  "tmux" or "screen".  Independent of Kind: a session may be both
      --  inside VS Code (Kind = VSCode) and inside tmux (Is_Multiplexer = True).
      Is_Multiplexer  : Boolean;
   end record;

   ---------------------------------------------------------------------------
   --  Detection Function (FUNC-TID-003, FUNC-TID-005, FUNC-TID-006)
   ---------------------------------------------------------------------------

   --  @summary Detect the terminal identity from an environment snapshot.
   --  @param Env An immutable environment variable snapshot.
   --  @return A Terminal_Identity record classifying the active terminal.
   --  @description Reads TERM_PROGRAM, TERMINAL_EMULATOR, WT_SESSION,
   --  KONSOLE_VERSION, VTE_VERSION, TMUX, and TERM in that priority order.
   --  All value comparisons are case-insensitive.  No OS calls are performed.
   --  @relation(FUNC-TID-003): Pure detection function signature
   --  @relation(FUNC-TID-005): Unknown fallback postcondition
   --  @relation(FUNC-TID-006): Is_Multiplexer derivation rule
   --  @relation(FUNC-TID-007): SPARK Silver provability
   function Detect_Terminal_Identity (Env : Termicap.Environment.Environment) return Terminal_Identity
   with
     Global => null,
     Post =>
       (if not Termicap.Environment.Contains (Env, "TERM_PROGRAM")
          and then not Termicap.Environment.Contains (Env, "TERMINAL_EMULATOR")
          and then not Termicap.Environment.Contains (Env, "WT_SESSION")
          and then not Termicap.Environment.Contains (Env, "KONSOLE_VERSION")
          and then not Termicap.Environment.Contains (Env, "VTE_VERSION")
          and then not Termicap.Environment.Contains (Env, "TMUX")
          and then not Termicap.Environment.Contains (Env, "TERM")
        then Detect_Terminal_Identity'Result.Kind = Unknown and then not Detect_Terminal_Identity'Result.Is_Multiplexer)
       and then (if Termicap.Environment.Contains (Env, "TMUX") then Detect_Terminal_Identity'Result.Is_Multiplexer);

end Termicap.Terminal_Id;
