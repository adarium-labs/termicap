-------------------------------------------------------------------------------
--  Termicap.Win32_Cygwin - Cygwin / MSYS2 PTY Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Implements the Cygwin/MSYS2 PTY detection pipeline:
--
--    1.  Package elaboration probes GetFileInformationByHandleEx availability
--        via LoadLibraryA/GetProcAddress (FUNC-CYG-002).
--    2.  Is_Cygwin_Pipe_Name validates a decoded pipe name against the
--        Cygwin/MSYS2 grammar (FUNC-CYG-006 through FUNC-CYG-012).
--    3.  Is_Cygwin_Terminal sequences GetFileType guard, pipe-name retrieval
--        (primary via GetFileInformationByHandleEx, fallback via NtQueryObject),
--        UTF-16 decoding, and pattern matching (FUNC-CYG-014).
--
--  Requirements Coverage:
--    - @relation(FUNC-CYG-002): Elaboration-time probe for GetFileInformationByHandleEx
--    - @relation(FUNC-CYG-003): Pipe name retrieval via GetFileInformationByHandleEx
--    - @relation(FUNC-CYG-004): Fallback retrieval via NtQueryObject
--    - @relation(FUNC-CYG-005): UTF-16 to ASCII decoder
--    - @relation(FUNC-CYG-006): Is_Cygwin_Pipe_Name implementation
--    - @relation(FUNC-CYG-014): Is_Cygwin_Terminal pipeline
--    - @relation(FUNC-CYG-016): No-exception contract

with Ada.Unchecked_Conversion;
with Interfaces.C;
with System;
with Win32;
with Win32.Windef;
with Win32.Winbase;
with Termicap.Win32_Ntdll;

package body Termicap.Win32_Cygwin
   with SPARK_Mode => Off
