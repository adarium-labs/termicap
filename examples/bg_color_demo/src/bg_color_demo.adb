-------------------------------------------------------------------------------
--  BG_Color_Demo - Background / Foreground Color Query Usage Examples
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap background and foreground color detection API.
--
--  @description
--  Covers four realistic scenarios:
--
--  Scenario A — Background Color Detection (OSC 11 cascade):
--    Call Detect_Background_Color with the default 1-second timeout.  Print
--    the resulting RGB value when successful, or the Detect_Error when not.
--    Show how the result can drive a dark/light theme decision.
--
--  Scenario B — Foreground Color Detection (OSC 10 cascade):
--    Call Detect_Foreground_Color with the default timeout and print the
--    result in the same style as Scenario A.
--
--  Scenario C — COLORFGBG Fallback Parsing (bypass OSC query):
--    Read the COLORFGBG environment variable from a live snapshot, call
--    Parse_Colorfgbg, and then Ansi_To_RGB to obtain an RGB value without
--    ever sending an OSC escape sequence.  Useful in multiplexers where OSC
--    queries are unreliable.
--
--  Scenario D — Direct rgb: Response Parsing (hardcoded byte array):
--    Call Parse_RGB_Response with a synthetic "rgb:8080/8080/8080" payload
--    to show how callers can use the pure SPARK parsing layer independently
--    of the I/O boundary.
--
--  Requirements demonstrated:
--    FUNC-BGC-007  Parse_RGB_Response
--    FUNC-BGC-009  Parse_Hex_Channel (exercised indirectly)
--    FUNC-BGC-011  Parse_Colorfgbg
--    FUNC-BGC-012  Ansi_To_RGB
--    FUNC-BGC-013  Detect_Background_Color
--    FUNC-BGC-014  Detect_Foreground_Color

with Ada.Text_IO;

with Termicap.Color.BG_Query;          use Termicap.Color.BG_Query;
with Termicap.Color.Detection;         use Termicap.Color.Detection;
with Termicap.Environment;             use Termicap.Environment;
with Termicap.Environment.Capture;

procedure BG_Color_Demo is

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

   --  Classify a background color as dark or light based on perceived
   --  luminance.  Uses the standard integer approximation of the ITU-R BT.601
   --  luma formula (Y = 0.299 R + 0.587 G + 0.114 B).  Values below 128 are
   --  considered dark.
   function Is_Dark_Background (C : RGB) return Boolean is
      Luma : constant Natural :=
        (299 * C.Red + 587 * C.Green + 114 * C.Blue) / 1000;
   begin
      return Luma < 128;
   end Is_Dark_Background;

   ---------------------------------------------------------------------------
   --  Live environment snapshot (captured once at startup)
   ---------------------------------------------------------------------------

   Live_Env : Environment;

