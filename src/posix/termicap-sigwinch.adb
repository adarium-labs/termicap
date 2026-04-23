-------------------------------------------------------------------------------
--  Termicap.Sigwinch - SIGWINCH Resize Notification (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Full Unix implementation of the SIGWINCH resize notification package.
--
--  @description
--  This body uses a C-level signal trampoline (termicap_sigwinch.c) for
--  async-signal-safe SIGWINCH handling.  All mutable state is encapsulated
--  in the library-level protected object State_Handler, which serialises
--  concurrent access from multiple tasks (FUNC-SWC-007).
--
--  Requirements Coverage:
--    - @relation(FUNC-SWC-001): Install / Uninstall lifecycle, idempotent
--    - @relation(FUNC-SWC-002): C handler does ioctl; Ada reads via accessor
--    - @relation(FUNC-SWC-003): Has_Resize / Acknowledge_Resize polling
--    - @relation(FUNC-SWC-004): Pipe creation with O_NONBLOCK on write end
--    - @relation(FUNC-SWC-005): Get_Pipe_Read_FD exposes read end
--    - @relation(FUNC-SWC-006): Ordered cleanup in Uninstall
--    - @relation(FUNC-SWC-007): Protected object serialises all state access
--    - @relation(FUNC-SWC-008): Graceful degradation on non-Unix platforms
--    - @relation(FUNC-SWC-009): Terminal_FD parameter at install time
--    - @relation(FUNC-SWC-010): Cached size valid immediately after Install
--    - @relation(FUNC-SWC-011): SPARK_Mode => Off; FFI boundary

pragma SPARK_Mode (Off);

with Interfaces.C;

package body Termicap.Sigwinch is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_short;

   ---------------------------------------------------------------------------
   --  C FFI bindings
   ---------------------------------------------------------------------------

   --  pipe(2): create a pair of file descriptors.
   --  pipefd[0] = read end, pipefd[1] = write end.
   type Pipe_FD_Array is array (0 .. 1) of Interfaces.C.int;

   function C_Pipe (Pipefd : access Pipe_FD_Array) return Interfaces.C.int;
   pragma Import (C, C_Pipe, "pipe");

   --  Set O_NONBLOCK on a file descriptor.  Implemented in C so the
   --  platform-specific value of O_NONBLOCK (Linux=2048, Darwin/BSD=4, ...)
   --  stays inside the C layer where <fcntl.h> guarantees correctness.
   --  Returns 0 on success, -1 on error.
   function C_Set_Nonblock (Fd : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Set_Nonblock, "termicap_set_nonblock");

   --  close(2): close a file descriptor.
   function C_Close (Fd : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Close, "close");

   --  C trampoline: install SIGWINCH handler via sigaction, perform initial
   --  ioctl query, store pipe write FD for use in the signal handler.
   --  Returns 0 on success, -1 on error (FUNC-SWC-001, FUNC-SWC-010).
   function C_Sigwinch_Install
     (Fd : Interfaces.C.int; Write_FD : Interfaces.C.int)
      return Interfaces.C.int;
   pragma Import (C, C_Sigwinch_Install, "termicap_sigwinch_install");

   --  C trampoline: restore the previous SIGWINCH disposition and reset
   --  C-side state.  Returns 0 on success, -1 on error (FUNC-SWC-006).
   function C_Sigwinch_Restore return Interfaces.C.int;
   pragma Import (C, C_Sigwinch_Restore, "termicap_sigwinch_restore");

   --  Return 1 if a resize event is pending, 0 otherwise (FUNC-SWC-003).
   function C_Sigwinch_Pending return Interfaces.C.int;
   pragma Import (C, C_Sigwinch_Pending, "termicap_sigwinch_pending");

   --  Clear the C-side resize-pending flag (FUNC-SWC-003).
   procedure C_Sigwinch_Acknowledge;
   pragma Import (C, C_Sigwinch_Acknowledge, "termicap_sigwinch_acknowledge");

   --  Copy the cached terminal dimensions out of C-side volatile storage
   --  (FUNC-SWC-002, FUNC-SWC-010).
   procedure C_Sigwinch_Get_Size
     (Cols   : access Interfaces.C.unsigned_short;
      Rows   : access Interfaces.C.unsigned_short;
      Xpixel : access Interfaces.C.unsigned_short;
      Ypixel : access Interfaces.C.unsigned_short);
   pragma Import (C, C_Sigwinch_Get_Size, "termicap_sigwinch_get_size");

   ---------------------------------------------------------------------------
   --  Platform constants (POSIX; Linux/macOS/BSDs)
   ---------------------------------------------------------------------------

   INVALID_FD : constant Interfaces.C.int := -1;

   DEFAULT_SIZE : constant Termicap.Dimensions.Terminal_Size :=
     (Rows         => Termicap.Dimensions.DEFAULT_ROWS,
      Columns      => Termicap.Dimensions.DEFAULT_COLUMNS,
      Pixel_Width  => 0,
      Pixel_Height => 0);

   ---------------------------------------------------------------------------
   --  Internal Protected Object (FUNC-SWC-007)
   ---------------------------------------------------------------------------

   protected State_Handler is
      procedure Install (Terminal_FD : Interfaces.C.int);
      procedure Uninstall;
      function Has_Resize return Boolean;
      procedure Acknowledge_Resize;
      function Get_Pipe_Read_FD return Interfaces.C.int;
      procedure Query_Cached_Size
        (Result : out Termicap.Dimensions.Terminal_Size);
   private
      Installed   : Boolean := False;
      Cached_Size : Termicap.Dimensions.Terminal_Size := DEFAULT_SIZE;
      Pipe_Read   : Interfaces.C.int := INVALID_FD;
      Pipe_Write  : Interfaces.C.int := INVALID_FD;
   end State_Handler;

   ---------------------------------------------------------------------------
   --  Protected Body
   ---------------------------------------------------------------------------

   protected body State_Handler is

      procedure Install (Terminal_FD : Interfaces.C.int) is
         Actual_FD : Interfaces.C.int;
         Pipe_FDs  : aliased Pipe_FD_Array := [others => INVALID_FD];
         Status    : Interfaces.C.int;
         pragma Unreferenced (Status);
      begin
         --  Idempotency guard (FUNC-SWC-001).
         if Installed then
            return;
         end if;

         --  Treat INVALID_FD as STDOUT_FILENO (FUNC-SWC-009).
         if Terminal_FD = INVALID_FD then
            Actual_FD := 1;
         else
            Actual_FD := Terminal_FD;
         end if;

         --  Create self-pipe (FUNC-SWC-004) and set write end non-blocking.
         if C_Pipe (Pipe_FDs'Access) = 0 then
            Status := C_Set_Nonblock (Pipe_FDs (1));
            Pipe_Read := Pipe_FDs (0);
            Pipe_Write := Pipe_FDs (1);
         else
            Pipe_Read := INVALID_FD;
            Pipe_Write := INVALID_FD;
         end if;

         --  Install C signal trampoline; performs initial ioctl (FUNC-SWC-010).
         Status := C_Sigwinch_Install (Actual_FD, Pipe_Write);

         --  Retrieve initial cached size from C-side state (FUNC-SWC-010).
         declare
            C_Cols   : aliased Interfaces.C.unsigned_short := 80;
            C_Rows   : aliased Interfaces.C.unsigned_short := 24;
            C_Xpixel : aliased Interfaces.C.unsigned_short := 0;
            C_Ypixel : aliased Interfaces.C.unsigned_short := 0;
         begin
            C_Sigwinch_Get_Size
              (C_Cols'Access, C_Rows'Access, C_Xpixel'Access, C_Ypixel'Access);
            if C_Cols > 0 and then C_Rows > 0 then
               Cached_Size :=
                 (Columns      => Positive (C_Cols),
                  Rows         => Positive (C_Rows),
                  Pixel_Width  => Natural (C_Xpixel),
                  Pixel_Height => Natural (C_Ypixel));
            else
               Cached_Size := DEFAULT_SIZE;
            end if;
         end;

         Installed := True;
      end Install;

      procedure Uninstall is
         Status : Interfaces.C.int;
         pragma Unreferenced (Status);
      begin
         --  Idempotency guard (FUNC-SWC-001).
         if not Installed then
            return;
         end if;

         --  Step 1: restore previous SIGWINCH disposition (FUNC-SWC-006).
         Status := C_Sigwinch_Restore;

         --  Step 2: close write end of self-pipe (FUNC-SWC-006).
         if Pipe_Write /= INVALID_FD then
            Status := C_Close (Pipe_Write);
            Pipe_Write := INVALID_FD;
         end if;

         --  Step 3: close read end of self-pipe (FUNC-SWC-006).
         if Pipe_Read /= INVALID_FD then
            Status := C_Close (Pipe_Read);
            Pipe_Read := INVALID_FD;
         end if;

         --  Step 4: reset cached size to default (FUNC-SWC-006).
         Cached_Size := DEFAULT_SIZE;

         Installed := False;
      end Uninstall;

      function Has_Resize return Boolean is
      begin
         if not Installed then
            return False;
         end if;
         return C_Sigwinch_Pending /= 0;
      end Has_Resize;

      procedure Acknowledge_Resize is
      begin
         if not Installed then
            return;
         end if;
         C_Sigwinch_Acknowledge;
      end Acknowledge_Resize;

      function Get_Pipe_Read_FD return Interfaces.C.int is
      begin
         if not Installed then
            return INVALID_FD;
         end if;
         return Pipe_Read;
      end Get_Pipe_Read_FD;

      procedure Query_Cached_Size
        (Result : out Termicap.Dimensions.Terminal_Size)
      is
         C_Cols   : aliased Interfaces.C.unsigned_short := 0;
         C_Rows   : aliased Interfaces.C.unsigned_short := 0;
         C_Xpixel : aliased Interfaces.C.unsigned_short := 0;
         C_Ypixel : aliased Interfaces.C.unsigned_short := 0;
      begin
         if not Installed then
            Result := DEFAULT_SIZE;
            return;
         end if;

         --  Re-read from C-side volatile storage to capture any signal-handler
         --  update since the last call (FUNC-SWC-002, FUNC-SWC-010).
         C_Sigwinch_Get_Size
           (C_Cols'Access, C_Rows'Access, C_Xpixel'Access, C_Ypixel'Access);

         if C_Cols > 0 and then C_Rows > 0 then
            Cached_Size :=
              (Columns      => Positive (C_Cols),
               Rows         => Positive (C_Rows),
               Pixel_Width  => Natural (C_Xpixel),
               Pixel_Height => Natural (C_Ypixel));
         end if;

         Result := Cached_Size;
      end Query_Cached_Size;

   end State_Handler;

   ---------------------------------------------------------------------------
   --  Public Package-Level Subprograms (delegate to State_Handler)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-SWC-001): Explicit installation, idempotent
   --  @relation(FUNC-SWC-004): Self-pipe created with O_NONBLOCK
   --  @relation(FUNC-SWC-009): Terminal_FD parameter; defaults to 1
   --  @relation(FUNC-SWC-010): Initial ioctl query
   procedure Install (Terminal_FD : Integer := 1) is
   begin
      State_Handler.Install (Interfaces.C.int (Terminal_FD));
   end Install;

   --  @relation(FUNC-SWC-001): Explicit removal, idempotent
   --  @relation(FUNC-SWC-006): Ordered cleanup
   procedure Uninstall is
   begin
      State_Handler.Uninstall;
   end Uninstall;

   --  @relation(FUNC-SWC-003): Non-blocking polling
   --  @relation(FUNC-SWC-008): Returns False when not installed
   function Has_Resize return Boolean is
   begin
      return State_Handler.Has_Resize;
   end Has_Resize;

   --  @relation(FUNC-SWC-003): Acknowledgement clears flag
   procedure Acknowledge_Resize is
   begin
      State_Handler.Acknowledge_Resize;
   end Acknowledge_Resize;

   --  @relation(FUNC-SWC-005): Exposes read end of self-pipe
   --  @relation(FUNC-SWC-008): Returns -1 when not installed
   function Get_Pipe_Read_FD return Integer is
   begin
      return Integer (State_Handler.Get_Pipe_Read_FD);
   end Get_Pipe_Read_FD;

   --  @relation(FUNC-SWC-002): Reflects automatic dimension re-query
   --  @relation(FUNC-SWC-010): Returns cached value without new ioctl
   function Get_Cached_Size return Termicap.Dimensions.Terminal_Size is
      Result : Termicap.Dimensions.Terminal_Size;
   begin
      State_Handler.Query_Cached_Size (Result);
      return Result;
   end Get_Cached_Size;

end Termicap.Sigwinch;
