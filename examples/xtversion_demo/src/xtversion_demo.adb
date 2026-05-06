-------------------------------------------------------------------------------
--  XTVERSION_Demo - Active Terminal Identification via XTVERSION Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.XTVERSION.IO API for active terminal
--  identification using the XTVERSION (CSI > q) protocol.
--
--  @description
--  Shows how to:
--    1. Call Query_And_Identify (the primary convenience API) to send a
--       CSI > q query and obtain a structured XTVERSION_Result in one step.
--    2. Check the Status discriminant (Success / Timeout / Parse_Error)
--       using a case statement.
--    3. Access Terminal_Name and Terminal_Version when Status = Success.
--    4. Fall back to passive identification (Termicap.Terminal_Id) when the
--       terminal does not respond within the timeout.
--    5. Call Query_XTVERSION directly for callers who want raw response bytes
--       and wish to call Parse_XTVERSION_Response themselves.
--
--  Run this program from different terminal contexts:
--    ./xtversion_demo                    -- active identification (most terminals)
--    TERM=dumb ./xtversion_demo          -- typically triggers a timeout
--    Inside tmux: the query is wrapped for passthrough automatically.
--
--  Requirements demonstrated:
--    FUNC-XTV-001  XTVERSION_Status / XTVERSION_Result types
--    FUNC-XTV-006  Parse_XTVERSION_Response (exercised via Query_And_Identify)
--    FUNC-XTV-008  Query_XTVERSION procedure
--    FUNC-XTV-013  Query_And_Identify convenience function
--    FUNC-XTV-015  Timeout path maps to Status = Timeout

with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Termicap.Environment;            use Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.Terminal_Id;            use Termicap.Terminal_Id;
with Termicap.XTVERSION;              use Termicap.XTVERSION;
with Termicap.XTVERSION.IO;

procedure XTVERSION_Demo is

   ---------------------------------------------------------------------------
   --  Helper: render an Unbounded_String, substituting a placeholder when
   --  the value is empty.
   ---------------------------------------------------------------------------

   function Display (S : Ada.Strings.Unbounded.Unbounded_String) return String
   is
      Raw : constant String := Ada.Strings.Unbounded.To_String (S);
   begin
      if Raw = "" then
         return "(empty)";
      else
         return Raw;
      end if;
   end Display;


   ---------------------------------------------------------------------------
   --  Helper: map Terminal_Kind to a human-readable short label.
   ---------------------------------------------------------------------------

   function Kind_Label (K : Terminal_Kind) return String is
   begin
      case K is
         when Unknown          => return "Unknown";
         when Alacritty        => return "Alacritty";
         when Apple_Terminal   => return "Apple Terminal";
         when Dumb             => return "Dumb";
         when Foot             => return "Foot";
         when Ghostty          => return "Ghostty";
         when ITerm2           => return "iTerm2";
         when JediTerm         => return "JediTerm";
         when Kitty            => return "Kitty";
         when Konsole          => return "Konsole";
         when Linux_Console    => return "Linux Console";
         when Mintty           => return "Mintty";
         when Rxvt             => return "rxvt";
         when Screen           => return "GNU Screen";
         when Tmux             => return "tmux";
         when VSCode           => return "VS Code";
         when VTE              => return "VTE";
         when WarpTerminal     => return "Warp";
         when WezTerm          => return "WezTerm";
         when Windows_Terminal => return "Windows Terminal";
         when Xterm            => return "xterm";
         when others           =>
            return "Unrecognised (update Kind_Label for new values)";
      end case;
   end Kind_Label;


   ---------------------------------------------------------------------------
   --  Declarations
   ---------------------------------------------------------------------------

   --  Used by the passive-identification fallback in Scenario B.
   Live_Env : Environment;

