-------------------------------------------------------------------------------
--  Termicap.Dimensions - Terminal Dimensions Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects terminal dimensions (rows, columns, pixel size) with a fallback
--  chain: ioctl(TIOCGWINSZ) -> COLUMNS/LINES env vars -> 80x24 default.
--
--  @description
--  Provides a Terminal_Size record type and a Get_Size function that determines
--  terminal dimensions from an immutable environment snapshot and a TTY status
--  flag.  The function performs no OS calls when Is_TTY is False, making the
--  environment variable fallback path fully testable and SPARK-contract-
--  compatible.
--
--  The package spec is SPARK-annotated for type safety.  The body uses
--  SPARK_Mode => Off for the ioctl FFI binding via a thin C wrapper.
--
--  Requirements Coverage:
--    - @relation(FUNC-DIM-001): Terminal_Size record type
--    - @relation(FUNC-DIM-002): Primary detection via ioctl(TIOCGWINSZ)
--    - @relation(FUNC-DIM-003): Environment variable fallback
--    - @relation(FUNC-DIM-004): Default fallback to 80x24
--    - @relation(FUNC-DIM-005): Pure query function signature
--    - @relation(FUNC-DIM-006): C wrapper for ioctl(TIOCGWINSZ)
--    - @relation(FUNC-DIM-007): SPARK boundary
--    - @relation(FUNC-DIM-008): Pixel dimensions support

with Termicap.Environment;

package Termicap.Dimensions
   with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Constants (FUNC-DIM-004)
   ---------------------------------------------------------------------------

   --  @summary Industry-standard default terminal width.
   --  @relation(FUNC-DIM-004): Default fallback column count
   DEFAULT_COLUMNS : constant Positive := 80;

   --  @summary Industry-standard default terminal height.
   --  @relation(FUNC-DIM-004): Default fallback row count
   DEFAULT_ROWS : constant Positive := 24;

   ---------------------------------------------------------------------------
   --  Types (FUNC-DIM-001)
   ---------------------------------------------------------------------------

   --  @summary Terminal dimensions including character and pixel sizes.
   --  @description Rows and Columns are typed Positive (a terminal always has
   --  at least one row and one column).  Pixel_Width and Pixel_Height are typed
   --  Natural because many terminals do not report pixel dimensions; a value
   --  of 0 indicates pixel information is unavailable.
   --  @relation(FUNC-DIM-001): Terminal_Size record type
   --  @relation(FUNC-DIM-008): Pixel dimensions support
   type Terminal_Size is record
      Rows         : Positive;
      Columns      : Positive;
      Pixel_Width  : Natural;
      Pixel_Height : Natural;
   end record;

   ---------------------------------------------------------------------------
   --  Detection (FUNC-DIM-002 through FUNC-DIM-008)
   ---------------------------------------------------------------------------

   --  @summary Detect terminal dimensions using a fallback chain.
   --  @param Env    An immutable environment variable snapshot.
   --  @param Is_TTY Whether the target output stream (stdout) is connected
   --                to a TTY.  When True, ioctl(TIOCGWINSZ) is attempted
   --                first.  When False, only env var fallback and defaults
   --                are used.
   --  @return The detected terminal dimensions.  Rows and Columns are always
   --          >= 1.  Pixel_Width and Pixel_Height may be 0.
   --  @relation(FUNC-DIM-002): Primary detection via ioctl(TIOCGWINSZ)
   --  @relation(FUNC-DIM-003): Environment variable fallback
   --  @relation(FUNC-DIM-004): Default fallback to 80x24
   --  @relation(FUNC-DIM-005): Pure query function signature
   function Get_Size
      (Env    : Termicap.Environment.Environment;
       Is_TTY : Boolean) return Terminal_Size
      with Global => null;

end Termicap.Dimensions;
