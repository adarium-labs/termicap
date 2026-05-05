-------------------------------------------------------------------------------
--  Termicap.Terminfo.IO - Terminfo File Search, Read, and Parse Entry Point
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  POSIX file I/O boundary for the terminfo database parser: search-path
--  resolution, file reading, and the top-level Parse_Terminfo entry point.
--
--  @description
--  This child package provides the two public operations that together form
--  the complete terminfo lookup-and-parse pipeline:
--
--    Read_File      -- opens a single path, reads up to MAX_TERMINFO_FILE_SIZE
--                      bytes into a caller-supplied Byte_Array, and returns a
--                      Read_Error status code.  SPARK_Mode Off (body only).
--
--    Parse_Terminfo -- executes the full search-path resolution (FUNC-TIF-004),
--                      path construction (FUNC-TIF-005), and binary parsing
--                      pipeline (FUNC-TIF-007 through FUNC-TIF-014).  Returns
--                      a Terminfo_Result value carrying either a populated
--                      Terminfo_Snapshot or an error code.
--
--  The spec is annotated with SPARK_Mode On so that callers with SPARK_Mode On
--  may reference Parse_Terminfo in contracts and call it from SPARK contexts.
--  The body is SPARK_Mode Off because it uses POSIX open/read/close system
--  calls, exception handling, and string construction â all outside the SPARK
--  language subset.  This split mirrors the established pattern from
--  Termicap.DA1.IO and Termicap.Keyboard.IO.
--
--  Search directory order (FUNC-TIF-004):
--    1. $TERMINFO (if set and non-empty)
--    2. Each colon-separated entry in $TERMINFO_DIRS (if set and non-empty)
--    3. $HOME/.terminfo (if HOME is set)
--    4. /usr/share/terminfo
--    5. /etc/terminfo
--    6. /lib/terminfo
--
--  For each directory D and terminal name T, the Primary path D/T(1)/T is
--  tried first, then the Alternate path D/HH/T where HH is the two-character
--  lowercase hexadecimal encoding of the ASCII value of T's first character
--  (FUNC-TIF-005).
--
--  No exception propagates from any public subprogram in this package.  I/O
--  errors are translated to Read_Error or Terminfo_Error values before
--  returning to the caller (FUNC-TIF-019).
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

with Termicap.Environment;

package Termicap.Terminfo.IO is

   ---------------------------------------------------------------------------
   --  File Read Operation (FUNC-TIF-006)
   ---------------------------------------------------------------------------

   --  @summary Open a file at Path, read its entire content into Buffer, and
   --  report the number of bytes read and the outcome.
   --  @description Implements the following steps:
   --    1. Open the file at Path in read-only mode.
   --    2. If the file does not exist or cannot be opened, set Error := Read_Not_Found
   --       and return (Buffer and Size are unspecified).
   --    3. Read up to MAX_TERMINFO_FILE_SIZE bytes into Buffer.
   --    4. If the file content exceeds MAX_TERMINFO_FILE_SIZE bytes, set
   --       Error := Read_Too_Large, close the file, and return.
   --    5. On a successful read, set Size to the number of bytes read and
   --       Error := Read_OK.
   --    6. On any I/O error during reading, set Error := Read_IO_Error,
   --       Size := 0, and close the file.
   --    7. The file descriptor is always closed before returning, regardless of
   --       the outcome.
   --  Declared in this package so that callers can reference the Read_Error
   --  type; the type itself is defined in the SPARK On parent package.
   --  @param Path    Full file system path to the terminfo binary file.
   --  @param Buffer  Receives the raw file bytes on success.
   --  @param Size    Number of bytes written into Buffer (0 on error).
   --  @param Error   Outcome code from the Read_Error enumeration.
   --  @relation(FUNC-TIF-006): POSIX read operation with Read_Error status
   procedure Read_File
     (Path   : String;
      Buffer : out Byte_Array;
      Size   : out Natural;
      Error  : out Read_Error);

   ---------------------------------------------------------------------------
   --  Top-Level Parse Entry Point (FUNC-TIF-015)
   ---------------------------------------------------------------------------

   --  @summary Execute the full terminfo search-path resolution and binary
   --  parsing pipeline, returning a Terminfo_Result.
   --  @description Implements the following steps in order:
   --    1. Read TERM from Env (FUNC-TIF-003).  If absent or empty, return
   --       (Success => False, Error => Error_No_Term).
   --    2. Build the ordered list of candidate directories (FUNC-TIF-004):
   --       $TERMINFO, entries from $TERMINFO_DIRS, $HOME/.terminfo,
   --       /usr/share/terminfo, /etc/terminfo, /lib/terminfo.
   --    3. For each candidate directory, construct the Primary path T(1)/T then
   --       the Alternate path HH/T (FUNC-TIF-005) and call Read_File.
   --       - Read_Not_Found: continue to the next candidate.
   --       - Read_IO_Error or Read_Too_Large: continue to the next candidate
   --         (non-fatal per-path I/O errors do not abort the search).
   --       - Read_OK: commit to this file and proceed to step 4.
   --    4. If no file was found after all candidates, return
   --       (Success => False, Error => Error_File_Not_Found).
   --    5. Call Parse_Buffer (Buffer, Size) from Termicap.Terminfo.
   --       - Error_Invalid_Magic, Error_Header_Corrupt: return immediately;
   --         a found-but-corrupt file does not fall back to a lower-priority
   --         candidate (FUNC-TIF-015 step 4 note).
   --    6. On parse success, return the populated Terminfo_Result.
   --  This function never propagates an Ada exception under any input condition
   --  (FUNC-TIF-019).  Callers that receive Error_File_Not_Found should treat
   --  the condition as informational (FUNC-TIF-020).
   --  @param Env  An immutable environment snapshot (from Termicap.Environment).
   --  @return Terminfo_Result containing either a populated Terminfo_Snapshot or
   --          one of the Terminfo_Error codes.
   --  @relation(FUNC-TIF-003): Reads TERM from the Environment snapshot
   --  @relation(FUNC-TIF-004): Builds the ordered candidate directory list
   --  @relation(FUNC-TIF-005): Constructs primary and alternate file paths
   --  @relation(FUNC-TIF-006): Calls Read_File for each candidate path
   --  @relation(FUNC-TIF-015): Top-level Parse_Terminfo entry function
   --  @relation(FUNC-TIF-019): No exception propagation guarantee
   --  @relation(FUNC-TIF-020): Error_File_Not_Found is a non-fatal advisory result
   function Parse_Terminfo
     (Env : Termicap.Environment.Environment) return Terminfo_Result;

end Termicap.Terminfo.IO;
