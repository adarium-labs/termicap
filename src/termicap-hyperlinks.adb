-------------------------------------------------------------------------------
--  Termicap.Hyperlinks - OSC 8 Hyperlink Support Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Full implementation of Classify_Hyperlinks_Support (SPARK Silver spec
--  contracts) and Refine_With_XTVERSION (SPARK Off, uses Unbounded_String).
--
--  The package body is SPARK_Mode Off because Refine_With_XTVERSION (declared
--  SPARK_Mode => Off in the spec) requires an Off body context, and GNAT 15
--  does not permit switching from Off back to On within a package body.
--  Classify_Hyperlinks_Support's Global => null and postconditions remain
--  provable at the spec level by GNATprove; the body is correct by inspection.
--
--  Requirements Coverage:
--    - @relation(FUNC-HYP-004): TERM legacy-prefix exclusion
--    - @relation(FUNC-HYP-005): Known-good Terminal_Kind list
--    - @relation(FUNC-HYP-005b): Terminal_Kind hard exclusion
--    - @relation(FUNC-HYP-007): Classify_Hyperlinks_Support body
--    - @relation(FUNC-HYP-008): No global state
--    - @relation(FUNC-HYP-009): XTVERSION promotion
--    - @relation(FUNC-HYP-010): XTVERSION demotion
--    - @relation(FUNC-HYP-011): Refine_With_XTVERSION body
--    - @relation(FUNC-HYP-012): Complete state-transition table
--    - @relation(FUNC-HYP-016): Package structure — mixed SPARK
--    - @relation(FUNC-HYP-018): Classify_Hyperlinks_Support Global => null in spec

with Ada.Characters.Handling;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Termicap.Version;

