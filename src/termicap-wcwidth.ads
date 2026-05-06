-------------------------------------------------------------------------------
--  Termicap.Wcwidth - wcwidth() Probing for Unicode Level
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Probes the POSIX C library wcwidth() function to determine the Unicode
--  version supported by the terminal's C runtime locale.
--
--  @description
--  This package provides fine-grained Unicode version detection by calling
--  wcwidth() on three sentinel codepoints, each introduced in a specific
--  Unicode version.  The probe result is expressed as a Wcwidth_Level
--  enumeration (Unknown, Unicode_3, Unicode_13, Unicode_16) that can be
--  integrated with the environment-variable-based Unicode_Level result from
--  Termicap.Unicode via the pure Refine_Unicode_Level function.
--
--  The probe function body is SPARK_Mode => Off (C FFI).  The result type,
--  sentinel constants, and integration function are SPARK_Mode => On and
--  Silver-provable.
--
--  Threading constraints (FUNC-WCW-009):
--    Probe_Wcwidth_Level is safe to call from multiple threads provided no
--    thread is changing the locale (setlocale()) concurrently.  The
--    recommended usage is to call Probe_Wcwidth_Level once at process
--    initialisation, before application threads are spawned.
--
--  Locale requirement (FUNC-WCW-006):
--    Probe_Wcwidth_Level must be called only after setlocale(LC_CTYPE, "")
--    (or equivalent) has been invoked by the application.  The library does
--    not call setlocale() itself.  If the current LC_CTYPE locale is "C" or
--    "POSIX" at probe time, Probe_Wcwidth_Level returns Unknown immediately
--    without calling wcwidth().
--
--  Typical caller sequence:
--    Env_Level   := Termicap.Unicode.Detect_Unicode_Level (Env);
--    Wcw_Level   := Termicap.Wcwidth.Probe_Wcwidth_Level;
--    Final_Level := Termicap.Wcwidth.Refine_Unicode_Level (Env_Level, Wcw_Level);
--
--  Requirements Coverage:
--    - @relation(FUNC-WCW-002): Sentinel codepoint constants
--    - @relation(FUNC-WCW-004): Wcwidth_Level result enumeration
--    - @relation(FUNC-WCW-005): Refine_Unicode_Level integration function
--    - @relation(FUNC-WCW-006): Locale initialisation requirement (documented)
--    - @relation(FUNC-WCW-008): SPARK boundary
--    - @relation(FUNC-WCW-009): Thread safety constraints (documented)
--    - @relation(FUNC-WCW-010): Optional_Wcwidth_Level type for caching
--    - @relation(FUNC-WCW-012): Public API specification

with Termicap.Unicode;