begin

   --  Capture the live environment once so it is available for the passive
   --  identification fallback.  The XTVERSION query is independent of this.
   Termicap.Environment.Capture.Capture_Current (Live_Env);

   Ada.Text_IO.Put_Line ("=== Termicap XTVERSION Active Terminal Identification Demo ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO A — Active Identification with Query_And_Identify (primary API)
   --
   --  Query_And_Identify is the recommended entry point for most callers.  It:
   --    1. Sends the CSI > q XTVERSION query to the terminal (100 ms timeout).
   --    2. Wraps the query for multiplexer passthrough when running inside tmux
   --       or GNU Screen (FUNC-XTV-012).
   --    3. Returns an XTVERSION_Result whose Status discriminant indicates the
   --       outcome: Success, Timeout, or Parse_Error.
   --
   --  The discriminated record guarantees that Terminal_Name and
   --  Terminal_Version are only accessible when Status = Success; accessing
   --  them on any other variant raises Constraint_Error (FUNC-XTV-001).
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario A: Active Identification (Query_And_Identify) ---");

   declare
      --  One call does everything: I/O, timeout handling, and parsing.
      Result : constant XTVERSION_Result :=
        Termicap.XTVERSION.IO.Query_And_Identify (Timeout_Ms => 100);
   begin
      case Result.Status is

         when Success =>
            --  The terminal responded with a valid DCS XTVERSION envelope.
            --  Terminal_Name and Terminal_Version are safe to access here.
            Ada.Text_IO.Put_Line ("Status       : Success");
            Ada.Text_IO.Put_Line
              ("Terminal     : " & Display (Result.Terminal_Name));
            Ada.Text_IO.Put_Line
              ("Version      : " & Display (Result.Terminal_Version));

            --  FUNC-XTV-001: both fields are trimmed; Version may be ""
            --  when the terminal emits a name-only payload.
            if Ada.Strings.Unbounded.Length (Result.Terminal_Version) = 0 then
               Ada.Text_IO.Put_Line
                 ("  (no version token in the XTVERSION response)");
            end if;

         when Timeout =>
            --  The terminal did not respond within Timeout_Ms milliseconds.
            --  This is the expected outcome for terminals that do not support
            --  XTVERSION, for dumb terminals, and for non-TTY streams.
            Ada.Text_IO.Put_Line ("Status       : Timeout");
            Ada.Text_IO.Put_Line
              ("  The terminal did not respond to the CSI > q query.");
            Ada.Text_IO.Put_Line
              ("  Falling back to passive identification — see Scenario B.");

         when Parse_Error =>
            --  A response was received but could not be parsed as a valid
            --  DCS XTVERSION envelope (wrong prefix, missing terminator,
            --  or empty name token).  Treat like Timeout for rendering purposes.
            Ada.Text_IO.Put_Line ("Status       : Parse_Error");
            Ada.Text_IO.Put_Line
              ("  The terminal sent a response that could not be parsed.");
            Ada.Text_IO.Put_Line
              ("  Falling back to passive identification — see Scenario B.");

      end case;
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO B — Passive Identification Fallback
   --
   --  When XTVERSION times out (common for multiplexers without passthrough
   --  support, SSH sessions with high latency, or terminals that predate the
   --  XTVERSION protocol), passive identification via environment variables is
   --  a reliable fallback.  Detect_Terminal_Identity (FUNC-TID-003) inspects
   --  TERM_PROGRAM, TERM, TMUX, and related variables from an environment
   --  snapshot captured at startup.
   --
   --  This scenario always runs so the output shows both methods side by side.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario B: Passive Identification Fallback ---");

   declare
      Identity : constant Terminal_Identity :=
        Detect_Terminal_Identity (Live_Env);
   begin
      Ada.Text_IO.Put_Line
        ("Kind           : " & Kind_Label (Identity.Kind));
      Ada.Text_IO.Put_Line
        ("Is_Multiplexer : " & (if Identity.Is_Multiplexer then "Yes" else "No"));
      Ada.Text_IO.Put_Line
        ("Program_Name   : "
         & Ada.Strings.Unbounded.To_String (Identity.Program_Name));
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  SCENARIO C — Raw Query + Manual Parse
   --
   --  Callers who need the raw response bytes — for logging, for custom parsing
   --  logic, or for combining with other escape-sequence responses — can call
   --  Query_XTVERSION directly and then pass the buffer to
   --  Parse_XTVERSION_Response themselves.
   --
   --  The Response buffer must be at least MAX_RESPONSE_SIZE bytes (4 096).
   --  Resp_Length reports how many bytes were actually written.  The buffer
   --  contents beyond Resp_Length are undefined.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scenario C: Raw Query and Manual Parse ---");

   declare
      --  Allocate a buffer large enough to satisfy the Query_XTVERSION
      --  precondition: Response'Length >= MAX_RESPONSE_SIZE (FUNC-XTV-008).
      Response    : Termicap.Byte_Array (1 .. Termicap.MAX_RESPONSE_SIZE);
      Resp_Length : Natural;
      Timed_Out   : Boolean;
   begin
      Termicap.XTVERSION.IO.Query_XTVERSION
        (Timeout_Ms  => 100,
         Response    => Response,
         Resp_Length => Resp_Length,
         Timed_Out   => Timed_Out);

      Ada.Text_IO.Put_Line
        ("Bytes received : " & Natural'Image (Resp_Length));
      Ada.Text_IO.Put_Line
        ("Timed out      : " & (if Timed_Out then "Yes" else "No"));

      if Timed_Out then
         Ada.Text_IO.Put_Line
           ("  No DCS response to parse.");
      else
         --  Parse_XTVERSION_Response handles all edge cases internally and
         --  returns Parse_Error for any malformed input (FUNC-XTV-006,
         --  FUNC-XTV-016).  The Pre contract requires
         --  Resp_Length <= MAX_RESPONSE_SIZE, which holds by construction.
         declare
            Parsed : constant XTVERSION_Result :=
              Parse_XTVERSION_Response
                (Bytes  => Response,
                 Length => Resp_Length);
         begin
            case Parsed.Status is
               when Success =>
                  Ada.Text_IO.Put_Line
                    ("Parsed name    : " & Display (Parsed.Terminal_Name));
                  Ada.Text_IO.Put_Line
                    ("Parsed version : " & Display (Parsed.Terminal_Version));
               when Parse_Error =>
                  Ada.Text_IO.Put_Line
                    ("  Response received but could not be parsed "
                     & "(malformed DCS envelope).");
               when Timeout =>
                  --  Parse_XTVERSION_Response never returns Timeout; this
                  --  branch is present for exhaustiveness.
                  null;
            end case;
         end;
      end if;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done.");

end XTVERSION_Demo;
