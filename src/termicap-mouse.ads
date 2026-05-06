-------------------------------------------------------------------------------
--  Termicap.Mouse - Mouse Protocol Detection Types and Parsers
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and parsing functions for mouse protocol
--  detection (MOUSE, Tier 4 Stretch Goal).
--
--  @description
--  This package provides all the SPARK-provable building blocks for mouse
--  protocol detection: the Mouse_Encoding enumeration for the six encoding
--  values (Unknown / None / X10 / URXVT / SGR / SGR_Pixels), the
--  Mouse_Capabilities aggregate result record with per-mode Boolean flags and
--  derived Best_Encoding, six MODE_MOUSE_* named constants for the DEC private
--  modes probed by the detection algorithm, the DECRPM_Parse_Result record,
--  and two pure functions (Parse_Mouse_DECRPM_Response and
--  Resolve_Best_Encoding) with SPARK Silver-level contracts.
--
--  All functions carry Global => null contracts.  No I/O, no global state,
--  and no exceptions are used in this package.  The I/O boundary, caching,
--  and platform-specific guards are in the child package Termicap.Mouse.IO
--  (SPARK_Mode => Off).
--
--  The Byte subtype and Byte_Array type are declared here independently of
--  Termicap.OSC (which is SPARK_Mode Off) using the same underlying
--  Interfaces.C.unsigned_char type, ensuring representation compatibility at
--  the I/O boundary without introducing a SPARK mode violation.  This
--  mirrors the pattern established by Termicap.Keyboard, Termicap.DECRPM,
--  Termicap.DA1, and Termicap.XTVERSION.
--
--  Requirements Coverage:
--    - @relation(FUNC-MSE-001): Mouse_Encoding enumeration
--    - @relation(FUNC-MSE-002): Mouse_Capabilities result record
--    - @relation(FUNC-MSE-003): MODE_MOUSE_* named constants
--    - @relation(FUNC-MSE-007): DECRPM_Parse_Result / Parse_Mouse_DECRPM_Response
--    - @relation(FUNC-MSE-008): Resolve_Best_Encoding cascade function
--    - @relation(FUNC-MSE-013): MOUSE_PROBE_TIMEOUT_MS / MAX_RESPONSE_SIZE
--    - @relation(FUNC-MSE-017): Package structure and SPARK boundary

with Termicap.DECRPM;

