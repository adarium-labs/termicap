-------------------------------------------------------------------------------
--  Termicap.Capabilities - Terminal Capability Record Assembly
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Aggregates all sub-detector results into a single Terminal_Capabilities
--  record, providing cached (Get) and fresh (Detect) detection entry points.
--
--  @description
--  This package is the primary integration point for applications that need
--  all terminal capability information in a single call.  Rather than invoking
--  each sub-detector independently, callers use Get (lazy cached) or Detect
--  (always fresh) to obtain a fully populated Terminal_Capabilities snapshot.
--
--  The pure assembly function Assemble is SPARK Silver-provable (Global => null)
--  and carries a postcondition that proves Downsampling_Available is consistent
--  with the Color field.  Detect and Get delegate to OS-calling sub-detectors
--  and are therefore not given SPARK Global contracts.
--
--  Requirements Coverage:
--    - @relation(FUNC-CAP-001): Terminal_Capabilities record type
--    - @relation(FUNC-CAP-002): Stream selection for per-stream color detection
--    - @relation(FUNC-CAP-003): Get function â cached lazy initialisation
--    - @relation(FUNC-CAP-004): Detect function â fresh detection
--    - @relation(FUNC-CAP-005): Default stream convenience (default parameter)
--    - @relation(FUNC-CAP-006): Override state applied to Color field
--    - @relation(FUNC-CAP-007): TTY fields reflect override state
--    - @relation(FUNC-CAP-008): Thread-safe cache initialisation
--    - @relation(FUNC-CAP-009): Immutability of returned record
--    - @relation(FUNC-CAP-010): Sub-detector invocation order
--    - @relation(FUNC-CAP-011): Environment snapshot used consistently
--    - @relation(FUNC-CAP-012): SPARK Silver target for pure assembly logic
--    - @relation(FUNC-CAP-013): No FFI in capability record assembly
--    - @relation(FUNC-CAP-014): Re-detection on explicit Detect call

with Termicap.Color;
with Termicap.DA1;
with Termicap.Dimensions;
with Termicap.Terminal_Id;
with Termicap.TTY;
with Termicap.Unicode;

package Termicap.Capabilities
  with SPARK_Mode
