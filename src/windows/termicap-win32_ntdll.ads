-------------------------------------------------------------------------------
--  Termicap.Win32_Ntdll - Windows Build Number Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Dynamically loads ntdll.dll and calls RtlGetNtVersionNumbers to obtain
--  the Windows build number.
--
--  @description
--  This is the only custom FFI package in Termicap's Windows integration.
--  All other Win32 API calls use the win32ada Alire crate.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-006): Windows build number detection
--    - @relation(FUNC-WIN-012): Custom FFI boundary

with Interfaces;

package Termicap.Win32_Ntdll
   with SPARK_Mode => Off
is

   --  @summary Obtain the Windows build number via RtlGetNtVersionNumbers.
   --  @return The canonical build number (low 16 bits of the raw value),
   --          or 0 if ntdll.dll cannot be loaded or the function is not found.
   --  @relation(FUNC-WIN-006): Dynamic load and invocation
   function Get_Build_Number return Interfaces.Unsigned_32;

end Termicap.Win32_Ntdll;
