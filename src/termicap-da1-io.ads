-------------------------------------------------------------------------------
--  Termicap.DA1.IO - DA1 Primary Device Attributes Query I/O
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Sends a CSI c DA1 query to the active terminal and returns the interpreted
--  DA1 capability results, with optional multiplexer passthrough wrapping.
--
--  @description
--  This package provides the Query_DA1 I/O boundary procedure and the
--  Detect_DA1 convenience function, which together form the I/O layer of
--  the DA1 feature.  Query_DA1 opens a Probe_Session, optionally wraps
--  DA1_QUERY for multiplexer passthrough (tmux, screen), writes the query
--  to the terminal, and accumulates bytes until a complete DA1 response is
--  detected (via Contains_DA1_Response) or the timeout expires.
--
--  Unlike other Termicap active probes (XTVERSION, background colour),
--  Query_DA1 cannot use the Sentinel_Query pattern because the DA1 response
--  IS the data being sought.  Appending a second CSI c sentinel would produce
--  two overlapping DA1 responses in the accumulation buffer, making boundary
--  detection ambiguous.  Query_DA1 therefore uses a timeout-only termination
--  approach consistent with how tcell and notcurses handle direct DA1 queries.
--
--  All terminal interaction is performed through the existing
--  Termicap.OSC.Probe_Session, Write_Query, and Timed_Read infrastructure.
--  No new C wrappers or system calls are introduced by this package.
--
--  This package is SPARK_Mode Off because it calls Ada.Finalization controlled
--  types (Probe_Session) and performs terminal I/O, both of which are outside
--  the SPARK 2014 language subset.  The pure interpretation logic remains
--  provable in the parent package Termicap.DA1.
--
--  Requirements Coverage:
--    - @relation(FUNC-DA1-008): Query_DA1 I/O procedure
--    - @relation(FUNC-DA1-009): Detect_DA1 top-level convenience function
--    - @relation(FUNC-DA1-010): Foreground process group guard via Probe_Session.Open
--    - @relation(FUNC-DA1-011): Not-a-TTY guard via Probe_Session.Open
--    - @relation(FUNC-DA1-012): Multiplexer passthrough via Wrap_For_Passthrough

pragma SPARK_Mode (Off);

with Termicap.OSC;

package Termicap.DA1.IO is

   ---------------------------------------------------------------------------
   --  DA1 Query I/O (FUNC-DA1-008)
   ---------------------------------------------------------------------------

   --  @summary Send a CSI c query to the terminal and return the raw response bytes.
   --  @description Executes the following steps in order:
   --    1. Capture an environment snapshot and detect the terminal identity via
   --       Detect_Terminal_Identity.  Derive the multiplexer passthrough mode:
   --       Kind = Tmux -> Tmux_Passthrough; Kind = Screen -> Screen_Passthrough;
   --       any other multiplexer -> Tmux_Passthrough (safe default);
   --       Is_Multiplexer = False -> No_Passthrough.
   --    2. Wrap DA1_QUERY (FUNC-DA1-007) using Wrap_For_Passthrough if required.
   --    3. Open a Probe_Session (FUNC-OSC-008).  If the session fails to open
   --       for any reason (Session_Not_Foreground, Session_No_Terminal,
   --       Session_Save_Failed, Session_Raw_Failed, Session_Already_Active),
   --       set Timed_Out := True, Resp_Length := 0, and return immediately.
   --    4. Write the (possibly wrapped) DA1_QUERY bytes to the terminal via
   --       Write_Query.  If Write_Query fails, set Timed_Out := True,
   --       Resp_Length := 0, and return.
   --    5. Enter a timeout-only read loop: call Timed_Read, accumulating bytes
   --       into Response.  After each batch, call Contains_DA1_Response on the
   --       accumulated bytes.  Exit when Contains_DA1_Response returns True or
   --       when the elapsed time exceeds Timeout_Ms.
   --    6. If Contains_DA1_Response returned True, set Resp_Length to the
   --       accumulated byte count and Timed_Out := False.
   --    7. If the loop exited due to timeout, set Timed_Out := True,
   --       Resp_Length := 0.
   --    8. Allow the Probe_Session to close unconditionally via RAII Finalize.
   --  This procedure does not raise an exception on any code path.
   --  @param Timeout_Ms  Millisecond timeout for the response accumulation loop.
   --  @param Response    Buffer receiving the raw DA1 response bytes.
   --  @param Resp_Length Number of valid bytes written into Response.
   --  @param Timed_Out   True if no complete DA1 response was detected within
   --                     Timeout_Ms, or if the Probe_Session failed to open.
   --  @relation(FUNC-DA1-008): DA1 I/O procedure with timeout-only read loop
   --  @relation(FUNC-DA1-010): Foreground guard via Probe_Session.Open
   --  @relation(FUNC-DA1-011): Not-a-TTY guard via Probe_Session.Open
   --  @relation(FUNC-DA1-012): Multiplexer passthrough selection
   procedure Query_DA1
     (Timeout_Ms  : Natural;
      Response    : out Termicap.OSC.Response_Buffer;
      Resp_Length : out Natural;
      Timed_Out   : out Boolean)
   with Pre => Response'Length >= MAX_RESPONSE_SIZE;

   ---------------------------------------------------------------------------
   --  Top-Level Convenience Function (FUNC-DA1-009)
   ---------------------------------------------------------------------------

   --  @summary Combine DA1 I/O, parsing, and interpretation into a single call.
   --  @description Executes the following steps:
   --    1. Call Query_DA1 with Timeout_Ms to obtain raw response bytes.
   --    2. If Timed_Out is True, return a default DA1_Capabilities record
   --       (Supported => False, Level => Unknown, Flags => [others => False]).
   --    3. Call Parse_DA1_Response (FUNC-OSC-010) on the response buffer.
   --    4. Call Interpret_DA1 (FUNC-DA1-004) on the parsed DA1_Params.
   --    5. Return the resulting DA1_Capabilities record.
   --  The default timeout of 100 ms is consistent with Query_And_Identify
   --  (FUNC-XTV-013) and is appropriate for local terminal sessions.  Callers
   --  requiring lower latency may pass a smaller value; callers operating over
   --  high-latency links (SSH, serial) may pass a larger value.
   --  This function does not raise an exception on any code path.
   --  @param Timeout_Ms  Millisecond timeout for the DA1 query (default: 100).
   --  @return A DA1_Capabilities record; Supported = False when no response
   --          was received within the timeout or the session could not be opened.
   --  @relation(FUNC-DA1-009): Detect_DA1 convenience function
   function Detect_DA1 (Timeout_Ms : Natural := 100) return DA1_Capabilities;

end Termicap.DA1.IO;
