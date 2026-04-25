-------------------------------------------------------------------------------
--  Termicap.Graphics - Sixel / Kitty Graphics Detection Types and Parsers
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and parsing functions for Sixel and Kitty
--  graphics protocol detection (SIXEL, Tier 4 Stretch Goal).
--
--  @description
--  This package provides all the SPARK-provable building blocks for graphics
--  protocol detection: the Graphics_Capabilities aggregate result record
--  combining Sixel support, Kitty graphics protocol support, provenance flags
--  (Sixel_Via_DA1, Kitty_Via_Active_Probe), probe metadata (Probed), and
--  optional sub-fields (Sixel_Color_Registers, Kitty_Graphics_Version).
--
--  Named string constants centralise terminal identifier values used in
--  passive detection (TERM, TERM_PROGRAM, KITTY_WINDOW_ID, XTVERSION name
--  tokens) per FUNC-SXL-004.
--
--  The APC_Parse_Result enumeration and Parse_Kitty_APC_Response function
--  implement the three-way Kitty graphics APC response parser (FUNC-SXL-011),
--  a pure SPARK Silver function with Global => null and Pre/Post contracts.
--
--  The KITTY_APC_QUERY constant holds the 12-byte APC query sequence
--  (ESC _ G i=1,a=q ESC \) used by the optional Kitty active probe
--  (FUNC-SXL-010).
--
--  All functions carry Global => null contracts.  No I/O, no global state,
--  and no exceptions are used in this package.  The I/O boundary, caching,
--  and platform-specific guards are in the child package
--  Termicap.Graphics.IO (SPARK_Mode => Off).
--
--  The Byte subtype and Byte_Array type are declared here independently of
--  Termicap.OSC (which is SPARK_Mode Off) using the same underlying
--  Interfaces.C.unsigned_char type, ensuring representation compatibility at
--  the I/O boundary without introducing a SPARK mode violation.  This mirrors
--  the pattern established by Termicap.Mouse, Termicap.Keyboard, Termicap.DA1,
--  and Termicap.XTVERSION.
--
--  Requirements Coverage:
--    - @relation(FUNC-SXL-001): Graphics_Capabilities result record
--    - @relation(FUNC-SXL-002): Sixel_Color_Registers optional field
--    - @relation(FUNC-SXL-003): Kitty_Graphics_Version optional field
--    - @relation(FUNC-SXL-004): Named constants for known terminal identifiers
--    - @relation(FUNC-SXL-011): APC_Parse_Result / Parse_Kitty_APC_Response
--    - @relation(FUNC-SXL-015): GRAPHICS_PROBE_TIMEOUT_MS constant
--    - @relation(FUNC-SXL-018): Package structure and SPARK boundary

with Interfaces.C;

