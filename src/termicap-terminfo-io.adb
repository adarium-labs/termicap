-------------------------------------------------------------------------------
--  Termicap.Terminfo.IO - Terminfo File Search, Read, and Parse Entry Point (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  POSIX file I/O boundary for the terminfo database parser.
--
--  @description
--  Implements Read_File (Ada.Streams.Stream_IO) and Parse_Terminfo (search-path
--  resolution + binary parsing pipeline).  All exceptions from I/O operations
--  are caught internally; no exception propagates to callers.
--
--  Requirements Coverage:
--    - @relation(FUNC-TIF-003): TERM variable read from Environment snapshot
--    - @relation(FUNC-TIF-004): Standard search directory order
--    - @relation(FUNC-TIF-005): Primary and alternate path construction
--    - @relation(FUNC-TIF-006): Read_File POSIX FFI with Read_Error status
--    - @relation(FUNC-TIF-015): Parse_Terminfo top-level entry function
--    - @relation(FUNC-TIF-019): No exception propagation guarantee
--    - @relation(FUNC-TIF-020): Error_File_Not_Found treated as non-fatal

pragma SPARK_Mode (Off);

with Ada.Streams.Stream_IO;

package body Termicap.Terminfo.IO is

   ---------------------------------------------------------------------------
   --  Read_File (FUNC-TIF-006)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-006): POSIX read operation with Read_Error status
   procedure Read_File
     (Path   : String;
      Buffer : out Byte_Array;
      Size   : out Natural;
      Error  : out Read_Error)
   is
      use Ada.Streams.Stream_IO;

      File   : File_Type;
      Stream : Stream_Access;
      Byte_V : Byte;
      Count  : Natural := 0;
   begin
      --  Initialise outputs.
      Buffer := [others => 0];
      Size := 0;
      Error := Read_Not_Found;

      --  Attempt to open the file.
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            Error := Read_Not_Found;
            return;
      end;

      --  Obtain the stream access.
      Stream := Ada.Streams.Stream_IO.Stream (File);

      --  Read bytes one at a time up to MAX_TERMINFO_FILE_SIZE.
      begin
         loop
            --  Check if the file is exhausted.
            if End_Of_File (File) then
               exit;
            end if;

            --  Check if we have reached the maximum size.
            if Count >= MAX_TERMINFO_FILE_SIZE then
               --  File is larger than allowed.
               Close (File);
               Error := Read_Too_Large;
               Size := 0;
               return;
            end if;

            --  Read one byte from the stream.
            Byte'Read (Stream, Byte_V);
            Count := Count + 1;
            Buffer (Count) := Byte_V;
         end loop;

         Close (File);
         Size := Count;
         Error := Read_OK;

      exception
         when others =>
            --  I/O error during reading.
            begin
               Close (File);
            exception
               when others =>
                  null;
            end;
            Size := 0;
            Error := Read_IO_Error;
      end;
   end Read_File;

   ---------------------------------------------------------------------------
   --  Hex encoding helper
   ---------------------------------------------------------------------------

   --  Return the two-character lowercase hex string for an ASCII byte value.
   function Hex_Of_Char (C : Character) return String is
      Val       : constant Natural := Character'Pos (C);
      Hi        : constant Natural := Val / 16;
      Lo        : constant Natural := Val mod 16;
      Hex_Chars : constant String := "0123456789abcdef";
   begin
      return
        [Hex_Chars (Hex_Chars'First + Hi), Hex_Chars (Hex_Chars'First + Lo)];
   end Hex_Of_Char;

   ---------------------------------------------------------------------------
   --  Parse_Terminfo (FUNC-TIF-015)
   ---------------------------------------------------------------------------

   --  Maximum number of candidate directories to search.
   MAX_DIRS : constant := 32;

   --  @relation(FUNC-TIF-015): Top-level Parse_Terminfo entry function
   function Parse_Terminfo
     (Env : Termicap.Environment.Environment) return Terminfo_Result
   is
      use Termicap.Environment;

      --  Step 1: Read the TERM environment variable.
      Term : constant String := Value (Env, "TERM");
   begin
      if Term'Length = 0 then
         return (Success => False, Error => Error_No_Term);
      end if;

      --  Step 2: Build the candidate directory list.
      declare
         type Dir_Array is array (1 .. MAX_DIRS) of access String;
         Dirs      : Dir_Array := [others => null];
         Dir_Count : Natural := 0;

         --  Helper to add a directory to the list.
         procedure Add_Dir (D : String) is
         begin
            if Dir_Count < MAX_DIRS and then D'Length > 0 then
               Dir_Count := Dir_Count + 1;
               Dirs (Dir_Count) := new String'(D);
            end if;
         end Add_Dir;

         --  Helper to split TERMINFO_DIRS on ':' and add each entry.
         procedure Add_Terminfo_Dirs (Dirs_Val : String) is
            Start : Positive := Dirs_Val'First;
            I     : Positive;
         begin
            I := Dirs_Val'First;
            loop
               exit when I > Dirs_Val'Last;
               if Dirs_Val (I) = ':' then
                  if I > Start then
                     Add_Dir (Dirs_Val (Start .. I - 1));
                  end if;
                  Start := I + 1;
               end if;
               I := I + 1;
            end loop;
            --  Add the last segment.
            if Start <= Dirs_Val'Last then
               Add_Dir (Dirs_Val (Start .. Dirs_Val'Last));
            end if;
         end Add_Terminfo_Dirs;

      begin
         --  a. $TERMINFO (if set and non-empty)
         if Contains (Env, "TERMINFO") then
            declare
               TI : constant String := Value (Env, "TERMINFO");
            begin
               if TI'Length > 0 then
                  Add_Dir (TI);
               end if;
            end;
         end if;

         --  b. Entries from $TERMINFO_DIRS
         if Contains (Env, "TERMINFO_DIRS") then
            declare
               TID : constant String := Value (Env, "TERMINFO_DIRS");
            begin
               if TID'Length > 0 then
                  Add_Terminfo_Dirs (TID);
               end if;
            end;
         end if;

         --  c. $HOME/.terminfo
         if Contains (Env, "HOME") then
            declare
               Home_Val : constant String := Value (Env, "HOME");
            begin
               if Home_Val'Length > 0 then
                  Add_Dir (Home_Val & "/.terminfo");
               end if;
            end;
         end if;

         --  d. Standard system directories
         Add_Dir ("/usr/share/terminfo");
         Add_Dir ("/etc/terminfo");
         Add_Dir ("/lib/terminfo");

         --  Step 3: Search each candidate directory.
         declare
            Term_First  : constant Character := Term (Term'First);
            Term_Hex    : constant String := Hex_Of_Char (Term_First);
            Primary_Sub : constant String := [Term_First];
            Alt_Sub     : constant String := Term_Hex;

            Buffer    : Byte_Array (1 .. MAX_TERMINFO_FILE_SIZE) :=
              [others => 0];
            Read_Size : Natural;
            Read_Err  : Read_Error;
         begin
            for I in 1 .. Dir_Count loop
               declare
                  Dir_Str : constant String := Dirs (I).all;
               begin
                  --  Primary path: Dir/T(1)/Term
                  declare
                     Primary_Path : constant String :=
                       Dir_Str & "/" & Primary_Sub & "/" & Term;
                  begin
                     if Primary_Path'Length <= MAX_PATH_LENGTH then
                        Read_File (Primary_Path, Buffer, Read_Size, Read_Err);
                        if Read_Err = Read_OK then
                           return Parse_Buffer (Buffer, Read_Size);
                        end if;
                     end if;
                  end;

                  --  Alternate path: Dir/HH/Term (hex encoding of first char)
                  declare
                     Alt_Path : constant String :=
                       Dir_Str & "/" & Alt_Sub & "/" & Term;
                  begin
                     if Alt_Path'Length <= MAX_PATH_LENGTH then
                        Read_File (Alt_Path, Buffer, Read_Size, Read_Err);
                        if Read_Err = Read_OK then
                           return Parse_Buffer (Buffer, Read_Size);
                        end if;
                        if Read_Err = Read_Too_Large then
                           return
                             (Success => False, Error => Error_File_Too_Large);
                        end if;
                     end if;
                  end;
               end;
            end loop;
         end;

         --  Step 4: No file found.
         return (Success => False, Error => Error_File_Not_Found);
      end;
   end Parse_Terminfo;

end Termicap.Terminfo.IO;
