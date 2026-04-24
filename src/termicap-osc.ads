-------------------------------------------------------------------------------
--  Termicap.OSC - OSC Probe Session and Terminal I/O
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Provides the probe session type and low-level terminal I/O operations
--  for sending OSC/DCS/CSI escape sequence queries and reading responses.
--
--  @description
--  This package is the FFI boundary for all active terminal probing.  It
--  encapsulates the full open/raw-mode/query/restore/close lifecycle in a
--  Probe_Session controlled type that guarantees terminal state restoration
--  via Ada.Finalization.Limited_Controlled semantics.
--
--  The probe session opens /dev/tty directly so that queries and responses
--  use a dedicated file descriptor independent of how stdin, stdout, and
--  stderr are connected.  Before opening, the foreground process group is
--  checked to avoid sending queries from background jobs.  The terminal is
--  switched to raw mode (no echo, no line buffering) during the query phase
--  and unconditionally restored on scope exit or exception propagation.
--
--  The sentinel-bounded query pattern sends each user query followed by a
--  DA1 request (CSI c).  Response bytes are accumulated until the DA1
--  response (CSI ? ... c) is detected or the timeout expires.  This pattern
--  makes response boundaries unambiguous across heterogeneous terminals.
--
--  This package is an Ada FFI boundary and does not carry SPARK provability.
--  It uses Ada.Finalization.Limited_Controlled and calls POSIX system calls
--  (open, close, tcgetattr, tcsetattr, ioctl, select, read, write), all of
--  which are outside the SPARK 2014 language subset.  Pure parsing and
--  detection logic is isolated in the SPARK On child package
--  Termicap.OSC.Parsing.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-001): Terminal file descriptor via /dev/tty
--    - @relation(FUNC-OSC-002): Termios state save and restore
--    - @relation(FUNC-OSC-003): Raw mode activation
--    - @relation(FUNC-OSC-004): Timed read with select()
--    - @relation(FUNC-OSC-005): Query write to terminal
--    - @relation(FUNC-OSC-006): Sentinel-bounded query
--    - @relation(FUNC-OSC-007): Foreground process group check
--    - @relation(FUNC-OSC-008): Probe session lifecycle
--    - @relation(FUNC-OSC-009): Bounded response buffer
--    - @relation(FUNC-OSC-011): Stale input drain before query
--    - @relation(FUNC-OSC-012): Single concurrent session enforcement
--    - @relation(FUNC-OSC-013): Query retry on timeout
--    - @relation(FUNC-OSC-015): SPARK boundary declaration

pragma SPARK_Mode (Off);

with Ada.Finalization;
with Interfaces.C;

