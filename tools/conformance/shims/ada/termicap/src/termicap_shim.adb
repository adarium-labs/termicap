-------------------------------------------------------------------------------
--  Termicap_Shim — Conformance harness driver for termicap
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------
--
--  Reads a conformance envelope JSON file (path in $CONFORMANCE_ENVELOPE),
--  calls Termicap.Capabilities.Detect_Full, translates the result to the
--  canonical schema vocabulary, and writes one JSON document conforming to
--  tools/conformance/schema/canonical.schema.json.
--
--  Output path: argv(1), default "termicap.json".
--
--  Hand-rolled JSON output — the envelope file is spliced verbatim as the
--  value of the "run" key; the rest is generated from a fixed shape so the
--  shim has no dependency on a JSON library.
--
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Termicap.Capabilities;
with Termicap.Clipboard;
with Termicap.Color;
with Termicap.DA1;
with Termicap.Graphics;
with Termicap.Hyperlinks;
with Termicap.Keyboard;
with Termicap.Mouse;
with Termicap.Terminal_Id;
with Termicap.Unicode;
with Termicap.XTVERSION;

procedure Termicap_Shim is

   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use type Termicap.Mouse.Mouse_Encoding;
   use type Termicap.Keyboard.Keyboard_Protocol;
   use type Termicap.XTVERSION.XTVERSION_Status;

   SHIM_VERSION : constant String := "0.1.0";
   LIB_VERSION  : constant String := "0.5.0";   --  termicap version
   LIB_NAME     : constant String := "termicap";
   LIB_LANG     : constant String := "ada";
   LIB_TIER     : constant String := "active";
   SCHEMA_VERSION : constant String := "0.1.0";
   pragma Unreferenced (SHIM_VERSION);

   ---------------------------------------------------------------------------
   --  JSON helpers
   ---------------------------------------------------------------------------

   function Bool_JSON (B : Boolean) return String is
     (if B then "true" else "false");

   --  Quote a string as a JSON string literal, escaping backslash, double
   --  quote, and ASCII control characters per RFC 8259.
   function Quote (S : String) return String is
      Result : Unbounded_String;
      Hex_Digits : constant String := "0123456789abcdef";
   begin
      Append (Result, '"');
      for C of S loop
         case C is
            when '"' =>
               Append (Result, '\');
               Append (Result, '"');
            when '\' =>
               Append (Result, "\\");
            when ASCII.LF => Append (Result, "\n");
            when ASCII.CR => Append (Result, "\r");
            when ASCII.HT => Append (Result, "\t");
            when ASCII.BS => Append (Result, "\b");
            when ASCII.FF => Append (Result, "\f");
            when Character'Val (0) .. Character'Val (7)
               | Character'Val (11)
               | Character'Val (14) .. Character'Val (31) =>
               Append (Result, "\u00");
               declare
                  N : constant Natural := Character'Pos (C);
               begin
                  Append (Result, Hex_Digits (Hex_Digits'First + N / 16));
                  Append (Result, Hex_Digits (Hex_Digits'First + N mod 16));
               end;
            when others =>
               Append (Result, C);
         end case;
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Quote;

   ---------------------------------------------------------------------------
   --  Envelope reader (slurp-and-trim)
   ---------------------------------------------------------------------------

   function Read_File (Path : String) return String is
      F   : File_Type;
      Buf : Unbounded_String;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
         begin
            Append (Buf, Line);
            Append (Buf, ASCII.LF);
         end;
      end loop;
      Close (F);
      return To_String (Buf);
   end Read_File;

   function Trim_WS (S : String) return String is
      First : Integer := S'First;
      Last  : Integer := S'Last;
   begin
      while First <= Last
        and then (S (First) = ' ' or else S (First) = ASCII.LF
                  or else S (First) = ASCII.CR or else S (First) = ASCII.HT)
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then (S (Last) = ' ' or else S (Last) = ASCII.LF
                  or else S (Last) = ASCII.CR or else S (Last) = ASCII.HT)
      loop
         Last := Last - 1;
      end loop;
      return S (First .. Last);
   end Trim_WS;

   ---------------------------------------------------------------------------
   --  Termicap → canonical mappings
   ---------------------------------------------------------------------------

   function Color_Depth_Str (C : Termicap.Color.Color_Level) return String is
     (case C is
        when Termicap.Color.None         => "none",
        when Termicap.Color.Basic_16     => "ansi16",
        when Termicap.Color.Extended_256 => "ansi256",
        when Termicap.Color.True_Color   => "truecolor");

   function Unicode_Str (U : Termicap.Unicode.Unicode_Level) return String is
     (case U is
        when Termicap.Unicode.None     => "none",
        when Termicap.Unicode.Basic    => "basic",
        when Termicap.Unicode.Extended => "extended");

   function Terminal_Kind_Str (K : Termicap.Terminal_Id.Terminal_Kind) return String is
     (case K is
        when Termicap.Terminal_Id.Unknown          => "unknown",
        when Termicap.Terminal_Id.Alacritty        => "alacritty",
        when Termicap.Terminal_Id.Apple_Terminal   => "apple_terminal",
        when Termicap.Terminal_Id.Dumb             => "dumb",
        when Termicap.Terminal_Id.Foot             => "foot",
        when Termicap.Terminal_Id.Ghostty          => "ghostty",
        when Termicap.Terminal_Id.ITerm2           => "iterm2",
        when Termicap.Terminal_Id.JediTerm         => "jediterm",
        when Termicap.Terminal_Id.Kitty            => "kitty",
        when Termicap.Terminal_Id.Konsole          => "konsole",
        when Termicap.Terminal_Id.Linux_Console    => "linux_console",
        when Termicap.Terminal_Id.Mintty           => "mintty",
        when Termicap.Terminal_Id.Rxvt             => "rxvt",
        when Termicap.Terminal_Id.Screen           => "screen",
        when Termicap.Terminal_Id.Tmux             => "tmux",
        when Termicap.Terminal_Id.VSCode           => "vscode",
        when Termicap.Terminal_Id.VTE              => "vte",
        when Termicap.Terminal_Id.WarpTerminal     => "warp",
        when Termicap.Terminal_Id.WezTerm          => "wezterm",
        when Termicap.Terminal_Id.Windows_Terminal => "windows_terminal",
        when Termicap.Terminal_Id.Xterm            => "xterm");

   function Hyperlinks_Str (H : Termicap.Hyperlinks.Hyperlinks_Support) return String is
     (case H is
        when Termicap.Hyperlinks.Unsupported      => "unsupported",
        when Termicap.Hyperlinks.Likely_Supported => "likely_supported",
        when Termicap.Hyperlinks.Supported        => "supported",
        when Termicap.Hyperlinks.Unknown          => "unknown");

   function Hyperlinks_Provenance_Str
     (P : Termicap.Hyperlinks.Hyperlinks_Provenance) return String is
     (Termicap.Hyperlinks.Hyperlinks_Provenance'Image (P));

   function Clipboard_Str (C : Termicap.Clipboard.Clipboard_Support) return String is
     (case C is
        when Termicap.Clipboard.None       => "none",
        when Termicap.Clipboard.Write_Only => "write_only",
        when Termicap.Clipboard.Read_Write => "read_write");

   --  Mouse and Keyboard — Unknown maps to {supported:false} elsewhere; the
   --  mapping here covers only the recognised values.
   function Mouse_Str (M : Termicap.Mouse.Mouse_Encoding) return String is
     (case M is
        when Termicap.Mouse.None       => "none",
        when Termicap.Mouse.X10        => "x10",
        when Termicap.Mouse.URXVT      => "urxvt",
        when Termicap.Mouse.SGR        => "sgr",
        when Termicap.Mouse.SGR_Pixels => "sgr_pixels",
        when Termicap.Mouse.Unknown    => "");  --  unreachable in canonical path

   function Keyboard_Str (K : Termicap.Keyboard.Keyboard_Protocol) return String is
     (case K is
        when Termicap.Keyboard.Legacy    => "legacy",
        when Termicap.Keyboard.XTerm_CSI => "xterm_csi",
        when Termicap.Keyboard.Kitty     => "kitty",
        when Termicap.Keyboard.Win32     => "win32",
        when Termicap.Keyboard.Unknown   => "");  --  unreachable in canonical path

   --  Convert termicap's curated DA1_Capability flag array into a sorted
   --  list of Ps integer values, returned as a JSON array literal.
   function DA1_Attributes_Array (Caps : Termicap.DA1.Capability_Flags) return String is
      Buf : Unbounded_String;
      First_Item : Boolean := True;

      procedure Emit (Ps : Natural; Set : Boolean) is
      begin
         if Set then
            if not First_Item then
               Append (Buf, ", ");
            end if;
            Append (Buf, Natural'Image (Ps) (2 .. Natural'Image (Ps)'Last));
            First_Item := False;
         end if;
      end Emit;

   begin
      Append (Buf, "[");
      Emit (2,  Caps (Termicap.DA1.Printer));
      Emit (3,  Caps (Termicap.DA1.ReGIS_Graphics));
      Emit (4,  Caps (Termicap.DA1.Sixel_Graphics));
      Emit (6,  Caps (Termicap.DA1.Selective_Erase));
      Emit (8,  Caps (Termicap.DA1.User_Defined_Keys));
      Emit (18, Caps (Termicap.DA1.Windowing));
      Emit (22, Caps (Termicap.DA1.ANSI_Color));
      Emit (28, Caps (Termicap.DA1.Rectangular_Editing));
      Emit (52, Caps (Termicap.DA1.Clipboard_Access));
      Append (Buf, "]");
      return To_String (Buf);
   end DA1_Attributes_Array;

   ---------------------------------------------------------------------------
   --  Capability emitters — each writes one JSON object value.
   ---------------------------------------------------------------------------

   function Cap_Bool_Measured (V : Boolean; Method : String) return String is
      ("{ ""supported"": true, ""value"": " & Bool_JSON (V)
       & ", ""method"": " & Quote (Method) & " }");

   function Cap_Str_Measured (V : String; Method : String) return String is
      ("{ ""supported"": true, ""value"": " & Quote (V)
       & ", ""method"": " & Quote (Method) & " }");

   function Cap_Not_Measured return String is
      ("{ ""supported"": false }");

   ---------------------------------------------------------------------------
   --  Multiplexer derivation
   ---------------------------------------------------------------------------

   function Multiplexer_Str (Identity : Termicap.Terminal_Id.Terminal_Identity) return String is
   begin
      case Identity.Kind is
         when Termicap.Terminal_Id.Tmux   => return "tmux";
         when Termicap.Terminal_Id.Screen => return "screen";
         when others =>
            if Identity.Is_Multiplexer
              and then Ada.Environment_Variables.Exists ("TMUX")
            then
               return "tmux";
            elsif Identity.Is_Multiplexer
              and then Ada.Environment_Variables.Exists ("STY")
            then
               return "screen";
            else
               return "none";
            end if;
      end case;
   end Multiplexer_Str;

   ---------------------------------------------------------------------------
   --  Main
   ---------------------------------------------------------------------------

   Envelope_Path : constant String :=
     (if Ada.Environment_Variables.Exists ("CONFORMANCE_ENVELOPE")
      then Ada.Environment_Variables.Value ("CONFORMANCE_ENVELOPE")
      else "");
   Output_Path : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "termicap.json");

   Caps          : Termicap.Capabilities.Full_Terminal_Capabilities;
   Envelope_Json : Unbounded_String;
   Out_File      : File_Type;

   --  Render a Natural as a JSON-friendly decimal (no leading space).
   function N (X : Natural) return String is
      Img : constant String := Natural'Image (X);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end N;

begin
   if Envelope_Path = "" then
      Put_Line (Standard_Error, "termicap_shim: error: $CONFORMANCE_ENVELOPE not set");
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   Envelope_Json := To_Unbounded_String (Trim_WS (Read_File (Envelope_Path)));

   Caps := Termicap.Capabilities.Detect_Full;

   Create (File => Out_File, Name => Output_Path);

   Put_Line (Out_File, "{");
   Put_Line (Out_File, "  ""schema_version"": " & Quote (SCHEMA_VERSION) & ",");
   Put (Out_File, "  ""run"": ");
   Put_Line (Out_File, To_String (Envelope_Json) & ",");

   --  Lib block
   Put_Line (Out_File, "  ""lib"": {");
   Put_Line (Out_File, "    ""name"":     " & Quote (LIB_NAME) & ",");
   Put_Line (Out_File, "    ""version"":  " & Quote (LIB_VERSION) & ",");
   Put_Line (Out_File, "    ""language"": " & Quote (LIB_LANG) & ",");
   Put_Line (Out_File, "    ""tier"":     " & Quote (LIB_TIER));
   Put_Line (Out_File, "  },");

   --  Capabilities block
   Put_Line (Out_File, "  ""capabilities"": {");

   Put_Line (Out_File, "    ""tty_stdin"":  "
             & Cap_Bool_Measured (Caps.TTY_Stdin,  "termicap.TTY (isatty)") & ",");
   Put_Line (Out_File, "    ""tty_stdout"": "
             & Cap_Bool_Measured (Caps.TTY_Stdout, "termicap.TTY (isatty)") & ",");
   Put_Line (Out_File, "    ""tty_stderr"": "
             & Cap_Bool_Measured (Caps.TTY_Stderr, "termicap.TTY (isatty)") & ",");

   Put_Line (Out_File, "    ""color_depth"": " & Cap_Str_Measured
             (Color_Depth_Str (Caps.Color),
              "termicap.Color.Detect_Color_Level (env+TTY cascade)") & ",");

   Put_Line (Out_File, "    ""windows_console_color"": " & Cap_Not_Measured & ",");

   Put_Line (Out_File, "    ""dimensions"": { ""supported"": true, ""value"": {");
   Put_Line (Out_File, "      ""cols"": "         & N (Caps.Size.Columns) & ",");
   Put_Line (Out_File, "      ""rows"": "         & N (Caps.Size.Rows) & ",");
   Put_Line (Out_File, "      ""pixel_width"": "  & N (Caps.Size.Pixel_Width) & ",");
   Put_Line (Out_File, "      ""pixel_height"": " & N (Caps.Size.Pixel_Height));
   Put_Line (Out_File, "    }, ""method"": "
             & Quote ("termicap.Dimensions (ioctl(TIOCGWINSZ) -> env -> 80x24)") & " },");

   Put_Line (Out_File, "    ""unicode"": " & Cap_Str_Measured
             (Unicode_Str (Caps.Unicode),
              "termicap.Unicode.Detect_Unicode_Level (locale + env heuristics)") & ",");

   Put_Line (Out_File, "    ""terminal_kind"": " & Cap_Str_Measured
             (Terminal_Kind_Str (Caps.Identity.Kind),
              "termicap.Terminal_Id (passive env-var heuristics)") & ",");

   Put_Line (Out_File, "    ""multiplexer"": " & Cap_Str_Measured
             (Multiplexer_Str (Caps.Identity),
              "termicap.Terminal_Id.Identity.Is_Multiplexer + Kind") & ",");

   --  Theme and background — termicap has internal sub-detectors but does not
   --  expose them through Full_Terminal_Capabilities. Mark not-measured.
   Put_Line (Out_File, "    ""theme"":      " & Cap_Not_Measured & ",");
   Put_Line (Out_File, "    ""background"": " & Cap_Not_Measured & ",");

   --  Hyperlinks (canonical value + raw provenance/version-known)
   Put_Line (Out_File, "    ""hyperlinks"": { ""supported"": true, ""value"": "
             & Quote (Hyperlinks_Str (Caps.Hyperlinks.Support))
             & ", ""method"": "
             & Quote ("termicap.Hyperlinks (passive + XTVERSION refinement)")
             & ", ""raw"": { ""support"": "
             & Quote (Termicap.Hyperlinks.Hyperlinks_Support'Image (Caps.Hyperlinks.Support))
             & ", ""provenance"": "
             & Quote (Hyperlinks_Provenance_Str (Caps.Hyperlinks.Provenance))
             & ", ""version_known"": "
             & Bool_JSON (Caps.Hyperlinks.Terminal_Version_Known) & " } },");

   --  Mouse — Unknown maps to not-measured.
   if Caps.Mouse.Best_Encoding = Termicap.Mouse.Unknown then
      Put_Line (Out_File, "    ""mouse"": " & Cap_Not_Measured & ",");
   else
      Put_Line (Out_File, "    ""mouse"": " & Cap_Str_Measured
                (Mouse_Str (Caps.Mouse.Best_Encoding),
                 "termicap.Mouse (active SGR/SGR-pixel/URXVT/X10 probes)") & ",");
   end if;

   --  Keyboard — Unknown maps to not-measured.
   if Caps.Keyboard.Protocol = Termicap.Keyboard.Unknown then
      Put_Line (Out_File, "    ""keyboard"": " & Cap_Not_Measured & ",");
   else
      Put_Line (Out_File, "    ""keyboard"": " & Cap_Str_Measured
                (Keyboard_Str (Caps.Keyboard.Protocol),
                 "termicap.Keyboard (Kitty progressive + XTerm modifyOtherKeys probes)") & ",");
   end if;

   Put_Line (Out_File, "    ""clipboard_osc52"": " & Cap_Str_Measured
             (Clipboard_Str (Caps.Clipboard.Support),
              "termicap.Clipboard (DA1 Ps=52 + active OSC 52 probe)") & ",");

   Put_Line (Out_File, "    ""graphics_sixel"": "
             & Cap_Bool_Measured (Caps.Graphics.Sixel_Supported,
                                  "termicap.Graphics (DA1 Ps=4 + heuristic)") & ",");
   Put_Line (Out_File, "    ""graphics_kitty"": "
             & Cap_Bool_Measured (Caps.Graphics.Kitty_Graphics_Supported,
                                  "termicap.Graphics (active probe + XTVERSION)") & ",");

   --  XTVERSION — emit when Status = Success; otherwise mark not-measured.
   if Caps.XTVERSION.Status = Termicap.XTVERSION.Success then
      Put_Line (Out_File, "    ""xtversion"": { ""supported"": true, ""value"": { ""name"": "
                & Quote (To_String (Caps.XTVERSION.Terminal_Name))
                & ", ""version"": "
                & Quote (To_String (Caps.XTVERSION.Terminal_Version))
                & " }, ""method"": " & Quote ("termicap.XTVERSION (active CSI > q probe)") & " },");
   else
      Put_Line (Out_File, "    ""xtversion"": " & Cap_Not_Measured & ",");
   end if;

   --  DA1 attributes — emit when Supported, otherwise not-measured.
   if Caps.DA1.Supported then
      Put_Line (Out_File, "    ""da1_attributes"": { ""supported"": true, ""value"": "
                & DA1_Attributes_Array (Caps.DA1.Flags)
                & ", ""method"": "
                & Quote ("termicap.DA1 (active CSI c probe; canonical Ps subset)") & " },");
   else
      Put_Line (Out_File, "    ""da1_attributes"": " & Cap_Not_Measured & ",");
   end if;

   Put_Line (Out_File, "    ""ci_detected"": "
             & Cap_Bool_Measured (Ada.Environment_Variables.Exists ("CI")
                                  or else Ada.Environment_Variables.Exists ("GITHUB_ACTIONS")
                                  or else Ada.Environment_Variables.Exists ("GITLAB_CI")
                                  or else Ada.Environment_Variables.Exists ("CIRCLECI")
                                  or else Ada.Environment_Variables.Exists ("TRAVIS")
                                  or else Ada.Environment_Variables.Exists ("BUILDKITE")
                                  or else Ada.Environment_Variables.Exists ("APPVEYOR")
                                  or else Ada.Environment_Variables.Exists ("TF_BUILD"),
                                  "shim-side env-var allowlist scan"));

   Put_Line (Out_File, "  }");
   Put_Line (Out_File, "}");
   Close (Out_File);

   Put_Line (Standard_Error, "termicap_shim: wrote " & Output_Path);

end Termicap_Shim;
