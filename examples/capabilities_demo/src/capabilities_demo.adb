-------------------------------------------------------------------------------
--  Capabilities_Demo - Terminal Capability Record Assembly Usage Examples
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Demonstrates the Termicap.Capabilities API for obtaining a fully assembled
--  terminal capability snapshot in a single call.
--
--  @description
--  Covers five realistic scenarios:
--
--  Scene 1 — Basic usage (Get):
--    The most common pattern.  Call Get with no arguments to obtain a cached
--    Terminal_Capabilities record populated from all sub-detectors.  Print
--    every field so the reader can see what the record contains.
--
--  Scene 2 — Per-stream query:
--    Query for stderr instead of stdout.  Useful for logging libraries that
--    write coloured diagnostic output to stderr while the application writes
--    its own output to stdout.
--
--  Scene 3 — Detect (fresh, uncached):
--    Use Detect when up-to-date information is required, for example after a
--    SIGWINCH resize signal or after an override change.  Detect never touches
--    the cache and always runs every sub-detector from scratch.
--
--  Scene 4 — Override integration:
--    Simulate a --color=always CLI flag by calling Set_Override before Detect.
--    Show that Color becomes True_Color and Downsampling_Available becomes True
--    regardless of the real terminal.  Restore Auto afterwards.
--
--  Scene 5 — Downsampling_Available gate:
--    Demonstrate the guard pattern: inspect Downsampling_Available before
--    enabling any 256-color or TrueColor rendering path.
--
--  Requirements demonstrated:
--    FUNC-CAP-001  Terminal_Capabilities record type
--    FUNC-CAP-002  Stream selection for per-stream color detection
--    FUNC-CAP-003  Get function — cached lazy initialisation
--    FUNC-CAP-004  Detect function — fresh detection
--    FUNC-CAP-005  Default stream convenience (default parameter)
--    FUNC-CAP-006  Override state applied to Color field
--    FUNC-CAP-009  Immutability of returned record (value semantics)
--    FUNC-CAP-014  Re-detection on explicit Detect call

with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Termicap.Capabilities;
with Termicap.Color;
with Termicap.Override;
with Termicap.Terminal_Id;
with Termicap.TTY;
with Termicap.Unicode;

