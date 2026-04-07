-------------------------------------------------------------------------------
--  Termicap.DECRPM.IO - DECRPM Private Mode Query I/O
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Sends CSI ? Ps $ p DECRPM queries to the active terminal and returns
--  structured Mode_Report results, for both single-mode and batch queries.
--
--  @description
--  This package provides the I/O boundary for the DECRPM feature:
--  Query_Mode sends a single DECRPM query using the Probe_Session and
--  Sentinel_Query infrastructure; Detect_Mode combines I/O and parsing
--  into a typed Mode_Query_Result; Detect_Modes performs a batch of queries
--  within a single Probe_Session for lower overhead.
--
--  DECRPM queries use standard CSI sequences (CSI ? Ps $ p), which are
--  generally forwarded by multiplexers without wrapping.  Multiplexer
--  passthrough infrastructure is included for defensive completeness,
--  following the Query_XTVERSION pattern.
--
--  All terminal interaction is performed through the existing
--  Termicap.OSC.Probe_Session and Sentinel_Query infrastructure.  No new
--  C wrappers or system calls are introduced by this package.
--
--  This package is SPARK_Mode Off because it calls Ada.Finalization controlled
--  types (Probe_Session) and performs terminal I/O, both of which are outside
--  the SPARK 2014 language subset.  The pure parsing logic remains provable in
--  the parent package Termicap.DECRPM.
--
--  Requirements Coverage:
--    - @relation(FUNC-RPM-004): Query_Error enumeration and Mode_Query_Result record
--    - @relation(FUNC-RPM-008): Query_Mode I/O procedure
--    - @relation(FUNC-RPM-009): Detect_Mode top-level convenience function
--    - @relation(FUNC-RPM-011): Detect_Modes batch convenience function
--    - @relation(FUNC-RPM-011): Batch_Query_Result discriminated record

pragma SPARK_Mode (Off);

with Termicap.OSC;

