-------------------------------------------------------------------------------
--  Termicap.Win32_Ntdll - Windows Build Number Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Implements Get_Build_Number by dynamically loading ntdll.dll and resolving
--  RtlGetNtVersionNumbers via GetProcAddress (FUNC-WIN-006).
--  Implements Query_Object_Name by dynamically loading ntdll.dll and resolving
--  NtQueryObject via GetProcAddress (FUNC-CYG-004).
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-006): Dynamic load and invocation of RtlGetNtVersionNumbers
--    - @relation(FUNC-CYG-004): Fallback pipe-name retrieval via NtQueryObject

with Ada.Unchecked_Conversion;
with Interfaces.C;
with System;
with Win32;
with Win32.Windef;
with Win32.Winbase;

package body Termicap.Win32_Ntdll
   with SPARK_Mode => Off
is

   use type Win32.Windef.HINSTANCE;
   use type Win32.Windef.FARPROC;
   use type Win32.DWORD;
   use type Interfaces.C.long;

   ---------------------------------------------------------------------------
   --  RtlGetNtVersionNumbers procedure type
   ---------------------------------------------------------------------------

   --  RtlGetNtVersionNumbers has the Stdcall convention (same as all Win32 APIs)
   --  and takes three OUT DWORD parameters (Major, Minor, Build).
   type Rtl_Get_Nt_Version_Proc is access procedure
     (Major : out Win32.DWORD;
      Minor : out Win32.DWORD;
      Build : out Win32.DWORD);
   pragma Convention (Stdcall, Rtl_Get_Nt_Version_Proc);

   --  Conversion from FARPROC (access function return INT, Stdcall) to our
   --  procedure access type, using Ada.Unchecked_Conversion.
   function To_Version_Proc is new Ada.Unchecked_Conversion
     (Win32.Windef.FARPROC, Rtl_Get_Nt_Version_Proc);

   ---------------------------------------------------------------------------
   --  NtQueryObject access-to-function type (FUNC-CYG-004)
   ---------------------------------------------------------------------------

   --  NtQueryObject signature:
   --    NTSYSCALLAPI NTSTATUS NtQueryObject(
   --      HANDLE Handle,
   --      OBJECT_INFORMATION_CLASS ObjectInformationClass,
   --      PVOID ObjectInformation,
   --      ULONG ObjectInformationLength,
   --      PULONG ReturnLength);
   --  NTSTATUS maps to Interfaces.C.long; ObjectInformationClass is ULONG.
   type Nt_Query_Object_Fn is access function
     (Handle                    : Win32.Winnt.HANDLE;
      Object_Information_Class  : Win32.DWORD;
      Object_Information        : System.Address;
      Object_Information_Length : Interfaces.Unsigned_32;
      Return_Length             : access Interfaces.Unsigned_32)
     return Interfaces.C.long;
   pragma Convention (Stdcall, Nt_Query_Object_Fn);

   function To_Nt_Query_Object is new Ada.Unchecked_Conversion
     (Win32.Windef.FARPROC, Nt_Query_Object_Fn);

   --  OBJECT_NAME_INFORMATION class constant
   OBJECT_NAME_INFORMATION_CLASS : constant Win32.DWORD := 1;


   function Get_Build_Number return Interfaces.Unsigned_32 is

      --  NUL-terminated library and procedure name strings
      Lib_Name  : constant String := "ntdll.dll" & ASCII.NUL;
      Proc_Name : constant String := "RtlGetNtVersionNumbers" & ASCII.NUL;

      H_Module : Win32.Windef.HINSTANCE;
      Proc_Ptr : Win32.Windef.FARPROC;
      Fn       : Rtl_Get_Nt_Version_Proc;

      Major     : Win32.DWORD := 0;
      Minor     : Win32.DWORD := 0;
      Build_Raw : Win32.DWORD := 0;

      Unused_Bool : Win32.BOOL;
      pragma Unreferenced (Unused_Bool);

   begin
      --  Step 1: Load ntdll.dll
      H_Module := Win32.Winbase.LoadLibraryA (Win32.Addr (Lib_Name));

      if H_Module = System.Null_Address then
         return 0;
      end if;

      --  Step 2: Resolve RtlGetNtVersionNumbers
      Proc_Ptr := Win32.Winbase.GetProcAddress
        (H_Module, Win32.Addr (Proc_Name));

      if Proc_Ptr = null then
         Unused_Bool := Win32.Winbase.FreeLibrary (H_Module);
         return 0;
      end if;

      --  Step 3: Convert FARPROC to typed procedure access
      Fn := To_Version_Proc (Proc_Ptr);

      --  Step 4: Call the resolved procedure
      Fn (Major, Minor, Build_Raw);

      --  Step 5: Free the library
      Unused_Bool := Win32.Winbase.FreeLibrary (H_Module);

      --  Step 6: Mask to the low 16 bits to get the canonical build number
      Build_Raw := Build_Raw and 16#0000_FFFF#;

      return Interfaces.Unsigned_32 (Build_Raw);

   end Get_Build_Number;


   function Query_Object_Name
     (Handle      : Win32.Winnt.HANDLE;
      Buffer      : System.Address;
      Buffer_Size : Interfaces.Unsigned_32) return Boolean
   is
      Lib_Name  : constant String := "ntdll.dll" & ASCII.NUL;
      Proc_Name : constant String := "NtQueryObject" & ASCII.NUL;

      H_Module    : Win32.Windef.HINSTANCE;
      Proc_Ptr    : Win32.Windef.FARPROC;
      Fn          : Nt_Query_Object_Fn;
      Status      : Interfaces.C.long;
      Return_Len  : aliased Interfaces.Unsigned_32 := 0;
      Unused_Bool : Win32.BOOL;
      pragma Unreferenced (Unused_Bool);

   begin
      --  Step 1: Load ntdll.dll
      H_Module := Win32.Winbase.LoadLibraryA (Win32.Addr (Lib_Name));

      if H_Module = System.Null_Address then
         return False;
      end if;

      --  Step 2: Resolve NtQueryObject
      Proc_Ptr := Win32.Winbase.GetProcAddress
        (H_Module, Win32.Addr (Proc_Name));

      if Proc_Ptr = null then
         Unused_Bool := Win32.Winbase.FreeLibrary (H_Module);
         return False;
      end if;

      --  Step 3: Convert FARPROC to typed function access
      Fn := To_Nt_Query_Object (Proc_Ptr);

      --  Step 4: Call NtQueryObject with ObjectNameInformation (class 1)
      Status := Fn
        (Handle                    => Handle,
         Object_Information_Class  => OBJECT_NAME_INFORMATION_CLASS,
         Object_Information        => Buffer,
         Object_Information_Length => Buffer_Size,
         Return_Length             => Return_Len'Access);

      --  Step 5: Free the library
      Unused_Bool := Win32.Winbase.FreeLibrary (H_Module);

      --  Step 6: Return True iff NTSTATUS = STATUS_SUCCESS (0)
      return Status = 0;

   exception
      when others =>
         return False;
   end Query_Object_Name;

end Termicap.Win32_Ntdll;
