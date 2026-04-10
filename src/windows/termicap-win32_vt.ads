-------------------------------------------------------------------------------
--  Termicap.Win32_VT - VT Processing and Console Handle Helpers
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Provides VT processing enablement and CONIN$/CONOUT$ fallback operations.
--
--  @description
--  This package centralises all Win32 console handle helpers used by the
--  Windows platform bodies of Termicap.TTY, Termicap.Dimensions, and
--  Termicap.Capabilities.  It declares the ENABLE_VIRTUAL_TERMINAL_PROCESSING
--  constant missing from win32ada, the Is_Valid_Handle predicate, CONIN$/CONOUT$
--  open/close operations, and the VT processing enablement function.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-001): Is_Valid_Handle predicate
--    - @relation(FUNC-WIN-004): CONIN$/CONOUT$ fallback
--    - @relation(FUNC-WIN-009): ENABLE_VIRTUAL_TERMINAL_PROCESSING constant
--    - @relation(FUNC-WIN-010): SetConsoleMode binding usage
--    - @relation(FUNC-WIN-011): Enable VT processing

with Win32;
with Win32.Winnt;

package Termicap.Win32_VT
   with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Constants (FUNC-WIN-009)
   ---------------------------------------------------------------------------

   --  Missing from win32ada; declared by Termicap.
   --  This is the Windows 10 console flag that instructs the console host
   --  to interpret ANSI/VT escape sequences.
   ENABLE_VIRTUAL_TERMINAL_PROCESSING : constant Win32.DWORD := 16#0004#;

   ---------------------------------------------------------------------------
   --  Handle Validation (FUNC-WIN-001)
   ---------------------------------------------------------------------------

   --  @summary Check whether a Win32 handle is valid (not INVALID_HANDLE_VALUE
   --           and not null).
   --  @param H The handle to validate.
   --  @return True when H is a usable console handle.
   --  @relation(FUNC-WIN-001): INVALID_HANDLE_VALUE check
   function Is_Valid_Handle (H : Win32.Winnt.HANDLE) return Boolean;

   ---------------------------------------------------------------------------
   --  CONIN$/CONOUT$ Fallback (FUNC-WIN-004)
   ---------------------------------------------------------------------------

   --  @summary Open the console input device directly via CONIN$.
   --  @return A handle to CONIN$, or INVALID_HANDLE_VALUE on failure.
   --  @relation(FUNC-WIN-004): CONIN$ device access
   function Open_Console_Input return Win32.Winnt.HANDLE;

   --  @summary Open the console output device directly via CONOUT$.
   --  @return A handle to CONOUT$, or INVALID_HANDLE_VALUE on failure.
   --  @relation(FUNC-WIN-004): CONOUT$ device access
   function Open_Console_Output return Win32.Winnt.HANDLE;

   --  @summary Close a console handle. Does not raise on failure.
   --  @param H The handle to close.
   --  @relation(FUNC-WIN-004): Cleanup for opened CONIN$/CONOUT$ handles
   procedure Close_Handle (H : Win32.Winnt.HANDLE);

   ---------------------------------------------------------------------------
   --  VT Processing (FUNC-WIN-011)
   ---------------------------------------------------------------------------

   --  @summary Enable ANSI/VT escape sequence processing on a console handle.
   --  @param H The console output handle.
   --  @return True if VT processing is now enabled, False on failure.
   --  @relation(FUNC-WIN-011): Enable via read-modify-write GetConsoleMode/SetConsoleMode
   function Enable_VT_Processing (H : Win32.Winnt.HANDLE) return Boolean;

end Termicap.Win32_VT;