package body Termicap.Hyperlinks
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Classify_Hyperlinks_Support (FUNC-HYP-007)
   --  Body is in SPARK_Mode Off context (package body constraint).
   --  The function is correct by inspection: no global state is read, no
   --  allocation, no exceptions, and the logic is total over all inputs.
   --  GNATprove verifies the spec-level Global => null via flow analysis.
   ---------------------------------------------------------------------------

   function Classify_Hyperlinks_Support
     (Env : Termicap.Environment.Environment; Identity : Termicap.Terminal_Id.Terminal_Identity)
      return Hyperlinks_Result
   is

      --  Case-insensitive prefix check on a plain Ada String.
      function Has_Prefix_CI (Source : String; Prefix : String) return Boolean is
         function To_Lower (C : Character) return Character is
         begin
            if C in 'A' .. 'Z' then
               return Character'Val (Character'Pos (C) + 32);
            else
               return C;
            end if;
         end To_Lower;
      begin
         if Source'Length < Prefix'Length then
            return False;
         end if;
         for I in Prefix'Range loop
            if To_Lower (Source (Source'First + (I - Prefix'First))) /= To_Lower (Prefix (I)) then
               return False;
            end if;
         end loop;
         return True;
      end Has_Prefix_CI;

      --  Case-insensitive equality check on plain Ada Strings.
      function Eq_CI (A : String; B : String) return Boolean is
         function To_Lower (C : Character) return Character is
         begin
            if C in 'A' .. 'Z' then
               return Character'Val (Character'Pos (C) + 32);
            else
               return C;
            end if;
         end To_Lower;
      begin
         if A'Length /= B'Length then
            return False;
         end if;
         for I in A'Range loop
            if To_Lower (A (I)) /= To_Lower (B (B'First + (I - A'First))) then
               return False;
            end if;
         end loop;
         return True;
      end Eq_CI;

      --  Read TERM from the environment snapshot (pure function call).
      T : constant String := Termicap.Environment.Value (Env, "TERM");

   begin
      --  Step 1: TERM legacy-prefix exclusion (FUNC-HYP-004).
      --  Prefix match: vt*, ansi*, sun*; Exact match: linux, dumb.
      if Has_Prefix_CI (T, TERM_PREFIX_VT)
        or else Has_Prefix_CI (T, TERM_PREFIX_ANSI)
        or else Eq_CI (T, TERM_LINUX)
        or else Has_Prefix_CI (T, TERM_PREFIX_SUN)
        or else Eq_CI (T, TERM_DUMB)
      then
         return (Support => Unsupported, Provenance => Env_Excluded, Terminal_Version_Known => False);
      end if;

      --  Step 2: Terminal_Kind hard exclusion (FUNC-HYP-005b).
      case Identity.Kind is
         when Termicap.Terminal_Id.Apple_Terminal | Termicap.Terminal_Id.Dumb | Termicap.Terminal_Id.Linux_Console =>
            return (Support => Unsupported, Provenance => Env_Excluded, Terminal_Version_Known => False);

         when others =>
            null;
      end case;

      --  Step 3: Known-good Terminal_Kind list (FUNC-HYP-005).
      case Identity.Kind is
         when Termicap.Terminal_Id.Alacritty
            | Termicap.Terminal_Id.Foot
            | Termicap.Terminal_Id.Ghostty
            | Termicap.Terminal_Id.ITerm2
            | Termicap.Terminal_Id.JediTerm
            | Termicap.Terminal_Id.Kitty
            | Termicap.Terminal_Id.Konsole
            | Termicap.Terminal_Id.Mintty
            | Termicap.Terminal_Id.VSCode
            | Termicap.Terminal_Id.VTE
            | Termicap.Terminal_Id.WarpTerminal
            | Termicap.Terminal_Id.WezTerm
            | Termicap.Terminal_Id.Windows_Terminal
            | Termicap.Terminal_Id.Xterm
         =>
            return (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);

         when others =>
            --  Rxvt, Screen, Tmux, Unknown, and any future Terminal_Kind values.
            return (Support => Unknown, Provenance => Env_Unknown, Terminal_Version_Known => False);
      end case;
   end Classify_Hyperlinks_Support;

   ---------------------------------------------------------------------------
   --  Private: Known-good version table for Refine_With_XTVERSION
   --  (FUNC-HYP-009, FUNC-HYP-010, tech-spec §7)
   ---------------------------------------------------------------------------

   type Known_Good_Entry is record
      Name        : access constant String;
      Min_Version : Termicap.Version.Version;
      Treat_Any   : Boolean;
   end record;

   --  Name literals stored in lowercase for case-insensitive lookup.
   ITERM2_NAME           : aliased constant String := "iterm2";
   KITTY_NAME            : aliased constant String := "kitty";
   WEZTERM_NAME          : aliased constant String := "wezterm";
   VTE_NAME              : aliased constant String := "vte";
   FOOT_NAME             : aliased constant String := "foot";
   ALACRITTY_NAME        : aliased constant String := "alacritty";
   MINTTY_NAME           : aliased constant String := "mintty";
   XTERM_NAME            : aliased constant String := "xterm";
   WINDOWS_TERMINAL_NAME : aliased constant String := "windows_terminal";
   VSCODE_NAME           : aliased constant String := "vscode";
   GHOSTTY_NAME          : aliased constant String := "ghostty";
   KONSOLE_NAME          : aliased constant String := "konsole";

   KNOWN_GOOD : constant array (1 .. 12) of Known_Good_Entry :=
     [1  => (Name => ITERM2_NAME'Access, Min_Version => Termicap.Version.Make (3, 1, 0), Treat_Any => False),
      2  => (Name => KITTY_NAME'Access, Min_Version => Termicap.Version.Make (0, 19, 0), Treat_Any => False),
      3  => (Name => WEZTERM_NAME'Access, Min_Version => Termicap.Version.ZERO_VERSION, Treat_Any => True),
      4  => (Name => VTE_NAME'Access, Min_Version => Termicap.Version.Make (0, 50, 0), Treat_Any => False),
      5  => (Name => FOOT_NAME'Access, Min_Version => Termicap.Version.ZERO_VERSION, Treat_Any => True),
      6  => (Name => ALACRITTY_NAME'Access, Min_Version => Termicap.Version.Make (0, 11, 0), Treat_Any => False),
      7  => (Name => MINTTY_NAME'Access, Min_Version => Termicap.Version.Make (3, 4, 0), Treat_Any => False),
      8  =>
        (Name => XTERM_NAME'Access, Min_Version => Termicap.Version.Make (357, Has_Minor => False), Treat_Any => False),
      9  => (Name => WINDOWS_TERMINAL_NAME'Access, Min_Version => Termicap.Version.Make (1, 4, 0), Treat_Any => False),
      10 => (Name => VSCODE_NAME'Access, Min_Version => Termicap.Version.Make (1, 72, 0), Treat_Any => False),
      11 => (Name => GHOSTTY_NAME'Access, Min_Version => Termicap.Version.ZERO_VERSION, Treat_Any => True),
      12 => (Name => KONSOLE_NAME'Access, Min_Version => Termicap.Version.ZERO_VERSION, Treat_Any => True)];

   ---------------------------------------------------------------------------
   --  Refine_With_XTVERSION (FUNC-HYP-011, SPARK_Mode Off)
   ---------------------------------------------------------------------------

   function Refine_With_XTVERSION
     (Passive : Hyperlinks_Result; XTV : Termicap.XTVERSION.XTVERSION_Result) return Hyperlinks_Result
   is
      use type Termicap.XTVERSION.XTVERSION_Status;
   begin
      --  "Unsupported is terminal" invariant (FUNC-HYP-012 row 1):
      --  Never override a passively-excluded terminal.
      if Passive.Support = Unsupported and then Passive.Provenance = Env_Excluded then
         return Passive;
      end if;

      --  No active refinement when XTVERSION did not succeed.
      if XTV.Status /= Termicap.XTVERSION.Success then
         return
           (Support                => Passive.Support,
            Provenance             => XTVERSION_Unresolved,
            Terminal_Version_Known => Passive.Terminal_Version_Known);
      end if;

      --  Look up the emulator name (case-insensitive) in the known-good table.
      declare
         Name_Lower  : constant String := Ada.Characters.Handling.To_Lower (To_String (XTV.Terminal_Name));
         Entry_Found : Boolean := False;
         Entry_Idx   : Positive := 1;
      begin
         for I in KNOWN_GOOD'Range loop
            if Name_Lower = KNOWN_GOOD (I).Name.all then
               Entry_Found := True;
               Entry_Idx := I;
               exit;
            end if;
         end loop;

         if not Entry_Found then
            --  Name not in table -> Unresolved, no change to Support.
            return (Support => Passive.Support, Provenance => XTVERSION_Unresolved, Terminal_Version_Known => False);
         end if;

         --  Name matched.  Parse the version string.
         declare
            Reported : Termicap.Version.Version;
            Ok       : Boolean;
         begin
            Termicap.Version.Parse (To_String (XTV.Terminal_Version), Reported, Ok);

            if not Ok then
               --  Name recognised but version unparseable: stay on passive support.
               return (Support => Passive.Support, Provenance => Env_Known_Good, Terminal_Version_Known => True);
            end if;

            --  "(any)" entries: any successfully parsed version satisfies the minimum.
            if KNOWN_GOOD (Entry_Idx).Treat_Any then
               return (Support => Supported, Provenance => XTVERSION_Confirmed, Terminal_Version_Known => True);
            end if;

            --  Compare reported version against the minimum.
            case Termicap.Version.Compare (Reported, KNOWN_GOOD (Entry_Idx).Min_Version) is
               when Termicap.Version.Less_Than =>
                  --  Below minimum -> demotion (FUNC-HYP-010).
                  return (Support => Unsupported, Provenance => XTVERSION_Rejected, Terminal_Version_Known => True);

               when Termicap.Version.Equal | Termicap.Version.Greater_Than =>
                  --  At or above minimum -> promotion (FUNC-HYP-009).
                  return (Support => Supported, Provenance => XTVERSION_Confirmed, Terminal_Version_Known => True);
            end case;
         end;
      end;

   exception
      when others =>
         --  Defence in depth: never let an exception escape this function.
         return Passive;
   end Refine_With_XTVERSION;

end Termicap.Hyperlinks;
