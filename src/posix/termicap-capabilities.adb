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

with Termicap.DA1.IO;
with Termicap.Environment.Capture;

package body Termicap.Capabilities
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Assemble (FUNC-CAP-012, FUNC-CAP-013)
   ---------------------------------------------------------------------------

   function Assemble
     (TTY_Stdin  : Boolean;
      TTY_Stdout : Boolean;
      TTY_Stderr : Boolean;
      Color      : Termicap.Color.Color_Level;
      Size       : Termicap.Dimensions.Terminal_Size;
      Unicode    : Termicap.Unicode.Unicode_Level;
      Identity   : Termicap.Terminal_Id.Terminal_Identity;
      DA1        : Termicap.DA1.DA1_Capabilities) return Terminal_Capabilities is
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
           DA1                    => DA1);
   end Assemble;

   ---------------------------------------------------------------------------
   --  Cache â protected object for lazy per-stream caching (FUNC-CAP-008)
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
   --  Detect (FUNC-CAP-004) â fresh, uncached detection
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
           DA1        => DA1_Caps);
   end Detect;

   ---------------------------------------------------------------------------
   --  Get (FUNC-CAP-003) â lazy cached detection
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

end Termicap.Capabilities;
