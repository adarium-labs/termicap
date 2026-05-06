-------------------------------------------------------------------------------
--  Termicap.XTVERSION.IO - XTVERSION Query I/O Procedure
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Sends a CSI > q XTVERSION query to the terminal and returns the raw
--  DCS response bytes, with optional multiplexer passthrough wrapping.
--
--  @description
--  This package provides the Query_XTVERSION procedure and the
--  Query_And_Identify convenience function, which together form the I/O
--  boundary of the XTVERSION feature.  Query_XTVERSION opens a
--  Probe_Session, optionally wraps the CSI > q query for multiplexer
--  passthrough (tmux, screen), sends the query via Sentinel_Query with a
--  DA1 boundary sentinel, and returns the accumulated pre-sentinel response
--  bytes to the caller.  Query_And_Identify combines this I/O step with
--  Parse_XTVERSION_Response to deliver a fully structured XTVERSION_Result.
--
--  All terminal interaction is performed through the existing
--  Termicap.OSC.Probe_Session and Sentinel_Query infrastructure.  No new
--  C wrappers or system calls are introduced by this package.
--
--  This package is SPARK_Mode Off because it calls Ada.Finalization
--  controlled types (Probe_Session) and performs terminal I/O, both of
--  which are outside the SPARK 2014 language subset.  The pure parsing
--  logic remains provable in the parent package Termicap.XTVERSION.
--
--  Requirements Coverage:
--    - @relation(FUNC-XTV-008): Query_XTVERSION procedure
--    - @relation(FUNC-XTV-009): Sentinel-bounded query with DA1 marker and Retry => False
--    - @relation(FUNC-XTV-010): Foreground process group guard via Probe_Session.Open
--    - @relation(FUNC-XTV-011): Not-a-TTY guard via Probe_Session.Open
--    - @relation(FUNC-XTV-012): Multiplexer passthrough via Wrap_For_Passthrough
--    - @relation(FUNC-XTV-013): Query_And_Identify convenience function

pragma SPARK_Mode (Off);

package Termicap.XTVERSION.IO is

   ---------------------------------------------------------------------------
   --  XTVERSION Query I/O (FUNC-XTV-008)
   ---------------------------------------------------------------------------

   --  @summary Send a CSI > q query to the terminal and return the raw DCS response.
   --  @description Executes the following steps in order:
   --    1. Use CSI_XTVERSION_QUERY (ESC [ > q) as the query byte sequence.
   --    2. Capture an environment snapshot and detect the terminal identity via
   --       Detect_Terminal_Identity (FUNC-TID-003).
   --    3. If the terminal is a multiplexer (Is_Multiplexer = True), wrap the
   --       query via Termicap.OSC.Parsing.Wrap_For_Passthrough (FUNC-OSC-014):
   --       Kind = Tmux -> Tmux_Passthrough; Kind = Screen -> Screen_Passthrough;
   --       other multiplexers -> Tmux_Passthrough (safe default).
   --    4. Open a Probe_Session (FUNC-OSC-008).  If the session fails to open
   --       for any reason (not foreground, /dev/tty unavailable, raw mode error),
   --       set Timed_Out := True, Resp_Length := 0, and return immediately.
   --    5. Call Sentinel_Query (FUNC-OSC-006) with the (possibly wrapped) query,
   --       Timeout_Ms, and Retry => False (no automatic retry, FUNC-XTV-009).
   --    6. Allow the Probe_Session to close unconditionally via RAII (Finalize).
   --    7. Populate Response with the pre-sentinel response bytes, Resp_Length
   --       with the valid byte count, and Timed_Out with the sentinel-detection
   --       outcome.
   --  This procedure does not raise an exception on any code path.
   --  @param Timeout_Ms  Millisecond timeout passed to Sentinel_Query.
   --  @param Response    Buffer receiving the raw pre-sentinel response bytes.
   --  @param Resp_Length Number of valid bytes written into Response.
   --  @param Timed_Out   True if no DA1 response was detected within Timeout_Ms,
   --                     or if the Probe_Session failed to open.
   --  @relation(FUNC-XTV-008): XTVERSION I/O procedure
   --  @relation(FUNC-XTV-009): Sentinel-bounded query, Retry => False
   --  @relation(FUNC-XTV-010): Foreground guard via Probe_Session.Open
   --  @relation(FUNC-XTV-011): Not-a-TTY guard via Probe_Session.Open
   --  @relation(FUNC-XTV-012): Multiplexer passthrough selection
   procedure Query_XTVERSION
     (Timeout_Ms : Natural; Response : out Byte_Array; Resp_Length : out Natural; Timed_Out : out Boolean)
   with Pre => Response'Length >= MAX_RESPONSE_SIZE;

   ---------------------------------------------------------------------------
   --  Top-Level Convenience Function (FUNC-XTV-013)
   ---------------------------------------------------------------------------

   --  @summary Combine XTVERSION I/O and parsing into a single call.
   --  @description Executes the following steps:
   --    1. Call Query_XTVERSION with Timeout_Ms to obtain raw response bytes.
   --    2. If Timed_Out is True, return XTVERSION_Result (Status => Timeout).
   --    3. Call Parse_XTVERSION_Response on the response buffer.
   --    4. Return the Parse_XTVERSION_Response result directly (Success or Parse_Error).
   --  The default timeout of 100 ms balances responsiveness with adequate time
   --  for slow or multiplexed terminals to deliver the DCS response.  Callers
   --  requiring lower latency may pass a smaller value; callers with relaxed
   --  timing may pass a larger one.
   --  @param Timeout_Ms Millisecond timeout for Query_XTVERSION (default: 100).
   --  @return XTVERSION_Result with Status = Success, Timeout, or Parse_Error.
   --  @relation(FUNC-XTV-013): Query_And_Identify convenience function
   --  @relation(FUNC-XTV-015): Timed_Out => True maps to Status = Timeout
   function Query_And_Identify (Timeout_Ms : Natural := 100) return XTVERSION_Result;

end Termicap.XTVERSION.IO;
