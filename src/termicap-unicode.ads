-------------------------------------------------------------------------------
--  Termicap.Unicode - Unicode Support Level Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects the Unicode rendering capability of a terminal from environment
--  variable heuristics.
--
--  @description
--  Provides a pure, SPARK-provable function that determines the terminal's
--  Unicode support level (None, Basic, or Extended) from an immutable
--  environment snapshot.  The function performs no OS calls and reads no
--  global state.  No TTY status parameter is required: Unicode capability is
--  a property of the terminal emulator and locale configuration, not of
--  whether the output stream is connected to a TTY.
--
--  The detection algorithm implements a 5-step priority cascade defined by
--  FUNC-UNI-008, covering locale inspection (LC_ALL, LC_CTYPE, LANG), CI
--  environment awareness (GITHUB_ACTIONS, GITEA_ACTIONS, CIRCLECI), the
--  Linux kernel console exclusion (TERM=linux), and Windows terminal
--  heuristics (WT_SESSION, TERM_PROGRAM, TERMINAL_EMULATOR).
--
--  Requirements Coverage:
--    - @relation(FUNC-UNI-001): Unicode_Level enumeration type
--    - @relation(FUNC-UNI-002): Pure detection function signature
--    - @relation(FUNC-UNI-003): Locale-based detection via LC_ALL, LC_CTYPE, LANG
--    - @relation(FUNC-UNI-004): TERM=linux exclusion
--    - @relation(FUNC-UNI-005): Windows terminal heuristics
--    - @relation(FUNC-UNI-006): CI environment Unicode awareness
--    - @relation(FUNC-UNI-007): SPARK Silver provability
--    - @relation(FUNC-UNI-008): Detection priority order

with Termicap.Environment;

package Termicap.Unicode
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Types (FUNC-UNI-001)
   ---------------------------------------------------------------------------

   --  @summary Terminal Unicode rendering capability level.
   --  @description Ordered enumeration: None < Basic < Extended.
   --  Supports Unicode_Level'Max for floor operations.
   --  @relation(FUNC-UNI-001): Three-valued ordered enumeration
   type Unicode_Level is (None, Basic, Extended);

   ---------------------------------------------------------------------------
   --  Detection (FUNC-UNI-002 through FUNC-UNI-008)
   ---------------------------------------------------------------------------

   --  @summary Detect the Unicode support level of the terminal environment.
   --  @param Env An immutable environment variable snapshot.
   --  @return The detected Unicode level based on the 5-step priority cascade.
   --  @relation(FUNC-UNI-002): Pure detection function
   --  @relation(FUNC-UNI-007): SPARK Silver provability
   --  @relation(FUNC-UNI-008): Detection priority order
   function Detect_Unicode_Level
     (Env : Termicap.Environment.Environment) return Unicode_Level
   with Global => null;

end Termicap.Unicode;
