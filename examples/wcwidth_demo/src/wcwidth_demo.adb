-------------------------------------------------------------------------------
--  Wcwidth_Demo - Usage example for Termicap.Wcwidth
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates wcwidth() probing for Unicode level detection.
--
--  @description
--  This program showcases the typical caller sequence for the WCWIDTH feature:
--
--    1. Basic probe: call Probe_Wcwidth_Level and print the result.
--    2. Integration: combine the env-var-based Unicode_Level with the wcwidth
--       probe result via Refine_Unicode_Level.
--    3. Sentinel constants: print the three sentinel codepoint values for
--       reference.
--
--  NOTE: Probe_Wcwidth_Level requires setlocale(LC_CTYPE, "") to have been
--  called before the probe.  Ada's runtime performs locale initialisation
--  at program startup on GNAT/Linux, so this requirement is satisfied
--  automatically in practice.

with Ada.Text_IO;

with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Unicode;
with Termicap.Wcwidth;

procedure Wcwidth_Demo is

   package IO renames Ada.Text_IO;

   --  Codepoint_IO: print Unicode codepoint values in Ada hex notation
   --  (16#XXXX#), which is the idiomatic Ada representation for hex literals.
   type Codepoint is range 0 .. 16#1FFFFF#;
   package Codepoint_IO is new Ada.Text_IO.Integer_IO (Codepoint);

   ---------------------------------------------------------------------------
   --  Helper: print a codepoint value in Ada hex literal notation.
   ---------------------------------------------------------------------------

   procedure Put_Codepoint (Value : Codepoint) is
   begin
      Codepoint_IO.Put (Item  => Value,
                        Width => 0,
                        Base  => 16);
      --  Output format: "16#XXXX#" (Ada hex literal notation).
   end Put_Codepoint;

   ---------------------------------------------------------------------------
   --  Local helper: human-readable Unicode_Level label.
   ---------------------------------------------------------------------------

   function Unicode_Level_Image
     (Level : Termicap.Unicode.Unicode_Level) return String
   is
   begin
      case Level is
         when Termicap.Unicode.None     => return "None (no Unicode support detected)";
         when Termicap.Unicode.Basic    => return "Basic (UTF-8 locale, Unicode 3 / 13)";
         when Termicap.Unicode.Extended => return "Extended (modern Unicode 16+ support)";
      end case;
   end Unicode_Level_Image;

   ---------------------------------------------------------------------------
   --  Local helper: human-readable Wcwidth_Level label.
   ---------------------------------------------------------------------------

   function Wcwidth_Level_Image
     (Level : Termicap.Wcwidth.Wcwidth_Level) return String
   is
   begin
      case Level is
         when Termicap.Wcwidth.Unknown    =>
            return "Unknown    (probe inconclusive, or locale is C / POSIX)";
         when Termicap.Wcwidth.Unicode_3  =>
            return "Unicode_3  (locale supports at least Unicode 3.0)";
         when Termicap.Wcwidth.Unicode_13 =>
            return "Unicode_13 (locale supports at least Unicode 13.0)";
         when Termicap.Wcwidth.Unicode_16 =>
            return "Unicode_16 (locale supports at least Unicode 16.0)";
      end case;
   end Wcwidth_Level_Image;

   ---------------------------------------------------------------------------
   --  Local variables
   ---------------------------------------------------------------------------

   Env         : Termicap.Environment.Environment;
   Env_Level   : Termicap.Unicode.Unicode_Level;
   Wcw_Level   : Termicap.Wcwidth.Wcwidth_Level;
   Final_Level : Termicap.Unicode.Unicode_Level;

begin

   IO.Put_Line ("=== Termicap.Wcwidth Demo ===");
   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 1: Sentinel codepoint constants
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Sentinel Codepoint Constants (FUNC-WCW-002) ---");
   IO.Put_Line ("These three codepoints are used to probe the C locale wcwidth() tables.");
   IO.Put_Line ("Each was introduced in a specific Unicode version; a positive wcwidth()");
   IO.Put_Line ("result confirms the locale's character width tables cover that version.");
   IO.New_Line;

   IO.Put ("  WCW_SENTINEL_UNI3  = ");
   Put_Codepoint (Codepoint (Termicap.Wcwidth.WCW_SENTINEL_UNI3));
   IO.Put_Line ("  -- BRAILLE PATTERN DOTS-12345678, Unicode 3.0, Braille Patterns block");

   IO.Put ("  WCW_SENTINEL_UNI13 = ");
   Put_Codepoint (Codepoint (Termicap.Wcwidth.WCW_SENTINEL_UNI13));
   IO.Put_Line ("  -- UPPER LEFT BLOCK SEXTANT, Unicode 13.0, Symbols for Legacy Computing");

   IO.Put ("  WCW_SENTINEL_UNI16 = ");
   Put_Codepoint (Codepoint (Termicap.Wcwidth.WCW_SENTINEL_UNI16));
   IO.Put_Line ("  -- Symbols for Legacy Computing Supplement, Unicode 16.0");

   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 2: Basic probe
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Basic Probe (FUNC-WCW-003) ---");
   IO.Put_Line ("Calling Probe_Wcwidth_Level ...");
   IO.Put_Line ("  The probe tests sentinels in descending order (16 -> 13 -> 3)");
   IO.Put_Line ("  for early exit on modern systems.");
   IO.New_Line;

   Wcw_Level := Termicap.Wcwidth.Probe_Wcwidth_Level;

   IO.Put_Line ("  Result: " & Wcwidth_Level_Image (Wcw_Level));
   IO.New_Line;

   IO.Put_Line ("  The result is cached after the first call (FUNC-WCW-010).");
   IO.Put_Line ("  A second call returns the cached value without additional FFI calls:");

   declare
      Cached : constant Termicap.Wcwidth.Wcwidth_Level :=
                 Termicap.Wcwidth.Probe_Wcwidth_Level;
   begin
      IO.Put_Line ("  Cached result: " & Wcwidth_Level_Image (Cached));
   end;

   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 3: Integration with Termicap.Unicode (FUNC-WCW-005)
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Integration with Unicode Detection (FUNC-WCW-005) ---");
   IO.Put_Line ("Typical caller sequence:");
   IO.Put_Line ("  1. Capture the current process environment snapshot");
   IO.Put_Line ("  2. Detect the env-var-based Unicode level (Termicap.Unicode)");
   IO.Put_Line ("  3. Obtain the wcwidth probe result (Termicap.Wcwidth)");
   IO.Put_Line ("  4. Call Refine_Unicode_Level to produce the final level");
   IO.New_Line;

   --  Step 1: capture the current process environment.
   Termicap.Environment.Capture.Capture_Current (Env);

   --  Step 2: env-var-based Unicode detection (pure, SPARK Silver).
   Env_Level := Termicap.Unicode.Detect_Unicode_Level (Env);
   IO.Put_Line ("  Env_Level   (env-var cascade result) : " & Unicode_Level_Image (Env_Level));

   --  Step 3: wcwidth probe result (cached from the call in Section 2 above).
   IO.Put_Line ("  Wcw_Level   (wcwidth() probe result) : " & Wcwidth_Level_Image (Wcw_Level));

   --  Step 4: combine — the probe may upgrade but never downgrades Env_Level.
   Final_Level := Termicap.Wcwidth.Refine_Unicode_Level (Env_Level, Wcw_Level);
   IO.Put_Line ("  Final_Level (refined, upgrade-only)  : " & Unicode_Level_Image (Final_Level));

   IO.New_Line;

   ---------------------------------------------------------------------------
   --  Section 4: Refine_Unicode_Level mapping summary (FUNC-WCW-004)
   ---------------------------------------------------------------------------

   IO.Put_Line ("--- Refine_Unicode_Level Mapping Rules (FUNC-WCW-004) ---");
   IO.Put_Line ("  Wcw_Level = Unknown    => Final = Env_Level          (no change)");
   IO.Put_Line ("  Wcw_Level = Unicode_3  => Final = max(Env_Level, Basic)");
   IO.Put_Line ("  Wcw_Level = Unicode_13 => Final = max(Env_Level, Basic)");
   IO.Put_Line ("  Wcw_Level = Unicode_16 => Final = max(Env_Level, Extended)");
   IO.New_Line;
   IO.Put_Line ("  The probe may upgrade but NEVER downgrades the env-var result.");
   IO.New_Line;

   IO.Put_Line ("=== Demo complete ===");

end Wcwidth_Demo;