is

   use type Win32.Windef.HINSTANCE;
   use type Win32.Windef.FARPROC;
   use type Win32.BOOL;
   use type Win32.DWORD;
   use type Interfaces.C.size_t;
   use type Interfaces.Unsigned_16;

   ---------------------------------------------------------------------------
   --  Constants
   ---------------------------------------------------------------------------

   --  Maximum UTF-16 code units in a pipe name buffer (FUNC-CYG-003)
   MAX_PIPE_NAME_LENGTH : constant := 512;

   --  FileNameInfo class for GetFileInformationByHandleEx (FUNC-CYG-003)
   FILE_NAME_INFO_CLASS : constant Win32.DWORD := 2;

   --  FILE_TYPE_PIPE value returned by GetFileType (FUNC-CYG-001)
   FILE_TYPE_PIPE : constant Win32.DWORD := 16#0003#;

   ---------------------------------------------------------------------------
   --  FILE_NAME_INFO buffer record (FUNC-CYG-003)
   ---------------------------------------------------------------------------

   type File_Name_Info_Record is record
      File_Name_Length : Win32.DWORD;
      File_Name        : Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1);
   end record
      with Convention => C;

   ---------------------------------------------------------------------------
   --  Access-to-function type for GetFileInformationByHandleEx (FUNC-CYG-003)
   ---------------------------------------------------------------------------

   type Get_File_Info_Fn_Ptr is access function
     (H_File                 : Win32.Winnt.HANDLE;
      File_Information_Class : Win32.DWORD;
      Lp_File_Information    : System.Address;
      Dw_Buffer_Size         : Win32.DWORD)
     return Win32.BOOL;
   pragma Convention (Stdcall, Get_File_Info_Fn_Ptr);

   function To_Get_File_Info is new Ada.Unchecked_Conversion
     (Win32.Windef.FARPROC, Get_File_Info_Fn_Ptr);

   ---------------------------------------------------------------------------
   --  Package-level elaboration state (FUNC-CYG-002)
   ---------------------------------------------------------------------------

   Has_Get_File_Info : Boolean             := False;
   Get_File_Info_Fn  : Get_File_Info_Fn_Ptr := null;

   ---------------------------------------------------------------------------
   --  UNICODE_STRING overlay for NtQueryObject buffer (FUNC-CYG-004)
   ---------------------------------------------------------------------------

   type Unicode_String is record
      Length         : Interfaces.C.unsigned_short;
      Maximum_Length : Interfaces.C.unsigned_short;
      Buffer         : System.Address;
   end record
      with Convention => C;

   ---------------------------------------------------------------------------
   --  Probe_Get_File_Info — elaboration-time availability check (FUNC-CYG-002)
   ---------------------------------------------------------------------------

   procedure Probe_Get_File_Info is
      Lib_Name  : constant String := "kernel32.dll" & ASCII.NUL;
      Proc_Name : constant String := "GetFileInformationByHandleEx" & ASCII.NUL;

      H_Module    : Win32.Windef.HINSTANCE;
      Proc_Ptr    : Win32.Windef.FARPROC;
      Unused_Bool : Win32.BOOL;
      pragma Unreferenced (Unused_Bool);
   begin
      H_Module := Win32.Winbase.LoadLibraryA (Win32.Addr (Lib_Name));

      if H_Module = System.Null_Address then
         Has_Get_File_Info := False;
         Get_File_Info_Fn  := null;
         return;
      end if;

      Proc_Ptr := Win32.Winbase.GetProcAddress
                    (H_Module, Win32.Addr (Proc_Name));

      if Proc_Ptr = null then
         Unused_Bool       := Win32.Winbase.FreeLibrary (H_Module);
         Has_Get_File_Info := False;
         Get_File_Info_Fn  := null;
         return;
      end if;

      Get_File_Info_Fn  := To_Get_File_Info (Proc_Ptr);
      Has_Get_File_Info := True;

      --  Free the module handle — kernel32.dll stays loaded for the process
      --  lifetime so the function pointer remains valid (FUNC-CYG-002 step 5).
      Unused_Bool := Win32.Winbase.FreeLibrary (H_Module);

   exception
      when others =>
         Has_Get_File_Info := False;
         Get_File_Info_Fn  := null;
   end Probe_Get_File_Info;

   ---------------------------------------------------------------------------
   --  Decode_UTF16_To_ASCII (FUNC-CYG-005)
   ---------------------------------------------------------------------------

   procedure Decode_UTF16_To_ASCII
     (Input      : Interfaces.C.char16_array;
      Unit_Count : Natural;
      Output     : out String;
      Last       : out Natural)
   is
      Out_Idx : Natural := Output'First - 1;
   begin
      Last := Output'First - 1;

      for I in 0 .. Unit_Count - 1 loop
         exit when Out_Idx + 1 > Output'Last;
         Out_Idx := Out_Idx + 1;

         declare
            --  Convert char16_t to an unsigned 16-bit integer via Pos so that
            --  arithmetic and range comparisons are straightforward (FUNC-CYG-005).
            Code : constant Interfaces.Unsigned_16 :=
                      Interfaces.Unsigned_16
                        (Interfaces.C.char16_t'Pos
                          (Input (Interfaces.C.size_t (I))));
         begin
            if Code >= 16#0001# and then Code <= 16#007F# then
               Output (Out_Idx) := Character'Val (Integer (Code));
            else
               Output (Out_Idx) := '?';
            end if;
         end;
      end loop;

      Last := Out_Idx;

   exception
      when others =>
         Last := Output'First - 1;
   end Decode_UTF16_To_ASCII;

   ---------------------------------------------------------------------------
   --  Get_File_Type_Is_Pipe helper (FUNC-CYG-001)
   ---------------------------------------------------------------------------

   function Get_File_Type_Is_Pipe (Handle : Win32.Winnt.HANDLE) return Boolean is
   begin
      return Win32.Winbase.GetFileType (Handle) = FILE_TYPE_PIPE;
   exception
      when others => return False;
   end Get_File_Type_Is_Pipe;

   ---------------------------------------------------------------------------
   --  Retrieve_Name_Via_GetFileInfo (FUNC-CYG-003)
   ---------------------------------------------------------------------------

   function Retrieve_Name_Via_GetFileInfo
     (Handle   : Win32.Winnt.HANDLE;
      Out_Name : out String;
      Out_Last : out Natural) return Boolean
   is
      Buffer : aliased File_Name_Info_Record;
      Ok     : Win32.BOOL;
      Units  : Natural;
   begin
      Out_Last := Out_Name'First - 1;

      if Get_File_Info_Fn = null then
         return False;
      end if;

      Ok := Get_File_Info_Fn
              (H_File                 => Handle,
               File_Information_Class => FILE_NAME_INFO_CLASS,
               Lp_File_Information    => Buffer'Address,
               Dw_Buffer_Size         => Win32.DWORD
                                           (File_Name_Info_Record'Size / 8));

      if Ok = Win32.FALSE then
         return False;
      end if;

      --  Length field is in bytes; divide by 2 for UTF-16 code units.
      Units := Natural (Buffer.File_Name_Length) / 2;
      if Units > MAX_PIPE_NAME_LENGTH then
         Units := MAX_PIPE_NAME_LENGTH;
      end if;

      Decode_UTF16_To_ASCII
        (Input      => Buffer.File_Name,
         Unit_Count => Units,
         Output     => Out_Name,
         Last       => Out_Last);

      return True;

   exception
      when others =>
         Out_Last := Out_Name'First - 1;
         return False;
   end Retrieve_Name_Via_GetFileInfo;

   ---------------------------------------------------------------------------
   --  Retrieve_Name_Via_NtQueryObject (FUNC-CYG-004)
   ---------------------------------------------------------------------------

   function Retrieve_Name_Via_NtQueryObject
     (Handle   : Win32.Winnt.HANDLE;
      Out_Name : out String;
      Out_Last : out Natural) return Boolean
   is
      --  1024-byte raw buffer; the UNICODE_STRING header is overlaid
      --  via a local object with Import at the same address.
      Buffer : aliased Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1);
      Header : Unicode_String
         with Import, Convention => C, Address => Buffer'Address;

      Units : Natural;
   begin
      Out_Last := Out_Name'First - 1;

      if not Termicap.Win32_Ntdll.Query_Object_Name
               (Handle      => Handle,
                Buffer      => Buffer'Address,
                Buffer_Size => Interfaces.Unsigned_32 (Buffer'Size / 8))
      then
         return False;
      end if;

      --  Length field is in bytes; divide by 2 for UTF-16 code units.
      Units := Natural (Header.Length) / 2;
      if Units > MAX_PIPE_NAME_LENGTH then
         Units := MAX_PIPE_NAME_LENGTH;
      end if;

      --  The name data is at Header.Buffer (System.Address inside the same
      --  stack allocation).  Overlay a char16_array at that address.
      declare
         Name_Codes : Interfaces.C.char16_array (0 .. MAX_PIPE_NAME_LENGTH - 1)
            with Import, Convention => C, Address => Header.Buffer;
      begin
         Decode_UTF16_To_ASCII
           (Input      => Name_Codes,
            Unit_Count => Units,
            Output     => Out_Name,
            Last       => Out_Last);
      end;

      return True;

   exception
      when others =>
         Out_Last := Out_Name'First - 1;
         return False;
   end Retrieve_Name_Via_NtQueryObject;

   ---------------------------------------------------------------------------
   --  Is_Cygwin_Pipe_Name (FUNC-CYG-006 through FUNC-CYG-012)
   ---------------------------------------------------------------------------

   function Is_Cygwin_Pipe_Name (Name : String) return Boolean is

      --  Four accepted token[0] prefixes (FUNC-CYG-007)
      CYG_PREFIX_1 : constant String := "\cygwin";
      CYG_PREFIX_2 : constant String := "\msys";
      CYG_PREFIX_3 : constant String := "\Device\NamedPipe\cygwin";
      CYG_PREFIX_4 : constant String := "\Device\NamedPipe\msys";

      function Is_Valid_Prefix (T : String) return Boolean is
        (T = CYG_PREFIX_1 or else T = CYG_PREFIX_2
         or else T = CYG_PREFIX_3 or else T = CYG_PREFIX_4);

      function Starts_With_Pty (T : String) return Boolean is
        (T'Length >= 3
         and then T (T'First)     = 'p'
         and then T (T'First + 1) = 't'
         and then T (T'First + 2) = 'y');

      function Is_From_Or_To (T : String) return Boolean is
        (T = "from" or else T = "to");

      Token_Start : Positive;
      Token_Idx   : Natural;
      I           : Natural;

   begin
      if Name'Length = 0 then
         return False;
      end if;

      Token_Start := Name'First;
      Token_Idx   := 0;
      I           := Name'First - 1;

      loop
         I := I + 1;

         if I > Name'Last or else Name (I) = '-' then
            declare
               Token_End : constant Integer := I - 1;
            begin
               case Token_Idx is
                  when 0 =>
                     if not Is_Valid_Prefix (Name (Token_Start .. Token_End)) then
                        return False;
                     end if;
                  when 1 =>
                     --  Empty token[1] -> reject (FUNC-CYG-008)
                     if Token_End < Token_Start then
                        return False;
                     end if;
                  when 2 =>
                     if not Starts_With_Pty (Name (Token_Start .. Token_End)) then
                        return False;
                     end if;
                  when 3 =>
                     if not Is_From_Or_To (Name (Token_Start .. Token_End)) then
                        return False;
                     end if;
                  when 4 =>
                     if Name (Token_Start .. Token_End) /= "master" then
                        return False;
                     end if;
                     --  Early success: tokens 5+ are ignored (FUNC-CYG-011)
                     return True;
                  when others =>
                     null;
               end case;
            end;

            exit when I > Name'Last;
            Token_Idx   := Token_Idx + 1;
            Token_Start := I + 1;
         end if;

      end loop;

      --  Loop exited without reaching token 4 -> fewer than 5 segments
      --  (FUNC-CYG-012)
      return False;

   end Is_Cygwin_Pipe_Name;

   ---------------------------------------------------------------------------
   --  Is_Cygwin_Terminal (FUNC-CYG-014)
   ---------------------------------------------------------------------------

   function Is_Cygwin_Terminal (Handle : Win32.Winnt.HANDLE) return Boolean is
      Name : String (1 .. MAX_PIPE_NAME_LENGTH);
      Last : Natural := 0;
      Got  : Boolean;
   begin
      --  Defensive guard: invalid or null handle cannot be a Cygwin PTY
      --  (FUNC-CYG-016).
      if Handle = Win32.Winbase.INVALID_HANDLE_VALUE
         or else Handle = System.Null_Address
      then
         return False;
      end if;

      --  Step 1: GetFileType guard (FUNC-CYG-001)
      if not Get_File_Type_Is_Pipe (Handle) then
         return False;
      end if;

      --  Step 2: Retrieve the pipe name via the available API.
      if Has_Get_File_Info then
         Got := Retrieve_Name_Via_GetFileInfo
                   (Handle => Handle, Out_Name => Name, Out_Last => Last);
      else
         Got := Retrieve_Name_Via_NtQueryObject
                   (Handle => Handle, Out_Name => Name, Out_Last => Last);
      end if;

      if not Got or else Last < Name'First then
         return False;
      end if;

      --  Step 3: Hand off to the pure SPARK predicate (FUNC-CYG-006).
      return Is_Cygwin_Pipe_Name (Name (Name'First .. Last));

   exception
      when others =>
         --  FUNC-CYG-016: absolute no-exception contract.
         return False;
   end Is_Cygwin_Terminal;

begin
   --  Package body elaboration: probe GetFileInformationByHandleEx availability
   --  exactly once at program startup (FUNC-CYG-002).
   Probe_Get_File_Info;

end Termicap.Win32_Cygwin;
