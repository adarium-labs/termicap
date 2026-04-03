-------------------------------------------------------------------------------
--  Termicap.TTY - Terminal Teletype Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects whether standard I/O streams are connected to an interactive
--  terminal (TTY).
--
--  @description
--  Provides per-stream TTY detection using the POSIX isatty() system call.
--  The package spec is SPARK-annotated for type safety; the body uses
--  SPARK_Mode => Off for the C FFI binding.
--
--  All detection functions are safe and non-destructive: they return False
--  on error and never raise exceptions or modify terminal state.
--
--  Requirements Coverage:
--    - @relation(FUNC-TTY-001): Stream_Kind enumeration type
--    - @relation(FUNC-TTY-002): Per-stream TTY detection
--    - @relation(FUNC-TTY-003): POSIX isatty() binding
--    - @relation(FUNC-TTY-004): Safe, non-destructive query
--    - @relation(FUNC-TTY-005): SPARK boundary
--    - @relation(FUNC-TTY-006): Bulk TTY status query

with Termicap.Override;

package Termicap.TTY
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Types (FUNC-TTY-001)
   ---------------------------------------------------------------------------

   --  @summary Identifies a standard I/O stream.
   --  @relation(FUNC-TTY-001): Stream kind enumeration
   type Stream_Kind is (Stdin, Stdout, Stderr);

   --  @summary TTY status for all three standard streams.
   --  @relation(FUNC-TTY-006): Bulk query result type
   type TTY_Status is record
      Stdin  : Boolean;
      Stdout : Boolean;
      Stderr : Boolean;
   end record;

   ---------------------------------------------------------------------------
   --  Per-Stream Detection (FUNC-TTY-002, FUNC-TTY-003, FUNC-TTY-004)
   ---------------------------------------------------------------------------

   --  @summary Check whether a standard stream is connected to a terminal.
   --  @param Stream The stream to query.
   --  @return True if the stream is connected to an interactive terminal,
   --          False otherwise (including when the stream handle is invalid
   --          or the query fails for any reason).
   --  @relation(FUNC-TTY-002): Per-stream TTY detection
   --  @relation(FUNC-TTY-003): Uses POSIX isatty() internally
   --  @relation(FUNC-TTY-004): Returns False on error, never raises
   function Is_TTY (Stream : Stream_Kind) return Boolean
   with Global => (Input => Termicap.Override.Override_State);

   ---------------------------------------------------------------------------
   --  Bulk Query (FUNC-TTY-006)
   ---------------------------------------------------------------------------

   --  @summary Query TTY status for all three streams at once.
   --  @return A record containing the TTY status of Stdin, Stdout, and Stderr.
   --  @relation(FUNC-TTY-006): Convenience function reducing FFI calls
   function Query_All return TTY_Status;

end Termicap.TTY;
