-------------------------------------------------------------------------------
--  Termicap.Keyboard.IO - Keyboard Protocol Detection I/O Orchestration
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Platform-dispatched I/O orchestration for keyboard protocol detection:
--  caching entry point, cache-bypass probe, and supporting cascade logic.
--
--  @description
--  This child package provides the two public entry points for keyboard
--  protocol detection:
--
--    Detect_Keyboard_Protocol  — cached, process-lifetime result.
--    Probe_Keyboard_Protocol   — uncached, always runs the full cascade.
--
--  Detect_Keyboard_Protocol implements the Win32 > Kitty > XTerm > Legacy
--  priority cascade (FUNC-KKB-009) and caches the result in a protected
--  object for the process lifetime (FUNC-KKB-017).  The first call runs the
--  cascade; all subsequent calls return the cached Keyboard_Capability
--  without re-probing.  The no-exception guarantee (FUNC-KKB-014) means
--  any failure degrades gracefully to Protocol = Unknown, Probed = False.
--
--  Probe_Keyboard_Protocol runs the same cascade without reading or writing
--  the cache, intended for test harnesses and edge cases where the terminal
--  may have changed (FUNC-KKB-017 Should clause).
--
--  I/O is performed exclusively through Termicap.OSC.Probe_Session and
--  Sentinel_Query (FUNC-KKB-012); no direct tcgetattr/tcsetattr/read/write
--  calls are made.  Platform differences (Win32 Console gate vs. POSIX-only
--  cascade) are isolated in two separate body files:
--    src/posix/termicap-keyboard-io.adb   — starts at TTY guard (step 2).
--    src/windows/termicap-keyboard-io.adb — adds GetConsoleMode gate (step 1).
--
--  The single shared spec here allows the project's GPR source-dir mechanism
--  (ADR-0018) to select exactly one body file per platform without any
--  conditional compilation in the spec, keeping Win32 dependencies out of
--  POSIX object files entirely.
--
--  This package is SPARK_Mode Off because it depends on Ada.Finalization
--  controlled types (Probe_Session) and performs terminal I/O; both are
--  outside the SPARK 2014 language subset.  The pure parsing and type logic
--  remain provable in the parent package Termicap.Keyboard.
--
--  Requirements Coverage:
--    - @relation(FUNC-KKB-009): Detection priority cascade
--    - @relation(FUNC-KKB-010): Win32 Console platform gate (Windows body)
--    - @relation(FUNC-KKB-011): Non-TTY and background-process guards
--    - @relation(FUNC-KKB-012): OSC-INFRA reuse via Probe_Session / Sentinel_Query
--    - @relation(FUNC-KKB-013): 1000 ms per-probe timeout
--    - @relation(FUNC-KKB-014): No-exception guarantee for Detect_Keyboard_Protocol
--    - @relation(FUNC-KKB-015): Termios restore on all exit paths via RAII
--    - @relation(FUNC-KKB-016): Garbled / partial response handling via parsers
--    - @relation(FUNC-KKB-017): One-probe-per-process caching; Probe_Keyboard_Protocol bypass
--    - @relation(FUNC-KKB-018): Package structure and SPARK boundary

pragma SPARK_Mode (Off);

package Termicap.Keyboard.IO is

   ---------------------------------------------------------------------------
   --  Cached Detection Entry Point (FUNC-KKB-009, FUNC-KKB-017)
   ---------------------------------------------------------------------------

   --  @summary Detect the keyboard protocol, returning a cached result on all
   --  subsequent calls after the first.
   --  @description Implements the Win32 > Kitty > XTerm > Legacy cascade:
   --    Step 1 (Windows only): if GetConsoleMode(STD_INPUT_HANDLE) succeeds,
   --      return (Protocol => Win32, Probed => False) immediately.
   --    Step 2: if Is_TTY (Stdin) returns False, return NO_KEYBOARD_CAPABILITY.
   --    Step 3: open a Probe_Session (includes foreground guard); if the session
   --      fails to open for any reason, return NO_KEYBOARD_CAPABILITY.
   --    Step 4: run the Kitty sentinel probe (CSI_KITTY_QUERY, 1000 ms);
   --      if Parse_Kitty_Response returns Valid, return (Kitty, parsed flags, True).
   --    Step 5: run the XTerm sentinel probe (CSI_XTERM_KBD_QUERY, 1000 ms);
   --      if Parse_XTerm_Keyboard_Response returns True, return (XTerm_CSI, NO_KITTY_FLAGS, True).
   --    Step 6: return (Legacy, NO_KITTY_FLAGS, True).
   --  The result is stored in a package-level protected object after the first
   --  call and returned from the cache on all subsequent calls (FUNC-KKB-017).
   --  This function never propagates an exception under any circumstances;
   --  any failure path returns NO_KEYBOARD_CAPABILITY (FUNC-KKB-014).
   --  @return Keyboard_Capability with the detected protocol, Kitty flags, and
   --          Probed flag.  Returns NO_KEYBOARD_CAPABILITY on any error.
   --  @relation(FUNC-KKB-009): Full detection cascade
   --  @relation(FUNC-KKB-010): Win32 Console gate (Windows body only)
   --  @relation(FUNC-KKB-011): Non-TTY and foreground guards
   --  @relation(FUNC-KKB-014): No-exception guarantee
   --  @relation(FUNC-KKB-017): One-probe-per-process caching
   function Detect_Keyboard_Protocol return Keyboard_Capability;

   ---------------------------------------------------------------------------
   --  Cache-Bypass Probe (FUNC-KKB-017 Should Clause)
   ---------------------------------------------------------------------------

   --  @summary Run the full keyboard protocol detection cascade without
   --  consulting or updating the process-lifetime cache.
   --  @description Executes the same Win32 > Kitty > XTerm > Legacy cascade as
   --  Detect_Keyboard_Protocol but does not read from or write to the cache.
   --  Intended for test harnesses that need a fresh probe result after a
   --  terminal change (e.g., tmux reattach to a different outer terminal) and
   --  for integration tests that must verify detection behaviour in isolation.
   --  Like Detect_Keyboard_Protocol, this function never propagates an exception;
   --  any failure path returns NO_KEYBOARD_CAPABILITY (FUNC-KKB-014).
   --  @return Keyboard_Capability from a fresh cascade execution.
   --  @relation(FUNC-KKB-017): Cache-bypass detection for test use
   --  @relation(FUNC-KKB-014): No-exception guarantee
   function Probe_Keyboard_Protocol return Keyboard_Capability;

end Termicap.Keyboard.IO;
