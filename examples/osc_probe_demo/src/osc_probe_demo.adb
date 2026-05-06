-------------------------------------------------------------------------------
--  Osc_Probe_Demo - OSC Query Infrastructure Usage Example
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.OSC and Termicap.OSC.Parsing APIs for active
--  terminal probing via OSC/DA1 sentinel-bounded queries.
--
--  @description
--  Shows how to:
--    1. Open a Probe_Session and check the Session_Status
--    2. Send an OSC 11 background color query via Sentinel_Query
--    3. Inspect the response buffer (or detect timeout)
--    4. Parse DA1 response bytes with Parse_DA1_Response / Contains_DA1_Response
--    5. Wrap a query in tmux DCS passthrough via Wrap_For_Passthrough
--
--  The example covers three complementary usage patterns:
--
--  Pattern A — Basic probe session: the primary use case.  Open a session,
--  send an OSC 11 background color query with a 2000 ms timeout, print the
--  raw response bytes as hex, then let the session go out of scope.  Finalize
--  restores the terminal automatically even if an exception propagates.
--
--  Pattern B — DA1 parsing demo: pure functions, no terminal required.
--  Construct a known DA1 response byte array and call Parse_DA1_Response and
--  Contains_DA1_Response to inspect the parameter list.
--
--  Pattern C — Passthrough wrapping demo: pure functions, no terminal required.
--  Construct an OSC 11 query and call Wrap_For_Passthrough with
--  Tmux_Passthrough to see how the DCS envelope changes the byte count.
--
--  Run this program from an interactive terminal.  The OSC 11 query requires
--  a VTE-compatible terminal emulator that responds to background color queries.

with Ada.Text_IO;

with Termicap.OSC;
with Termicap.OSC.Parsing;