package Termicap.DECRPM.IO is

   ---------------------------------------------------------------------------
   --  Query Error Enumeration (FUNC-RPM-004)
   ---------------------------------------------------------------------------

   --  @summary Four-value enumeration for DECRPM query failure reasons.
   --  @description Covers the three physical reasons a query cannot produce a
   --  result (no terminal, wrong process group, timeout) plus one semantic
   --  reason (response arrived but could not be interpreted).  Values correspond
   --  to the Probe_Session error vocabulary for consistency across all active
   --  probing features.
   --
   --  Mapping from Probe_Session / Sentinel_Query outcomes:
   --    Session_No_Terminal     => Not_A_Terminal
   --    Session_Not_Foreground  => Not_Foreground
   --    Timed_Out = True        => Query_Timeout
   --    Parse failure (Mode=0)  => Parse_Failed
   --  @relation(FUNC-RPM-004): Query_Error enumeration
   type Query_Error is
     (Not_A_Terminal,   --  No controlling terminal (/dev/tty unavailable)
      Not_Foreground,   --  Process not in terminal foreground process group
      Query_Timeout,    --  No response within Timeout_Ms
      Parse_Failed);    --  Response received but could not be parsed

   ---------------------------------------------------------------------------
   --  Single-Mode Result Type (FUNC-RPM-004)
   ---------------------------------------------------------------------------

   --  @summary Discriminated record carrying the outcome of a single-mode query.
   --  @description When Success is True, Report holds the Mode_Report returned
   --  by the terminal (mode number plus decoded Mode_Status).  When Success is
   --  False, Error holds a Query_Error value explaining the failure.
   --
   --  The default discriminant False ensures that an uninitialised
   --  Mode_Query_Result is always in the failure state, preventing silent use
   --  of invalid data (accessing Report raises Constraint_Error).
   --  Mirrors XTVERSION_Result (FUNC-XTV-001) and the BG-COLOR result pattern.
   --  @relation(FUNC-RPM-004): Mode_Query_Result discriminated record
   type Mode_Query_Result (Success : Boolean := False) is record
      case Success is
         when True  =>
            Report : Mode_Report;
         when False =>
            Error  : Query_Error;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Batch Result Type (FUNC-RPM-011)
   ---------------------------------------------------------------------------

   --  @summary Discriminated record carrying the outcome of a batch mode query.
   --  @description When Success is True, Reports(1 .. Count) holds the
   --  Mode_Report for each queried mode in input order.  Modes that timed out
   --  individually have Status => Not_Recognized rather than causing the entire
   --  batch to fail.  When Success is False (session open failure), Error
   --  identifies the reason.
   --
   --  The default discriminant False ensures uninitialised values are in the
   --  failure state.  Count is the number of valid entries in Reports and
   --  equals the Count parameter passed to Detect_Modes on success.
   --  @relation(FUNC-RPM-011): Batch_Query_Result discriminated record
   type Batch_Query_Result (Success : Boolean := False) is record
      case Success is
         when True  =>
            Reports : Mode_Report_Array;
            Count   : Positive;
         when False =>
            Error   : Query_Error;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Query_Mode I/O Procedure (FUNC-RPM-008)
   ---------------------------------------------------------------------------

   --  @summary Send a single DECRPM query and return the raw response bytes.
   --  @description Executes the following steps in order:
   --    1. Construct the query bytes via DECRPM_Query (FUNC-RPM-005):
   --       CSI ? <Mode> $ p.
   --    2. Capture an environment snapshot and detect terminal identity via
   --       Detect_Terminal_Identity.  Derive the passthrough mode:
   --       Is_Multiplexer = False -> No_Passthrough;
   --       Kind = Tmux -> Tmux_Passthrough;
   --       Kind = Screen -> Screen_Passthrough;
   --       other multiplexer -> Tmux_Passthrough (safe default).
   --    3. Wrap the query via Wrap_For_Passthrough if required.
   --    4. Open a Probe_Session (FUNC-OSC-008).  If the session fails to open
   --       for any reason (Session_No_Terminal, Session_Not_Foreground,
   --       Session_Save_Failed, Session_Raw_Failed, Session_Already_Active),
   --       set Timed_Out := True, Resp_Length := 0, and return.
   --    5. Call Sentinel_Query (FUNC-OSC-006) with the (possibly wrapped) query,
   --       Timeout_Ms, and Retry => False.
   --    6. Allow the Probe_Session to close unconditionally via RAII Finalize.
   --    7. Populate Response with the pre-sentinel response bytes, Resp_Length
   --       with the valid byte count, and Timed_Out with the sentinel-detection
   --       outcome.
   --  This procedure does not raise an exception on any code path.
   --  @param Mode        The DEC private mode number to query.
   --  @param Timeout_Ms  Millisecond timeout for the sentinel query (must be > 0).
   --  @param Response    Buffer receiving the raw DECRPM response bytes.
   --  @param Resp_Length Number of valid bytes written into Response.
   --  @param Timed_Out   True if no DA1 sentinel was detected within Timeout_Ms,
   --                     or if the Probe_Session failed to open.
   --  @relation(FUNC-RPM-008): Query_Mode I/O procedure
   procedure Query_Mode
     (Mode        :     Mode_Id;
      Timeout_Ms  :     Natural;
      Response    : out Termicap.OSC.Response_Buffer;
      Resp_Length : out Natural;
      Timed_Out   : out Boolean)
   with Pre => Timeout_Ms > 0;

   ---------------------------------------------------------------------------
   --  Detect_Mode Convenience Function (FUNC-RPM-009)
   ---------------------------------------------------------------------------

   --  @summary Combine a DECRPM query with response parsing into a single call.
   --  @description Executes the following steps:
   --    1. Call Query_Mode with Mode and Timeout_Ms to obtain Response,
   --       Resp_Length, and Timed_Out.
   --    2. If Timed_Out is True, return
   --       Mode_Query_Result'(Success => False, Error => Query_Timeout).
   --       (Both Not_A_Terminal and Not_Foreground arrive via Timed_Out = True
   --       in v1; an extended API may expose Session_Status in a future revision.)
   --    3. Call Parse_DECRPM_Response (FUNC-RPM-007) on the response buffer.
   --    4. If Parse_DECRPM_Response returns Mode => 0 (parse failure), return
   --       Mode_Query_Result'(Success => False, Error => Parse_Failed).
   --    5. Return Mode_Query_Result'(Success => True, Report => <parsed report>).
   --  This function does not raise an exception on any code path.
   --  @param Mode        The DEC private mode number to query.
   --  @param Timeout_Ms  Millisecond timeout for Query_Mode (default: 100).
   --  @return Mode_Query_Result with Success = True and the parsed Mode_Report on
   --          success; Success = False with a Query_Error on failure.
   --  @relation(FUNC-RPM-009): Detect_Mode top-level convenience function
   function Detect_Mode
     (Mode       : Mode_Id;
      Timeout_Ms : Natural := 100) return Mode_Query_Result;

   ---------------------------------------------------------------------------
   --  Detect_Modes Batch Function (FUNC-RPM-011)
   ---------------------------------------------------------------------------

   --  @summary Query multiple DEC private modes within a single Probe_Session.
   --  @description Executes the following steps:
   --    1. Capture environment and derive passthrough mode (as in Query_Mode).
   --    2. Open a single Probe_Session (FUNC-OSC-008).  If opening fails, return
   --       Batch_Query_Result'(Success => False, Error => Not_A_Terminal).
   --    3. For each index I in 1 .. Count:
   --         a. Construct the DECRPM query for Modes(I) via DECRPM_Query.
   --         b. Call Sentinel_Query with the query and a per-query timeout of
   --            max(50, Timeout_Ms / Count) milliseconds.
   --         c. Call Parse_DECRPM_Response on the response bytes.
   --         d. Accumulate the resulting Mode_Report (Status => Not_Recognized
   --            for individual timeouts).
   --    4. Close the Probe_Session via RAII Finalize.
   --    5. Return Batch_Query_Result'(Success => True,
   --                                   Reports => <accumulated reports>,
   --                                   Count   => Count).
   --  Modes that time out individually within the batch receive
   --  Status => Not_Recognized rather than causing the entire batch to fail.
   --  The default Timeout_Ms of 200 ms allocates approximately 12 ms per mode
   --  for a 16-mode batch, sufficient for local terminals.
   --  This function does not raise an exception on any code path.
   --  @param Modes      Array of DEC private mode numbers to query.
   --  @param Count      Number of valid entries in Modes (1 .. MAX_BATCH_MODES).
   --  @param Timeout_Ms Total millisecond budget for the batch (default: 200).
   --  @return Batch_Query_Result with Success = True and Reports(1..Count) on
   --          success; Success = False with a Query_Error on session open failure.
   --  @relation(FUNC-RPM-011): Detect_Modes batch convenience function
   function Detect_Modes
     (Modes      : Mode_Id_Array;
      Count      : Positive;
      Timeout_Ms : Natural := 200) return Batch_Query_Result
   with Pre => Count <= MAX_BATCH_MODES;

end Termicap.DECRPM.IO;
