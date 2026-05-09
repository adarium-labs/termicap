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
--    - @relation(FUNC-WIN-014): ConPTY-aware active-probe gate
--    - @relation(FUNC-OSC-017): ENABLE_VIRTUAL_TERMINAL_INPUT / DISABLE_NEWLINE_AUTO_RETURN

with Win32;
with Win32.Winnt;

package Termicap.Win32_VT
   with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Constants (FUNC-WIN-009, FUNC-OSC-017)
   ---------------------------------------------------------------------------

   --  Missing from win32ada; declared by Termicap.
   --  This is the Windows 10 console flag that instructs the console host
   --  to interpret ANSI/VT escape sequences.
   ENABLE_VIRTUAL_TERMINAL_PROCESSING : constant Win32.DWORD := 16#0004#;

   --  Missing from win32ada.  Enables VT-encoded key reports on the input
   --  handle so that escape-sequence responses round-trip through ReadFile
   --  without console-host translation.  Used by the OSC raw-mode activation
   --  on Windows (FUNC-OSC-017).
   ENABLE_VIRTUAL_TERMINAL_INPUT      : constant Win32.DWORD := 16#0200#;

   --  Missing from win32ada.  Prevents the console host from inserting CR
   --  before LF in CSI cursor-position responses, which would corrupt
   --  parsing of replies that legitimately contain bare LFs (FUNC-OSC-017).
   DISABLE_NEWLINE_AUTO_RETURN        : constant Win32.DWORD := 16#0008#;

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

   ---------------------------------------------------------------------------
   --  ConPTY-Aware Active-Probe Gate (FUNC-WIN-014)
   ---------------------------------------------------------------------------

   --  Three-way classification of the current console host as observed via
   --  STD_OUTPUT_HANDLE.  Used by Tier-3 active-probe sites to decide whether
   --  sending VT escape probes is appropriate.
   --
   --    Not_A_Console      STD_OUTPUT_HANDLE is not a console (redirected to
   --                       a file or pipe; possibly an MSYS2/Cygwin PTY).
   --                       Caller should fall through to the POSIX-like
   --                       cascade.
   --
   --    Legacy_Conhost     STD_OUTPUT_HANDLE is a console AND
   --                       ENABLE_VIRTUAL_TERMINAL_PROCESSING is neither set
   --                       nor settable.  Active probes will not work; the
   --                       caller should bail and return passive results.
   --
   --    ConPTY_VT_Enabled  STD_OUTPUT_HANDLE is a console AND
   --                       ENABLE_VIRTUAL_TERMINAL_PROCESSING is already
   --                       set, OR was successfully set by the classifier.
   --                       Active probes are appropriate.
   type Console_VT_Status is
     (Not_A_Console,
      Legacy_Conhost,
      ConPTY_VT_Enabled);

   --  @summary Classify STD_OUTPUT_HANDLE for the purpose of deciding whether
   --           to send VT-based active probes.
   --  @return  One of Not_A_Console / Legacy_Conhost / ConPTY_VT_Enabled.
   --  @note    This function may have a side effect: when the bit was not
   --           already set on a console handle, it attempts to set it via
   --           SetConsoleMode.  A successful set leaves the bit enabled
   --           (matching Enable_VT_Processing's semantics).  Repeated calls
   --           are idempotent.
   --  @relation(FUNC-WIN-014): three-way classifier
   function Classify_Console_VT return Console_VT_Status;

   --  @summary Convenience predicate: should the caller skip Tier-3 active
   --           probes on the basis of console-host detection alone?
   --  @return  True iff Classify_Console_VT returns Legacy_Conhost.
   --  @relation(FUNC-WIN-014): probe-or-bail decision
   function Should_Skip_Active_Probes return Boolean;

end Termicap.Win32_VT;