package Termicap.Wcwidth
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Sentinel Codepoint Constants (FUNC-WCW-002)
   ---------------------------------------------------------------------------

   --  @summary Unicode codepoint sentinel for Unicode 3.0 detection.
   --  @description U+28FF BRAILLE PATTERN DOTS-12345678.
   --  Introduced in Unicode 3.0 (Braille Patterns block, U+2800Ã¢ÂÂU+28FF).
   --  A wcwidth() return value >= 1 for this codepoint confirms that the
   --  locale's character width tables include at least Unicode 3.0.
   --  @relation(FUNC-WCW-002): Sentinel codepoint for Unicode 3.0
   WCW_SENTINEL_UNI3 : constant := 16#28FF#;

   --  @summary Unicode codepoint sentinel for Unicode 13.0 detection.
   --  @description U+1FB38 UPPER LEFT BLOCK SEXTANT-2 AND 5 AND 6.
   --  Introduced in Unicode 13.0 (Symbols for Legacy Computing block,
   --  U+1FB00Ã¢ÂÂU+1FBFF).  A wcwidth() return value >= 1 for this codepoint
   --  confirms that the locale's character width tables include at least
   --  Unicode 13.0.
   --  @relation(FUNC-WCW-002): Sentinel codepoint for Unicode 13.0
   WCW_SENTINEL_UNI13 : constant := 16#1FB38#;

   --  @summary Unicode codepoint sentinel for Unicode 16.0 detection.
   --  @description U+1CD00 (Symbols for Legacy Computing Supplement block).
   --  Introduced in Unicode 16.0.  A wcwidth() return value >= 1 for this
   --  codepoint confirms that the locale's character width tables include at
   --  least Unicode 16.0.
   --  @relation(FUNC-WCW-002): Sentinel codepoint for Unicode 16.0
   WCW_SENTINEL_UNI16 : constant := 16#1CD00#;

   ---------------------------------------------------------------------------
   --  Result Type (FUNC-WCW-004)
   ---------------------------------------------------------------------------

   --  @summary Unicode version level determined by wcwidth() probing.
   --  @description Ordered enumeration representing the Unicode version
   --  supported by the terminal's C runtime locale character width tables.
   --  Values are ordered: Unknown < Unicode_3 < Unicode_13 < Unicode_16.
   --  This enables Wcwidth_Level'Max for floor/ceiling operations.
   --
   --  Wcwidth_Level is distinct from Termicap.Unicode.Unicode_Level:
   --    - The probe distinguishes three positive levels (Unicode 3, 13, 16)
   --      whereas Unicode_Level has only two (Basic, Extended).
   --    - Unknown means "probe not performed or inconclusive", which is
   --      semantically different from Unicode_Level's None ("confirmed no
   --      Unicode support").
   --    - Decoupling allows each feature to evolve independently.
   --
   --  Mapping to Unicode_Level (used by Refine_Unicode_Level, FUNC-WCW-005):
   --    Unknown    -> no upgrade (existing Unicode_Level unchanged)
   --    Unicode_3  -> at least Termicap.Unicode.Basic
   --    Unicode_13 -> at least Termicap.Unicode.Basic
   --    Unicode_16 -> at least Termicap.Unicode.Extended
   --  @relation(FUNC-WCW-004): Wcwidth_Level result enumeration
   type Wcwidth_Level is
     (Unknown,
      --  wcwidth() probe was inconclusive or not performed.
      --  Causes Refine_Unicode_Level to return Env_Level unchanged.
      Unicode_3,
      --  Locale supports at least Unicode 3.0.
      --  U+28FF (WCW_SENTINEL_UNI3) returned column width >= 1.
      Unicode_13,
      --  Locale supports at least Unicode 13.0.
      --  U+1FB38 (WCW_SENTINEL_UNI13) returned column width >= 1.
      Unicode_16
      --  Locale supports at least Unicode 16.0.
      --  U+1CD00 (WCW_SENTINEL_UNI16) returned column width >= 1.
     );

   ---------------------------------------------------------------------------
   --  Optional Wcwidth_Level for Caching (FUNC-WCW-010)
   ---------------------------------------------------------------------------

   --  @summary Discriminated record wrapping an optional Wcwidth_Level value.
   --  @description Used by the package body to implement the probe result
   --  cache.  Is_Set = False indicates the probe has not yet been performed.
   --  Is_Set = True indicates the probe has been performed and Level holds
   --  the result.  Declared in the spec (SPARK-visible) so the type is
   --  available to GNATprove when analysing callers.
   --  @relation(FUNC-WCW-010): Optional cache wrapper type
   type Optional_Wcwidth_Level (Is_Set : Boolean := False) is record
      case Is_Set is
         when True =>
            Level : Wcwidth_Level;

         when False =>
            null;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Probe Function (FUNC-WCW-003, FUNC-WCW-012)
   ---------------------------------------------------------------------------

   --  @summary Probe the locale's wcwidth() support to determine the Unicode
   --  version level of the C runtime character width tables.
   --  @description Calls the POSIX C library wcwidth() function on the three
   --  sentinel codepoints in descending Unicode version order (16 -> 13 -> 3)
   --  for early exit in the common case.  Returns the highest Wcwidth_Level
   --  for which wcwidth() returns a column width >= 1.
   --
   --  The result is cached after the first call.  Subsequent calls return the
   --  cached value immediately without additional wcwidth() calls (FUNC-WCW-010).
   --
   --  Returns Unknown when:
   --    - The current LC_CTYPE locale is "C" or "POSIX" (FUNC-WCW-006).
   --    - setlocale() returns NULL (locale not initialised).
   --    - All sentinel codepoints return -1 or 0 from wcwidth() (FUNC-WCW-007).
   --    - The platform is Windows (no POSIX wcwidth() available) (FUNC-WCW-011).
   --
   --  Precondition (not enforceable at compile time):
   --    setlocale(LC_CTYPE, "") must have been called by the application
   --    before this function (FUNC-WCW-006).
   --
   --  Thread safety (FUNC-WCW-009):
   --    Safe to call from multiple threads provided no concurrent setlocale()
   --    calls are in progress.  Recommended usage: call once at startup.
   --
   --  @return The detected Wcwidth_Level, or Unknown on any failure.
   --  @relation(FUNC-WCW-003): Sentinel probing algorithm
   --  @relation(FUNC-WCW-007): Graceful handling of wcwidth() returning -1
   --  @relation(FUNC-WCW-011): Fallback when probe fails or is inconclusive
   --  @relation(FUNC-WCW-012): Public API specification
   function Probe_Wcwidth_Level return Wcwidth_Level;

   ---------------------------------------------------------------------------
   --  Integration Function (FUNC-WCW-005)
   ---------------------------------------------------------------------------

   --  @summary Combine the env-var Unicode level with the wcwidth probe result.
   --  @description Returns a refined Unicode_Level that is never lower than
   --  Env_Level.  The wcwidth probe may upgrade but never downgrade the
   --  env-var-based result.
   --
   --  Combination rules (FUNC-WCW-004 mapping):
   --    Wcw_Level = Unknown    -> return Env_Level unchanged
   --    Wcw_Level = Unicode_3  -> return Unicode_Level'Max (Env_Level, Basic)
   --    Wcw_Level = Unicode_13 -> return Unicode_Level'Max (Env_Level, Basic)
   --    Wcw_Level = Unicode_16 -> return Unicode_Level'Max (Env_Level, Extended)
   --
   --  This function is pure (Global => null), has no side effects, and is
   --  GNATprove Silver-provable.
   --
   --  @param Env_Level  The Unicode level inferred from environment variables
   --                    (result of Termicap.Unicode.Detect_Unicode_Level).
   --  @param Wcw_Level  The Unicode level determined by wcwidth() probing
   --                    (result of Probe_Wcwidth_Level).
   --  @return The refined Unicode_Level: max(Env_Level, mapped(Wcw_Level)).
   --  @relation(FUNC-WCW-005): Integration with existing Unicode detection cascade
   --  @relation(FUNC-WCW-012): Public API specification
   function Refine_Unicode_Level
     (Env_Level : Termicap.Unicode.Unicode_Level; Wcw_Level : Wcwidth_Level)
      return Termicap.Unicode.Unicode_Level
   with Global => null;

end Termicap.Wcwidth;
