-------------------------------------------------------------------------------
--  Termicap.Clipboard - OSC 52 Clipboard Detection Types and Parser
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and parsing functions for OSC 52 clipboard
--  capability detection (OSC52, Tier 4 Stretch Goal).
--
--  @description
--  This package provides all the SPARK-provable building blocks for clipboard
--  capability detection via the OSC 52 escape sequence protocol:
--
--    - The Clipboard_Support enumeration (None / Write_Only / Read_Write) with
--      an ordered representation supporting >= comparisons (FUNC-C52-001).
--
--    - The Clipboard_Capabilities aggregate result record with the support level,
--      three provenance flags (Via_DA1, Via_Active_Probe, Via_Env_Heuristic), and
--      a Probed metadata flag (FUNC-C52-002).
--
--    - Named string constants centralising terminal identifier values used in
--      passive env-var heuristics (TERM_PROGRAM, WT_SESSION, TERM) and environment
--      variable names for multiplexer detection (TMUX, STY) (FUNC-C52-005).
--
--    - The OSC52_QUERY byte constant encoding the 9-byte OSC 52 read query
--      ESC ] 52 ; c ; ? BEL (FUNC-C52-007).
--
--    - The OSC52_Parse_Result enumeration (Not_Present / Valid_Response / Malformed)
--      and the Parse_OSC52_Response function with SPARK Silver-level contracts
--      (FUNC-C52-008).
--
--    - The NO_CLIPBOARD_CAPABILITIES constant as the canonical "unprobed" value.
--
--  All functions carry Global => null contracts.  No I/O, no global state,
--  and no exceptions are used in this package.  The I/O boundary, caching, and
--  platform-specific guards are in the child package Termicap.Clipboard.IO
--  (SPARK_Mode => Off).
--
--  The Byte subtype and Byte_Array type are declared here independently of
--  Termicap.OSC (which is SPARK_Mode Off) using the same underlying
--  Interfaces.C.unsigned_char type, ensuring representation compatibility at
--  the I/O boundary without introducing a SPARK mode violation.  This mirrors
--  the pattern established by Termicap.Mouse, Termicap.Keyboard, Termicap.DA1,
--  and Termicap.Graphics.
--
--  Detection cascade summary (implemented in Termicap.Clipboard.IO):
--    Phase 1: DA1 passive probe (Ps=52 -> Write_Only, Via_DA1=True).
--    Phase 2: Active OSC 52 read-back probe (Valid_Response -> Read_Write,
--             Via_Active_Probe=True).
--    Phase 3: Env-var heuristics (TERM_PROGRAM, WT_SESSION, TERM).
--
--  Requirements Coverage:
--    - @relation(FUNC-C52-001): Clipboard_Support enumeration
--    - @relation(FUNC-C52-002): Clipboard_Capabilities result record
--    - @relation(FUNC-C52-005): Named constants for known terminal identifiers
--    - @relation(FUNC-C52-007): OSC52_QUERY byte constant
--    - @relation(FUNC-C52-008): OSC52_Parse_Result / Parse_OSC52_Response
--    - @relation(FUNC-C52-015): CLIPBOARD_PROBE_TIMEOUT_MS constant
--    - @relation(FUNC-C52-018): Package structure and SPARK boundary