package Termicap.Mouse
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Mouse_Encoding Enumeration (FUNC-MSE-001)
   ---------------------------------------------------------------------------

   --  @summary Detected best mouse encoding available in the controlling terminal.
   --  @description Six values representing the result of mouse protocol detection:
   --    Unknown    -- Detection was not performed or could not be completed
   --                  (stdin not a TTY, foreground guard failed, probe timed out
   --                  entirely, Win32 DECRPM path not applicable).
   --    None       -- Detection was performed successfully but no supported mouse
   --                  encoding was found (all modes returned Not_Recognized).
   --    X10        -- Classic X10 encoding (ESC [ M Cb Cx Cy, three raw bytes,
   --                  range limited to columns/rows 1-222).  Mode 1000 recognised
   --                  but modes 1006 and 1016 were not.
   --    URXVT      -- URXVT decimal encoding (ESC [ Cb ; Cx ; Cy M, unlimited
   --                  range).  Mode 1015 recognised but modes 1006/1016 were not.
   --    SGR        -- SGR encoding (ESC [ < Cb ; Cx ; Cy M/m, decimal, unlimited
   --                  range, distinguishes press/release).  Mode 1006 recognised
   --                  but mode 1016 was not.
   --    SGR_Pixels -- SGR pixel-precision encoding (same format as SGR but Cx/Cy
   --                  are pixel coordinates).  Mode 1016 recognised.
   --  Ordering: Unknown first so that default-initialised variables are Unknown.
   --  None is second to express "probed but nothing found" cleanly.
   --  The four real encodings follow in expressive-power order (weakest to richest).
   --  Best_Encoding is the result of Resolve_Best_Encoding (FUNC-MSE-008).
   --  @relation(FUNC-MSE-001): Mouse encoding enumeration
   type Mouse_Encoding is
     (Unknown,
      --  Detection not performed or not possible (non-TTY, foreground guard
      --  failed, probe timed out entirely, Win32 non-DECRPM path, or error).
      None,
      --  Probed successfully; all queried modes returned Not_Recognized.
      X10,
      --  Mode 1000 recognised; best available encoding.  Range limited to
      --  columns 1-222 due to X10 three-byte coordinate encoding.
      URXVT,
      --  Mode 1015 recognised; unlimited coordinate range via decimal encoding.
      --  Preferred over X10 when both are available (no coordinate ceiling).
      SGR,
      --  Mode 1006 recognised; unlimited range plus press/release distinction
      --  via M/m terminator.  Preferred over URXVT when available.
      SGR_Pixels
      --  Mode 1016 recognised; pixel-precision coordinates.  Most expressive
      --  encoding available; preferred over all others when present.
     );

   ---------------------------------------------------------------------------
   --  Mouse_Capabilities Result Record (FUNC-MSE-002)
   ---------------------------------------------------------------------------

   --  @summary Aggregate result of mouse protocol detection.
   --  @description Combines the derived encoding preference (Best_Encoding), six
   --  per-mode Boolean support flags, two platform-specific flags, and a
   --  metadata flag recording whether an active DECRPM probe was attempted.
   --
   --  Canonical interpretations:
   --    Best_Encoding = Unknown, Probed = False:
   --      Detection was not performed, or failed before any probe was issued
   --      (non-TTY, foreground guard, /dev/tty open failure, Win32 gate, GPM
   --      heuristic, or total timeout with zero responses).
   --    Best_Encoding = None, Probed = True:
   --      DECRPM probe was issued and completed; all six modes returned
   --      Not_Recognized.  Terminal does not support mouse protocols.
   --    Best_Encoding in X10 | URXVT | SGR | SGR_Pixels, Probed = True:
   --      At least one encoding mode was recognised; Best_Encoding is the
   --      result of the Resolve_Best_Encoding cascade (FUNC-MSE-008).
   --    Win32_Console_Mouse = True:
   --      Windows Console API mouse is available (STD_INPUT_HANDLE is a Console
   --      handle).  Mutually exclusive with Probed = True.
   --    GPM_Available = True:
   --      Linux/GPM daemon detected (TERM=linux and /dev/gpmctl exists).
   --      Mutually exclusive with Probed = True.
   --
   --  The four implicit invariants I1-I4 (tech spec §F.2) are enforced by
   --  construction in body-private helpers (Make_Win32_Result, Make_GPM_Result,
   --  Make_Probed_Result) rather than by Type_Invariant aspect, to avoid SPARK
   --  proof complexity at the SPARK On / SPARK Off boundary (see §F.3).
   --  @relation(FUNC-MSE-002): Mouse capabilities result record
   type Mouse_Capabilities is record

      --  Encoding preference (derived, FUNC-MSE-008)
      Best_Encoding : Mouse_Encoding := Unknown;
      --     The highest-preference encoding available, per the FUNC-MSE-008 cascade.
      --     Unknown when detection was not performed or Probed = False.

      --  Per-mode support flags (FUNC-MSE-006)
      Supports_X10          : Boolean := False;
      --     True when DECRPM mode 1000 (X10/X11 button tracking) was recognised
      --     (Mode_Status /= Not_Recognized, i.e., Pm in 1..4).
      Supports_Button_Event : Boolean := False;
      --     True when DECRPM mode 1002 (button-event / drag tracking) was recognised.
      Supports_Any_Event    : Boolean := False;
      --     True when DECRPM mode 1003 (any-motion tracking) was recognised.
      Supports_URXVT        : Boolean := False;
      --     True when DECRPM mode 1015 (URXVT decimal encoding) was recognised.
      Supports_SGR          : Boolean := False;
      --     True when DECRPM mode 1006 (SGR decimal encoding) was recognised.
      Supports_SGR_Pixels   : Boolean := False;
      --     True when DECRPM mode 1016 (SGR pixel-precision encoding) was recognised.

      --  Platform-specific flags (FUNC-MSE-010, FUNC-MSE-011)
      Win32_Console_Mouse : Boolean := False;
      --     True when the Win32 platform gate fired (GetConsoleMode succeeded on
      --     STD_INPUT_HANDLE).  When True, all Supports_* = False and Probed = False.
      GPM_Available       : Boolean := False;
      --     True when the Linux/GPM heuristic fired (TERM=linux and /dev/gpmctl
      --     exists).  When True, all Supports_* = False and Probed = False.

      --  Probe metadata
      Probed : Boolean := False;
      --     True when an active DECRPM probe sequence was attempted (stdin was a
      --     TTY, foreground guard passed, probe session was opened and the batch
      --     of six DECRPM queries was sent).  False when the result was determined
      --     without probing (Win32 gate, GPM heuristic, non-TTY, foreground guard,
      --     or /dev/tty not openable).
   end record;

   ---------------------------------------------------------------------------
   --  Canonical "No Result" Constant (FUNC-MSE-002)
   ---------------------------------------------------------------------------

   --  @summary Canonical initial / "no result" Mouse_Capabilities value.
   --  @description Represents the state before probing has been performed, or
   --  when probing could not be completed.  Used as the cache initial value
   --  and as the fallback on every error path of Detect_Mouse_Protocols.
   --  A Mouse_Capabilities declared without an explicit aggregate is equivalent
   --  to this value via default initialisation.
   --  @relation(FUNC-MSE-002): Canonical unknown / unprobed value
   NO_MOUSE_CAPABILITIES : constant Mouse_Capabilities :=
     (Best_Encoding         => Unknown,
      Supports_X10          => False,
      Supports_Button_Event => False,
      Supports_Any_Event    => False,
      Supports_URXVT        => False,
      Supports_SGR          => False,
      Supports_SGR_Pixels   => False,
      Win32_Console_Mouse   => False,
      GPM_Available         => False,
      Probed                => False);

   ---------------------------------------------------------------------------
   --  DEC Private Mode Constants (FUNC-MSE-003)
   ---------------------------------------------------------------------------

   --  @summary DEC private mode number for X10 / X11 button tracking.
   --  @description CSI ? 1000 $ p — probes press and release events only.
   --  Mode_Id is a subtype of Natural (Termicap.DECRPM.Mode_Id).
   --  @relation(FUNC-MSE-003): MODE_MOUSE_X10 constant
   MODE_MOUSE_X10 : constant Termicap.DECRPM.Mode_Id := 1000;

   --  @summary DEC private mode number for button-event (drag) tracking.
   --  @description CSI ? 1002 $ p — probes press, release, and drag motion.
   --  @relation(FUNC-MSE-003): MODE_MOUSE_BUTTON_EVENT constant
   MODE_MOUSE_BUTTON_EVENT : constant Termicap.DECRPM.Mode_Id := 1002;

   --  @summary DEC private mode number for any-motion tracking.
   --  @description CSI ? 1003 $ p — probes all motion events, regardless of
   --  button state.
   --  @relation(FUNC-MSE-003): MODE_MOUSE_ANY_EVENT constant
   MODE_MOUSE_ANY_EVENT : constant Termicap.DECRPM.Mode_Id := 1003;

   --  @summary DEC private mode number for URXVT decimal mouse encoding.
   --  @description CSI ? 1015 $ p — probes unlimited coordinate range via
   --  decimal encoding.  Still found in urxvt-derived terminals and foot.
   --  @relation(FUNC-MSE-003): MODE_MOUSE_URXVT constant
   MODE_MOUSE_URXVT : constant Termicap.DECRPM.Mode_Id := 1015;

   --  @summary DEC private mode number for SGR decimal mouse encoding.
   --  @description CSI ? 1006 $ p — probes unlimited coordinate range with
   --  press/release distinction via M/m terminator.
   --  @relation(FUNC-MSE-003): MODE_MOUSE_SGR constant
   MODE_MOUSE_SGR : constant Termicap.DECRPM.Mode_Id := 1006;

   --  @summary DEC private mode number for SGR pixel-precision mouse encoding.
   --  @description CSI ? 1016 $ p — same wire format as SGR (mode 1006) but
   --  Cx/Cy are pixel coordinates rather than character-cell coordinates.
   --  @relation(FUNC-MSE-003): MODE_MOUSE_SGR_PIXELS constant
   MODE_MOUSE_SGR_PIXELS : constant Termicap.DECRPM.Mode_Id := 1016;

   ---------------------------------------------------------------------------
   --  Probe Timeout Constant (FUNC-MSE-013)
   ---------------------------------------------------------------------------

   --  @summary Millisecond timeout for the entire batched mouse DECRPM probe session.
   --  @description Applied to the full six-query batch (one DA1 sentinel for
   --  all six queries).  1000 ms matches FUNC-MSE-013 and is consistent with
   --  KITTY_PROBE_TIMEOUT_MS (FUNC-KKB-013) and the OSC-INFRA default
   --  (FUNC-OSC-004).  Implementations may use a shorter timeout (minimum 100 ms)
   --  on local PTYs where round-trip latency is negligible.
   --  @relation(FUNC-MSE-013): Probe session timeout
   MOUSE_PROBE_TIMEOUT_MS : constant Natural := 1_000;

   ---------------------------------------------------------------------------
   --  DECRPM Parse Result Record (FUNC-MSE-007)
   ---------------------------------------------------------------------------

   --  @summary Result record returned by Parse_Mouse_DECRPM_Response.
   --  @description Three-field aggregate encoding whether a DECRPM response
   --  was found, the decoded mode number, and the decoded status code:
   --    Valid = True:  Buffer matched the DECRPM response pattern CSI ? Ps ; Pm $ y.
   --                   Mode holds the decoded mode number; Status holds the
   --                   decoded Mode_Status.
   --    Valid = False: Buffer did not match (garbled, partial, or unrecognised).
   --                   Mode = 0 (guaranteed by Parse_Mouse_DECRPM_Response Post).
   --                   Status = Not_Recognized.
   --  @relation(FUNC-MSE-007): DECRPM parse result record
   type DECRPM_Parse_Result is record
      Valid  : Boolean := False;
      Mode   : Termicap.DECRPM.Mode_Id := 0;
      Status : Termicap.DECRPM.Mode_Status := Termicap.DECRPM.Not_Recognized;
   end record;

   ---------------------------------------------------------------------------
   --  DECRPM Mouse Response Parser (FUNC-MSE-007)
   ---------------------------------------------------------------------------

   --  @summary Parse a single DECRPM response frame from a raw byte buffer.
   --  @description Returns a DECRPM_Parse_Result with Valid = True when
   --  Buffer (Buffer'First .. Buffer'First + Length - 1) matches:
   --
   --    ESC (0x1B) '[' (0x5B) '?' (0x3F) <mode_digits>+ ';' (0x3B)
   --    <status_digit> '$' (0x24) 'y' (0x79)
   --
   --  where <mode_digits>+ is one or more ASCII decimal digits encoding the
   --  DEC private mode number Ps, and <status_digit> is a single ASCII decimal
   --  digit in the range '0'..'4' encoding the response status Pm.
   --
   --  On success:
   --    Valid  = True
   --    Mode   = decoded Ps (> 0 for any recognised DEC private mode)
   --    Status = decoded Mode_Status from Pm (Not_Recognized for Pm = 0,
   --             Set for 1, Reset for 2, Permanently_Set for 3,
   --             Permanently_Reset for 4)
   --
   --  On failure (no match, partial frame, garbled bytes, Pm outside 0..4,
   --  missing ';', missing '$', or missing 'y'):
   --    Valid  = False
   --    Mode   = 0   (guaranteed by postcondition)
   --    Status = Not_Recognized
   --
   --  The function never raises for any buffer content; stray or out-of-range
   --  bytes are treated as non-matching and return Valid = False.
   --
   --  Note: this parser recognises exactly ONE frame beginning at Buffer'First.
   --  The multi-frame scanner in Termicap.Mouse.IO scans across the full
   --  response buffer calling this function at successive positions.
   --
   --  @param Buffer  The raw response byte buffer.
   --  @param Length  Number of valid bytes in Buffer to examine (0..MAX_RESPONSE_SIZE).
   --  @return DECRPM_Parse_Result with Valid/Mode/Status set per above.
   --  @relation(FUNC-MSE-007): DECRPM response parser (SPARK Silver)
   function Parse_Mouse_DECRPM_Response (Buffer : Byte_Array; Length : Natural) return DECRPM_Parse_Result
   with
     SPARK_Mode => On,
     Global => null,
     Pre => Length <= Buffer'Length and then Length <= MAX_RESPONSE_SIZE,
     Post => (if not Parse_Mouse_DECRPM_Response'Result.Valid then Parse_Mouse_DECRPM_Response'Result.Mode = 0);

   ---------------------------------------------------------------------------
   --  Best-Encoding Cascade Function (FUNC-MSE-008)
   ---------------------------------------------------------------------------

   --  @summary Derive the best available mouse encoding from a Mouse_Capabilities record.
   --  @description Evaluates the per-mode Supports_* flags in Caps using the
   --  preference cascade (SGR_Pixels > SGR > URXVT > X10 > None):
   --
   --    Step 1: if Caps.Supports_SGR_Pixels => return SGR_Pixels
   --    Step 2: elsif Caps.Supports_SGR     => return SGR
   --    Step 3: elsif Caps.Supports_URXVT   => return URXVT
   --    Step 4: elsif Caps.Supports_X10     => return X10
   --    Step 5: else                         => return None
   --
   --  The cascade is evaluated only when Caps.Probed = True; if Probed = False
   --  the function returns Unknown regardless of any Supports_* flags, as
   --  guaranteed by the postcondition.
   --
   --  The cascade is a pure SPARK function with no I/O and no global state.
   --  Tracking-mode flags (Supports_Button_Event, Supports_Any_Event) are
   --  intentionally ignored in the encoding decision: encoding scheme is
   --  orthogonal to tracking mode.  Callers that need drag-support information
   --  should inspect Supports_Button_Event independently.
   --
   --  ADR-0023 documents the rationale for the cascade order; the URXVT/X10
   --  placement (URXVT above X10) reflects unlimited-coordinate superiority
   --  over X10's 222-cell coordinate ceiling.
   --
   --  @param Caps  The Mouse_Capabilities record to evaluate.
   --  @return Mouse_Encoding denoting the best available encoding, or Unknown
   --          when Probed = False, or None when all Supports_* are False.
   --  @relation(FUNC-MSE-008): Best-encoding cascade (SPARK Silver)
   function Resolve_Best_Encoding (Caps : Mouse_Capabilities) return Mouse_Encoding
   with
     SPARK_Mode => On,
     Global => null,
     Pre => True,
     Post =>
       (if not Caps.Probed then Resolve_Best_Encoding'Result = Unknown)
       and then (if Caps.Probed and then Caps.Supports_SGR_Pixels then Resolve_Best_Encoding'Result = SGR_Pixels)
       and then (if Caps.Probed and then not Caps.Supports_SGR_Pixels and then Caps.Supports_SGR
                 then Resolve_Best_Encoding'Result = SGR);
   --  Postcondition is partial (tech spec §F.5); remaining cascade levels are
   --  validated by unit tests rather than proved.  A full case-analysis
   --  postcondition is deferred to a future SPARK Gold-level pass.

end Termicap.Mouse;
