-------------------------------------------------------------------------------
--  Termicap.Win32_Ntdll - Windows Build Number Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Dynamically loads ntdll.dll and calls RtlGetNtVersionNumbers to obtain
--  the Windows build number, and NtQueryObject to retrieve handle names.
--
--  @description
--  This is the only custom FFI package in Termicap's Windows integration.
--  All other Win32 API calls use the win32ada Alire crate.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-006): Windows build number detection
--    - @relation(FUNC-WIN-012): Custom FFI boundary
--    - @relation(FUNC-CYG-004): Fallback pipe-name retrieval via NtQueryObject

with Interfaces;
with System;
with Win32.Winnt;

package Termicap.Win32_Ntdll
   with SPARK_Mode => Off
is

   --  @summary Obtain the Windows build number via RtlGetNtVersionNumbers.
   --  @return The canonical build number (low 16 bits of the raw value),
   --          or 0 if ntdll.dll cannot be loaded or the function is not found.
   --  @relation(FUNC-WIN-006): Dynamic load and invocation
   function Get_Build_Number return Interfaces.Unsigned_32;

   ---------------------------------------------------------------------------
   --  NtQueryObject binding (FUNC-CYG-004)
   ---------------------------------------------------------------------------

   --  @summary Retrieve the NT object name of a handle via ntdll!NtQueryObject.
   --  @param Handle      The handle to query.
   --  @param Buffer      A caller-allocated System.Address of at least
   --                     Buffer_Size bytes.  On success, populated with an
   --                     OBJECT_NAME_INFORMATION record whose UNICODE_STRING
   --                     header is followed by the UTF-16 name data.
   --  @param Buffer_Size Size of Buffer in bytes (caller ensures >= 1024).
   --  @return True iff NtQueryObject returned NTSTATUS 0 (STATUS_SUCCESS).
   --  @relation(FUNC-CYG-004): Fallback pipe-name retrieval
   function Query_Object_Name
     (Handle      : Win32.Winnt.HANDLE;
      Buffer      : System.Address;
      Buffer_Size : Interfaces.Unsigned_32) return Boolean;

end Termicap.Win32_Ntdll;
