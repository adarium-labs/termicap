-------------------------------------------------------------------------------
--  Termicap.Color - Color Level Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects the color output capability of a terminal from environment
--  variable heuristics.
--
--  @description
--  Provides a pure, SPARK-provable function that determines the terminal's
--  color level (None, 16, 256, or TrueColor) from an immutable environment
--  snapshot and a TTY status flag.  The function performs no OS calls and
--  reads no global state.
--
--  The detection algorithm implements an 11-step priority cascade defined
--  by FUNC-CLR-015, supporting NO_COLOR, FORCE_COLOR, CLICOLOR_FORCE,
--  CLICOLOR, COLORTERM, TERM, TERM_PROGRAM, and CI environment detection.
--
--  Requirements Coverage:
--    - @relation(FUNC-CLR-001): Color_Level enumeration type
--    - @relation(FUNC-CLR-002): Pure detection function signature
--    - @relation(FUNC-CLR-003): NO_COLOR compliance
--    - @relation(FUNC-CLR-004): FORCE_COLOR override
--    - @relation(FUNC-CLR-005): CLICOLOR_FORCE support
--    - @relation(FUNC-CLR-006): TERM=dumb handling
--    - @relation(FUNC-CLR-007): TTY gate
--    - @relation(FUNC-CLR-008): COLORTERM detection
--    - @relation(FUNC-CLR-009): TERM-based color detection
--    - @relation(FUNC-CLR-010): TERM_PROGRAM detection
--    - @relation(FUNC-CLR-011): CI environment detection
--    - @relation(FUNC-CLR-012): CLICOLOR support
--    - @relation(FUNC-CLR-013): Multiplexer awareness
--    - @relation(FUNC-CLR-014): SPARK Silver provability
--    - @relation(FUNC-CLR-015): Detection priority order

with Termicap.Environment;
with Termicap.Override;

package Termicap.Color
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Types (FUNC-CLR-001)
   ---------------------------------------------------------------------------

   --  @summary Terminal color capability level.
   --  @description Ordered enumeration: None < Basic_16 < Extended_256 < True_Color.
   --  Supports Color_Level'Max for floor operations.
   --  @relation(FUNC-CLR-001): Four-valued ordered enumeration
   type Color_Level is (None, Basic_16, Extended_256, True_Color);

   ---------------------------------------------------------------------------
   --  Detection (FUNC-CLR-002 through FUNC-CLR-015)
   ---------------------------------------------------------------------------

   --  @summary Detect the color level supported by the terminal.
   --  @param Env    An immutable environment variable snapshot.
   --  @param Is_TTY Whether the target output stream is connected to a TTY.
   --  @return The detected color level based on the 11-step priority cascade.
   --  @relation(FUNC-CLR-002): Pure detection function
   --  @relation(FUNC-CLR-014): SPARK Silver provability
   --  @relation(FUNC-CLR-015): Detection priority order
   function Detect_Color_Level
     (Env : Termicap.Environment.Environment; Is_TTY : Boolean)
      return Color_Level
   with Global => (Input => Termicap.Override.Override_State);

end Termicap.Color;
