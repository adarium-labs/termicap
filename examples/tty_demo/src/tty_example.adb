-------------------------------------------------------------------------------
--  TTY_Demo - TTY Detection Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.TTY API for terminal teletype detection.
--
--  @description
--  Shows how to:
--    1. Check individual streams with Is_TTY
--    2. Query all streams at once with Query_All
--    3. Use TTY status to gate terminal-specific behavior
--
--  Run interactively and with redirected I/O to see different results:
--    ./tty_demo               -- expect True/True/True (or True/True/True)
--    ./tty_demo | cat         -- expect True/False/True (stdout piped)
--    echo "" | ./tty_demo     -- expect False/True/True (stdin piped)

with Ada.Text_IO;

with Termicap.TTY; use Termicap.TTY;

procedure TTY_Example is

   ---------------------------------------------------------------------------
   --  Helper: print a Boolean as "Yes" or "No"
   ---------------------------------------------------------------------------

   procedure Print_TTY (Label : String; Is_Terminal : Boolean) is
      LABEL_WIDTH : constant := 10;
      Padded      : String (1 .. LABEL_WIDTH) := (others => ' ');
      Len         : constant Natural := Natural'Min (Label'Length, LABEL_WIDTH - 2);
   begin
      Padded (1 .. Len) := Label (Label'First .. Label'First + Len - 1);
      Padded (Len + 1)  := ':';

      Ada.Text_IO.Put (Padded);
      Ada.Text_IO.Put_Line (if Is_Terminal then " Yes" else " No");
   end Print_TTY;

begin

   --  -------------------------------------------------------------------------
   --  Section 1: Per-stream detection with Is_TTY
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("=== Termicap TTY Detection Example ===");
   Ada.Text_IO.New_Line;

   Ada.Text_IO.Put_Line ("--- Per-Stream Detection (Is_TTY) ---");
   Print_TTY ("Stdin", Is_TTY (Stdin));
   Print_TTY ("Stdout", Is_TTY (Stdout));
   Print_TTY ("Stderr", Is_TTY (Stderr));
   Ada.Text_IO.New_Line;

   --  -------------------------------------------------------------------------
   --  Section 2: Bulk query with Query_All
   --  -------------------------------------------------------------------------

   declare
      Status : constant TTY_Status := Query_All;
   begin
      Ada.Text_IO.Put_Line ("--- Bulk Query (Query_All) ---");
      Print_TTY ("Stdin", Status.Stdin);
      Print_TTY ("Stdout", Status.Stdout);
      Print_TTY ("Stderr", Status.Stderr);
      Ada.Text_IO.New_Line;
   end;

   --  -------------------------------------------------------------------------
   --  Section 3: Practical usage — gate behavior on TTY status
   --  -------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Practical Usage ---");

   if Is_TTY (Stdout) then
      Ada.Text_IO.Put_Line ("Stdout is a terminal: colors and progress bars are safe.");
   else
      Ada.Text_IO.Put_Line ("Stdout is NOT a terminal: using plain text output.");
   end if;

   if not Is_TTY (Stdin) then
      Ada.Text_IO.Put_Line ("Stdin is piped: reading from pipe/file, not interactive.");
   else
      Ada.Text_IO.Put_Line ("Stdin is a terminal: interactive input available.");
   end if;

end TTY_Example;