package Termicap.OSC is

   ---------------------------------------------------------------------------
   --  Primitive Types (FUNC-OSC-001)
   ---------------------------------------------------------------------------

   --  @summary POSIX file descriptor for terminal I/O.
   --  @description A distinct integer type prevents accidental confusion
   --  between file descriptors and other integer quantities.
   --  @relation(FUNC-OSC-001): Terminal file descriptor
   type File_Descriptor is new Interfaces.C.int;

   --  @summary Sentinel value indicating an invalid or closed file descriptor.
   --  @relation(FUNC-OSC-001): Error return from Open_Terminal
   INVALID_FD : constant File_Descriptor := -1;

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for terminal queries and responses.
   --  @description Used both as the type for arbitrary escape sequence queries
   --  (sent to the terminal) and for accumulated response bytes (read from it).
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Termios State (FUNC-OSC-002)
   ---------------------------------------------------------------------------

   --  @summary Maximum byte size of an opaque termios buffer.
   --  @description Chosen as a conservative upper bound: Linux struct termios
   --  is 60 bytes, macOS is 72 bytes, FreeBSD is 44 bytes.  128 bytes provides
   --  headroom for future platforms.  The C helper copies the platform-specific
   --  struct into this buffer and reports the actual size via the Size field.
   --  @relation(FUNC-OSC-002): Termios state opaque byte buffer
   MAX_TERMIOS_SIZE : constant := 128;

   --  @summary Opaque buffer holding a saved struct termios from a C helper.
   --  @description The Data field receives the raw struct termios bytes from
   --  termicap_osc_save_termios().  Size records the actual sizeof(struct termios)
   --  on the current platform, as returned by termicap_osc_termios_size().
   --  This record is passed back to termicap_osc_restore_termios() and
   --  termicap_osc_set_raw() to avoid C-side static state, which would prevent
   --  concurrent sessions on different file descriptors.
   --  @relation(FUNC-OSC-002): Termios state save and restore buffer
   type Termios_State is limited record
      Data : Byte_Array (1 .. MAX_TERMIOS_SIZE);
      Size : Natural;
   end record;

   ---------------------------------------------------------------------------
   --  Session Status (FUNC-OSC-008)
   ---------------------------------------------------------------------------

   --  @summary Outcome of a Probe_Session Open call.
   --  @description Each value reports the exact step at which opening failed,
   --  so callers can distinguish "no terminal" (pipes, non-interactive) from
   --  "background process" from an OS-level save/raw failure.
   --  @relation(FUNC-OSC-008): Probe session lifecycle error reporting
   type Session_Status is
     (Session_OK,
      Session_Not_Foreground,
      Session_No_Terminal,
      Session_Save_Failed,
      Session_Raw_Failed,
      Session_Already_Active);

   ---------------------------------------------------------------------------
   --  Response Buffer (FUNC-OSC-009)
   ---------------------------------------------------------------------------

   --  @summary Maximum number of response bytes accumulated by Sentinel_Query.
   --  @description 4096 bytes is far larger than any known OSC/DCS response
   --  (background color: ~20 bytes, window title: ~256 bytes).  Exceeding this
   --  limit is treated as a timeout condition to prevent unbounded accumulation.
   --  @relation(FUNC-OSC-009): Bounded response buffer capacity
   MAX_RESPONSE_SIZE : constant := 4_096;

   --  @summary Fixed-size accumulation buffer for Sentinel_Query responses.
   --  @description Stack-allocated; no heap allocation occurs during probing.
   --  @relation(FUNC-OSC-009): Stack-allocated bounded response buffer
   subtype Response_Buffer is Byte_Array (1 .. MAX_RESPONSE_SIZE);

   ---------------------------------------------------------------------------
   --  Probe Session (FUNC-OSC-008, FUNC-OSC-015)
   ---------------------------------------------------------------------------

   --  @summary RAII probe session encapsulating /dev/tty open, raw mode, and restore.
   --  @description Declare a Probe_Session in a declare block, call Open, perform
   --  one or more Sentinel_Query calls, then let the session go out of scope.
   --  Finalize unconditionally restores termios and closes the file descriptor,
   --  even if an exception propagates through the query phase.
   --
   --  The type is limited so that it cannot be copied or assigned, enforcing
   --  single-owner semantics.  Only one Probe_Session may be open at any time;
   --  a second concurrent Open returns Session_Already_Active.
   --  @relation(FUNC-OSC-008): Probe session lifecycle via Limited_Controlled
   --  @relation(FUNC-OSC-012): Single concurrent session via Is_Raw guard
   --  @relation(FUNC-OSC-015): SPARK_Mode Off for controlled type
   type Probe_Session is new Ada.Finalization.Limited_Controlled with private;

   ---------------------------------------------------------------------------
   --  Session Lifecycle (FUNC-OSC-008)
   ---------------------------------------------------------------------------

   --  @summary Open a probe session: check foreground, open /dev/tty, enter raw mode.
   --  @description Performs the following steps in order:
   --    1. Foreground process group check (FUNC-OSC-007).  Returns
   --       Session_Not_Foreground and stops if the process is in the background.
   --    2. Acquire the single-session guard (FUNC-OSC-012).  Returns
   --       Session_Already_Active if another session is open.
   --    3. Open /dev/tty (FUNC-OSC-001).  Returns Session_No_Terminal on failure.
   --    4. Save termios state (FUNC-OSC-002).  Returns Session_Save_Failed and
   --       closes the FD on failure.
   --    5. Activate raw mode (FUNC-OSC-003).  Returns Session_Raw_Failed and
   --       restores termios and closes the FD on failure.
   --    6. Drain stale input (FUNC-OSC-011).  Non-fatal; proceeds regardless.
   --  On success, Status is Session_OK and Is_Open returns True.
   --  @param Session The session object being opened.
   --  @param Status  Outcome of the open sequence.
   --  @relation(FUNC-OSC-008): Full open sequence
   procedure Open (Session : in out Probe_Session; Status : out Session_Status);

   --  @summary Return True if the session was opened successfully and not yet closed.
   --  @param Session The session to query.
   --  @return True when the session's file descriptor is valid and raw mode is active.
   --  @relation(FUNC-OSC-008): Session state predicate
   function Is_Open (Session : Probe_Session) return Boolean;

   --  @summary Close the probe session: restore termios and close /dev/tty.
   --  @description Safe to call when not open (no-op).  Also called automatically
   --  by Finalize on scope exit or exception propagation.
   --  @param Session The session to close.
   --  @relation(FUNC-OSC-008): Ordered close: restore termios then close FD
   procedure Close (Session : in out Probe_Session);

   ---------------------------------------------------------------------------
   --  Query Operations (FUNC-OSC-006, FUNC-OSC-013)
   ---------------------------------------------------------------------------

   --  @summary Send a query and a DA1 sentinel, then accumulate the response.
   --  @description Writes Query to the session's terminal FD, immediately
   --  followed by the DA1 sentinel (ESC [ c, three bytes: 0x1B 0x5B 0x63).
   --  Then reads response bytes in a loop until the DA1 response pattern
   --  (ESC [ ? ... c) is detected in the accumulated bytes or the total elapsed
   --  time exceeds Timeout_Ms.
   --
   --  On DA1 detection, Response is populated with the pre-sentinel bytes and
   --  Resp_Length is set to the number of valid bytes.  Timed_Out is False.
   --
   --  On timeout, Timed_Out is True and Resp_Length is 0.  If Retry is True
   --  and the first attempt timed out, the query and sentinel are resent and
   --  the read loop is repeated with a timeout of 2 * Timeout_Ms.
   --
   --  The Session must be open (Is_Open returns True) before calling.
   --  @param Session    The open probe session providing the terminal FD.
   --  @param Query      The escape sequence bytes to send (e.g., OSC 11 query).
   --  @param Response   Buffer receiving the pre-sentinel response bytes.
   --  @param Resp_Length Number of valid bytes written into Response.
   --  @param Timeout_Ms Millisecond timeout for the read accumulation loop.
   --  @param Timed_Out  True if the DA1 response was not detected within the timeout.
   --  @param Retry      When True and the first attempt times out, retry once
   --                    with 2 * Timeout_Ms.  Defaults to False.
   --  @relation(FUNC-OSC-006): Sentinel-bounded query accumulation
   --  @relation(FUNC-OSC-009): Uses bounded Response_Buffer; overflow = timeout
   --  @relation(FUNC-OSC-013): Optional single retry with doubled timeout
   procedure Sentinel_Query
     (Session     : Probe_Session;
      Query       : Byte_Array;
      Response    : out Response_Buffer;
      Resp_Length : out Natural;
      Timeout_Ms  : Natural;
      Timed_Out   : out Boolean;
      Retry       : Boolean := False);

   --  @summary Write a query and accumulate bytes until a DA1 response is found or timeout.
   --  @description Timeout-only variant of Sentinel_Query for use when the DA1 response
   --  IS the data being sought (FUNC-DA1-008, ADR-0017).  Unlike Sentinel_Query, no DA1
   --  sentinel is appended after the query.  The read loop exits when
   --  Contains_DA1_Response returns True for the accumulated bytes, or when the elapsed
   --  time exceeds Timeout_Ms.
   --
   --  On DA1 detection, Response is populated with all accumulated bytes (including the
   --  DA1 response itself) and Resp_Length is set to the byte count.  Timed_Out is False.
   --
   --  On timeout, Timed_Out is True and Resp_Length is 0.
   --
   --  The Session must be open (Is_Open returns True) before calling.
   --  @param Session     The open probe session providing the terminal FD.
   --  @param Query       The escape sequence bytes to write (e.g., DA1_QUERY).
   --  @param Response    Buffer receiving the accumulated response bytes.
   --  @param Resp_Length Number of valid bytes written into Response.
   --  @param Timeout_Ms  Millisecond timeout for the read accumulation loop.
   --  @param Timed_Out   True if no complete DA1 response was detected within Timeout_Ms.
   --  @relation(FUNC-DA1-008): Timeout-only read loop for DA1 query
   procedure Timeout_Query
     (Session     : Probe_Session;
      Query       : Byte_Array;
      Response    : out Response_Buffer;
      Resp_Length : out Natural;
      Timeout_Ms  : Natural;
      Timed_Out   : out Boolean);

   ---------------------------------------------------------------------------
   --  Low-Level I/O (FUNC-OSC-004, FUNC-OSC-005, FUNC-OSC-007)
   ---------------------------------------------------------------------------

   --  @summary Write a byte sequence (escape sequence query) to the session's FD.
   --  @description Calls write() on the session's terminal file descriptor.
   --  Success is False if write() writes fewer bytes than Query'Length or returns
   --  an error.  Does not retry partial writes.
   --  @param Session The open probe session.
   --  @param Query   The bytes to write (an escape sequence).
   --  @param Written Number of bytes actually written by write().
   --  @param Success False on partial write or write() error.
   --  @relation(FUNC-OSC-005): Query write to terminal via write()
   procedure Write_Query (Session : Probe_Session; Query : Byte_Array; Written : out Natural; Success : out Boolean);

   --  @summary Read bytes from a file descriptor with a millisecond timeout.
   --  @description Uses select() to wait up to Timeout_Ms milliseconds for the
   --  FD to become readable, then calls read().  If select() times out, Timed_Out
   --  is True and Bytes_Read is 0.  If select() or read() returns an error,
   --  Bytes_Read is 0 and Timed_Out is False.
   --  @param FD         File descriptor to read from.
   --  @param Buffer     Output buffer for received bytes.
   --  @param Bytes_Read Number of bytes placed into Buffer.
   --  @param Timeout_Ms Timeout in milliseconds (0 = non-blocking poll).
   --  @param Timed_Out  True when select() returned 0 (no data within timeout).
   --  @relation(FUNC-OSC-004): Timed read via select() + read()
   procedure Timed_Read
     (FD         : File_Descriptor;
      Buffer     : out Byte_Array;
      Bytes_Read : out Natural;
      Timeout_Ms : Natural;
      Timed_Out  : out Boolean);

   --  @summary Check whether this process is in the foreground process group.
   --  @description Calls ioctl(FD, TIOCGPGRP, &fg_pgrp) and compares with
   --  getpgrp().  Returns False on ioctl failure to err on the side of not
   --  sending queries.
   --  @param FD The terminal file descriptor to check.
   --  @return True if the calling process is in the terminal's foreground group.
   --  @relation(FUNC-OSC-007): Foreground process group check via TIOCGPGRP
   function Is_Foreground_Process (FD : File_Descriptor) return Boolean;

   ---------------------------------------------------------------------------
   --  Internal Terminal Operations (FUNC-OSC-001..003, FUNC-OSC-011)
   ---------------------------------------------------------------------------

   --  @summary Open /dev/tty for direct terminal I/O.
   --  @description Calls open("/dev/tty", O_RDWR) via the C helper.
   --  Returns INVALID_FD if /dev/tty cannot be opened.
   --  @return A valid file descriptor, or INVALID_FD on failure.
   --  @relation(FUNC-OSC-001): Terminal file descriptor acquisition
   function Open_Terminal return File_Descriptor;

   --  @summary Close a terminal file descriptor.
   --  @description Calls close(FD) via the C helper.  Sets FD to INVALID_FD.
   --  Safe to call with INVALID_FD (no-op).
   --  @param FD The file descriptor to close; set to INVALID_FD on return.
   --  @relation(FUNC-OSC-001): Terminal file descriptor release
   procedure Close_Terminal (FD : in out File_Descriptor);

   --  @summary Save the current termios state of a terminal file descriptor.
   --  @description Calls termicap_osc_save_termios() which invokes tcgetattr()
   --  and copies the struct termios raw bytes into State.Data, recording the
   --  actual platform size in State.Size.
   --  @param FD    Terminal file descriptor.
   --  @param State Populated with the current termios on success.
   --  @param OK    False if tcgetattr() failed.
   --  @relation(FUNC-OSC-002): Termios state save via tcgetattr()
   procedure Save_Termios (FD : File_Descriptor; State : out Termios_State; OK : out Boolean);

   --  @summary Restore a previously saved termios state.
   --  @description Calls termicap_osc_restore_termios() which copies State.Data
   --  back into a struct termios and calls tcsetattr(FD, TCSANOW, &termios).
   --  Does not raise an exception on failure; OK reports the outcome.
   --  @param FD    Terminal file descriptor.
   --  @param State Saved state previously obtained from Save_Termios.
   --  @param OK    False if tcsetattr() failed.
   --  @relation(FUNC-OSC-002): Termios state restore via tcsetattr(TCSANOW)
   procedure Restore_Termios (FD : File_Descriptor; State : Termios_State; OK : out Boolean);

   --  @summary Switch a terminal file descriptor to raw mode.
   --  @description Calls termicap_osc_set_raw() which derives a raw-mode
   --  struct termios from State (clearing ICANON, ECHO, ISIG, IXON, ICRNL,
   --  BRKINT and setting VMIN=0, VTIME=0) and applies it via tcsetattr(TCSANOW).
   --  Does not modify State.  Must only be called after a successful Save_Termios.
   --  @param FD    Terminal file descriptor.
   --  @param State Saved termios state (used as the base for raw mode derivation).
   --  @param OK    False if tcsetattr() failed.
   --  @relation(FUNC-OSC-003): Raw mode activation via tcsetattr()
   procedure Set_Raw_Mode (FD : File_Descriptor; State : Termios_State; OK : out Boolean);

   --  @summary Drain stale buffered bytes from a terminal file descriptor.
   --  @description Performs non-blocking Timed_Read calls (Timeout_Ms = 0),
   --  discarding all received bytes, until a read returns 0 bytes.  Bounded
   --  to at most MAX_DRAIN_ITERATIONS iterations to prevent an infinite loop
   --  against a continuously-streaming terminal.
   --  @param FD The terminal file descriptor to drain.
   --  @relation(FUNC-OSC-011): Stale input drain with iteration bound
   procedure Drain_Input (FD : File_Descriptor);

private

   type Probe_Session is new Ada.Finalization.Limited_Controlled with record
      FD          : File_Descriptor := INVALID_FD;
      Saved_State : Termios_State;
      Is_Raw      : Boolean := False;
   end record;

   overriding
   procedure Finalize (Session : in out Probe_Session);

end Termicap.OSC;
