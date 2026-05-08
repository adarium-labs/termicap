-------------------------------------------------------------------------------
--  Termicap.Keyboard.IO - Keyboard Protocol Detection I/O (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows implementation of the keyboard protocol detection cascade.
--  Prepends a Win32 Console gate (step 1) before the POSIX-like cascade.
--
--  @description
--  Step 1: GetConsoleMode (STD_INPUT_HANDLE).  If it succeeds, stdin is a
--  native Windows Console (not a Cygwin/MSYS PTY); return Win32 immediately
--  without probing (FUNC-KKB-010).  If it fails, fall through to the
--  POSIX-like cascade starting at the TTY guard (step 2).
--
--  Steps 2-6 are identical to the POSIX body.  On Cygwin/MSYS PTY,
--  GetConsoleMode returns FALSE, Is_TTY returns True (via Cygwin branch),
--  and the Kitty/XTerm probes run normally (FUNC-KKB-010 fall-through).
--
--  A single protected object caches the result for the process lifetime
--  (FUNC-KKB-017).  Probe_Keyboard_Protocol bypasses the cache.
--
--  The outer exception handler satisfies the no-exception contract for
--  Detect_Keyboard_Protocol (FUNC-KKB-014).
--
--  Requirements Coverage:
--    - @relation(FUNC-KKB-009): Full detection cascade
--    - @relation(FUNC-KKB-010): Win32 Console platform gate
--    - @relation(FUNC-KKB-011): Non-TTY and foreground guards
--    - @relation(FUNC-KKB-012): OSC-INFRA reuse via Probe_Session / Sentinel_Query
--    - @relation(FUNC-KKB-013): 1000 ms per-probe timeout
--    - @relation(FUNC-KKB-014): No-exception guarantee
--    - @relation(FUNC-KKB-015): Termios restore via Probe_Session RAII
--    - @relation(FUNC-KKB-016): Garbled / partial response handling
--    - @relation(FUNC-KKB-017): Process-lifetime cache

pragma SPARK_Mode (Off);

with Termicap.OSC;
with Termicap.TTY;
with Termicap.Win32_VT;
with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;

package body Termicap.Keyboard.IO is

   --  The Win32 package name is shadowed inside this body by the Win32
   --  enum literal in Termicap.Keyboard.Keyboard_Protocol.  Rename through
   --  Standard to disambiguate; child packages remain accessible via W32.
   package W32 renames Standard.Win32;

   use type W32.BOOL;

   ---------------------------------------------------------------------------
   --  Process-lifetime cache (FUNC-KKB-017)
   ---------------------------------------------------------------------------

   type Cache_Slot is record
      Initialized : Boolean := False;
      Value       : Keyboard_Capability;
   end record;

   protected Cache is
      function  Get_Cached return Cache_Slot;
      procedure Set_Cached (Cap : Keyboard_Capability);
   private
      Slot : Cache_Slot := (Initialized => False, Value => NO_KEYBOARD_CAPABILITY);
   end Cache;

   protected body Cache is

      function Get_Cached return Cache_Slot is
      begin
         return Slot;
      end Get_Cached;

      procedure Set_Cached (Cap : Keyboard_Capability) is
      begin
         Slot := (Initialized => True, Value => Cap);
      end Set_Cached;

   end Cache;


   ---------------------------------------------------------------------------
   --  Internal helper: run the full cascade without cache interaction.
   ---------------------------------------------------------------------------

   function Run_Cascade return Keyboard_Capability is
      use Termicap.OSC;

      Session     : Termicap.OSC.Probe_Session;
      Status      : Termicap.OSC.Session_Status;
      Raw         : Termicap.OSC.Response_Buffer;
      Raw_Len     : Natural;
      Timed_Out   : Boolean;
      Kitty_Parse : Parse_Result;

      --  Win32 gate (FUNC-KKB-010)
      H    : W32.Winnt.HANDLE;
      Mode : aliased W32.DWORD := 0;
      Res  : W32.BOOL;
   begin
      --  Step 1: Win32 Console gate (FUNC-KKB-010).
      --  GetStdHandle may return INVALID_HANDLE_VALUE or null on failure.
      H := W32.Winbase.GetStdHandle (W32.Winbase.STD_INPUT_HANDLE);
      if Termicap.Win32_VT.Is_Valid_Handle (H) then
         Res := W32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
         if Res /= W32.FALSE then
            --  Native Windows Console confirmed; no escape probe needed.
            return
              (Protocol => Win32,
               Flags    => NO_KITTY_FLAGS,
               Probed   => False);
         end if;
         --  GetConsoleMode returned FALSE: Cygwin/MSYS PTY, pipe, or file.
         --  Fall through to the POSIX-like cascade below.
      end if;

      --  Step 2: TTY guard (FUNC-KKB-011).
      if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdin) then
         return NO_KEYBOARD_CAPABILITY;
      end if;

      --  Step 3: Open Probe_Session (foreground guard is inside Open).
      Termicap.OSC.Open (Session, Status);
      if Status /= Session_OK then
         return NO_KEYBOARD_CAPABILITY;
      end if;

      --  Step 4: Kitty probe (FUNC-KKB-004).
      Termicap.OSC.Sentinel_Query
        (Session     => Session,
         Query       => CSI_KITTY_QUERY,
         Response    => Raw,
         Resp_Length => Raw_Len,
         Timeout_Ms  => KITTY_PROBE_TIMEOUT_MS,
         Timed_Out   => Timed_Out,
         Retry       => False);

      if not Timed_Out and then Raw_Len > 0 then
         Kitty_Parse := Parse_Kitty_Response
           (Byte_Array (Raw (1 .. MAX_RESPONSE_SIZE)), Raw_Len);
         if Kitty_Parse.Valid then
            return
              (Protocol => Kitty,
               Flags    => Parse_Kitty_Flags (Kitty_Parse.Flags_Int),
               Probed   => True);
         end if;
      end if;

      --  Step 5: XTerm modifyOtherKeys probe (FUNC-KKB-007).
      Termicap.OSC.Sentinel_Query
        (Session     => Session,
         Query       => CSI_XTERM_KBD_QUERY,
         Response    => Raw,
         Resp_Length => Raw_Len,
         Timeout_Ms  => XTERM_KBD_PROBE_TIMEOUT_MS,
         Timed_Out   => Timed_Out,
         Retry       => False);

      if not Timed_Out and then Raw_Len > 0 then
         if Parse_XTerm_Keyboard_Response
              (Byte_Array (Raw (1 .. MAX_RESPONSE_SIZE)), Raw_Len)
         then
            return
              (Protocol => XTerm_CSI,
               Flags    => NO_KITTY_FLAGS,
               Probed   => True);
         end if;
      end if;

      --  Step 6: Legacy — probed successfully; no enhanced protocol found.
      return (Protocol => Legacy, Flags => NO_KITTY_FLAGS, Probed => True);
   end Run_Cascade;


   ---------------------------------------------------------------------------
   --  Detect_Keyboard_Protocol (FUNC-KKB-009, FUNC-KKB-017)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-KKB-009): Full detection cascade
   --  @relation(FUNC-KKB-014): No-exception guarantee
   --  @relation(FUNC-KKB-017): One-probe-per-process caching
   function Detect_Keyboard_Protocol return Keyboard_Capability is
      Cached : Cache_Slot;
      Result : Keyboard_Capability;
   begin
      Cached := Cache.Get_Cached;
      if Cached.Initialized then
         return Cached.Value;
      end if;

      Result := Run_Cascade;
      Cache.Set_Cached (Result);
      return Result;
   exception
      when others =>
         --  FUNC-KKB-014: no-exception guarantee net.
         return NO_KEYBOARD_CAPABILITY;
   end Detect_Keyboard_Protocol;


   ---------------------------------------------------------------------------
   --  Probe_Keyboard_Protocol (FUNC-KKB-017 Should Clause)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-KKB-017): Cache-bypass detection for test use
   --  @relation(FUNC-KKB-014): No-exception guarantee
   function Probe_Keyboard_Protocol return Keyboard_Capability is
   begin
      return Run_Cascade;
   exception
      when others =>
         return NO_KEYBOARD_CAPABILITY;
   end Probe_Keyboard_Protocol;

end Termicap.Keyboard.IO;
