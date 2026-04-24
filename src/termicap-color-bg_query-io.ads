-------------------------------------------------------------------------------
--  Termicap.Color.BG_Query.IO - OSC Color Query I/O Procedure
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Sends an OSC 10 or OSC 11 color query to the terminal and returns the
--  raw response bytes.
--
--  @description
--  This package provides the Query_Color procedure, which is the I/O
--  boundary of the BG-COLOR feature.  It opens a Probe_Session, optionally
--  wraps the query for multiplexer passthrough (tmux, screen), sends the
--  OSC byte sequence via Sentinel_Query, and returns the accumulated
--  response bytes to the caller.
--
--  All terminal interaction is performed through the existing
--  Termicap.OSC.Probe_Session and Sentinel_Query infrastructure.  No new
--  C wrappers or system calls are introduced by this package.
--
--  This package is SPARK_Mode Off because it calls Ada.Finalization
--  controlled types (Probe_Session) and performs terminal I/O, both of
--  which are outside the SPARK 2014 language subset.  The pure parsing
--  logic remains provable in the parent package Termicap.Color.BG_Query.
--
--  Requirements Coverage:
--    - @relation(FUNC-BGC-006): OSC color query execution via Probe_Session

pragma SPARK_Mode (Off);

package Termicap.Color.BG_Query.IO is

   ---------------------------------------------------------------------------
   --  Color Query I/O (FUNC-BGC-006)
   ---------------------------------------------------------------------------

   --  @summary Send an OSC color query to the terminal and return the raw response.
   --  @description Executes the following steps:
   --    1. Obtain the query byte sequence via Query_Sequence (Kind).
   --    2. Capture an environment snapshot and detect the terminal identity.
   --    3. If the terminal is a multiplexer (tmux or screen), wrap the query
   --       via Termicap.OSC.Parsing.Wrap_For_Passthrough before sending.
   --    4. Open a Probe_Session.  If the session fails to open (not foreground,
   --       /dev/tty unavailable, raw mode error), set Timed_Out to True,
   --       Resp_Length to 0, and return immediately.
   --    5. Call Sentinel_Query with the (possibly wrapped) query and Timeout_Ms.
   --    6. Close the Probe_Session unconditionally via RAII (Finalize).
   --    7. Return the pre-sentinel response bytes in Response, the valid byte
   --       count in Resp_Length, and the timeout flag in Timed_Out.
   --  This procedure does not raise an exception on any code path.
   --  @param Kind        Whether to query Background (OSC 11) or Foreground (OSC 10).
   --  @param Timeout_Ms  Millisecond timeout passed to Sentinel_Query.
   --  @param Response    Buffer receiving the raw pre-sentinel response bytes.
   --  @param Resp_Length Number of valid bytes written into Response.
   --  @param Timed_Out   True if no DA1 response was detected within Timeout_Ms,
   --                     or if the Probe_Session failed to open.
   --  @relation(FUNC-BGC-006): OSC color query execution via Probe_Session
   procedure Query_Color
     (Kind        : BG_Query.Query_Kind;
      Timeout_Ms  : Natural;
      Response    : out BG_Query.Byte_Array;
      Resp_Length : out Natural;
      Timed_Out   : out Boolean)
   with Pre => Response'Length >= BG_Query.MAX_RESPONSE_SIZE;

end Termicap.Color.BG_Query.IO;