procedure Capabilities_Demo is

   ---------------------------------------------------------------------------
   --  Helper: print every field of a Terminal_Capabilities record.
   ---------------------------------------------------------------------------

   procedure Print_Caps
     (Label : String;
      Caps  : Termicap.Capabilities.Terminal_Capabilities)
   is
      use Ada.Text_IO;
      use Ada.Strings.Unbounded;
   begin
      Put_Line ("  [" & Label & "]");
      Put_Line ("  TTY_Stdin              : "
                & Boolean'Image (Caps.TTY_Stdin));
      Put_Line ("  TTY_Stdout             : "
                & Boolean'Image (Caps.TTY_Stdout));
      Put_Line ("  TTY_Stderr             : "
                & Boolean'Image (Caps.TTY_Stderr));
      Put_Line ("  Color                  : "
                & Termicap.Color.Color_Level'Image (Caps.Color));
      Put_Line ("  Size (Cols x Rows)     : "
                & Positive'Image (Caps.Size.Columns)
                & " x"
                & Positive'Image (Caps.Size.Rows));
      Put_Line ("  Unicode                : "
                & Termicap.Unicode.Unicode_Level'Image (Caps.Unicode));
      Put_Line ("  Identity.Kind          : "
                & Termicap.Terminal_Id.Terminal_Kind'Image
                    (Caps.Identity.Kind));
      Put_Line ("  Identity.Is_Multiplexer: "
                & Boolean'Image (Caps.Identity.Is_Multiplexer));
      Put_Line ("  Identity.Program_Name  : """
                & To_String (Caps.Identity.Program_Name) & """");
      Put_Line ("  Downsampling_Available : "
                & Boolean'Image (Caps.Downsampling_Available));
   end Print_Caps;

begin

   Ada.Text_IO.Put_Line ("=== Termicap Capabilities API Demo ===");
   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Scene 1 — Basic usage (Get)
   --
   --  Get is the right call for most applications: it returns the cached
   --  result for the default stream (Stdout) on first call, and returns the
   --  same cached snapshot on every subsequent call.  No overhead on repeated
   --  use.  (FUNC-CAP-003, FUNC-CAP-005)
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scene 1: Basic usage (Get) ---");

   declare
      --  Caps is a plain record value — no pointers, no aliasing.  Each field
      --  was populated by running all sub-detectors exactly once.
      --  (FUNC-CAP-001, FUNC-CAP-009)
      Caps : constant Termicap.Capabilities.Terminal_Capabilities :=
        Termicap.Capabilities.Get;
   begin
      Print_Caps ("stdout, cached", Caps);
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Scene 2 — Per-stream query
   --
   --  A logging library that writes coloured diagnostic lines to stderr should
   --  inspect stderr capabilities, not stdout.  Pass Stream => Stderr to Get
   --  (or Detect) to obtain a record whose Color and TTY_Stderr fields reflect
   --  that stream.  (FUNC-CAP-002, FUNC-CAP-005)
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scene 2: Per-stream query (stderr) ---");

   declare
      --  Query stderr: Color and TTY_* fields are determined from the stderr
      --  stream.  Size is always derived from stdout regardless of Stream.
      Stderr_Caps : constant Termicap.Capabilities.Terminal_Capabilities :=
        Termicap.Capabilities.Get (Stream => Termicap.TTY.Stderr);
   begin
      Print_Caps ("stderr, cached", Stderr_Caps);
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Scene 3 — Detect (fresh, uncached)
   --
   --  After a SIGWINCH signal the terminal dimensions may have changed.
   --  Get would return the stale cached size; Detect always runs every
   --  sub-detector from scratch and never reads or writes the cache.
   --  (FUNC-CAP-004, FUNC-CAP-014)
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scene 3: Detect (fresh, uncached) ---");

   declare
      --  Fresh re-detection: reads the live OS state.  Override state at the
      --  time of this call is applied (currently Auto — no override).
      Fresh : constant Termicap.Capabilities.Terminal_Capabilities :=
        Termicap.Capabilities.Detect;
   begin
      Print_Caps ("stdout, fresh", Fresh);
   end;

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Scene 4 — Override integration
   --
   --  An application that accepts a --color=always flag should call
   --  Set_Override before querying capabilities.  Because the Scene 1 call to
   --  Get already populated the stdout cache (under Auto), we use Detect here
   --  to obtain a fresh, override-aware snapshot without disturbing the cache.
   --  (FUNC-CAP-006, FUNC-OVR-002)
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scene 4: Override integration (--color=always) ---");

   --  Simulate the user passing --color=always on the command line.
   --  Force_True_Color bypasses all environment heuristics and TTY checks.
   Termicap.Override.Set_Override (Termicap.Override.Force_True_Color);

   declare
      --  Detect re-runs every sub-detector.  Color must be True_Color and
      --  Downsampling_Available must be True regardless of the real terminal.
      Forced : constant Termicap.Capabilities.Terminal_Capabilities :=
        Termicap.Capabilities.Detect;
   begin
      Print_Caps ("stdout, Force_True_Color override", Forced);

      --  Assertions the reader should verify in the output:
      --    Color                  = TRUE_COLOR
      --    Downsampling_Available = TRUE
      Ada.Text_IO.Put_Line
        ("  (Color should be TRUE_COLOR; Downsampling_Available should be TRUE)");
   end;

   --  Restore Auto so the process ends in a clean state.  Any subsequent call
   --  to Get or Detect will use normal detection logic again.
   Termicap.Override.Set_Override (Termicap.Override.Auto);

   Ada.Text_IO.New_Line;

   ---------------------------------------------------------------------------
   --  Scene 5 — Downsampling_Available gate
   --
   --  Downsampling_Available is True when Color >= Extended_256.  Applications
   --  should check this field before enabling any rendering path that relies on
   --  color downsampling (e.g. mapping 24-bit RGB to the nearest 256-color
   --  palette entry).  On Basic_16 or None terminals the field is False.
   --  (FUNC-CAP-001, FUNC-CAP-012)
   ---------------------------------------------------------------------------

   Ada.Text_IO.Put_Line ("--- Scene 5: Downsampling_Available gate ---");

   declare
      --  Re-use the cached stdout capabilities from Scene 1.
      --  The Downsampling_Available field is guaranteed by the SPARK postcondition
      --  on Assemble to be consistent with the Color field:
      --    Downsampling_Available = (Color >= Extended_256)
      Caps : constant Termicap.Capabilities.Terminal_Capabilities :=
        Termicap.Capabilities.Get;
   begin
      Ada.Text_IO.Put_Line
        ("  Color level detected: "
         & Termicap.Color.Color_Level'Image (Caps.Color));

      if Caps.Downsampling_Available then
         --  Safe to use 256-color or TrueColor rendering paths.
         Ada.Text_IO.Put_Line
           ("  Downsampling is available — color downsampling path enabled.");
      else
         --  Fall back to ANSI 16-color output or plain text.
         Ada.Text_IO.Put_Line
           ("  Downsampling not available (Basic_16 or None)"
            & " — plain output path selected.");
      end if;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("Done.");

end Capabilities_Demo;