package Termicap.Clipboard
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Clipboard_Support Enumeration (FUNC-C52-001)
   ---------------------------------------------------------------------------

   --  @summary Three-level enumeration for clipboard access support via OSC 52.
   --  @description
   --    None       -- No clipboard access detected.  Either the terminal does not
   --                  support OSC 52, or detection was not performed (non-TTY,
   --                  no DA1 Ps=52, no active probe response, no heuristic match).
   --    Write_Only -- Terminal accepts OSC 52 write sequences (ESC ] 52 ; c ; <base64> BEL)
   --                  but does not respond to read queries (ESC ] 52 ; c ; ? BEL).
   --                  Established by DA1 Ps=52 without an active probe upgrade, or by
   --                  env-var heuristics for write-capable-only terminals.
   --    Read_Write -- Terminal supports both writing and reading via OSC 52.  Reading
   --                  was confirmed by the active probe returning a valid OSC 52 response.
   --
   --  Ordering: None < Write_Only < Read_Write (increasing capability level).
   --  Callers may compare: if Support >= Write_Only then emit OSC 52 writes.
   --  Position values: None = 0, Write_Only = 1, Read_Write = 2.
   --  @relation(FUNC-C52-001): Clipboard support level enumeration
   type Clipboard_Support is (None, Write_Only, Read_Write);

   ---------------------------------------------------------------------------
   --  Clipboard_Capabilities Result Record (FUNC-C52-002)
   ---------------------------------------------------------------------------

   --  @summary Aggregate result of OSC 52 clipboard capability detection.
   --  @description Combines the detected clipboard access level, three detection
   --  provenance flags, and a probe metadata flag.
   --
   --  Canonical interpretations:
   --    Support = None, Probed = False:
   --      Detection was not performed, or all guards suppressed probing (non-TTY,
   --      foreground guard failed, /dev/tty open failure, Win32 Console gate).
   --      No heuristic matched either.
   --    Support >= Write_Only, Via_DA1 = True, Probed = True:
   --      DA1 Ps=52 was present; clipboard write capability confirmed.
   --    Support = Read_Write, Via_Active_Probe = True, Probed = True:
   --      Active OSC 52 probe returned a valid response; full read-write confirmed.
   --    Support /= None, Via_Env_Heuristic = True, Probed = False:
   --      Passive env-var heuristic matched; no active probe was performed.
   --
   --  Implicit invariants (enforced by construction in Termicap.Clipboard.IO,
   --  not by Type_Invariant):
   --    I1. Via_DA1 = True implies Support >= Write_Only and Probed = True.
   --    I2. Via_Active_Probe = True implies Support = Read_Write and Probed = True.
   --    I3. Via_Env_Heuristic = True implies Via_DA1 = False and
   --        Via_Active_Probe = False (env-var heuristics are the sole source).
   --    I4. Probed = False implies Via_DA1 = False and Via_Active_Probe = False.
   --  @relation(FUNC-C52-002): Clipboard capabilities result record
   type Clipboard_Capabilities is record

      --  The detected clipboard access level (FUNC-C52-001). Default: None.
      Support : Clipboard_Support := None;

      --  True when Support was set based on DA1 Ps=52 (FUNC-C52-006).
      --  False when Support was determined by active probe or env-var heuristic only.
      Via_DA1 : Boolean := False;

      --  True when Support was upgraded to Read_Write by the active OSC 52 probe.
      --  (FUNC-C52-007): Active probe confirmed read-back capability.
      Via_Active_Probe : Boolean := False;

      --  True when Support was set by env-var heuristics alone (FUNC-C52-009).
      --  Via_DA1 and Via_Active_Probe are both False when this is True.
      Via_Env_Heuristic : Boolean := False;

      --  True when at least one active probe (DA1 or OSC 52) was attempted.
      --  False when the result was determined entirely by passive env-var heuristics
      --  (non-TTY, foreground guard failed, /dev/tty unopenable, or Win32 gate).
      Probed : Boolean := False;

   end record;

   ---------------------------------------------------------------------------
   --  Canonical "No Result" Constant (FUNC-C52-002)
   ---------------------------------------------------------------------------

   --  @summary Canonical initial / "no result" Clipboard_Capabilities value.
   --  @description Represents the state before probing has been performed, or
   --  when probing could not be completed.  Used as the cache initial value and
   --  as the fallback on every error path of Detect_Clipboard.
   --  A Clipboard_Capabilities declared without an explicit aggregate is equivalent
   --  to this value via default initialisation.
   --  @relation(FUNC-C52-002): Canonical safe-default "no result" value
   NO_CLIPBOARD_CAPABILITIES : constant Clipboard_Capabilities :=
     (Support => None, Via_DA1 => False, Via_Active_Probe => False, Via_Env_Heuristic => False, Probed => False);

   ---------------------------------------------------------------------------
   --  Named Terminal Identifier Constants (FUNC-C52-005)
   ---------------------------------------------------------------------------

   --  TERM_PROGRAM values for terminals with known OSC 52 support (FUNC-C52-005)

   --  @summary TERM_PROGRAM value for WezTerm.
   --  @description Case-insensitive match for TERM_PROGRAM=WezTerm.  WezTerm supports
   --  full OSC 52 read and write (confirmed by DA1 Ps=52 in its capabilities advertisement).
   --  Heuristic inference: Read_Write (FUNC-C52-009 step 1).
   --  Note: intentionally duplicated from Termicap.Graphics to avoid a cross-package
   --  dependency between peer Tier 4 features.
   --  @relation(FUNC-C52-005): TERM_PROGRAM constant for WezTerm
   TERM_PROGRAM_WEZTERM : constant String := "WezTerm";

   --  @summary TERM_PROGRAM value for iTerm2.
   --  @description Case-insensitive match for TERM_PROGRAM=iTerm.app.  iTerm2 supports
   --  OSC 52 read and write via its clipboard integration.
   --  Heuristic inference: Read_Write (FUNC-C52-009 step 1).
   --  @relation(FUNC-C52-005): TERM_PROGRAM constant for iTerm2
   TERM_PROGRAM_ITERM2 : constant String := "iTerm.app";

   --  @summary TERM_PROGRAM value for Visual Studio Code integrated terminal.
   --  @description Case-insensitive match for TERM_PROGRAM=vscode.  VS Code's integrated
   --  terminal accepts OSC 52 writes but does not respond to read queries.
   --  Heuristic inference: Write_Only (FUNC-C52-009 step 2).
   --  @relation(FUNC-C52-005): TERM_PROGRAM constant for VS Code
   TERM_PROGRAM_VSCODE : constant String := "vscode";

   --  Environment variable names used in passive detection (FUNC-C52-005)

   --  @summary Name of the WT_SESSION environment variable.
   --  @description Windows Terminal sets this variable for every hosted terminal.
   --  Presence of a non-empty WT_SESSION indicates Windows Terminal, which
   --  supports OSC 52 write but not read-back.
   --  Heuristic inference: Write_Only (FUNC-C52-009 step 3).
   --  @relation(FUNC-C52-005): ENV_WT_SESSION constant for Windows Terminal detection
   ENV_WT_SESSION : constant String := "WT_SESSION";

   --  @summary Name of the TMUX environment variable.
   --  @description tmux sets this variable when running inside a tmux session.
   --  Used in Run_OSC52_Probe to derive the multiplexer passthrough mode
   --  (FUNC-C52-011).  Not used as a clipboard heuristic.
   --  @relation(FUNC-C52-005): ENV_TMUX constant for tmux passthrough detection
   ENV_TMUX : constant String := "TMUX";

   --  @summary Name of the STY environment variable.
   --  @description GNU screen sets this variable when running inside a screen session.
   --  Used in Run_OSC52_Probe to derive the multiplexer passthrough mode
   --  (FUNC-C52-011).  Not used as a clipboard heuristic.
   --  @relation(FUNC-C52-005): ENV_STY constant for screen passthrough detection
   ENV_STY : constant String := "STY";

   --  TERM values for terminals with known OSC 52 support (FUNC-C52-005)

   --  @summary TERM value for the kitty GPU terminal.
   --  @description Exact match for TERM=xterm-kitty.  kitty supports full OSC 52
   --  read and write.
   --  Heuristic inference: Read_Write (FUNC-C52-009 step 4).
   --  Note: intentionally duplicated from Termicap.Graphics to avoid cross-package
   --  dependency between peer Tier 4 features.
   --  @relation(FUNC-C52-005): TERM constant for kitty terminal
   TERM_XTERM_KITTY : constant String := "xterm-kitty";

   --  @summary TERM prefix for xterm-family terminals.
   --  @description Prefix match: TERM starts with "xterm".  xterm supports OSC 52
   --  write when allowWindowOps is enabled (disabled by default in most distributions).
   --  The prefix match is intentionally conservative; xterm is treated as Write_Only
   --  because allowWindowOps (which gates read-back) is disabled by default.
   --  Heuristic inference: Write_Only (FUNC-C52-009 step 4 continued).
   --  @relation(FUNC-C52-005): TERM prefix constant for xterm family
   TERM_XTERM : constant String := "xterm";

   ---------------------------------------------------------------------------
   --  Probe Timeout Constant (FUNC-C52-015)
   ---------------------------------------------------------------------------

   --  @summary Millisecond timeout for each active probe session (DA1 or OSC 52).
   --  @description Each probe session (DA1 and OSC 52) uses this independent timeout.
   --  DA1 and OSC 52 probes are separate sessions with separate 1000 ms budgets
   --  (FUNC-C52-015; mirroring ADR-0028 for SIXEL).  1000 ms is consistent with
   --  MOUSE_PROBE_TIMEOUT_MS (FUNC-MSE-013), GRAPHICS_PROBE_TIMEOUT_MS (FUNC-SXL-015),
   --  and the OSC-INFRA default (FUNC-OSC-004).  Worst-case latency of Detect_Clipboard
   --  is 2000 ms (both probes time out completely); the common case is much less.
   --  @relation(FUNC-C52-015): Per-session probe timeout
   CLIPBOARD_PROBE_TIMEOUT_MS : constant Natural := 1_000;

   ---------------------------------------------------------------------------
   --  OSC 52 Query Bytes (FUNC-C52-007)
   ---------------------------------------------------------------------------

   --  @summary The 9-byte OSC 52 clipboard read query.
   --  @description Encodes ESC ] 52 ; c ; ? BEL (OSC introducer + "52;c;?" + BEL
   --  terminator).  Sent to the terminal to query clipboard read-back support;
   --  a DA1 sentinel (ESC [ c) is appended as a response boundary marker by
   --  Termicap.OSC.Sentinel_Query (FUNC-C52-007).
   --
   --  Byte breakdown:
   --    0x1B  ESC      (OSC escape)
   --    0x5D  ]        (OSC introducer)
   --    0x35  5        (digit 5)
   --    0x32  2        (digit 2)
   --    0x3B  ;        (delimiter)
   --    0x63  c        (clipboard selection: primary clipboard)
   --    0x3B  ;        (delimiter)
   --    0x3F  ?        (read-back query)
   --    0x07  BEL      (OSC terminator)
   --  @relation(FUNC-C52-007): OSC 52 read query byte sequence
   OSC52_QUERY : constant Byte_Array :=
     [16#1B#,                  --  ESC      (0x1B)
      16#5D#,                  --  ]        (0x5D, OSC introducer)
      Character'Pos ('5'),     --  5        (0x35)
      Character'Pos ('2'),     --  2        (0x32)
      Character'Pos (';'),     --  ;        (0x3B)
      Character'Pos ('c'),     --  c        (0x63, clipboard selection)
      Character'Pos (';'),     --  ;        (0x3B)
      Character'Pos ('?'),     --  ?        (0x3F, query)
      16#07#];                 --  BEL      (0x07, OSC terminator)

   ---------------------------------------------------------------------------
   --  OSC 52 Parse Result Enumeration (FUNC-C52-008)
   ---------------------------------------------------------------------------

   --  @summary Three-way result of the OSC 52 response parser.
   --  @description
   --    Not_Present    -- No OSC 52 introducer (ESC ] 52) was found in the buffer.
   --                      The DA1 sentinel arrived first, or the terminal did not
   --                      respond to the read query.  Treated as "read-back not
   --                      available" for FUNC-C52-007; Support is not upgraded.
   --    Valid_Response -- A well-formed OSC 52 response was found: the introducer
   --                      ESC ] 52 ; <sel> ; <base64-or-empty> was present and
   --                      the response terminated with BEL (0x07) or ST (ESC \).
   --                      Indicates that the terminal supports OSC 52 read-back
   --                      (Read_Write upgrade in the cascade).
   --    Malformed      -- An OSC 52 introducer was found but the response did not
   --                      terminate correctly or lacked the required semicolon
   --                      structure.  Treated as "read-back not available" for
   --                      FUNC-C52-007.  Distinguished from Not_Present for
   --                      debugging and test assertions.
   --
   --  Both Not_Present and Malformed map to "read-back not available" in the
   --  detection cascade.
   --  @relation(FUNC-C52-008): OSC 52 parse result enumeration
   type OSC52_Parse_Result is (Not_Present, Valid_Response, Malformed);

   ---------------------------------------------------------------------------
   --  OSC 52 Response Parser (FUNC-C52-008)
   ---------------------------------------------------------------------------

   --  @summary Parse an OSC 52 read-back response from a raw byte buffer.
   --  @description Scans Buffer (Buffer'First .. Buffer'First + Length - 1) for
   --  an OSC 52 response matching the pattern:
   --
   --    ESC ] 52 ; <selection> ; <base64-or-empty> BEL
   --    or:
   --    ESC ] 52 ; <selection> ; <base64-or-empty> ESC \
   --
   --  Return values:
   --    Valid_Response -- A well-formed OSC 52 response envelope was found: the
   --                      bytes ESC ] 52 introduced the response, at least two
   --                      semicolons were present, and the response terminated with
   --                      BEL (0x07) or ST (ESC \, 0x1B 0x5C).  The base64 payload
   --                      is not decoded; structural presence is sufficient for
   --                      capability detection.
   --    Not_Present    -- No OSC 52 introducer (ESC ] 5 2) was found in the buffer.
   --                      The terminal did not respond to the read query, or the DA1
   --                      sentinel arrived before any OSC 52 bytes.
   --    Malformed      -- An OSC 52 introducer was found but the response did not
   --                      terminate with BEL or ESC \, or fewer than two semicolons
   --                      were present before the terminator.
   --
   --  The function never raises for any buffer content; stray or out-of-range
   --  bytes are skipped.  The scan is O(Length) worst-case.
   --
   --  @param Buffer  The raw response byte buffer (stack-allocated Response_Buffer
   --                 from Termicap.OSC or a subarray thereof).
   --  @param Length  Number of valid bytes in Buffer to examine (0 .. Buffer'Length).
   --  @return OSC52_Parse_Result per the rules above.
   --  @relation(FUNC-C52-008): OSC 52 response parser (SPARK Silver)
   function Parse_OSC52_Response (Buffer : Byte_Array; Length : Natural) return OSC52_Parse_Result
   with SPARK_Mode => On, Global => null, Pre => Length <= Buffer'Length, Post => True;

end Termicap.Clipboard;
