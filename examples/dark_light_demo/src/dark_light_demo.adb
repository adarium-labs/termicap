-------------------------------------------------------------------------------
--  Dark_Light_Demo - Dark / Light Theme Classification Usage Examples
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap dark/light terminal background theme API.
--
--  @description
--  Covers three realistic scenarios:
--
--  Scenario A — Pure classification from a known RGB value:
--    Compute BT.601 luminance and classify a hardcoded dark colour using the
--    SPARK Gold functions Luminance, Classify_Theme, Is_Dark and Is_Light.
--    No terminal I/O is involved; these functions are pure and provable.
--
--  Scenario B — Live terminal theme detection (Detect_Theme):
--    Call Detect_Theme with the default 1-second timeout.  On success, print
--    the detected Theme_Kind and the raw background RGB value.  On failure,
--    print the Detect_Error.  Pattern-match the result with a case statement
--    to show both discriminant branches.
--
--  Scenario C — Conditional output based on detected theme:
--    The primary use case: choose ANSI escape sequences (or any other
--    presentation choice) based on whether the terminal background is dark
--    or light.  Falls back gracefully when detection fails.
--
--  Requirements demonstrated:
--    FUNC-DKL-001  Theme_Kind enumeration
--    FUNC-DKL-002  Luminance computation
--    FUNC-DKL-003  Classify_Theme function
--    FUNC-DKL-004  Is_Dark / Is_Light convenience predicates
--    FUNC-DKL-005  Detect_Theme combined detection + classification
--    FUNC-DKL-006  Theme_Result discriminated record

with Ada.Text_IO;

with Termicap.Color.BG_Query;            use Termicap.Color.BG_Query;
with Termicap.Color.Dark_Light;          use Termicap.Color.Dark_Light;
with Termicap.Color.Dark_Light.Detect;   use Termicap.Color.Dark_Light.Detect;
with Termicap.Color.Detection;           use Termicap.Color.Detection;

procedure Dark_Light_Demo is

   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   --  Render an RGB value as a human-readable "R=NNN G=NNN B=NNN" string.
   function RGB_Image (C : RGB) return String is
   begin
      return
        "R=" & Natural'Image (C.Red)
        & " G=" & Natural'Image (C.Green)
        & " B=" & Natural'Image (C.Blue);
   end RGB_Image;

   --  Render a Detect_Error as a short human-readable string.
   function Error_Name (E : Detect_Error) return String is
   begin
      case E is
         when Not_A_Terminal => return "Not_A_Terminal";
         when Not_Foreground => return "Not_Foreground";
         when Query_Timeout  => return "Query_Timeout";
         when Parse_Failed   => return "Parse_Failed";
         when No_Fallback    => return "No_Fallback";
      end case;
   end Error_Name;

