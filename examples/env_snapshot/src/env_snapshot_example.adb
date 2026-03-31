-------------------------------------------------------------------------------
--  Env_Snapshot_Example - Environment Variable Abstraction Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Environment API for terminal capability detection.
--
--  @description
--  Shows how to:
--    1. Capture the live process environment via Capture_Current
--    2. Query common terminal variables (TERM, COLORTERM, TERM_PROGRAM)
--    3. Check NO_COLOR compliance using Contains (presence vs. value)
--    4. Compare values with Equal_Case_Insensitive
--    5. Match TERM against known terminal types with Value_Matches
--    6. Build a programmatic environment for testing

with Ada.Text_IO;

with Termicap.Environment;         use Termicap.Environment;
with Termicap.Environment.Capture;

procedure Env_Snapshot_Example is

   ---------------------------------------------------------------------------
   --  Helper: print a variable's value or "(not set)"
   ---------------------------------------------------------------------------

   procedure Print_Var (Env : Environment; Name : String) is
      --  Width of the label column (including trailing spaces and colon).
      LABEL_WIDTH : constant := 14;

      Padded : String (1 .. LABEL_WIDTH) := (others => ' ');
      Len    : constant Natural := Natural'Min (Name'Length, LABEL_WIDTH - 2);
   begin
      Padded (1 .. Len) := Name (Name'First .. Name'First + Len - 1);
      Padded (Len + 1)  := ':';

      Ada.Text_IO.Put (Padded);

      if Contains (Env, Name) then
         declare
            V : constant String := Value (Env, Name);
         begin
            if V = "" then
               Ada.Text_IO.Put_Line (" (empty)");
            else
               Ada.Text_IO.Put_Line (" " & V);
            end if;
         end;
      else
         Ada.Text_IO.Put_Line (" (not set)");
      end if;
   end Print_Var;

   ---------------------------------------------------------------------------
   --  Helper: print a Boolean detection result with a label
   ---------------------------------------------------------------------------

   procedure Print_Result (Label : String; Result : Boolean; Detail : String := "") is
      LABEL_WIDTH : constant := 18;
      Padded      : String (1 .. LABEL_WIDTH) := (others => ' ');
      Len         : constant Natural := Natural'Min (Label'Length, LABEL_WIDTH - 2);
   begin
      Padded (1 .. Len) := Label (Label'First .. Label'First + Len - 1);
      Padded (Len + 1)  := ':';

      Ada.Text_IO.Put (Padded);

      if Result then
         Ada.Text_IO.Put (" Yes");
         if Detail /= "" then
            Ada.Text_IO.Put_Line (" (" & Detail & ")");
         else
            Ada.Text_IO.New_Line;
         end if;
      else
         Ada.Text_IO.Put_Line (" No");
      end if;
   end Print_Result;

   ---------------------------------------------------------------------------
   --  Live environment snapshot
   ---------------------------------------------------------------------------

   Live_Env : Environment;

   ---------------------------------------------------------------------------
   --  Detection results from the live environment
   ---------------------------------------------------------------------------

   No_Color_Active   : Boolean;
   True_Color_Hint   : Boolean;
   Known_Terminal    : Boolean;

   --  Candidates for recognising common terminal emulators via TERM_PROGRAM
   Terminal_Candidates : String_Vector;

begin

   --  -------------------------------------------------------------------------
   --  Section 1: Capture the live environment
   --  -------------------------------------------------------------------------

   Termicap.Environment.Capture.Capture_Current (Live_Env);

   Ada.Text_IO.Put_Line ("=== Termicap Environment Snapshot Example ===");
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 2: Display raw variable values
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Live Environment ---");
   Print_Var (Live_Env, "TERM");
   Print_Var (Live_Env, "COLORTERM");
   Print_Var (Live_Env, "TERM_PROGRAM");
   Print_Var (Live_Env, "NO_COLOR");
   Print_Var (Live_Env, "FORCE_COLOR");
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 3: Detection results derived from the live environment
   --  -------------------------------------------------------------------------

   --  NO_COLOR compliance: the spec says presence of the variable (even when
   --  empty) must suppress colour output.  We therefore check Contains, not
   --  Value.  @relation(FUNC-ENV-002)
   No_Color_Active := Contains (Live_Env, "NO_COLOR");

   --  TrueColor hint: COLORTERM set to "truecolor" or "24bit".
   --  Equal_Case_Insensitive handles terminals that capitalise the value.
   --  @relation(FUNC-ENV-006)
   True_Color_Hint :=
      Contains (Live_Env, "COLORTERM")
      and then
        (Equal_Case_Insensitive (Value (Live_Env, "COLORTERM"), "truecolor")
         or else Equal_Case_Insensitive (Value (Live_Env, "COLORTERM"), "24bit"));

   --  Known terminal: match TERM_PROGRAM against a list of popular emulators.
   --  String_Vectors / Value_Matches enables concise multi-candidate checks.
   --  @relation(FUNC-ENV-008)
   String_Vectors.Append (Terminal_Candidates, "iTerm.app");
   String_Vectors.Append (Terminal_Candidates, "WezTerm");
   String_Vectors.Append (Terminal_Candidates, "Alacritty");
   String_Vectors.Append (Terminal_Candidates, "kitty");
   String_Vectors.Append (Terminal_Candidates, "Hyper");
   String_Vectors.Append (Terminal_Candidates, "vscode");

   Known_Terminal := Value_Matches (Live_Env, "TERM_PROGRAM", Terminal_Candidates);

   Ada.Text_IO.Put_Line ("--- Detection Results ---");
   Print_Result ("NO_COLOR active", No_Color_Active);
   Print_Result
      ("TrueColor hint", True_Color_Hint, "COLORTERM=" & Value (Live_Env, "COLORTERM"));
   Print_Result
      ("Known terminal", Known_Terminal,
       "matches " & Value (Live_Env, "TERM_PROGRAM"));
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 4: Programmatic environment for testing
   --
   --  Start from EMPTY_ENVIRONMENT and call Insert to build a deterministic
   --  snapshot — no live process environment needed.  This pattern lets unit
   --  tests exercise detection logic in isolation.  @relation(FUNC-ENV-005)
   --  -------------------------------------------------------------------------

   declare
      Test_Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  NO_COLOR set to empty string — presence is what matters
      Insert (Test_Env, "NO_COLOR", "");
      --  TERM set to "dumb" to represent a non-colour terminal
      Insert (Test_Env, "TERM", "dumb");

      Ada.Text_IO.Put_Line ("--- Programmatic Environment (for testing) ---");

      declare
         Has_No_Color : constant Boolean := Contains (Test_Env, "NO_COLOR");
         No_Color_Val : constant String  := Value (Test_Env, "NO_COLOR");
         Term_Val     : constant String  := Value (Test_Env, "TERM");
      begin
         Ada.Text_IO.Put ("Contains NO_COLOR     : ");
         Ada.Text_IO.Put_Line (if Has_No_Color then "True" else "False");

         Ada.Text_IO.Put ("NO_COLOR value        : ");
         if No_Color_Val = "" then
            Ada.Text_IO.Put_Line ("(empty)");
         else
            Ada.Text_IO.Put_Line (No_Color_Val);
         end if;

         Ada.Text_IO.Put ("TERM value            : ");
         Ada.Text_IO.Put_Line (Term_Val);
      end;
   end;

end Env_Snapshot_Example;
