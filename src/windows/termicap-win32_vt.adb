-------------------------------------------------------------------------------
--  Termicap.Win32_VT - VT Processing and Console Handle Helpers
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Implements console handle validation, CONIN$/CONOUT$ open/close operations,
--  and ENABLE_VIRTUAL_TERMINAL_PROCESSING enablement via Win32 API calls.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-001): Is_Valid_Handle predicate
--    - @relation(FUNC-WIN-004): CONIN$/CONOUT$ fallback
--    - @relation(FUNC-WIN-010): SetConsoleMode binding usage
--    - @relation(FUNC-WIN-011): Enable VT processing

with System;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;

package body Termicap.Win32_VT
   with SPARK_Mode => Off
is

   use type Win32.Winnt.HANDLE;
   use type Win32.BOOL;
   use type Win32.DWORD;

   ---------------------------------------------------------------------------
   --  Is_Valid_Handle (FUNC-WIN-001)
   ---------------------------------------------------------------------------

   function Is_Valid_Handle (H : Win32.Winnt.HANDLE) return Boolean is
   begin
      return H /= Win32.Winbase.INVALID_HANDLE_VALUE
             and then H /= System.Null_Address;
   end Is_Valid_Handle;

   ---------------------------------------------------------------------------
   --  Open_Console_Input (FUNC-WIN-004)
   ---------------------------------------------------------------------------

   function Open_Console_Input return Win32.Winnt.HANDLE is
      Name : constant String := "CONIN$" & ASCII.NUL;
   begin
      return Win32.Winbase.CreateFileA
        (lpFileName            => Win32.Addr (Name),
         dwDesiredAccess       => Win32.DWORD (Win32.Winnt.GENERIC_READ)
                                  or Win32.DWORD (Win32.Winnt.GENERIC_WRITE),
         dwShareMode           => Win32.DWORD (Win32.Winnt.FILE_SHARE_READ)
                                  or Win32.DWORD (Win32.Winnt.FILE_SHARE_WRITE),
         lpSecurityAttributes  => null,
         dwCreationDisposition => Win32.Winbase.OPEN_EXISTING,
         dwFlagsAndAttributes  => 0,
         hTemplateFile         => System.Null_Address);
   end Open_Console_Input;

   ---------------------------------------------------------------------------
   --  Open_Console_Output (FUNC-WIN-004)
   ---------------------------------------------------------------------------

   function Open_Console_Output return Win32.Winnt.HANDLE is
      Name : constant String := "CONOUT$" & ASCII.NUL;
   begin
      return Win32.Winbase.CreateFileA
        (lpFileName            => Win32.Addr (Name),
         dwDesiredAccess       => Win32.DWORD (Win32.Winnt.GENERIC_WRITE),
         dwShareMode           => Win32.DWORD (Win32.Winnt.FILE_SHARE_READ)
                                  or Win32.DWORD (Win32.Winnt.FILE_SHARE_WRITE),
         lpSecurityAttributes  => null,
         dwCreationDisposition => Win32.Winbase.OPEN_EXISTING,
         dwFlagsAndAttributes  => 0,
         hTemplateFile         => System.Null_Address);
   end Open_Console_Output;

   ---------------------------------------------------------------------------
   --  Close_Handle (FUNC-WIN-004)
   ---------------------------------------------------------------------------

   procedure Close_Handle (H : Win32.Winnt.HANDLE) is
      Unused : Win32.BOOL;
      pragma Unreferenced (Unused);
   begin
      Unused := Win32.Winbase.CloseHandle (H);
   end Close_Handle;

   ---------------------------------------------------------------------------
   --  Enable_VT_Processing (FUNC-WIN-011)
   ---------------------------------------------------------------------------

   function Enable_VT_Processing (H : Win32.Winnt.HANDLE) return Boolean is
      Current_Mode : aliased Win32.DWORD := 0;
      Result       : Win32.BOOL;
   begin
      --  Step 1: Read current console mode
      Result := Win32.Wincon.GetConsoleMode (H, Current_Mode'Unchecked_Access);
      if Result = Win32.FALSE then
         return False;
      end if;

      --  Step 2: Check whether VT processing is already enabled
      if (Current_Mode and ENABLE_VIRTUAL_TERMINAL_PROCESSING) /= 0 then
         return True;
      end if;

      --  Step 3: Enable VT processing via read-modify-write
      Result := Win32.Wincon.SetConsoleMode
        (H, Current_Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);

      return Result /= Win32.FALSE;
   end Enable_VT_Processing;

end Termicap.Win32_VT;
