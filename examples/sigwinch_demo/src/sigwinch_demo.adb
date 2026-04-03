-------------------------------------------------------------------------------
--  Sigwinch_Demo - SIGWINCH Resize Notification Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Sigwinch API for terminal resize notification.
--
--  @description
--  Shows how to:
--    1. Install the SIGWINCH handler and read the self-pipe FD
--    2. Query initial cached dimensions with Get_Cached_Size
--    3. Poll for resize events using Has_Resize / Acknowledge_Resize
--    4. Integrate with I/O multiplexing via the self-pipe FD
--    5. Clean up with Uninstall
--

--  The example covers three complementary usage patterns:
--
--  Pattern A — Polling: call Has_Resize once per render-loop iteration.
--  No extra file descriptors are needed.  Simple and correct for most TUIs.
--
--  Pattern B — Self-pipe: register Get_Pipe_Read_FD with select()/poll()/
--  epoll() so the event loop wakes only when a resize has actually occurred.
--  Ideal for long-blocking I/O loops that must not spin.
--
--  Pattern C — Live demo: a real 10-second poll loop that prints new
--  dimensions each time you resize the terminal window.
--
--  Run this program from an interactive terminal, then resize the terminal
--  window while the poll loop is running to see the new dimensions printed.

with Ada.Calendar;   use Ada.Calendar;
with Ada.Text_IO;

with Termicap.Dimensions;
with Termicap.Sigwinch;

procedure Sigwinch_Demo is

   ---------------------------------------------------------------------------
   --  Helper: render a Terminal_Size as a readable "COLSxROWS" string
   ---------------------------------------------------------------------------

   function Size_Image (S : Termicap.Dimensions.Terminal_Size) return String is
      Cols : constant String := S.Columns'Image;
      Rows : constant String := S.Rows'Image;
   begin
      --  'Image on Positive always starts with a leading space; strip it.
      return Cols (Cols'First + 1 .. Cols'Last)
           & "x"
           & Rows (Rows'First + 1 .. Rows'Last);
   end Size_Image;

   ---------------------------------------------------------------------------
   --  Constants
   ---------------------------------------------------------------------------

   POLL_DURATION  : constant Duration := 10.0;  --  seconds to watch for resize
   POLL_INTERVAL  : constant Duration := 0.25;  --  check frequency

begin

   Ada.Text_IO.Put_Line ("=== Termicap SIGWINCH Resize Notification Example ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Install the handler
   ---------------------------------------------------------------------------

   Termicap.Sigwinch.Install;

   declare
      Pipe_FD      : constant Integer := Termicap.Sigwinch.Get_Pipe_Read_FD;
      Initial_Size : constant Termicap.Dimensions.Terminal_Size :=
         Termicap.Sigwinch.Get_Cached_Size;
   begin
      Ada.Text_IO.Put_Line
         ("Handler installed.  Self-pipe read FD: " & Pipe_FD'Image);
      Ada.Text_IO.Put_Line
         ("Initial size: " & Size_Image (Initial_Size));
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Poll loop — runs for POLL_DURATION seconds
   --
   --  Each iteration checks Has_Resize.  When True, the new dimensions are
   --  printed and the flag is cleared with Acknowledge_Resize so the next
   --  SIGWINCH will trigger again.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line
      ("Watching for resize events for"
       & Integer (POLL_DURATION)'Image & " seconds ...");
   Ada.Text_IO.Put_Line ("(Resize your terminal window now)");
   Ada.Text_IO.New_Line;

   declare
      Deadline : constant Time := Clock + POLL_DURATION;
   begin
      while Clock < Deadline loop
         if Termicap.Sigwinch.Has_Resize then
            declare
               New_Size : constant Termicap.Dimensions.Terminal_Size :=
                  Termicap.Sigwinch.Get_Cached_Size;
            begin
               Ada.Text_IO.Put_Line
                  ("Resize detected -> " & Size_Image (New_Size)
                   & "  (columns x rows)");
            end;
            Termicap.Sigwinch.Acknowledge_Resize;
         end if;

         delay POLL_INTERVAL;
      end loop;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Poll loop finished.");

   ---------------------------------------------------------------------------
   --  Pattern A — Polling (render-loop style)
   --
   --  The simplest integration: call Has_Resize once per render iteration.
   --  No extra file descriptors.  Correct for most TUI applications.
   --
   --    loop
   --       --  ... render the screen using Get_Cached_Size ...
   --       if Termicap.Sigwinch.Has_Resize then
   --          New_Size := Termicap.Sigwinch.Get_Cached_Size;
   --          Re_Layout (New_Size);
   --          Termicap.Sigwinch.Acknowledge_Resize;
   --       end if;
   --       --  ... wait for next frame / user input ...
   --    end loop;
   --
   --  The loop above is what the 10-second section demonstrates live.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Pattern A: Polling (render-loop) ---");
   Ada.Text_IO.Put_Line ("  Call Has_Resize each iteration; re-layout on True;");
   Ada.Text_IO.Put_Line ("  then Acknowledge_Resize to arm for the next signal.");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Pattern B — Self-pipe (event-loop / select style)
   --
   --  When the application already blocks in select()/poll()/epoll() waiting
   --  for I/O, add the self-pipe read FD to the watched set.  The C signal
   --  handler writes one byte to the write end on each SIGWINCH delivery
   --  (O_NONBLOCK; byte is silently dropped if the pipe buffer is full because
   --  there is already an unread notification).
   --
   --  Event-loop integration sketch:
   --
   --    Read_FD : constant Integer := Termicap.Sigwinch.Get_Pipe_Read_FD;
   --    --  Add Read_FD to your select/poll/epoll fd set.
   --    --  When the fd becomes readable:
   --    --    1. Drain the pipe (read until EAGAIN) to reset the readable state.
   --    --    2. Call Get_Cached_Size to obtain the new dimensions.
   --    --    3. Call Acknowledge_Resize to clear the pending flag.
   --    --    4. Re-layout the UI.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Pattern B: Self-pipe (event-loop / select) ---");
   declare
      Read_FD : constant Integer := Termicap.Sigwinch.Get_Pipe_Read_FD;
   begin
      Ada.Text_IO.Put_Line
         ("  Self-pipe read FD to add to select/poll/epoll set: "
          & Read_FD'Image);
      Ada.Text_IO.Put_Line
         ("  When readable: drain pipe, call Get_Cached_Size,");
      Ada.Text_IO.Put_Line
         ("  Acknowledge_Resize, then re-layout.");
   end;
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Cleanup
   ---------------------------------------------------------------------------

   Termicap.Sigwinch.Uninstall;

   declare
      FD_After : constant Integer := Termicap.Sigwinch.Get_Pipe_Read_FD;
   begin
      Ada.Text_IO.Put_Line
         ("Handler uninstalled.  Get_Pipe_Read_FD: " & FD_After'Image
          & (if FD_After = -1 then "  (closed, as expected)"
             else "  (unexpected: should be -1)"));
   end;

end Sigwinch_Demo;
