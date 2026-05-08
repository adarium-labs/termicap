-------------------------------------------------------------------------------
--  Termicap.Graphics.IO - Sixel / Kitty Graphics Detection I/O Orchestration
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Platform-dispatched I/O orchestration for Sixel / Kitty graphics protocol
--  detection: caching entry point and cache-bypass probe.
--
--  @description
--  This child package provides the two public entry points for graphics
--  protocol detection:
--
--    Detect_Graphics          — cached, process-lifetime result.
--    Detect_Graphics_Uncached — uncached, always runs the full cascade.
--
--  Detect_Graphics implements the detection cascade (FUNC-SXL-012):
--    Guard 4 (Windows only): Win32 Console gate — if GetConsoleMode succeeds
--      on STD_OUTPUT_HANDLE, skip all active probes and return the result of
--      passive env-var heuristics only (Probed = False).
--    Guard 1 (POSIX first): Non-TTY guard — if Is_TTY (Stdout) = False,
--      skip all active probes and return passive env-var heuristics only.
--    Guards 2+3: Foreground guard + /dev/tty openability, composed inside
--      Probe_Session.Open.
--  If all guards pass, the cascade runs:
--    Step 1: Passive Kitty env-var harvest (FUNC-SXL-009) — independent of TTY.
--    Step 2: Passive Sixel env-var harvest (FUNC-SXL-008) — independent of TTY.
--    Step 3: DA1 active probe for Sixel Ps=4 (FUNC-SXL-005, FUNC-SXL-006),
--      using Termicap.DA1.IO.Detect_DA1; sets Sixel_Via_DA1 and Probed on
--      success.
--    Step 4: XTVERSION name-substring fallback for Sixel (FUNC-SXL-007),
--      skipped when Sixel_Via_DA1 = True.
--    Step 5: Optional Kitty APC active probe (FUNC-SXL-010), skipped when
--      Kitty_Graphics_Supported is already True from env-var harvest.
--  The result is stored in a package-level protected object after the first
--  call and returned from the cache on all subsequent calls (FUNC-SXL-017).
--
--  The no-exception guarantee (FUNC-SXL-016) means any failure degrades
--  gracefully: partial results are preserved; total failures return
--  NO_GRAPHICS_CAPABILITIES (Probed = False).  Terminal attributes are
--  restored on every exit path from raw-mode sections (FUNC-SXL-014).
--
--  Detect_Graphics_Uncached runs the identical cascade without consulting or
--  updating the cache, intended for test harnesses and edge cases where a
--  fresh probe is needed (FUNC-SXL-017 Should clause).
--
--  I/O is performed exclusively through Termicap.OSC.Probe_Session,
--  Termicap.OSC.Write_Query, and Termicap.OSC.Sentinel_Query; no direct
--  tcgetattr / tcsetattr / select / read / write calls are made.  Termios
--  restore is guaranteed by the RAII semantics of Probe_Session's
--  Ada.Finalization.Limited_Controlled base (FUNC-SXL-014).
--
--  Platform differences are isolated in two separate body files:
--    src/posix/termicap-graphics-io.adb   — cascade starts at TTY guard.
--    src/windows/termicap-graphics-io.adb — cascade starts at Win32 gate
--      (FUNC-SXL-012 Guard 4 evaluated first on Windows per requirement).
--  The single shared spec here allows the project's GPR source-dir mechanism
--  to select exactly one body file per platform without any conditional
--  compilation in the spec, keeping Win32 dependencies out of POSIX object
--  files entirely (ADR-0018).
--
--  This package is SPARK_Mode Off because it depends on Ada.Finalization
--  controlled types (Probe_Session), terminal I/O, and the protected-object
--  cache; all are outside the SPARK 2014 language subset.  The pure type
--  definitions, named constants, and parser function remain provable in the
--  parent package Termicap.Graphics (SPARK_Mode On).
--
--  Requirements Coverage:
--    - @relation(FUNC-SXL-005): Sixel detection via DA1 Has_Capability
--    - @relation(FUNC-SXL-006): DA1 probe session via OSC-INFRA
--    - @relation(FUNC-SXL-007): XTVERSION name-substring Sixel fallback
--    - @relation(FUNC-SXL-008): Env-var Sixel heuristics
--    - @relation(FUNC-SXL-009): Env-var Kitty heuristics
--    - @relation(FUNC-SXL-010): Optional Kitty APC active probe
--    - @relation(FUNC-SXL-012): Pre-condition guards and TTY guards
--    - @relation(FUNC-SXL-013): No-TTY passive fallback
--    - @relation(FUNC-SXL-014): Termios restore on all exit paths via RAII
--    - @relation(FUNC-SXL-015): 1000 ms independent per-session timeout
--    - @relation(FUNC-SXL-016): No-exception guarantee for Detect_Graphics
--    - @relation(FUNC-SXL-017): One-probe-per-process cache; uncached bypass
--    - @relation(FUNC-SXL-018): Package structure and SPARK boundary

