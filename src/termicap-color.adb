-------------------------------------------------------------------------------
--  Termicap.Color - Color Level Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements the 11-step priority cascade for terminal color level detection.
--
--  @description
--  All logic is pure: enum comparisons, string matching via the Environment
--  API, no FFI.  Fully SPARK-provable (Silver target).

with Termicap.Environment; use Termicap.Environment;

package body Termicap.Color
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Body-local enumeration types
   ---------------------------------------------------------------------------

   --  Classifier for FORCE_COLOR raw string values (ADR-0005)
   type Force_Color_Token is (FC_Zero, FC_False, FC_One, FC_True, FC_Empty, FC_Two, FC_Three, FC_Other);

   --  Classifier for TERM_PROGRAM raw string values (FUNC-CLR-010)
   type Term_Program_Token is (TP_ITerm, TP_Apple_Terminal, TP_VSCode, TP_Other);

   ---------------------------------------------------------------------------
   --  Body-local helper: case-insensitive character lowering
   ---------------------------------------------------------------------------

   function To_Lower_Char (C : Character) return Character
   is (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32) else C)
   with Global => null;

   ---------------------------------------------------------------------------
   --  Body-local string helpers
   ---------------------------------------------------------------------------

   --  @summary Case-insensitive suffix check.
   function Ends_With (Source : String; Suffix : String) return Boolean
   with Global => null;
   pragma Inline (Ends_With);

   function Ends_With (Source : String; Suffix : String) return Boolean is
   begin
      if Suffix'Length = 0 then
         return True;
      end if;
      if Source'Length < Suffix'Length then
         return False;
      end if;
      declare
         Src_Slice : constant String := Source (Source'Last - Suffix'Length + 1 .. Source'Last);
      begin
         if Src_Slice'Length /= Suffix'Length then
            return False;
         end if;
         for I in Suffix'Range loop
            if To_Lower_Char (Src_Slice (Src_Slice'First + (I - Suffix'First))) /= To_Lower_Char (Suffix (I)) then
               return False;
            end if;
         end loop;
         return True;
      end;
   end Ends_With;

   --  @summary Case-insensitive substring check.
   function Contains_Substring (Source : String; Pattern : String) return Boolean
   with Global => null;
   pragma Inline (Contains_Substring);

   function Contains_Substring (Source : String; Pattern : String) return Boolean is
   begin
      if Pattern'Length = 0 then
         return True;
      end if;
      if Source'Length < Pattern'Length then
         return False;
      end if;
      for I in Source'First .. Source'Last - Pattern'Length + 1 loop
         declare
            Match : Boolean := True;
         begin
            for J in Pattern'Range loop
               if To_Lower_Char (Source (I + (J - Pattern'First))) /= To_Lower_Char (Pattern (J)) then
                  Match := False;
                  exit;
               end if;
            end loop;
            if Match then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Contains_Substring;

   --  @summary Case-insensitive prefix check (used for multiplexer detection).
   function Starts_With (Source : String; Prefix : String) return Boolean
   with Global => null;
   pragma Inline (Starts_With);

   function Starts_With (Source : String; Prefix : String) return Boolean is
   begin
      if Prefix'Length = 0 then
         return True;
      end if;
      if Source'Length < Prefix'Length then
         return False;
      end if;
      declare
         Src_Slice : constant String := Source (Source'First .. Source'First + Prefix'Length - 1);
      begin
         for I in Prefix'Range loop
            if To_Lower_Char (Src_Slice (Src_Slice'First + (I - Prefix'First))) /= To_Lower_Char (Prefix (I)) then
               return False;
            end if;
         end loop;
         return True;
      end;
   end Starts_With;

   ---------------------------------------------------------------------------
   --  FORCE_COLOR helpers (FUNC-CLR-004)
   ---------------------------------------------------------------------------

   function Classify_Force_Color (Val : String) return Force_Color_Token
   with Global => null;
   pragma Inline (Classify_Force_Color);

   function Classify_Force_Color (Val : String) return Force_Color_Token is
   begin
      if Val'Length = 0 then
         return FC_Empty;
      elsif Equal_Case_Insensitive (Val, "0") then
         return FC_Zero;
      elsif Equal_Case_Insensitive (Val, "false") then
         return FC_False;
      elsif Equal_Case_Insensitive (Val, "1") then
         return FC_One;
      elsif Equal_Case_Insensitive (Val, "true") then
         return FC_True;
      elsif Equal_Case_Insensitive (Val, "2") then
         return FC_Two;
      elsif Equal_Case_Insensitive (Val, "3") then
         return FC_Three;
      else
         return FC_Other;
      end if;
   end Classify_Force_Color;

   function Parse_Force_Color (Env : Termicap.Environment.Environment) return Color_Level
   with Global => null;
   pragma Inline (Parse_Force_Color);

   function Parse_Force_Color (Env : Termicap.Environment.Environment) return Color_Level is
      Token : constant Force_Color_Token := Classify_Force_Color (Value (Env, "FORCE_COLOR"));
   begin
      case Token is
         when FC_Zero | FC_False =>
            return None;

         when FC_Three =>
            return True_Color;

         when FC_Two =>
            return Extended_256;

         when FC_One | FC_True | FC_Empty | FC_Other =>
            return Basic_16;
      end case;
   end Parse_Force_Color;

   ---------------------------------------------------------------------------
   --  CLICOLOR_FORCE helper (FUNC-CLR-005)
   ---------------------------------------------------------------------------

   function Parse_Clicolor_Force (Env : Termicap.Environment.Environment) return Color_Level
   with Global => null;
   pragma Inline (Parse_Clicolor_Force);

   function Parse_Clicolor_Force (Env : Termicap.Environment.Environment) return Color_Level is
   begin
      if not Contains (Env, "CLICOLOR_FORCE") then
         return None;
      end if;
      --  CLICOLOR_FORCE=0 means no effect (disabled)
      if Equal_Case_Insensitive (Value (Env, "CLICOLOR_FORCE"), "0") then
         return None;
      end if;
      return Basic_16;
   end Parse_Clicolor_Force;

   ---------------------------------------------------------------------------
   --  NO_COLOR helper (FUNC-CLR-003)
   ---------------------------------------------------------------------------

   function Has_No_Color (Env : Termicap.Environment.Environment) return Boolean
   with Global => null;
   pragma Inline (Has_No_Color);

   function Has_No_Color (Env : Termicap.Environment.Environment) return Boolean is
   begin
      return Contains (Env, "NO_COLOR");
   end Has_No_Color;

   ---------------------------------------------------------------------------
   --  TERM=dumb helper (FUNC-CLR-006)
   ---------------------------------------------------------------------------

   function Is_Dumb_Terminal (Env : Termicap.Environment.Environment) return Boolean
   with Global => null;
   pragma Inline (Is_Dumb_Terminal);

   function Is_Dumb_Terminal (Env : Termicap.Environment.Environment) return Boolean is
   begin
      return Equal_Case_Insensitive (Value (Env, "TERM"), "dumb");
   end Is_Dumb_Terminal;

   ---------------------------------------------------------------------------
   --  CI environment detection (FUNC-CLR-011)
   ---------------------------------------------------------------------------

   function Detect_CI_Color (Env : Termicap.Environment.Environment) return Color_Level
   with Global => null;
   pragma Inline (Detect_CI_Color);

   function Detect_CI_Color (Env : Termicap.Environment.Environment) return Color_Level is
   begin
      --  Specific CI environments with TrueColor support
      if (Contains (Env, "GITHUB_ACTIONS") and then Equal_Case_Insensitive (Value (Env, "GITHUB_ACTIONS"), "true"))
        or else Contains (Env, "GITEA_ACTIONS")
        or else Contains (Env, "CIRCLECI")
      then
         return True_Color;
      end if;

      --  Specific CI environments with Basic color support
      if Contains (Env, "TRAVIS")
        or else Contains (Env, "APPVEYOR")
        or else Contains (Env, "GITLAB_CI")
        or else Contains (Env, "BUILDKITE")
        or else Contains (Env, "DRONE")
      then
         return Basic_16;
      end if;

      --  Generic CI fallback
      if Contains (Env, "CI") then
         return Basic_16;
      end if;

      return None;
   end Detect_CI_Color;

   ---------------------------------------------------------------------------
   --  TERM_PROGRAM helpers (FUNC-CLR-010)
   ---------------------------------------------------------------------------

   function Classify_Term_Program (TP : String) return Term_Program_Token
   with Global => null;
   pragma Inline (Classify_Term_Program);

   function Classify_Term_Program (TP : String) return Term_Program_Token is
   begin
      if Equal_Case_Insensitive (TP, "iTerm.app") then
         return TP_ITerm;
      elsif Equal_Case_Insensitive (TP, "Apple_Terminal") then
         return TP_Apple_Terminal;
      elsif Equal_Case_Insensitive (TP, "vscode") then
         return TP_VSCode;
      else
         return TP_Other;
      end if;
   end Classify_Term_Program;

   function Detect_Term_Program (Env : Termicap.Environment.Environment) return Color_Level
   with Global => null;
   pragma Inline (Detect_Term_Program);

   function Detect_Term_Program (Env : Termicap.Environment.Environment) return Color_Level is
      TP : constant String := Value (Env, "TERM_PROGRAM");
   begin
      if not Contains (Env, "TERM_PROGRAM") then
         return None;
      end if;

      case Classify_Term_Program (TP) is
         when TP_ITerm =>
            --  Version-gated: iTerm.app v3+ supports TrueColor
            declare
               Ver : constant String := Value (Env, "TERM_PROGRAM_VERSION");
            begin
               if Ver'Length > 0 and then Ver (Ver'First) >= '3' then
                  return True_Color;
               end if;
            end;
            return Extended_256;  --  iTerm.app < v3 or version absent

         when TP_Apple_Terminal | TP_VSCode =>
            return Extended_256;

         when TP_Other =>
            return None;
      end case;
   end Detect_Term_Program;

   ---------------------------------------------------------------------------
   --  COLORTERM detection with multiplexer cap (FUNC-CLR-008, FUNC-CLR-013)
   ---------------------------------------------------------------------------

   function Detect_Colorterm (Env : Termicap.Environment.Environment) return Color_Level
   with Global => null;
   pragma Inline (Detect_Colorterm);

   function Detect_Colorterm (Env : Termicap.Environment.Environment) return Color_Level is
      CT   : constant String := Value (Env, "COLORTERM");
      Term : constant String := Value (Env, "TERM");
   begin
      if not Contains (Env, "COLORTERM") then
         return None;
      end if;

      if Equal_Case_Insensitive (CT, "truecolor") or else Equal_Case_Insensitive (CT, "24bit") then
         --  Multiplexer cap (FUNC-CLR-013): screen cannot pass TrueColor
         if Starts_With (Term, "screen") and then not Equal_Case_Insensitive (Value (Env, "TERM_PROGRAM"), "tmux") then
            return Extended_256;
         end if;
         return True_Color;
      end if;

      --  Any other non-empty COLORTERM value -> at least Basic_16
      return Basic_16;
   end Detect_Colorterm;

   ---------------------------------------------------------------------------
   --  TERM suffix/pattern detection (FUNC-CLR-009)
   ---------------------------------------------------------------------------

   function Detect_Term_Pattern (Env : Termicap.Environment.Environment) return Color_Level
   with Global => null;
   pragma Inline (Detect_Term_Pattern);

   function Detect_Term_Pattern (Env : Termicap.Environment.Environment) return Color_Level is
      Term : constant String := Value (Env, "TERM");
   begin
      if Term'Length = 0 then
         return None;
      end if;

      --  256-color detection: TERM ends with "-256color" or "-256"
      if Ends_With (Term, "-256color") or else Ends_With (Term, "-256") then
         return Extended_256;
      end if;

      --  Basic color detection: known terminal type identifiers
      if Contains_Substring (Term, "xterm")
        or else Contains_Substring (Term, "screen")
        or else Contains_Substring (Term, "vt100")
        or else Contains_Substring (Term, "vt220")
        or else Contains_Substring (Term, "rxvt")
        or else Contains_Substring (Term, "color")
        or else Contains_Substring (Term, "ansi")
        or else Contains_Substring (Term, "cygwin")
        or else Contains_Substring (Term, "linux")
      then
         return Basic_16;
      end if;

      return None;
   end Detect_Term_Pattern;

   ---------------------------------------------------------------------------
   --  CLICOLOR helper (FUNC-CLR-012)
   ---------------------------------------------------------------------------

   function Has_Clicolor (Env : Termicap.Environment.Environment) return Boolean
   with Global => null;
   pragma Inline (Has_Clicolor);

   function Has_Clicolor (Env : Termicap.Environment.Environment) return Boolean is
   begin
      if not Contains (Env, "CLICOLOR") then
         return False;
      end if;
      --  CLICOLOR=0 means no effect (disabled)
      if Equal_Case_Insensitive (Value (Env, "CLICOLOR"), "0") then
         return False;
      end if;
      return True;
   end Has_Clicolor;

   ---------------------------------------------------------------------------
   --  Main detection function: 11-step priority cascade (FUNC-CLR-015)
   ---------------------------------------------------------------------------

   function Detect_Color_Level (Env : Termicap.Environment.Environment; Is_TTY : Boolean) return Color_Level is
      Floor     : Color_Level := None;
      Force_Set : Boolean := False;
      CI_Level  : Color_Level;
      Heuristic : Color_Level := None;
   begin
      --  @relation(FUNC-OVR-004)
      case Termicap.Override.Get_Override is
         when Termicap.Override.Force_None =>
            return None;

         when Termicap.Override.Force_Basic =>
            return Basic_16;

         when Termicap.Override.Force_256 =>
            return Extended_256;

         when Termicap.Override.Force_True_Color =>
            return True_Color;

         when Termicap.Override.Auto =>
            null;  --  proceed with normal detection
      end case;

      --  Step 1: FORCE_COLOR (FUNC-CLR-004)
      if Contains (Env, "FORCE_COLOR") then
         --  FORCE_COLOR=0/"false" -> immediately return None
         if Equal_Case_Insensitive (Value (Env, "FORCE_COLOR"), "0")
           or else Equal_Case_Insensitive (Value (Env, "FORCE_COLOR"), "false")
         then
            return None;
         end if;
         Floor := Parse_Force_Color (Env);
         Force_Set := Floor > None;
      end if;

      --  Step 2: CLICOLOR_FORCE (FUNC-CLR-005)
      if not Force_Set then
         Floor := Color_Level'Max (Floor, Parse_Clicolor_Force (Env));
         Force_Set := Floor > None;
      end if;

      --  Step 3: NO_COLOR (FUNC-CLR-003)
      if not Force_Set and then Has_No_Color (Env) then
         return None;
      end if;

      --  Step 4: TERM=dumb (FUNC-CLR-006)
      if Is_Dumb_Terminal (Env) then
         return Floor;  --  Floor is None unless steps 1-2 set it

      end if;

      --  Step 5: CI environment (FUNC-CLR-011)
      CI_Level := Detect_CI_Color (Env);
      if CI_Level > None then
         Heuristic := Color_Level'Max (Heuristic, CI_Level);
      end if;

      --  Step 6: TTY gate (FUNC-CLR-007)
      if not Is_TTY and then Floor = None and then Heuristic = None then
         return None;
      end if;

      --  Step 7: COLORTERM (FUNC-CLR-008)
      Heuristic := Color_Level'Max (Heuristic, Detect_Colorterm (Env));

      --  Step 8: TERM_PROGRAM (FUNC-CLR-010)
      Heuristic := Color_Level'Max (Heuristic, Detect_Term_Program (Env));

      --  Step 9: TERM suffix/pattern (FUNC-CLR-009)
      Heuristic := Color_Level'Max (Heuristic, Detect_Term_Pattern (Env));

      --  Step 10: CLICOLOR (FUNC-CLR-012)
      if Has_Clicolor (Env) then
         Heuristic := Color_Level'Max (Heuristic, Basic_16);
      end if;

      --  Step 11: Default â floor wins if higher than heuristic (FUNC-CLR-015)
      return Color_Level'Max (Floor, Heuristic);
   end Detect_Color_Level;

end Termicap.Color;
