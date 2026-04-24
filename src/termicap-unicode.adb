-------------------------------------------------------------------------------
--  Termicap.Unicode - Unicode Support Level Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements the 5-step priority cascade for terminal Unicode level detection.
--
--  @description
--  All logic is pure: enum comparisons, bounded string scans, and Environment
--  API calls with Global => null.  Fully SPARK-provable (Silver target).

with Termicap.Environment; use Termicap.Environment;

package body Termicap.Unicode
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Body-local helper: case-insensitive character lowering
   ---------------------------------------------------------------------------

   function To_Lower_Char (C : Character) return Character
   is (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32) else C)
   with Global => null;

   ---------------------------------------------------------------------------
   --  Body-local helper: case-insensitive string equality
   ---------------------------------------------------------------------------

   function Equal_Insensitive (A, B : String) return Boolean
   with Global => null;
   pragma Inline (Equal_Insensitive);

   function Equal_Insensitive (A, B : String) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in A'Range loop
         if To_Lower_Char (A (I)) /= To_Lower_Char (B (B'First + (I - A'First))) then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Insensitive;

   ---------------------------------------------------------------------------
   --  Body-local helper: 4-state FSM for UTF-8 substring detection
   ---------------------------------------------------------------------------

   function Contains_UTF8 (Source : String) return Boolean
   with Global => null;
   pragma Inline (Contains_UTF8);

   function Contains_UTF8 (Source : String) return Boolean is
      --  States: looking for 'u', then 't', then 'f', then '8'
      type Match_State is (Want_U, Want_T, Want_F, Want_8);
      State : Match_State := Want_U;
      C     : Character;
   begin
      for I in Source'Range loop
         C := To_Lower_Char (Source (I));
         case State is
            when Want_U =>
               if C = 'u' then
                  State := Want_T;
               end if;

            when Want_T =>
               if C = 't' then
                  State := Want_F;
               elsif C = 'u' then
                  State := Want_T;  --  restart: new potential 'u' start
               elsif C in 'a' .. 'z' | '0' .. '9' then
                  State := Want_U;  --  alphanumeric break: reset
               end if;
               --  Non-alphanumeric characters are ignored (separator tolerance)

            when Want_F =>
               if C = 'f' then
                  State := Want_8;
               elsif C = 'u' then
                  State := Want_T;  --  restart
               elsif C in 'a' .. 'z' | '0' .. '9' then
                  State := Want_U;
               end if;

            when Want_8 =>
               if C = '8' then
                  return True;
               elsif C = 'u' then
                  State := Want_T;  --  restart
               elsif C in 'a' .. 'z' | '0' .. '9' then
                  State := Want_U;
               end if;
         end case;
      end loop;
      return False;
   end Contains_UTF8;

   ---------------------------------------------------------------------------
   --  Body-local helper: locale inspection (FUNC-UNI-003)
   ---------------------------------------------------------------------------

   function Has_UTF8_Locale (Env : Termicap.Environment.Environment) return Boolean
   with Global => null;
   pragma Inline (Has_UTF8_Locale);

   function Has_UTF8_Locale (Env : Termicap.Environment.Environment) return Boolean is
   begin
      --  LC_ALL > LC_CTYPE > LANG (POSIX resolution order)
      if Contains (Env, "LC_ALL") and then Value (Env, "LC_ALL")'Length > 0 then
         return Contains_UTF8 (Value (Env, "LC_ALL"));
      end if;

      if Contains (Env, "LC_CTYPE") and then Value (Env, "LC_CTYPE")'Length > 0 then
         return Contains_UTF8 (Value (Env, "LC_CTYPE"));
      end if;

      if Contains (Env, "LANG") and then Value (Env, "LANG")'Length > 0 then
         return Contains_UTF8 (Value (Env, "LANG"));
      end if;

      return False;
   end Has_UTF8_Locale;

   ---------------------------------------------------------------------------
   --  Body-local helper: CI environment Unicode awareness (FUNC-UNI-006)
   ---------------------------------------------------------------------------

   function Is_CI_Unicode (Env : Termicap.Environment.Environment) return Boolean
   with Global => null;
   pragma Inline (Is_CI_Unicode);

   function Is_CI_Unicode (Env : Termicap.Environment.Environment) return Boolean is
   begin
      return
        Contains (Env, "GITHUB_ACTIONS") or else Contains (Env, "GITEA_ACTIONS") or else Contains (Env, "CIRCLECI");
   end Is_CI_Unicode;

   ---------------------------------------------------------------------------
   --  Body-local helper: Windows Unicode heuristics (FUNC-UNI-005)
   ---------------------------------------------------------------------------

   function Detect_Windows_Unicode (Env : Termicap.Environment.Environment) return Unicode_Level
   with Global => null;
   pragma Inline (Detect_Windows_Unicode);

   function Detect_Windows_Unicode (Env : Termicap.Environment.Environment) return Unicode_Level is
   begin
      --  Windows Terminal (WT_SESSION is set by Windows Terminal)
      if Contains (Env, "WT_SESSION") then
         return Basic;
      end if;

      --  VS Code integrated terminal
      if Equal_Insensitive (Value (Env, "TERM_PROGRAM"), "vscode") then
         return Basic;
      end if;

      --  Known Unicode-capable TERM values on Windows
      if Value_Matches (Env, "TERM", ["xterm-256color", "alacritty", "rxvt-unicode", "rxvt-unicode-256color"]) then
         return Basic;
      end if;

      --  JetBrains IDE terminal
      if Equal_Insensitive (Value (Env, "TERMINAL_EMULATOR"), "JetBrains-JediTerm") then
         return Basic;
      end if;

      return None;
   end Detect_Windows_Unicode;

   ---------------------------------------------------------------------------
   --  Main detection function: 5-step priority cascade (FUNC-UNI-008)
   ---------------------------------------------------------------------------

   function Detect_Unicode_Level (Env : Termicap.Environment.Environment) return Unicode_Level is
      Floor : Unicode_Level := None;
   begin
      --  Step 1: Locale inspection (FUNC-UNI-003)
      if Has_UTF8_Locale (Env) then
         Floor := Basic;
      end if;

      --  Step 2: CI heuristics (FUNC-UNI-006)
      if Is_CI_Unicode (Env) then
         Floor := Unicode_Level'Max (Floor, Basic);
      end if;

      --  Step 3: TERM=linux exclusion (FUNC-UNI-004)
      if Equal_Insensitive (Value (Env, "TERM"), "linux") and then Floor = None then
         return None;
      end if;

      --  Step 4: Windows heuristics (FUNC-UNI-005)
      if Equal_Insensitive (Value (Env, "OS_TYPE"), "Windows_NT") then
         Floor := Unicode_Level'Max (Floor, Detect_Windows_Unicode (Env));
      end if;

      --  Step 5: Default
      return Floor;
   end Detect_Unicode_Level;

end Termicap.Unicode;
