-------------------------------------------------------------------------------
--  Termicap.Capabilities - Terminal Capability Record Assembly
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Aggregates all sub-detector results into Terminal_Capabilities (fast) and
--  Full_Terminal_Capabilities (all Tier 4 probes), each with cached (Get/Get_Full)
--  and fresh (Detect/Detect_Full) detection entry points.
--
--  @description
--  This package is the primary integration point for applications that need
--  all terminal capability information in a single call.  Rather than invoking
--  each sub-detector independently, callers use Get (lazy cached) or Detect
--  (always fresh) to obtain a fully populated Terminal_Capabilities snapshot.
--
--  For applications that additionally need keyboard protocol, mouse encoding,
--  graphics (Sixel / Kitty), OSC 52 clipboard, or active XTVERSION terminal
--  identification, use Get_Full or Detect_Full.  These lift the ADR-0021,
--  ADR-0026, ADR-0028, and ADR-0031 deferrals at the cost of a higher worst-case
--  detection latency (~6 s vs ~150 ms for the base variant).
--
--  The pure assembly function Assemble is SPARK Silver-provable (Global => null)
--  and carries a postcondition that proves Downsampling_Available is consistent
--  with the Color field.  Detect and Get delegate to OS-calling sub-detectors
--  and are therefore not given SPARK Global contracts.  Assemble_Full, Detect_Full,
--  and Get_Full are declared with SPARK_Mode Off because Full_Terminal_Capabilities
--  contains Ada.Strings.Unbounded.Unbounded_String (via XTVERSION_Result).
--
--  Requirements Coverage:
--    - @relation(FUNC-HYP-014): Hyperlinks field in Terminal_Capabilities; Assemble parameter
--    - @relation(FUNC-HYP-015): Hyperlinks field in Full_Terminal_Capabilities; Assemble_Full parameter
--    - @relation(FUNC-CAP-001): Terminal_Capabilities record type
--    - @relation(FUNC-CAP-002): Stream selection for per-stream color detection
--    - @relation(FUNC-CAP-003): Get function Ã¢ÂÂ cached lazy initialisation
--    - @relation(FUNC-CAP-004): Detect function Ã¢ÂÂ fresh detection
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

