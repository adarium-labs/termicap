-------------------------------------------------------------------------------
--  Termicap.Sigwinch - SIGWINCH Resize Notification
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Provides asynchronous terminal resize notification via POSIX SIGWINCH,
--  with a self-pipe for I/O loop integration and a polling interface.
--
--  @description
--  This package manages a SIGWINCH signal handler lifecycle.  When installed,
--  the handler automatically re-queries terminal dimensions via
--  ioctl(TIOCGWINSZ) and caches the result in an internal thread-safe
--  protected object.  Applications can poll for resize events or integrate
--  with select()/poll()/epoll() via the exposed self-pipe read FD.
--
--  All public operations are thin wrappers around an internal protected
--  singleton object declared in the package body.  This keeps the protected
--  object a private implementation detail while presenting a flat procedural
--  API to callers.
--
--  This package is an Ada FFI boundary and does not carry SPARK provability.
--  Ada interrupt handlers on protected types and dynamic signal attachment
--  are outside the SPARK 2014 language subset.  Candidates for future SPARK
--  extraction: pending-flag management logic and cached-size update logic,
--  which are pure state transitions.
--
--  Requirements Coverage:
--    - @relation(FUNC-SWC-001): Signal handler installation and removal
--    - @relation(FUNC-SWC-002): Automatic dimension re-query on SIGWINCH
--    - @relation(FUNC-SWC-003): Resize event polling interface
--    - @relation(FUNC-SWC-004): Self-pipe write on SIGWINCH
--    - @relation(FUNC-SWC-005): Pipe read FD exposure
--    - @relation(FUNC-SWC-006): Handler cleanup and resource release
--    - @relation(FUNC-SWC-007): Thread safety via Ada protected object
--    - @relation(FUNC-SWC-008): Graceful degradation on non-Unix platforms
--    - @relation(FUNC-SWC-009): Registered file descriptor at install time
--    - @relation(FUNC-SWC-010): Current cached dimensions retrieval
--    - @relation(FUNC-SWC-011): SPARK boundary declaration

pragma SPARK_Mode (Off);

with Termicap.Dimensions;

package Termicap.Sigwinch is

   ---------------------------------------------------------------------------
   --  Lifecycle (FUNC-SWC-001, FUNC-SWC-004, FUNC-SWC-009)
   ---------------------------------------------------------------------------

   --  @summary Install the SIGWINCH signal handler and create the self-pipe.
   --  @description
   --  Creates a pipe with O_NONBLOCK on the write end, performs an initial
   --  ioctl(TIOCGWINSZ) query using Terminal_FD, and installs the C-level
   --  signal handler via sigaction().  The operation is idempotent: calling
   --  Install when the handler is already installed has no effect.
   --  @param Terminal_FD  File descriptor used for ioctl(TIOCGWINSZ) queries
   --                      inside the signal handler.  Defaults to 1
   --                      (STDOUT_FILENO), which is consistent with the
   --                      ioctl-based dimension detection in Termicap.Dimensions.
   --  @relation(FUNC-SWC-001): Explicit installation, not automatic at elaboration
   --  @relation(FUNC-SWC-004): Creates self-pipe with O_NONBLOCK on write end
   --  @relation(FUNC-SWC-009): Accepts terminal FD parameter, defaults to 1
   --  @relation(FUNC-SWC-010): Performs initial ioctl query at install time
   procedure Install (Terminal_FD : Integer := 1);

   --  @summary Uninstall the SIGWINCH signal handler and release all resources.
   --  @description
   --  Performs ordered cleanup: (1) restores the previous signal disposition
   --  saved at install time, (2) closes the write end of the self-pipe,
   --  (3) closes the read end of the self-pipe, (4) resets the pending-resize
   --  flag to False, (5) resets the cached Terminal_Size to the default
   --  (80 columns, 24 rows, 0 pixel dimensions).  The operation is idempotent:
   --  calling Uninstall when the handler is not installed has no effect.
   --  After this call the FD previously returned by Get_Pipe_Read_FD is
   --  closed and must not be used by the caller.
   --  @relation(FUNC-SWC-001): Explicit removal, idempotent
   --  @relation(FUNC-SWC-006): Ordered cleanup of resources and state
   procedure Uninstall;

   ---------------------------------------------------------------------------
   --  Polling Interface (FUNC-SWC-003)
   ---------------------------------------------------------------------------

   --  @summary Report whether a terminal resize event is pending.
   --  @description
   --  Returns True if at least one SIGWINCH signal has been received since
   --  the handler was installed or since the last call to Acknowledge_Resize.
   --  Returns False when the handler is not installed.
   --  Non-blocking; no side effects.
   --  @return True if a resize event is pending, False otherwise.
   --  @relation(FUNC-SWC-003): Non-blocking polling, no side effects
   function Has_Resize return Boolean;

   --  @summary Clear the pending-resize flag.
   --  @description
   --  After this call Has_Resize returns False until the next SIGWINCH signal.
   --  Separate from Has_Resize to avoid a race where a SIGWINCH arriving
   --  between a query and an acknowledgement is silently lost.
   --  No-op when the handler is not installed.
   --  @relation(FUNC-SWC-003): Acknowledgement clears flag atomically
   procedure Acknowledge_Resize;

   ---------------------------------------------------------------------------
   --  Self-Pipe (FUNC-SWC-004, FUNC-SWC-005)
   ---------------------------------------------------------------------------

   --  @summary Return the read end of the self-pipe for I/O multiplexing.
   --  @description
   --  Callers may register this FD with select(), poll(), epoll(), or any
   --  other I/O multiplexing interface.  When the FD becomes readable, the
   --  caller should drain it (read and discard all available bytes) and then
   --  call Has_Resize / Acknowledge_Resize or Get_Cached_Size to consume the
   --  notification.  The FD remains valid for the lifetime of the installed
   --  handler and is closed by Uninstall.
   --  @return A non-negative file descriptor when the handler is installed;
   --          -1 (invalid FD) when not installed or on non-Unix platforms.
   --  @relation(FUNC-SWC-005): Exposes read end of self-pipe for event loops
   --  @relation(FUNC-SWC-008): Returns -1 on non-Unix platforms
   function Get_Pipe_Read_FD return Integer;

   ---------------------------------------------------------------------------
   --  Cached Dimensions (FUNC-SWC-002, FUNC-SWC-010)
   ---------------------------------------------------------------------------

   --  @summary Return the most recently cached terminal dimensions.
   --  @description
   --  Returns the dimensions captured by the last ioctl(TIOCGWINSZ) call,
   --  which occurs either at install time or inside the signal handler on
   --  each SIGWINCH delivery.  No new ioctl call is performed.  Returns the
   --  default size (80 columns, 24 rows, 0 pixel dimensions) when the handler
   --  is not installed.  Safe to call concurrently from multiple tasks.
   --  @return The most recently cached Terminal_Size.
   --  @relation(FUNC-SWC-002): Reflects result of automatic dimension re-query
   --  @relation(FUNC-SWC-010): Returns cached value without a new ioctl call
   function Get_Cached_Size return Termicap.Dimensions.Terminal_Size;

end Termicap.Sigwinch;