pragma SPARK_Mode (Off);

with Termicap.Environment;
with Termicap.XTVERSION;

package Termicap.Graphics.IO is

   ---------------------------------------------------------------------------
   --  Cached Detection Entry Point (FUNC-SXL-016, FUNC-SXL-017)
   ---------------------------------------------------------------------------

   --  @summary Detect Sixel and Kitty graphics protocol support, returning a
   --  cached result on all subsequent calls after the first.
   --  @description Implements the platform cascade (FUNC-SXL-012):
   --    Guard 4 (Windows): GetConsoleMode (STD_OUTPUT_HANDLE) — on success,
   --      return Graphics_Capabilities from passive env-var heuristics only
   --      (Probed = False, Sixel_Via_DA1 = False, Kitty_Via_Active_Probe =
   --      False) (FUNC-SXL-012 Guard 4).
   --    Guard 1: Is_TTY (Stdout) = False — return passive env-var heuristics
   --      only (FUNC-SXL-013).
   --    Guards 2+3: Foreground + /dev/tty open (composed inside Probe_Session).
   --    Passive Kitty env-var harvest: KITTY_WINDOW_ID, TERM=xterm-kitty,
   --      TERM_PROGRAM=WezTerm (FUNC-SXL-009).
   --    Passive Sixel env-var harvest: TERM_PROGRAM=WezTerm, known TERM values,
   --      xterm prefix match (FUNC-SXL-008).
   --    DA1 probe for Sixel: Termicap.DA1.IO.Detect_DA1; sets Sixel_Via_DA1
   --      and Probed when Has_Capability returns True for Sixel_Graphics
   --      (FUNC-SXL-005).
   --    XTVERSION fallback: case-insensitive name-substring match for "kitty"
   --      and "WezTerm" when Sixel_Via_DA1 is False (FUNC-SXL-007).
   --    Optional Kitty APC probe: ESC _ G i=1,a=q ESC \ + DA1 sentinel;
   --      only when Kitty_Graphics_Supported is still False (FUNC-SXL-010).
   --  The result is stored in a package-level protected object after the first
   --  call and returned from the cache on all subsequent calls (FUNC-SXL-017).
   --  This function never propagates an exception under any circumstances;
   --  any failure path returns NO_GRAPHICS_CAPABILITIES or a partial result
   --  (FUNC-SXL-016).  Terminal attributes are restored on every exit path
   --  including error and timeout (FUNC-SXL-014).
   --  @return Graphics_Capabilities with the detected support flags, provenance
   --          fields, and Probed metadata.  Returns NO_GRAPHICS_CAPABILITIES
   --          on complete failure.
   --  @relation(FUNC-SXL-012): Full detection cascade with guards
   --  @relation(FUNC-SXL-016): No-exception guarantee
   --  @relation(FUNC-SXL-017): One-probe-per-process caching
   function Detect_Graphics return Graphics_Capabilities;

   ---------------------------------------------------------------------------
   --  Cache-Bypass Detection (FUNC-SXL-017 Should Clause)
   ---------------------------------------------------------------------------

   --  @summary Run the full graphics detection cascade without consulting or
   --  updating the process-lifetime cache.
   --  @description Executes the identical platform cascade as Detect_Graphics
   --  (all guards + passive harvest + DA1 probe + XTVERSION fallback + optional
   --  Kitty APC probe) but does not read from or write to the protected-object
   --  cache.  Intended for test harnesses that need a fresh probe result (e.g.,
   --  after a terminal change) and for integration tests that must verify
   --  detection behaviour in isolation from the cache.
   --  Like Detect_Graphics, this function never propagates an exception; any
   --  failure path returns NO_GRAPHICS_CAPABILITIES or a partial result
   --  (FUNC-SXL-016).
   --  @return Graphics_Capabilities from a fresh cascade execution.
   --  @relation(FUNC-SXL-017): Cache-bypass detection for test use
   --  @relation(FUNC-SXL-016): No-exception guarantee
   function Detect_Graphics_Uncached return Graphics_Capabilities;

   ---------------------------------------------------------------------------
   --  Pure passive-harvest helpers (FUNC-SXL-008, conformance B2)
   ---------------------------------------------------------------------------

   --  @summary Return True when env-var heuristics indicate Sixel support.
   --  @description Pure inspection of a captured Environment snapshot using
   --  the post-B2a allowlist:
   --    Step 1: TERM_PROGRAM = WezTerm (case-insensitive)
   --    Step 2: TERM in {foot, foot-extra, mlterm, mlterm-256color, yaft}
   --      (case-insensitive)
   --  No fallback "TERM prefix xterm" rule (removed in B2a) and no
   --  TERM=xterm-kitty (removed because kitty does not implement sixel).
   --  Used by the cascade as the passive prelude to the DA1 active probe;
   --  exposed publicly to support deterministic regression tests.
   --  @param Env Captured environment snapshot.
   --  @return True when one of the high-signal env-var heuristics fires.
   --  @relation(FUNC-SXL-008): Passive Sixel env-var heuristics
   function Has_Sixel_From_Env (Env : Termicap.Environment.Environment) return Boolean;

   ---------------------------------------------------------------------------
   --  XTVERSION-driven Kitty graphics refinement (conformance B3a)
   ---------------------------------------------------------------------------

   --  @summary Refine a passive Graphics_Capabilities result using XTVERSION.
   --  @description Mirrors Termicap.Hyperlinks.Refine_With_XTVERSION
   --  (FUNC-HYP-011): when the XTVERSION query succeeded and the reported
   --  terminal name is in the curated Kitty graphics known-good table, the
   --  result is promoted to Kitty_Graphics_Supported = True.  Strict-version
   --  entries (iterm2 >= 3.6.0, kitty >= 0.20.0, konsole >= 22.4.0) require a
   --  parseable version that meets the minimum; "any" entries (wezterm,
   --  ghostty) promote on a name match alone.  When XTVERSION did not
   --  succeed, when the name is unknown, or when the parsed version is below
   --  the minimum, Passive is returned unchanged.
   --
   --  This function does NOT downgrade a passive positive: a name absent from
   --  the table or a strict-version entry with a too-low version simply
   --  leaves the existing Kitty support flag (typically False on entry) in
   --  place, since the active APC probe is the only authority that downgrades
   --  Kitty graphics support.
   --
   --  @param Passive  The passive (env + APC-probe) Graphics_Capabilities.
   --  @param XTV      The XTVERSION query result.
   --  @return A copy of Passive with Kitty_Graphics_Supported = True when the
   --          known-good check passes; Passive unchanged otherwise.
   --  @relation(FUNC-SXL-010): Kitty graphics refinement via XTVERSION
   function Refine_Kitty_With_XTVERSION
     (Passive : Graphics_Capabilities; XTV : Termicap.XTVERSION.XTVERSION_Result) return Graphics_Capabilities;

end Termicap.Graphics.IO;
