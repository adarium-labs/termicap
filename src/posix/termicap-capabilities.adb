-------------------------------------------------------------------------------
--  Termicap.Capabilities - Terminal Capability Record Assembly (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  This body is compiled with SPARK_Mode => Off because it contains an Ada
--  protected object (cache) and calls to OS FFI sub-detectors, both of which
--  are outside the SPARK 2014 subset.  The Assemble function's contract
--  (Global => null, Post) is declared in the spec; the prover verifies callers
--  of Assemble against that contract.

with Termicap.Clipboard.IO;
with Termicap.DA1.IO;
with Termicap.Environment.Capture;
with Termicap.Graphics.IO;
with Termicap.Hyperlinks;
with Termicap.Keyboard.IO;
with Termicap.Mouse.IO;
with Termicap.XTVERSION.IO;

package body Termicap.Capabilities
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Assemble (FUNC-CAP-012, FUNC-CAP-013, FUNC-HYP-014)
   ---------------------------------------------------------------------------

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
      return Terminal_Capabilities is
   begin
      return
        Terminal_Capabilities'
          (TTY_Stdin              => TTY_Stdin,
           TTY_Stdout             => TTY_Stdout,
           TTY_Stderr             => TTY_Stderr,
           Color                  => Color,
           Size                   => Size,
           Unicode                => Unicode,
           Identity               => Identity,
           Downsampling_Available => Color >= Termicap.Color.Extended_256,
           DA1                    => DA1,
           Hyperlinks             => Hyperlinks);
   end Assemble;

   ---------------------------------------------------------------------------
   --  Cache Ã¢ÂÂ protected object for lazy per-stream caching (FUNC-CAP-008)
   ---------------------------------------------------------------------------

   type Cache_Slot is record
      Initialized : Boolean := False;
      Value       : Terminal_Capabilities;
   end record;

   type Cache_Array is array (Termicap.TTY.Stream_Kind) of Cache_Slot;

   protected Cache is
      function Get_Cached (Stream : Termicap.TTY.Stream_Kind) return Cache_Slot;
      procedure Set_Cached (Stream : Termicap.TTY.Stream_Kind; Caps : Terminal_Capabilities);
   private
      Slots : Cache_Array;
   end Cache;

   protected body Cache is

      function Get_Cached (Stream : Termicap.TTY.Stream_Kind) return Cache_Slot is
      begin
         return Slots (Stream);
      end Get_Cached;

      procedure Set_Cached (Stream : Termicap.TTY.Stream_Kind; Caps : Terminal_Capabilities) is
      begin
         Slots (Stream) := (Initialized => True, Value => Caps);
      end Set_Cached;

   end Cache;

   ---------------------------------------------------------------------------
   --  Detect (FUNC-CAP-004) Ã¢ÂÂ fresh, uncached detection
   ---------------------------------------------------------------------------

   function Detect (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Terminal_Capabilities is
      Env               : Termicap.Environment.Environment;
      Id                : Termicap.Terminal_Id.Terminal_Identity;
      TTY_All           : Termicap.TTY.TTY_Status;
      Is_TTY_For_Stream : Boolean;
      Color             : Termicap.Color.Color_Level;
      Size              : Termicap.Dimensions.Terminal_Size;
      Uni               : Termicap.Unicode.Unicode_Level;
      DA1_Caps          : Termicap.DA1.DA1_Capabilities;
   begin
      --  Step 1: Capture a single environment snapshot for this detection run.
      Termicap.Environment.Capture.Capture_Current (Env);

      --  Step 2: Identify the terminal emulator or multiplexer.
      Id := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);

      --  Step 3: Query TTY status for all three streams (override-aware).
      TTY_All := Termicap.TTY.Query_All;

      --  Step 4: Select the TTY flag for the requested stream.
      Is_TTY_For_Stream :=
        (case Stream is
           when Termicap.TTY.Stdin => TTY_All.Stdin,
           when Termicap.TTY.Stdout => TTY_All.Stdout,
           when Termicap.TTY.Stderr => TTY_All.Stderr);

      --  Step 4 (cont.): Detect color level (override-aware via Detect_Color_Level).
      Color := Termicap.Color.Detect_Color_Level (Env, Is_TTY_For_Stream);

      --  Step 5: Detect terminal dimensions (always via stdout TTY flag).
      Size := Termicap.Dimensions.Get_Size (Env, TTY_All.Stdout);

      --  Step 6: Detect Unicode support level.
      Uni := Termicap.Unicode.Detect_Unicode_Level (Env);

      --  Step 7: Detect DA1 primary device attributes (active probe).
      DA1_Caps := Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => 100);

      --  Step 7.5: Passive OSC 8 hyperlink classification (FUNC-HYP-014).
      --  Uses already-captured Env and Id; no I/O.
      declare
         HL : constant Termicap.Hyperlinks.Hyperlinks_Result :=
           Termicap.Hyperlinks.Classify_Hyperlinks_Support (Env, Id);
      begin
         --  Steps 8 + 9: Derive Downsampling_Available and assemble the record.
         return
           Assemble
             (TTY_Stdin  => TTY_All.Stdin,
              TTY_Stdout => TTY_All.Stdout,
              TTY_Stderr => TTY_All.Stderr,
              Color      => Color,
              Size       => Size,
              Unicode    => Uni,
              Identity   => Id,
              DA1        => DA1_Caps,
              Hyperlinks => HL);
      end;
   end Detect;

   ---------------------------------------------------------------------------
   --  Get (FUNC-CAP-003) Ã¢ÂÂ lazy cached detection
   ---------------------------------------------------------------------------

   function Get (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Terminal_Capabilities is
      Slot : constant Cache_Slot := Cache.Get_Cached (Stream);
   begin
      if Slot.Initialized then
         return Slot.Value;
      end if;

      declare
         Result : constant Terminal_Capabilities := Detect (Stream);
      begin
         Cache.Set_Cached (Stream, Result);
         return Result;
      end;
   end Get;

   ---------------------------------------------------------------------------
   --  Assemble_Full
   ---------------------------------------------------------------------------

   function Assemble_Full
     (Base       : Terminal_Capabilities;
      XTVERSION  : Termicap.XTVERSION.XTVERSION_Result;
      Keyboard   : Termicap.Keyboard.Keyboard_Capability;
      Mouse      : Termicap.Mouse.Mouse_Capabilities;
      Graphics   : Termicap.Graphics.Graphics_Capabilities;
      Clipboard  : Termicap.Clipboard.Clipboard_Capabilities;
      Hyperlinks : Termicap.Hyperlinks.Hyperlinks_Result := Termicap.Hyperlinks.DEFAULT_HYPERLINKS_RESULT)
      return Full_Terminal_Capabilities is
   begin
      return
        Full_Terminal_Capabilities'
          (TTY_Stdin              => Base.TTY_Stdin,
           TTY_Stdout             => Base.TTY_Stdout,
           TTY_Stderr             => Base.TTY_Stderr,
           Color                  => Base.Color,
           Size                   => Base.Size,
           Unicode                => Base.Unicode,
           Identity               => Base.Identity,
           Downsampling_Available => Base.Downsampling_Available,
           DA1                    => Base.DA1,
           XTVERSION              => XTVERSION,
           Keyboard               => Keyboard,
           Mouse                  => Mouse,
           Graphics               => Graphics,
           Clipboard              => Clipboard,
           Hyperlinks             => Hyperlinks);
   end Assemble_Full;

   ---------------------------------------------------------------------------
   --  Full_Cache -- protected object for lazy per-stream caching
   ---------------------------------------------------------------------------

   type Full_Cache_Slot is record
      Initialized : Boolean := False;
      Value       : Full_Terminal_Capabilities;
   end record;

   type Full_Cache_Array is array (Termicap.TTY.Stream_Kind) of Full_Cache_Slot;

   protected Full_Cache is
      function Get_Cached (Stream : Termicap.TTY.Stream_Kind) return Full_Cache_Slot;
      procedure Set_Cached (Stream : Termicap.TTY.Stream_Kind; Caps : Full_Terminal_Capabilities);
   private
      Slots : Full_Cache_Array;
   end Full_Cache;

   protected body Full_Cache is

      function Get_Cached (Stream : Termicap.TTY.Stream_Kind) return Full_Cache_Slot is
      begin
         return Slots (Stream);
      end Get_Cached;

      procedure Set_Cached (Stream : Termicap.TTY.Stream_Kind; Caps : Full_Terminal_Capabilities) is
      begin
         Slots (Stream) := (Initialized => True, Value => Caps);
      end Set_Cached;

   end Full_Cache;

   ---------------------------------------------------------------------------
   --  Detect_Full -- fresh, uncached full detection
   ---------------------------------------------------------------------------

   function Detect_Full (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Full_Terminal_Capabilities is
      --  Steps 1-8: Detect base capabilities (Env, Id, TTY, Color, Size, Unicode, DA1).
      Base_Caps : constant Terminal_Capabilities := Detect (Stream);

      --  Step 9: XTVERSION active probe (terminal name/version identification).
      XTV : constant Termicap.XTVERSION.XTVERSION_Result :=
        Termicap.XTVERSION.IO.Query_And_Identify (Timeout_Ms => 1_000);

      --  Step 10: Graphics detection (self-contained; uses its own DA1 + XTVERSION probes).
      GFX : constant Termicap.Graphics.Graphics_Capabilities := Termicap.Graphics.IO.Detect_Graphics_Uncached;

      --  Step 11: Keyboard protocol detection.
      KBD : constant Termicap.Keyboard.Keyboard_Capability := Termicap.Keyboard.IO.Probe_Keyboard_Protocol;

      --  Step 12: Mouse protocol detection.
      MSE : constant Termicap.Mouse.Mouse_Capabilities := Termicap.Mouse.IO.Probe_Mouse_Protocols;

      --  Step 13: Clipboard detection (self-contained; uses its own DA1 probe).
      CLB : constant Termicap.Clipboard.Clipboard_Capabilities := Termicap.Clipboard.IO.Detect_Clipboard_Uncached;

      --  Step 14: Hyperlinks XTVERSION refinement (FUNC-HYP-015, ADR-0038).
      --  Reuses the XTV value above; opens no new probe session.
      HLR : constant Termicap.Hyperlinks.Hyperlinks_Result :=
        Termicap.Hyperlinks.Refine_With_XTVERSION (Base_Caps.Hyperlinks, XTV);
   begin
      return Assemble_Full (Base_Caps, XTV, KBD, MSE, GFX, CLB, HLR);
   end Detect_Full;

   ---------------------------------------------------------------------------
   --  Get_Full -- lazy cached full detection
   ---------------------------------------------------------------------------

   function Get_Full (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout) return Full_Terminal_Capabilities is
      Slot : constant Full_Cache_Slot := Full_Cache.Get_Cached (Stream);
   begin
      if Slot.Initialized then
         return Slot.Value;
      end if;

      declare
         Result : constant Full_Terminal_Capabilities := Detect_Full (Stream);
      begin
         Full_Cache.Set_Cached (Stream, Result);
         return Result;
      end;
   end Get_Full;

end Termicap.Capabilities;