begin

   Ada.Text_IO.Put_Line ("=== Termicap Dark / Light Theme Classification Demo ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO A — Pure classification from a known RGB value
   --
   --  Luminance, Classify_Theme, Is_Dark and Is_Light are SPARK Gold pure
   --  functions with no I/O and no global state.  They can be called freely
   --  from non-terminal contexts (e.g., unit tests, CI pipelines) to classify
   --  any colour without ever opening a terminal.
   --
   --  The BT.601 formula used is:
   --    Y = (299 * R + 587 * G + 114 * B) / 1000
   --  Result range is 0..255.  Values below 128 are Dark; 128 or above are
   --  Light (consistent with the CSS and termenv convention).
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario A: Pure classification from a known RGB value ---");

   declare
      --  A near-black colour — typical dark terminal background.
      Dark_Color  : constant RGB := (Red => 30, Green => 30, Blue => 30);

      --  A near-white colour — typical light terminal background.
      Light_Color : constant RGB := (Red => 240, Green => 240, Blue => 240);
   begin
      --  ---- Dark colour ----
      Ada.Text_IO.Put_Line ("Dark colour  " & RGB_Image (Dark_Color) & ":");
      Ada.Text_IO.Put_Line
        ("  Luminance      :" & Natural'Image (Luminance (Dark_Color)));
      Ada.Text_IO.Put_Line
        ("  Classify_Theme : " & Theme_Kind'Image (Classify_Theme (Dark_Color)));
      Ada.Text_IO.Put_Line
        ("  Is_Dark        : " & Boolean'Image (Is_Dark (Dark_Color)));
      Ada.Text_IO.Put_Line
        ("  Is_Light       : " & Boolean'Image (Is_Light (Dark_Color)));
      Ada.Text_IO.New_Line;

      --  ---- Light colour ----
      Ada.Text_IO.Put_Line ("Light colour " & RGB_Image (Light_Color) & ":");
      Ada.Text_IO.Put_Line
        ("  Luminance      :" & Natural'Image (Luminance (Light_Color)));
      Ada.Text_IO.Put_Line
        ("  Classify_Theme : " & Theme_Kind'Image (Classify_Theme (Light_Color)));
      Ada.Text_IO.Put_Line
        ("  Is_Dark        : " & Boolean'Image (Is_Dark (Light_Color)));
      Ada.Text_IO.Put_Line
        ("  Is_Light       : " & Boolean'Image (Is_Light (Light_Color)));
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO B — Live terminal theme detection (FUNC-DKL-005)
   --
   --  Detect_Theme wraps Detect_Background_Color (OSC 11 cascade) and
   --  Classify_Theme into a single call.  Timeout_Ms is clamped to at most
   --  MAX_TIMEOUT_MS (30 000 ms).  The function never raises an exception.
   --
   --  Theme_Result is a discriminated record:
   --    (Success => True,  Theme => Dark | Light, Color => <RGB>)  -- success
   --    (Success => False, Error => <Detect_Error>)                -- failure
   --
   --  Callers must check the Success discriminant before accessing Theme or
   --  Error; the Ada compiler enforces this through variant record rules.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario B: Live terminal theme detection ---");

   declare
      Result : constant Theme_Result := Detect_Theme (Timeout_Ms => 1_000);
   begin
      if Result.Success then
         Ada.Text_IO.Put_Line
           ("Theme detected  : " & Theme_Kind'Image (Result.Theme));
         Ada.Text_IO.Put_Line
           ("Background color: " & RGB_Image (Result.Color));
      else
         Ada.Text_IO.Put_Line
           ("Theme detection failed: " & Error_Name (Result.Error));
         Ada.Text_IO.Put_Line
           ("  => Detection requires an interactive terminal with OSC 11 support.");
         Ada.Text_IO.Put_Line
           ("  => Falling back to dark-background assumption in Scenario C.");
      end if;
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO C — Conditional output based on detected theme
   --
   --  The primary use case for dark/light detection is selecting presentation
   --  parameters — ANSI escape colours, highlight intensities, or icon sets —
   --  that are legible against the actual terminal background.  This scenario
   --  shows the idiomatic pattern:
   --
   --    1. Call Detect_Theme (result is immutable after this point).
   --    2. When detection succeeds, branch on Theme.
   --    3. When detection fails, fall back to a safe default assumption.
   --
   --  Using Theme_Kind in a case expression (rather than a Boolean flag) lets
   --  the Ada compiler verify exhaustiveness: adding a third Theme_Kind value
   --  in the future would cause a compile error here, not a silent misbehaviour.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario C: Conditional output based on theme ---");

   declare
      Result : constant Theme_Result := Detect_Theme;
      --  Detect_Theme uses the default Timeout_Ms => 1_000.
   begin
      if Result.Success then
         case Result.Theme is
            when Dark =>
               Ada.Text_IO.Put_Line
                 ("Dark background detected.");
               Ada.Text_IO.Put_Line
                 ("  => Using bright foreground colors for maximum contrast.");
               Ada.Text_IO.Put_Line
                 ("  => Example: ESC[97m for bright white text.");

            when Light =>
               Ada.Text_IO.Put_Line
                 ("Light background detected.");
               Ada.Text_IO.Put_Line
                 ("  => Using muted/dark foreground colors to avoid glare.");
               Ada.Text_IO.Put_Line
                 ("  => Example: ESC[30m for black text.");
         end case;
      else
         --  Detection failed: the process may not be attached to a compatible
         --  interactive terminal (e.g., redirected output, unsupported terminal,
         --  or OSC 11 not implemented).  Apply the most common safe default:
         --  assume a dark background.
         Ada.Text_IO.Put_Line
           ("Theme unknown (detection failed: " & Error_Name (Result.Error) & ").");
         Ada.Text_IO.Put_Line
           ("  => Assuming dark background as a safe default.");
         Ada.Text_IO.Put_Line
           ("  => Using bright foreground colors.");
      end if;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done.");

end Dark_Light_Demo;