is

   pragma Elaborate_Body;

   use type Termicap.Color.Color_Level;

   ---------------------------------------------------------------------------
   --  Record Type (FUNC-CAP-001, FUNC-CAP-009)
   ---------------------------------------------------------------------------

   --  @summary Aggregated terminal capability snapshot.
   --  @description Immutable value record; assignment produces an independent
   --  copy with value semantics.  No access types, no mutable discriminants.
   --  All fields reflect detection results at the moment Get or Detect was called.
   --  @relation(FUNC-CAP-001): Aggregated record type for all sub-detector results
   --  @relation(FUNC-CAP-009): Plain Ada record â value semantics, no aliasing
   type Terminal_Capabilities is record
      TTY_Stdin              : Boolean;
      TTY_Stdout             : Boolean;
      TTY_Stderr             : Boolean;
      Color                  : Termicap.Color.Color_Level;
      Size                   : Termicap.Dimensions.Terminal_Size;
      Unicode                : Termicap.Unicode.Unicode_Level;
      Identity               : Termicap.Terminal_Id.Terminal_Identity;
      Downsampling_Available : Boolean;
      DA1                    : Termicap.DA1.DA1_Capabilities;
   end record;

   ---------------------------------------------------------------------------
   --  Pure Assembly (FUNC-CAP-012, FUNC-CAP-013)
   ---------------------------------------------------------------------------

   --  @summary Assemble a Terminal_Capabilities record from pre-computed
   --           sub-detector results.
   --  @description Pure function with no global state access.  Derives
   --  Downsampling_Available as Color >= Extended_256.  Called internally by
   --  Detect; may also be called directly by test code with known inputs.
   --  @param TTY_Stdin  True when the stdin stream is connected to a TTY.
   --  @param TTY_Stdout True when the stdout stream is connected to a TTY.
   --  @param TTY_Stderr True when the stderr stream is connected to a TTY.
   --  @param Color      Detected color level for the selected stream.
   --  @param Size       Detected terminal dimensions (always from stdout).
   --  @param Unicode    Detected Unicode support level.
   --  @param Identity   Passively identified terminal or multiplexer.
   --  @return A fully populated Terminal_Capabilities record.
   --  @relation(FUNC-CAP-012): SPARK Silver â Global => null, provable postcondition
   --  @relation(FUNC-CAP-013): No FFI â all inputs supplied as parameters
   --  @param DA1        DA1 primary device attributes result.
   --  @relation(FUNC-DA1-015): DA1 parameter added to Assemble
   function Assemble
     (TTY_Stdin  : Boolean;
      TTY_Stdout : Boolean;
      TTY_Stderr : Boolean;
      Color      : Termicap.Color.Color_Level;
      Size       : Termicap.Dimensions.Terminal_Size;
      Unicode    : Termicap.Unicode.Unicode_Level;
      Identity   : Termicap.Terminal_Id.Terminal_Identity;
      DA1        : Termicap.DA1.DA1_Capabilities)
      return Terminal_Capabilities
   with
     SPARK_Mode => On,
     Global     => null,
     Post       =>
       Assemble'Result.Downsampling_Available
       = (Assemble'Result.Color >= Termicap.Color.Extended_256);

   ---------------------------------------------------------------------------
   --  Detection Functions (FUNC-CAP-003, FUNC-CAP-004, FUNC-CAP-005)
   ---------------------------------------------------------------------------

   --  @summary Perform a complete, uncached detection for the given stream.
   --  @description Invokes all sub-detectors in dependency order (FUNC-CAP-010),
   --  captures a fresh environment snapshot, and assembles the result.  Does not
   --  read or write the cache used by Get.  Use this function when up-to-date
   --  capability information is required (e.g., after SIGWINCH or an override
   --  change).
   --  @param Stream The stream for which Color and TTY_Stdout/TTY_Stderr/TTY_Stdin
   --               are computed.  Size is always derived from the stdout stream.
   --  @return A Terminal_Capabilities record reflecting terminal state at the
   --          moment of the call.
   --  @relation(FUNC-CAP-004): Fresh detection â no cache read or write
   --  @relation(FUNC-CAP-005): Default Stream => Stdout for the common case
   --  @relation(FUNC-CAP-006): Override applied via Detect_Color_Level
   --  @relation(FUNC-CAP-007): TTY override applied via Is_TTY / Query_All
   --  @relation(FUNC-CAP-010): Sub-detector invocation order enforced in body
   --  @relation(FUNC-CAP-011): Single Capture_Current call per Detect invocation
   --  @relation(FUNC-CAP-014): Every Detect call performs a full detection run
   function Detect
     (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
      return Terminal_Capabilities;

   --  @summary Return a cached Terminal_Capabilities value for the given stream.
   --  @description On the first call for a given Stream, invokes Detect and
   --  caches the result in a thread-safe protected object (FUNC-CAP-008).
   --  Subsequent calls for the same Stream return the cached value without
   --  re-running any sub-detector.  The cache reflects the override state at
   --  the time the cache slot was first populated (FUNC-CAP-006).
   --  @param Stream The stream for which capabilities are requested.
   --  @return A Terminal_Capabilities record; a copy of the cached value.
   --  @relation(FUNC-CAP-003): Lazy per-stream caching
   --  @relation(FUNC-CAP-005): Default Stream => Stdout for the common case
   --  @relation(FUNC-CAP-008): Thread safety via protected object in body
   --  @relation(FUNC-CAP-009): Returned record is a copy; cache is not aliased
   function Get
     (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
      return Terminal_Capabilities;

end Termicap.Capabilities;