package Termicap.Graphics
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Byte Types (representation-compatible with Termicap.OSC)
   ---------------------------------------------------------------------------

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   --  @description Defined independently of Termicap.OSC (which is SPARK_Mode Off)
   --  to keep this package SPARK On.  Representation-compatible with
   --  Termicap.OSC.Byte, Termicap.Mouse.Byte, and Termicap.Keyboard.Byte;
   --  Termicap.Graphics.IO can convert between them at the I/O boundary without
   --  a copy.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for escape sequence data.
   --  @description Used for raw response buffers passed to parsing functions
   --  and for the KITTY_APC_QUERY constant.  Representation-compatible with
   --  Termicap.OSC.Byte_Array and Termicap.Mouse.Byte_Array.
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Graphics_Capabilities Result Record (FUNC-SXL-001, FUNC-SXL-002, FUNC-SXL-003)
   ---------------------------------------------------------------------------

   --  @summary Aggregate result of Sixel and Kitty graphics protocol detection.
   --  @description Combines Sixel support, Kitty graphics protocol support,
   --  detection provenance flags, probe metadata, and optional sub-fields.
   --
   --  Canonical interpretations:
   --    Sixel_Supported = False, Kitty_Graphics_Supported = False, Probed = False:
   --      Detection was not performed or all guards suppressed probing (non-TTY,
   --      foreground guard, /dev/tty open failure, Win32 Console gate).
   --    Sixel_Supported = True, Sixel_Via_DA1 = True, Probed = True:
   --      Sixel confirmed by DA1 Ps=4 active probe (highest confidence).
   --    Sixel_Supported = True, Sixel_Via_DA1 = False:
   --      Sixel inferred by XTVERSION name match or env-var heuristic.
   --    Kitty_Graphics_Supported = True, Kitty_Via_Active_Probe = True, Probed = True:
   --      Kitty graphics confirmed by APC active probe.
   --    Kitty_Graphics_Supported = True, Kitty_Via_Active_Probe = False:
   --      Kitty graphics inferred by env-var heuristics (KITTY_WINDOW_ID,
   --      TERM=xterm-kitty, or TERM_PROGRAM=WezTerm).
   --
   --  Implicit invariants (enforced by construction in body helpers, not by
   --  Type_Invariant, per the rationale in the tech spec §F.2):
   --    I1. Sixel_Via_DA1 = True => Sixel_Supported = True and Probed = True.
   --    I2. Kitty_Via_Active_Probe = True => Kitty_Graphics_Supported = True
   --        and Probed = True.
   --    I3. Probed = False => Sixel_Via_DA1 = False and
   --        Kitty_Via_Active_Probe = False.
   --    I4. Sixel_Color_Registers > 0 => Sixel_Supported = True.
   --  @relation(FUNC-SXL-001): Graphics capabilities result record
   --  @relation(FUNC-SXL-002): Sixel_Color_Registers field
   --  @relation(FUNC-SXL-003): Kitty_Graphics_Version field
   type Graphics_Capabilities is record

      --  Sixel support (FUNC-SXL-001)
      Sixel_Supported : Boolean := False;
      --     True when Sixel graphics are available on the controlling terminal,
      --     established by any of the three detection paths: DA1 active probe
      --     (FUNC-SXL-005), XTVERSION name match (FUNC-SXL-007), or env-var
      --     heuristic (FUNC-SXL-008).  False by default (safe: unsupported
      --     Sixel renders as visible garbage).

      --  Kitty graphics protocol support (FUNC-SXL-001)
      Kitty_Graphics_Supported : Boolean := False;
      --     True when the Kitty graphics protocol is available, established by
      --     passive env-var identification (FUNC-SXL-009) or the optional APC
      --     active probe (FUNC-SXL-010).  False by default.

      --  Detection provenance flags (informational, FUNC-SXL-001)
      Sixel_Via_DA1          : Boolean := False;
      --     True when Sixel_Supported was set via a successful DA1 probe
      --     (Ps=4 present).  False when set via passive heuristics only,
      --     or when Sixel_Supported is False.
      Kitty_Via_Active_Probe : Boolean := False;
      --     True when Kitty_Graphics_Supported was confirmed via the APC active
      --     probe (FUNC-SXL-010).  False when set via passive env-var heuristics
      --     only, or when Kitty_Graphics_Supported is False.

      --  Probe metadata (FUNC-SXL-001)
      Probed : Boolean := False;
      --     True when at least one active probe (DA1 or APC) was attempted.
      --     False when the result was determined entirely by passive env-var
      --     heuristics (no TTY, not foreground, /dev/tty unopenable, or
      --     Win32 Console gate).

      --  Optional sub-fields (FUNC-SXL-002, FUNC-SXL-003)
      Sixel_Color_Registers  : Natural := 0;
      --     Number of simultaneous colors available for sixel rendering, or 0
      --     when unknown.  Common values: 256 (most terminals), 1024, 65536
      --     (WezTerm).  Populated via XTSMGRAPHICS query when Sixel_Supported
      --     is True and the terminal is a TTY.  Defaults to 0 (unknown) in v1;
      --     XTSMGRAPHICS probing is deferred.
      Kitty_Graphics_Version : Natural := 0;
      --     Kitty graphics protocol version, or 0 when not determinable.
      --     kitty terminal reports its version via XTVERSION (e.g., "kitty
      --     0.35.2"); the major-minor version can be parsed from the XTVERSION
      --     result.  Defaults to 0 (unknown) in v1; version-string parsing is
      --     deferred.
   end record;

   ---------------------------------------------------------------------------
   --  Canonical "No Result" Constant (FUNC-SXL-001)
   ---------------------------------------------------------------------------

   --  @summary Canonical initial / "no result" Graphics_Capabilities value.
   --  @description Represents the state before probing has been performed, or
   --  when probing could not be completed.  Used as the cache initial value
   --  and as the fallback on every error path of Detect_Graphics.
   --  A Graphics_Capabilities declared without an explicit aggregate is equivalent
   --  to this value via default initialisation.
   --  @relation(FUNC-SXL-001): Canonical safe-default "no result" value
   NO_GRAPHICS_CAPABILITIES : constant Graphics_Capabilities :=
     (Sixel_Supported          => False,
      Kitty_Graphics_Supported => False,
      Sixel_Via_DA1            => False,
      Kitty_Via_Active_Probe   => False,
      Probed                   => False,
      Sixel_Color_Registers    => 0,
      Kitty_Graphics_Version   => 0);

   ---------------------------------------------------------------------------
   --  Named Terminal Identifier Constants (FUNC-SXL-004)
   ---------------------------------------------------------------------------

   --  TERM values for terminals with known Sixel support (FUNC-SXL-004)

   --  @summary TERM value for the kitty GPU terminal.
   --  @description Exact match for TERM=xterm-kitty.  kitty supports both
   --  the Kitty graphics protocol and Sixel.  Used in FUNC-SXL-008 (Sixel
   --  env-var heuristic) and FUNC-SXL-009 (Kitty env-var heuristic).
   --  @relation(FUNC-SXL-004): TERM constant for kitty terminal
   TERM_XTERM_KITTY : constant String := "xterm-kitty";

   --  @summary TERM value for the foot Wayland terminal.
   --  @description Exact match for TERM=foot.  foot supports Sixel via DA1 Ps=4.
   --  Used in FUNC-SXL-008 (Sixel env-var heuristic step 2).
   --  @relation(FUNC-SXL-004): TERM constant for foot terminal
   TERM_FOOT : constant String := "foot";

   --  @summary TERM value for the foot extra-capabilities build.
   --  @description Exact match for TERM=foot-extra.  Same Sixel support as foot.
   --  Used in FUNC-SXL-008 (Sixel env-var heuristic step 2).
   --  @relation(FUNC-SXL-004): TERM constant for foot-extra terminal
   TERM_FOOT_EXTRA : constant String := "foot-extra";

   --  @summary TERM prefix for xterm-family terminals.
   --  @description Prefix match: TERM starts with "xterm".  xterm supports
   --  Sixel when compiled with --enable-sixel.  The prefix match is intentionally
   --  imprecise; the DA1 path (FUNC-SXL-005) provides the definitive answer.
   --  Used in FUNC-SXL-008 (Sixel env-var heuristic step 2).
   --  @relation(FUNC-SXL-004): TERM prefix constant for xterm family
   TERM_XTERM : constant String := "xterm";

   --  @summary TERM value for MLterm.
   --  @description Exact match for TERM=mlterm.  MLterm supports Sixel natively.
   --  Used in FUNC-SXL-008 (Sixel env-var heuristic step 2).
   --  @relation(FUNC-SXL-004): TERM constant for mlterm terminal
   TERM_MLTERM : constant String := "mlterm";

   --  @summary TERM value for the yaft framebuffer terminal.
   --  @description Exact match for TERM=yaft.  yaft supports Sixel.
   --  Used in FUNC-SXL-008 (Sixel env-var heuristic step 2).
   --  @relation(FUNC-SXL-004): TERM constant for yaft terminal
   TERM_YAFT : constant String := "yaft";

   --  TERM_PROGRAM values for terminals with known Sixel or Kitty support (FUNC-SXL-004)

   --  @summary TERM_PROGRAM value for WezTerm.
   --  @description Case-insensitive match for TERM_PROGRAM=WezTerm.  WezTerm
   --  supports both Sixel and the Kitty graphics protocol.  Used in FUNC-SXL-008
   --  (Sixel env-var heuristic step 1) and FUNC-SXL-009 (Kitty env-var step 3).
   --  @relation(FUNC-SXL-004): TERM_PROGRAM constant for WezTerm
   TERM_PROGRAM_WEZTERM : constant String := "WezTerm";

   --  @summary TERM_PROGRAM value for iTerm2.
   --  @description Exact match for TERM_PROGRAM=iTerm.app.  iTerm2 for macOS
   --  supports Sixel via the iTerm2 image protocol.  Used in Sixel passive
   --  detection heuristics.
   --  @relation(FUNC-SXL-004): TERM_PROGRAM constant for iTerm2
   TERM_PROGRAM_ITERM2 : constant String := "iTerm.app";

   --  @summary TERM_PROGRAM value for macOS Terminal.app.
   --  @description Apple Terminal sets TERM_PROGRAM=Apple_Terminal.  It does not
   --  implement APC sequences (ESC _); sending the Kitty APC probe causes the
   --  query content to leak as literal text output.  Used to skip the APC probe
   --  (FUNC-SXL-010) on this terminal.
   TERM_PROGRAM_APPLE_TERMINAL : constant String := "Apple_Terminal";

   --  Environment variable names (FUNC-SXL-004)

   --  @summary Name of the KITTY_WINDOW_ID environment variable.
   --  @description kitty sets this variable for every window it manages,
   --  including when TERM has been overridden by a multiplexer.  Presence of
   --  this variable is the highest-confidence passive Kitty graphics indicator.
   --  Used in FUNC-SXL-009 (Kitty env-var heuristic step 1).
   --  @relation(FUNC-SXL-004): ENV_KITTY_WINDOW_ID constant
   ENV_KITTY_WINDOW_ID : constant String := "KITTY_WINDOW_ID";

   --  XTVERSION terminal name tokens (case-insensitive match, FUNC-SXL-004)

   --  @summary XTVERSION name token for the kitty terminal.
   --  @description Substring matched case-insensitively against the terminal
   --  name reported by XTVERSION (FUNC-XTV-006).  kitty advertises its name
   --  as "kitty" followed by the version.  Used in FUNC-SXL-007 (Sixel XTVERSION
   --  fallback) and FUNC-SXL-009 implicitly via terminal identification.
   --  @relation(FUNC-SXL-004): XTVERSION name token for kitty
   XTVERSION_NAME_KITTY : constant String := "kitty";

   --  @summary XTVERSION name token for WezTerm.
   --  @description Substring matched case-insensitively against the terminal
   --  name reported by XTVERSION.  WezTerm advertises its name as "WezTerm"
   --  followed by the version.  Used in FUNC-SXL-007 (Sixel XTVERSION fallback).
   --  @relation(FUNC-SXL-004): XTVERSION name token for WezTerm
   XTVERSION_NAME_WEZTERM : constant String := "WezTerm";

   ---------------------------------------------------------------------------
   --  Probe Timeout Constant (FUNC-SXL-015)
   ---------------------------------------------------------------------------

   --  @summary Millisecond timeout for each active probe session (DA1 or APC).
   --  @description Each probe session (DA1 for Sixel, APC for Kitty graphics)
   --  uses this independent timeout.  DA1 and APC are separate sessions with
   --  separate 1000 ms budgets (FUNC-SXL-015).  1000 ms is consistent with
   --  MOUSE_PROBE_TIMEOUT_MS (FUNC-MSE-013) and KITTY_PROBE_TIMEOUT_MS
   --  (FUNC-KKB-013) and the OSC-INFRA default (FUNC-OSC-004).
   --  Implementations may use a shorter timeout (minimum 100 ms) on local PTYs.
   --  @relation(FUNC-SXL-015): Probe session timeout
   GRAPHICS_PROBE_TIMEOUT_MS : constant Natural := 1_000;

   ---------------------------------------------------------------------------
   --  Kitty APC Query Bytes (FUNC-SXL-010)
   ---------------------------------------------------------------------------

   --  @summary The 12-byte APC Kitty graphics query sequence.
   --  @description Encodes ESC _ G i=1,a=q ESC \ (APC introducer + "Gi=1,a=q"
   --  payload + ST terminator).  Adopted verbatim from the notcurses KITTYQUERY
   --  macro (reference-frameworks/notcurses/src/lib/termdesc.c:383).  Sent to
   --  the terminal to query Kitty graphics protocol support; a DA1 sentinel
   --  (ESC [ c) is appended as a response boundary marker (FUNC-SXL-010).
   --  @relation(FUNC-SXL-010): Kitty APC query byte sequence
   KITTY_APC_QUERY : constant Byte_Array :=
     [16#1B#,                  --  ESC      (0x1B)
      16#5F#,                  --  _        (0x5F, APC introducer)
      Character'Pos ('G'),     --  G        (0x47)
      Character'Pos ('i'),     --  i        (0x69)
      Character'Pos ('='),     --  =        (0x3D)
      Character'Pos ('1'),     --  1        (0x31)
      Character'Pos (','),     --  ,        (0x2C)
      Character'Pos ('a'),     --  a        (0x61)
      Character'Pos ('='),     --  =        (0x3D)
      Character'Pos ('q'),     --  q        (0x71)
      16#1B#,                  --  ESC      (0x1B)
      16#5C#];                 --  \        (0x5C, ST terminator)

   ---------------------------------------------------------------------------
   --  APC Parse Result Enumeration (FUNC-SXL-011)
   ---------------------------------------------------------------------------

   --  @summary Three-way result of the Kitty graphics APC response parser.
   --  @description
   --    Not_Present  -- No APC G response envelope found in the buffer.  The
   --                    DA1 sentinel arrived first (terminal does not implement
   --                    the Kitty graphics query).  Treated as "not supported".
   --    OK           -- APC G response found and its params contain "OK".
   --                    Terminal confirmed Kitty graphics protocol support.
   --    Error        -- APC G response found but params contain "EINVAL".
   --                    Terminal answered but reported a protocol error.
   --                    Treated as "not supported".
   --  Both Not_Present and Error map to Kitty_Graphics_Supported = False for
   --  the purpose of FUNC-SXL-010.  The distinction is preserved for debugging
   --  and test assertions (mirrors Parse_Kitty_Response tri-state, FUNC-KKB-006).
   --  @relation(FUNC-SXL-011): APC parse result enumeration
   type APC_Parse_Result is (Not_Present, OK, Error);

   ---------------------------------------------------------------------------
   --  Kitty APC Response Parser (FUNC-SXL-011)
   ---------------------------------------------------------------------------

   --  @summary Parse a Kitty graphics APC response from a raw byte buffer.
   --  @description Scans Buffer (Buffer'First .. Buffer'First + Length - 1) for
   --  an APC G response envelope of the form:
   --
   --    ESC _ G <params> ESC \
   --    (APC introducer: 0x1B 0x5F; params end at: ESC \ = 0x1B 0x5C or BEL 0x07)
   --
   --  Return values:
   --    OK           -- APC G envelope found and <params> contains "OK".
   --    Error        -- APC G envelope found and <params> contains "EINVAL".
   --    Not_Present  -- No APC G envelope found in the buffer.
   --
   --  The function never raises for any buffer content; stray or out-of-range
   --  bytes are skipped.  BEL (0x07) is treated as an alternate APC terminator
   --  alongside ESC \ (consistent with DCS terminator handling).
   --
   --  @param Buffer  The raw response byte buffer.
   --  @param Length  Number of valid bytes in Buffer to examine (0..Buffer'Length).
   --  @return APC_Parse_Result per the rules above.
   --  @relation(FUNC-SXL-011): APC response parser (SPARK Silver)
   function Parse_Kitty_APC_Response (Buffer : Byte_Array; Length : Natural) return APC_Parse_Result
   with SPARK_Mode => On, Global => null, Pre => Length <= Buffer'Length, Post => True;

end Termicap.Graphics;