with Termicap.Clipboard;
with Termicap.Color;
with Termicap.DA1;
with Termicap.Dimensions;
with Termicap.Graphics;
with Termicap.Hyperlinks;
with Termicap.Keyboard;
with Termicap.Mouse;
with Termicap.Terminal_Id;
with Termicap.TTY;
with Termicap.Unicode;
with Termicap.XTVERSION;

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
   --  @relation(FUNC-CAP-009): Plain Ada record Ã¢ÂÂ value semantics, no aliasing
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
      --  @relation(FUNC-HYP-014): Passive OSC 8 hyperlink classification
      Hyperlinks             : Termicap.Hyperlinks.Hyperlinks_Result := Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT;
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
   --  @relation(FUNC-CAP-012): SPARK Silver Ã¢ÂÂ Global => null, provable postcondition
   --  @relation(FUNC-CAP-013): No FFI Ã¢ÂÂ all inputs supplied as parameters
   --  @param DA1        DA1 primary device attributes result.
   --  @param Hyperlinks Passive OSC 8 hyperlink classification result.
   --  @relation(FUNC-DA1-015): DA1 parameter added to Assemble
   --  @relation(FUNC-HYP-014): Hyperlinks parameter added to Assemble
   function Assemble
     (TTY_Stdin  : Boolean;
      TTY_Stdout : Boolean;
      TTY_Stderr : Boolean;
      Color      : Termicap.Color.Color_Level;
      Size       : Termicap.Dimensions.Terminal_Size;
      Unicode    : Termicap.Unicode.Unicode_Level;
      Identity   : Termicap.Terminal_Id.Terminal_Identity;
      DA1        : Termicap.DA1.DA1_Capabilities;
      Hyperlinks : Termicap.Hyperlinks.Hyperlinks_Result := Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT)
      return Terminal_Capabilities
   with
     SPARK_Mode => On,
     Global => null,
     Post => Assemble'Result.Downsampling_Available = (Assemble'Result.Color >= Termicap.Color.Extended_256);

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
   --  @relation(FUNC-CAP-004): Fresh detection Ã¢ÂÂ no cache read or write
   --  @relation(FUNC-CAP-005): Default Stream => Stdout for the common case
   --  @relation(FUNC-CAP-006): Override applied via Detect_Color_Level
   --  @relation(FUNC-CAP-007): TTY override applied via Is_TTY / Query_All
   --  @relation(FUNC-CAP-010): Sub-detector invocation order enforced in body
   --  @relation(FUNC-CAP-011): Single Capture_Current call per Detect invocation
   --  @relation(FUNC-CAP-014): Every Detect call performs a full detection run
   function Detect (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Terminal_Capabilities;

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
   function Get (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Terminal_Capabilities;

   ---------------------------------------------------------------------------
   --  Full Detection (SPARK_Mode Off)
   --
   --  The following declarations extend Terminal_Capabilities with all Tier 4
   --  deferred probes (XTVERSION, Keyboard, Mouse, Graphics, Clipboard).
   --  SPARK_Mode is switched Off here because Termicap.XTVERSION.XTVERSION_Result
   --  contains Ada.Strings.Unbounded.Unbounded_String, which is outside the SPARK
   --  2014 subset.  The base record and Assemble function above remain SPARK Silver.
   --
   --  Requirements lifted from deferral:
   --    - @relation(FUNC-KKB-019): Keyboard field in Full_Terminal_Capabilities (ADR-0021)
   --    - @relation(FUNC-MSE-019): Mouse field in Full_Terminal_Capabilities (ADR-0026)
   --    - @relation(FUNC-SXL-019): Graphics field in Full_Terminal_Capabilities (ADR-0028)
   --    - @relation(FUNC-C52-019): Clipboard field in Full_Terminal_Capabilities (ADR-0031)
   ---------------------------------------------------------------------------

   pragma SPARK_Mode (Off);

   ---------------------------------------------------------------------------
   --  Full Record Type
   ---------------------------------------------------------------------------

   --  @summary Aggregated terminal capability snapshot including all Tier 4 probes.
   --  @description Flat record containing all base fields (TTY, Color, Size,
   --  Unicode, Identity, Downsampling_Available, DA1) plus XTVERSION active
   --  terminal identification, keyboard protocol, mouse protocol, graphics
   --  (Sixel / Kitty), and OSC 52 clipboard detection.  All fields are directly
   --  accessible without indirection.  Callers that do not need Tier 4
   --  information should continue using Terminal_Capabilities via Get / Detect.
   --  @field XTVERSION  Active terminal name/version identification result.
   --  @field Keyboard   Keyboard protocol detection result (Kitty / XTerm CSI / Legacy).
   --  @field Mouse      Mouse encoding detection result (SGR_Pixels / SGR / URXVT / X10).
   --  @field Graphics   Sixel and Kitty graphics protocol detection result.
   --  @field Clipboard  OSC 52 clipboard access level detection result.
   --  @field Hyperlinks XTVERSION-refined OSC 8 hyperlink classification (FUNC-HYP-015).
   --                    The base passive classification lives in
   --                    Terminal_Capabilities.Hyperlinks; the field here carries
   --                    the refined value produced by
   --                    Termicap.Hyperlinks.Refine_With_XTVERSION using the
   --                    XTVERSION result already collected by Detect_Full
   --                    Step 9 (ADR-0038).
   type Full_Terminal_Capabilities is record
      TTY_Stdin              : Boolean;
      TTY_Stdout             : Boolean;
      TTY_Stderr             : Boolean;
      Color                  : Termicap.Color.Color_Level;
      Size                   : Termicap.Dimensions.Terminal_Size;
      Unicode                : Termicap.Unicode.Unicode_Level;
      Identity               : Termicap.Terminal_Id.Terminal_Identity;
      Downsampling_Available : Boolean;
      DA1                    : Termicap.DA1.DA1_Capabilities;
      XTVERSION              : Termicap.XTVERSION.XTVERSION_Result;
      Keyboard               : Termicap.Keyboard.Keyboard_Capability;
      Mouse                  : Termicap.Mouse.Mouse_Capabilities;
      Graphics               : Termicap.Graphics.Graphics_Capabilities;
      Clipboard              : Termicap.Clipboard.Clipboard_Capabilities;
      --  @relation(FUNC-HYP-015): Hyperlinks field in Full_Terminal_Capabilities
      Hyperlinks             : Termicap.Hyperlinks.Hyperlinks_Result := Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT;
   end record;

   ---------------------------------------------------------------------------
   --  Full Assembly
   ---------------------------------------------------------------------------

   --  @summary Assemble a Full_Terminal_Capabilities record from pre-computed results.
   --  @description Pure function (no global state, no I/O).  Constructs the record
   --  by extending an already-assembled Terminal_Capabilities value with the five
   --  Tier 4 sub-detector results.  Called internally by Detect_Full; may also be
   --  called directly by test code with known inputs.
   --  @param Base       Already-assembled base capability snapshot (parent view).
   --  @param XTVERSION  Result of the XTVERSION active probe.
   --  @param Keyboard   Result of keyboard protocol detection.
   --  @param Mouse      Result of mouse protocol detection.
   --  @param Graphics   Result of graphics (Sixel / Kitty) detection.
   --  @param Clipboard  Result of OSC 52 clipboard detection.
   --  @param Hyperlinks Refined OSC 8 hyperlink classification (FUNC-HYP-015).
   --                    Defaults to Base.Hyperlinks (i.e. the unrefined passive
   --                    value) so callers that do not yet supply the refinement
   --                    keep the previous behaviour.
   --  @return A fully populated Full_Terminal_Capabilities record.
   function Assemble_Full
     (Base       : Terminal_Capabilities;
      XTVERSION  : Termicap.XTVERSION.XTVERSION_Result;
      Keyboard   : Termicap.Keyboard.Keyboard_Capability;
      Mouse      : Termicap.Mouse.Mouse_Capabilities;
      Graphics   : Termicap.Graphics.Graphics_Capabilities;
      Clipboard  : Termicap.Clipboard.Clipboard_Capabilities;
      Hyperlinks : Termicap.Hyperlinks.Hyperlinks_Result := Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT)
      return Full_Terminal_Capabilities;

   ---------------------------------------------------------------------------
   --  Full Detection Functions
   ---------------------------------------------------------------------------

   --  @summary Perform a complete uncached detection including all Tier 4 probes.
   --  @description Invokes all sub-detectors in dependency order, then additionally
   --  runs the five Tier 4 probes listed below.  Does not read or write the cache
   --  used by Get or Get_Full.
   --
   --  Sub-detector invocation order:
   --    Steps 1-8: identical to Detect (Env, Terminal_Id, TTY, Color, Size, Unicode,
   --               DA1) Ã¢ produces the Base field.
   --    Step 9:  XTVERSION active probe Ã¢ terminal name/version identification.
   --             Run before Graphics so that the Graphics detector can consume
   --             the XTVERSION name tokens (kitty, WezTerm) for passive Sixel
   --             identification (FUNC-SXL-007).
   --    Step 10: Graphics detection Ã¢ uses Base.DA1 (Ps=4 for Sixel) and the
   --             XTVERSION result (name tokens) to avoid re-probing DA1.
   --    Step 11: Keyboard protocol detection Ã¢ independent of other Tier 4 probes.
   --    Step 12: Mouse protocol detection Ã¢ independent of other Tier 4 probes.
   --    Step 13: Clipboard detection Ã¢ uses Base.DA1 (Ps=52) to seed the cascade
   --             before the optional active OSC 52 probe.
   --
   --  Worst-case latency: ~6 s (DA1 100 ms + XTVERSION 1 s + Graphics 2 s +
   --  Keyboard 2 s + Mouse 1 s + Clipboard 1 s, all timing out).  Common-case
   --  latency on a local PTY is well under 500 ms total.
   --
   --  @param Stream The stream for which Color and TTY flags are computed.
   --                Size is always derived from stdout (same as Detect).
   --  @return A Full_Terminal_Capabilities record reflecting terminal state at
   --          the moment of the call.
   function Detect_Full (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Full_Terminal_Capabilities;

   --  @summary Return a cached Full_Terminal_Capabilities value for the given stream.
   --  @description On the first call for a given Stream, invokes Detect_Full and
   --  caches the result in a thread-safe protected object.  Subsequent calls for
   --  the same Stream return the cached value without re-running any sub-detector.
   --  The Full cache is separate from the base Get cache; calling Get does not
   --  populate the Get_Full cache and vice versa.
   --  @param Stream The stream for which full capabilities are requested.
   --  @return A Full_Terminal_Capabilities record; a copy of the cached value.
   function Get_Full (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Full_Terminal_Capabilities;

end Termicap.Capabilities;