begin

   --  Capture the live OS environment once for use in Scenario C.
   Termicap.Environment.Capture.Capture_Current (Live_Env);

   Ada.Text_IO.Put_Line ("=== Termicap BG/FG Color Detection Demo ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO A — Background Color Detection (FUNC-BGC-013)
   --
   --  Detect_Background_Color follows a two-level cascade:
   --    1. Send an OSC 11 query and parse the X11 rgb: response.
   --    2. Fall back to the COLORFGBG environment variable.
   --  The default timeout is 1 000 ms.  Pass Timeout_Ms => 0 to skip the OSC
   --  query entirely and jump straight to the COLORFGBG fallback.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario A: Background Color Detection ---");

   declare
      BG_Result : constant Detection_Result :=
        Detect_Background_Color (Timeout_Ms => 1_000);
   begin
      if BG_Result.Success then
         Ada.Text_IO.Put_Line
           ("Background color detected: " & RGB_Image (BG_Result.Color));

         --  Use the result for a dark/light theme decision.
         if Is_Dark_Background (BG_Result.Color) then
            Ada.Text_IO.Put_Line ("  => Dark theme detected; use light text.");
         else
            Ada.Text_IO.Put_Line ("  => Light theme detected; use dark text.");
         end if;
      else
         Ada.Text_IO.Put_Line
           ("Background color not available: " & Error_Name (BG_Result.Error));
         Ada.Text_IO.Put_Line
           ("  => Falling back to default dark-background assumption.");
      end if;
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO B — Foreground Color Detection (FUNC-BGC-014)
   --
   --  Detect_Foreground_Color follows the same cascade as Scenario A but
   --  sends an OSC 10 query instead of OSC 11, and reads the foreground index
   --  from COLORFGBG when the query fails.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario B: Foreground Color Detection ---");

   declare
      FG_Result : constant Detection_Result :=
        Detect_Foreground_Color (Timeout_Ms => 1_000);
   begin
      if FG_Result.Success then
         Ada.Text_IO.Put_Line
           ("Foreground color detected: " & RGB_Image (FG_Result.Color));
      else
         Ada.Text_IO.Put_Line
           ("Foreground color not available: " & Error_Name (FG_Result.Error));
         Ada.Text_IO.Put_Line
           ("  => Using DEFAULT_FOREGROUND: " & RGB_Image (DEFAULT_FOREGROUND));
      end if;
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO C — COLORFGBG Fallback Parsing (FUNC-BGC-011, FUNC-BGC-012)
   --
   --  Some callers prefer to bypass the OSC query entirely (e.g., inside a
   --  multiplexer where OSC passthrough is unavailable).  They can read
   --  COLORFGBG directly from an environment snapshot, call Parse_Colorfgbg,
   --  and then Ansi_To_RGB to obtain RGB values without any terminal I/O.
   --
   --  Parse_Colorfgbg accepts "fg;bg" or "fg;extra;bg" format where each
   --  field is a decimal integer in 0..15.  Both indices are constrained to
   --  the valid ANSI_COLOR_TABLE range, enabling a safe array lookup.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario C: COLORFGBG Fallback Parsing ---");

   declare
      Colorfgbg_Value : constant String :=
        Termicap.Environment.Value (Live_Env, "COLORFGBG");
   begin
      if Colorfgbg_Value = "" then
         Ada.Text_IO.Put_Line
           ("COLORFGBG is not set; skipping COLORFGBG fallback demo.");
         Ada.Text_IO.Put_Line
           ("  Hint: set COLORFGBG=15;0 (white on black) and re-run.");
      elsif Colorfgbg_Value'Length > MAX_COLORFGBG_LENGTH then
         Ada.Text_IO.Put_Line
           ("COLORFGBG value is too long (>" &
            Natural'Image (MAX_COLORFGBG_LENGTH) & " bytes); ignoring.");
      else
         declare
            --  Parse_Colorfgbg is a pure SPARK function with a precondition
            --  that the string length does not exceed MAX_COLORFGBG_LENGTH.
            --  The length check above guarantees this precondition is met.
            Parsed : constant Colorfgbg_Result :=
              Parse_Colorfgbg (Value => Colorfgbg_Value);
         begin
            if Parsed.Success then
               Ada.Text_IO.Put_Line
                 ("COLORFGBG parsed: FG index ="
                  & Natural'Image (Parsed.Foreground)
                  & "  BG index ="
                  & Natural'Image (Parsed.Background));

               --  Convert the ANSI indices to RGB using the canonical xterm
               --  palette.  Ansi_To_RGB takes an ANSI_Index (0..15) and
               --  returns the corresponding RGB from ANSI_COLOR_TABLE.
               declare
                  FG_Color : constant RGB :=
                    Ansi_To_RGB (Index => Parsed.Foreground);
                  BG_Color : constant RGB :=
                    Ansi_To_RGB (Index => Parsed.Background);
               begin
                  Ada.Text_IO.Put_Line
                    ("  Foreground RGB: " & RGB_Image (FG_Color));
                  Ada.Text_IO.Put_Line
                    ("  Background RGB: " & RGB_Image (BG_Color));
               end;
            else
               Ada.Text_IO.Put_Line
                 ("COLORFGBG value """ & Colorfgbg_Value
                  & """ could not be parsed.");
               Ada.Text_IO.Put_Line
                 ("  Expected format: ""fg;bg"" where fg,bg are integers 0..15.");
            end if;
         end;
      end if;
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO D — Direct rgb: Response Parsing (FUNC-BGC-007, FUNC-BGC-009)
   --
   --  Callers who receive a raw OSC response from another source (e.g., a
   --  custom I/O wrapper) can call Parse_RGB_Response directly on the payload
   --  bytes, after the OSC header has been stripped.  This demo uses a
   --  hardcoded payload simulating the string "rgb:8080/8080/8080", which
   --  encodes a mid-grey color with 4-digit channel encoding.  Each 4-digit
   --  channel value is normalised by taking the high byte: 0x80 => 128.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario D: Direct rgb: Response Parsing ---");

   declare
      --  Payload bytes encoding the ASCII string "rgb:8080/8080/8080".
      --  This simulates the payload that Strip_OSC_Header would return after
      --  removing the leading "ESC ] 1 1 ;" and trailing ST.
      --
      --  Hex values:  r     g     b     :     8     0     8     0
      --               /     8     0     8     0     /     8     0
      --               8     0
      Payload : constant Termicap.Byte_Array :=
        [Character'Pos ('r'), Character'Pos ('g'), Character'Pos ('b'),
         Character'Pos (':'),
         Character'Pos ('8'), Character'Pos ('0'),
         Character'Pos ('8'), Character'Pos ('0'),
         Character'Pos ('/'),
         Character'Pos ('8'), Character'Pos ('0'),
         Character'Pos ('8'), Character'Pos ('0'),
         Character'Pos ('/'),
         Character'Pos ('8'), Character'Pos ('0'),
         Character'Pos ('8'), Character'Pos ('0')];

      Result : constant Parse_Result :=
        Parse_RGB_Response
          (Bytes  => Payload,
           Length => Payload'Length);
   begin
      Ada.Text_IO.Put_Line
        ("Parsing hardcoded payload ""rgb:8080/8080/8080"":");
      if Result.Success then
         Ada.Text_IO.Put_Line
           ("  Parsed RGB: " & RGB_Image (Result.Color));
         --  Expected: R= 128  G= 128  B= 128  (mid-grey)
      else
         Ada.Text_IO.Put_Line ("  Parse_RGB_Response returned failure.");
      end if;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done.");

end BG_Color_Demo;