procedure Osc_Probe_Demo is

   ---------------------------------------------------------------------------
   --  Common byte constants for escape sequence construction
   ---------------------------------------------------------------------------

   ESC_BYTE  : constant Termicap.Byte := 16#1B#;  --  ESC
   OSC_BYTE  : constant Termicap.Byte := 16#5D#;  --  ']'
   ST_BYTE   : constant Termicap.Byte := 16#5C#;  --  '\'  (String Terminator with ESC)
   CSI_L     : constant Termicap.Byte := 16#5B#;  --  '['
   QUEST     : constant Termicap.Byte := 16#3F#;  --  '?'
   SEMI      : constant Termicap.Byte := 16#3B#;  --  ';'
   D_1       : constant Termicap.Byte := 16#31#;  --  '1'
   D_2       : constant Termicap.Byte := 16#32#;  --  '2'
   D_4       : constant Termicap.Byte := 16#34#;  --  '4'
   D_6       : constant Termicap.Byte := 16#36#;  --  '6'
   D_C       : constant Termicap.Byte := 16#63#;  --  'c'  (DA1 terminator)
   DCS_P     : constant Termicap.Byte := 16#50#;  --  'P'  (DCS introducer with ESC)
   TMUX_T    : constant Termicap.Byte := 16#74#;  --  't'
   TMUX_M    : constant Termicap.Byte := 16#6D#;  --  'm'
   TMUX_U    : constant Termicap.Byte := 16#75#;  --  'u'
   TMUX_X    : constant Termicap.Byte := 16#78#;  --  'x'

   ---------------------------------------------------------------------------
   --  Helper: print a byte value as two hex digits
   ---------------------------------------------------------------------------

   procedure Put_Hex_Byte (B : Termicap.Byte) is
      HEX_DIGITS : constant String := "0123456789ABCDEF";
      Hi         : constant Natural := Natural (B) / 16;
      Lo         : constant Natural := Natural (B) mod 16;
   begin
      Ada.Text_IO.Put (HEX_DIGITS (HEX_DIGITS'First + Hi)
                       & HEX_DIGITS (HEX_DIGITS'First + Lo));
   end Put_Hex_Byte;

   ---------------------------------------------------------------------------
   --  Helper: print a Byte_Array slice as space-separated hex bytes
   ---------------------------------------------------------------------------

   procedure Put_Hex_Array
     (Bytes  : Termicap.Byte_Array;
      Length : Natural)
   is
   begin
      if Length = 0 then
         Ada.Text_IO.Put ("(empty)");
         return;
      end if;
      for I in Bytes'First .. Bytes'First + Length - 1 loop
         if I > Bytes'First then
            Ada.Text_IO.Put (" ");
         end if;
         Put_Hex_Byte (Bytes (I));
      end loop;
   end Put_Hex_Array;

begin

   Ada.Text_IO.Put_Line ("=== Termicap OSC Query Infrastructure Example ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Pattern A — Basic probe session
   --
   --  Open a Probe_Session, handle each Session_Status case with an informative
   --  message, send an OSC 11 background color query via Sentinel_Query, and
   --  print the raw response bytes as hex.  Finalize (called automatically on
   --  scope exit) restores the terminal to its original cooked mode.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Pattern A: Basic probe session (OSC 11 background color) ---");
   Ada.Text_IO.New_Line;

   declare
      Session   : Termicap.OSC.Probe_Session;
      Status    : Termicap.OSC.Session_Status;

      --  OSC 11 background color query: ESC ] 1 1 ; ? ESC \
      OSC_11_Query : constant Termicap.Byte_Array :=
        [ESC_BYTE, OSC_BYTE, D_1, D_1, SEMI, QUEST, ESC_BYTE, ST_BYTE];

      Response    : Termicap.OSC.Response_Buffer;
      Resp_Length : Natural;
      Timed_Out   : Boolean;
   begin
      Termicap.OSC.Open (Session, Status);

      case Status is
         when Termicap.OSC.Session_OK =>
            Ada.Text_IO.Put_Line ("  Session opened successfully.");

         when Termicap.OSC.Session_Not_Foreground =>
            Ada.Text_IO.Put_Line
               ("  Session not opened: process is in a background job.");
            Ada.Text_IO.Put_Line
               ("  Tip: run this example from a foreground shell.");
            goto Pattern_B;

         when Termicap.OSC.Session_No_Terminal =>
            Ada.Text_IO.Put_Line
               ("  Session not opened: /dev/tty could not be opened.");
            Ada.Text_IO.Put_Line
               ("  Tip: run this example from an interactive terminal.");
            goto Pattern_B;

         when Termicap.OSC.Session_Save_Failed =>
            Ada.Text_IO.Put_Line
               ("  Session not opened: tcgetattr() failed (termios save).");
            goto Pattern_B;

         when Termicap.OSC.Session_Raw_Failed =>
            Ada.Text_IO.Put_Line
               ("  Session not opened: tcsetattr() failed (raw mode).");
            goto Pattern_B;

         when Termicap.OSC.Session_Already_Active =>
            Ada.Text_IO.Put_Line
               ("  Session not opened: another Probe_Session is already active.");
            Ada.Text_IO.Put_Line
               ("  Only one session may be open at a time.");
            goto Pattern_B;
      end case;

      --  Send the OSC 11 query.  The session appends a DA1 sentinel (ESC [ c)
      --  automatically so that the read loop knows when the terminal has
      --  finished responding.  Retry => True resends once if the first attempt
      --  times out (doubled timeout on retry).
      Termicap.OSC.Sentinel_Query
        (Session     => Session,
         Query       => OSC_11_Query,
         Response    => Response,
         Resp_Length => Resp_Length,
         Timeout_Ms  => 2_000,
         Timed_Out   => Timed_Out,
         Retry       => True);

      if Timed_Out then
         Ada.Text_IO.Put_Line
            ("  OSC 11 query timed out (terminal did not respond within 2 s).");
         Ada.Text_IO.Put_Line
            ("  This is normal on terminals that do not implement OSC 11.");
      else
         Ada.Text_IO.Put_Line
            ("  Response received. Length:"
             & Resp_Length'Image & " bytes.");
         Ada.Text_IO.Put ("  Raw bytes (hex): ");
         Put_Hex_Array (Response, Resp_Length);
         Ada.Text_IO.New_Line;
         Ada.Text_IO.Put_Line
            ("  (A full OSC 11 response looks like: ESC ] 1 1 ; rgb:RRRR/GGGG/BBBB ESC \\)");
      end if;

      --  Closing here is optional: Finalize will call Close on scope exit.
      Termicap.OSC.Close (Session);
      Ada.Text_IO.Put_Line ("  Session closed; terminal restored to cooked mode.");
   end;

   <<Pattern_B>>
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Pattern B — DA1 parsing demo  (pure functions, no terminal needed)
   --
   --  Construct the byte representation of a typical DA1 response:
   --    ESC [ ? 6 4 ; 1 ; 2 2 c
   --  then call Parse_DA1_Response and Contains_DA1_Response.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Pattern B: DA1 response parsing (pure functions) ---");
   Ada.Text_IO.New_Line;

   declare
      --  ESC [ ? 6 4 ; 1 ; 2 2 c
      --  Parameters: 64, 1, 22  (xterm capability flags)
      DA1_Bytes : constant Termicap.Byte_Array :=
        [ESC_BYTE,
         CSI_L,
         QUEST,
         D_6, D_4,           --  "64"
         SEMI,
         D_1,                --  "1"
         SEMI,
         D_2, D_2,           --  "22"
         D_C];               --  terminating 'c'

      DA1_Length : constant Natural := DA1_Bytes'Length;

      Params     : Termicap.OSC.Parsing.DA1_Params;
      Has_DA1    : Boolean;
   begin
      Ada.Text_IO.Put ("  Sample DA1 bytes (hex): ");
      Put_Hex_Array (DA1_Bytes, DA1_Length);
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line
         ("  Sequence: ESC [ ? 6 4 ; 1 ; 2 2 c");
      Ada.Text_IO.New_Line;

      --  Contains_DA1_Response: presence check used by Sentinel_Query
      Has_DA1 := Termicap.OSC.Parsing.Contains_DA1_Response
                   (DA1_Bytes, DA1_Length);
      Ada.Text_IO.Put_Line
         ("  Contains_DA1_Response: "
          & (if Has_DA1 then "True  (sentinel detected)" else "False"));

      --  Parse_DA1_Response: extract numeric parameters
      Params := Termicap.OSC.Parsing.Parse_DA1_Response
                  (DA1_Bytes, DA1_Length);

      Ada.Text_IO.Put_Line
         ("  Parse_DA1_Response returned Count ="
          & Params.Count'Image);

      for I in 1 .. Params.Count loop
         Ada.Text_IO.Put_Line
            ("    Values (" & I'Image & " ) ="
             & Params.Values (I)'Image);
      end loop;

      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line
         ("  Interpretation: param 64 = VT340-level device; param 1 = 132-column");
      Ada.Text_IO.Put_Line
         ("  mode; param 22 = ANSI colour (xterm extension).");
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Pattern C — Passthrough wrapping demo  (pure functions, no terminal needed)
   --
   --  Construct an OSC 11 query and wrap it with Wrap_For_Passthrough using
   --  Tmux_Passthrough.  Print the original and wrapped byte lengths and
   --  explain what the tmux DCS envelope adds.
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Pattern C: Multiplexer passthrough wrapping (pure functions) ---");
   Ada.Text_IO.New_Line;

   declare
      --  OSC 11 background color query: ESC ] 1 1 ; ? ESC \
      OSC_11 : constant Termicap.Byte_Array :=
        [ESC_BYTE, OSC_BYTE, D_1, D_1, SEMI, QUEST, ESC_BYTE, ST_BYTE];

      --  Wrap for tmux passthrough: ESC P tmux ; ESC <query> ESC \
      Wrapped : constant Termicap.Byte_Array :=
        Termicap.OSC.Parsing.Wrap_For_Passthrough
          (Query       => OSC_11,
           Passthrough => Termicap.OSC.Parsing.Tmux_Passthrough);
   begin
      Ada.Text_IO.Put ("  Original OSC 11 query bytes (hex): ");
      Put_Hex_Array (OSC_11, OSC_11'Length);
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line
         ("  Original length:" & OSC_11'Length'Image & " bytes.");
      Ada.Text_IO.New_Line;

      Ada.Text_IO.Put ("  Tmux-wrapped bytes (hex): ");
      Put_Hex_Array (Wrapped, Wrapped'Length);
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line
         ("  Wrapped length:" & Wrapped'Length'Image & " bytes.");
      Ada.Text_IO.New_Line;

      Ada.Text_IO.Put_Line
         ("  Wrapping added"
          & Integer'Image (Wrapped'Length - OSC_11'Length)
          & " bytes.");
      Ada.Text_IO.Put_Line
         ("  The tmux DCS envelope is: ESC P tmux ; ESC <query> ESC \\");
      Ada.Text_IO.Put_Line
         ("  This allows the inner OSC sequence to pass through the tmux");
      Ada.Text_IO.Put_Line
         ("  multiplexer and reach the outer terminal emulator.");
      Ada.Text_IO.New_Line;

      --  Also demonstrate No_Passthrough (identity)
      declare
         Direct : constant Termicap.Byte_Array :=
           Termicap.OSC.Parsing.Wrap_For_Passthrough
             (Query       => OSC_11,
              Passthrough => Termicap.OSC.Parsing.No_Passthrough);
      begin
         Ada.Text_IO.Put_Line
            ("  No_Passthrough length:" & Direct'Length'Image
             & " bytes (unchanged from original).");
      end;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("=== Example complete ===");

end Osc_Probe_Demo;
