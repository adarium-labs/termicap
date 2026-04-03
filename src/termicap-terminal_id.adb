-------------------------------------------------------------------------------
--  Termicap.Terminal_Id - Terminal Identification (Passive) (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements the 8-step priority cascade for passive terminal identification.
--
--  @description
--  Body is compiled with SPARK_Mode => Off because the implementation uses
--  Ada.Strings.Unbounded, which is a controlled type not supported by the
--  SPARK subset.  The spec-level SPARK contracts (Global => null and the
--  two Post conditions) remain verifiable for all callers in the SPARK zone.
--  See ADR-0008 for the full rationale.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Termicap.Environment;  use Termicap.Environment;
with Termicap.Terminal_Id;

package body Termicap.Terminal_Id
  with SPARK_Mode => Off
is

   --  Case-insensitive prefix check.  True when Source begins with Prefix.
   function Starts_With_CI (Source : String; Prefix : String) return Boolean is
      Src_Len : constant Natural := Source'Length;
      Pre_Len : constant Natural := Prefix'Length;

      function To_Lower (C : Character) return Character is
         Offset : constant := Character'Pos ('a') - Character'Pos ('A');
      begin
         if C in 'A' .. 'Z' then
            return Character'Val (Character'Pos (C) + Offset);
         else
            return C;
         end if;
      end To_Lower;

   begin
      if Src_Len < Pre_Len then
         return False;
      end if;
      for I in 1 .. Pre_Len loop
         if To_Lower (Source (Source'First + I - 1))
           /= To_Lower (Prefix (Prefix'First + I - 1))
         then
            return False;
         end if;
      end loop;
      return True;
   end Starts_With_CI;

   function Detect_Terminal_Identity
     (Env : Termicap.Environment.Environment) return Terminal_Identity
   is
      Result : Terminal_Identity :=
        (Kind            => Unknown,
         Program_Name    => Null_Unbounded_String,
         Program_Version => Null_Unbounded_String,
         Term_Value      => Null_Unbounded_String,
         Is_Multiplexer  => False);
   begin
      --  Populate raw string fields regardless of classification outcome
      --  (FUNC-TID-004: string fields always populated from env vars).
      Result.Program_Name := To_Unbounded_String (Value (Env, "TERM_PROGRAM"));
      Result.Program_Version :=
        To_Unbounded_String (Value (Env, "TERM_PROGRAM_VERSION"));
      Result.Term_Value := To_Unbounded_String (Value (Env, "TERM"));

      --  Step 1: TERM_PROGRAM (FUNC-TID-004, priority 1)
      if Contains (Env, "TERM_PROGRAM") then
         declare
            TP : constant String := Value (Env, "TERM_PROGRAM");
         begin
            if Equal_Case_Insensitive (TP, "iTerm.app") then
               Result.Kind := ITerm2;
            elsif Equal_Case_Insensitive (TP, "Apple_Terminal") then
               Result.Kind := Apple_Terminal;
            elsif Equal_Case_Insensitive (TP, "vscode") then
               Result.Kind := VSCode;
            elsif Equal_Case_Insensitive (TP, "WezTerm") then
               Result.Kind := WezTerm;
            elsif Equal_Case_Insensitive (TP, "WarpTerminal") then
               Result.Kind := WarpTerminal;
            elsif Equal_Case_Insensitive (TP, "mintty") then
               Result.Kind := Mintty;
            end if;
         end;
      end if;

      --  Step 2: TERMINAL_EMULATOR (FUNC-TID-004, priority 2)
      if Result.Kind = Unknown and then Contains (Env, "TERMINAL_EMULATOR")
      then
         if Equal_Case_Insensitive
              (Value (Env, "TERMINAL_EMULATOR"), "JetBrains-JediTerm")
         then
            Result.Kind := JediTerm;
         end if;
      end if;

      --  Step 3: WT_SESSION presence (FUNC-TID-004, priority 3)
      if Result.Kind = Unknown and then Contains (Env, "WT_SESSION") then
         Result.Kind := Windows_Terminal;
      end if;

      --  Step 4: KONSOLE_VERSION presence (FUNC-TID-004, priority 4)
      if Result.Kind = Unknown and then Contains (Env, "KONSOLE_VERSION") then
         Result.Kind := Konsole;
      end if;

      --  Step 5: VTE_VERSION presence (FUNC-TID-004, priority 5)
      if Result.Kind = Unknown and then Contains (Env, "VTE_VERSION") then
         Result.Kind := VTE;
      end if;

      --  Step 6: TMUX presence (FUNC-TID-004, priority 6)
      if Result.Kind = Unknown and then Contains (Env, "TMUX") then
         Result.Kind := Tmux;
      end if;

      --  Step 7: TERM value/prefix matching (FUNC-TID-004, priority 7)
      if Result.Kind = Unknown and then Contains (Env, "TERM") then
         declare
            T : constant String := Value (Env, "TERM");
         begin
            if Equal_Case_Insensitive (T, "dumb") then
               Result.Kind := Dumb;
            elsif Equal_Case_Insensitive (T, "linux") then
               Result.Kind := Linux_Console;
            elsif Starts_With_CI (T, "tmux") then
               Result.Kind := Tmux;
            elsif Starts_With_CI (T, "screen") then
               Result.Kind := Screen;
            elsif Equal_Case_Insensitive (T, "xterm-kitty") then
               Result.Kind := Kitty;
            elsif Equal_Case_Insensitive (T, "xterm-ghostty") then
               Result.Kind := Ghostty;
            elsif Equal_Case_Insensitive (T, "alacritty") then
               Result.Kind := Alacritty;
            elsif Equal_Case_Insensitive (T, "wezterm") then
               Result.Kind := WezTerm;
            elsif Starts_With_CI (T, "rxvt") then
               Result.Kind := Rxvt;
            elsif Equal_Case_Insensitive (T, "foot")
              or else Equal_Case_Insensitive (T, "foot-extra")
            then
               Result.Kind := Foot;
            elsif Starts_With_CI (T, "xterm") then
               Result.Kind := Xterm;
            end if;
         end;
      end if;

      --  Step 8: Default -- Kind remains Unknown if no rule matched.

      --  Derive Is_Multiplexer from raw env vars, independent of Kind
      --  (FUNC-TID-006, Approach B).  Is_Multiplexer is True when a
      --  multiplexer layer is present regardless of which terminal emulator
      --  was classified (e.g., VSCode inside tmux: Kind=VSCode, Is_Multiplexer=True).
      Result.Is_Multiplexer :=
        Contains (Env, "TMUX")
        or else (Contains (Env, "TERM")
                 and then (Starts_With_CI (Value (Env, "TERM"), "tmux")
                           or else Starts_With_CI (Value (Env, "TERM"), "screen")));

      return Result;
   end Detect_Terminal_Identity;

end Termicap.Terminal_Id;
