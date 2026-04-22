-------------------------------------------------------------------------------
--  Termicap.Win32_Cygwin - Cygwin / MSYS2 PTY Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects whether a Win32 handle refers to a Cygwin or MSYS2 pseudo-terminal.
--
--  @description
--  Provides two subprograms for Cygwin/MSYS2 PTY detection on Windows:
--
--  - Is_Cygwin_Pipe_Name: a pure SPARK function that validates a decoded pipe
--    name string against the Cygwin/MSYS2 pipe name grammar.  This is the
--    primary testable unit, provable at SPARK Silver with Global => null.
--
--  - Is_Cygwin_Terminal: an impure wrapper that sequences the full detection
--    pipeline — GetFileType guard, pipe name retrieval via
--    GetFileInformationByHandleEx (primary) or NtQueryObject (fallback), UTF-16
--    decoding, and pattern matching — for a live Win32 HANDLE.
--
--  This package is introduced because Win32.Wincon.GetConsoleMode returns FALSE
--  for Cygwin/MSYS2 PTY handles (which are named pipes, not console objects).
--  The disjunction in Termicap.TTY's Windows body calls Is_Cygwin_Terminal as a
--  second chance before returning False for a non-console handle (FUNC-CYG-015).
--
--  Requirements Coverage:
--    - @relation(FUNC-CYG-006): Is_Cygwin_Pipe_Name public SPARK function
--    - @relation(FUNC-CYG-007): token[0] prefix validation
--    - @relation(FUNC-CYG-008): token[1] non-empty validation
--    - @relation(FUNC-CYG-009): token[2] starts with lowercase "pty"
--    - @relation(FUNC-CYG-010): token[3] is exactly "from" or "to"
--    - @relation(FUNC-CYG-011): token[4] is exactly "master"
--    - @relation(FUNC-CYG-012): minimum 5 '-'-delimited segments
--    - @relation(FUNC-CYG-013): 14 acceptance test vectors
--    - @relation(FUNC-CYG-014): Is_Cygwin_Terminal high-level pipeline
--    - @relation(FUNC-CYG-015): TTY detection disjunction
--    - @relation(FUNC-CYG-016): no-exception contract
--    - @relation(FUNC-CYG-017): package structure and SPARK boundary

with Win32.Winnt;

package Termicap.Win32_Cygwin
   with SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Pipe Name Pattern Matching (FUNC-CYG-006 through FUNC-CYG-012)
   ---------------------------------------------------------------------------

   --  @summary Validate a decoded pipe name against the Cygwin/MSYS2 grammar.
   --  @param Name  The ASCII-decoded pipe name to validate.
   --  @return True if Name matches the Cygwin/MSYS2 PTY pipe name pattern,
   --          i.e. all five token-level rules (FUNC-CYG-007 through
   --          FUNC-CYG-012) are satisfied.  Returns False for any value of
   --          Name, including the empty string.
   --  @relation(FUNC-CYG-006): Public SPARK function with Global => null
   function Is_Cygwin_Pipe_Name (Name : String) return Boolean
      with SPARK_Mode => On,
           Global     => null,
           Pre        => True,
           Post       => True;

   ---------------------------------------------------------------------------
   --  High-Level PTY Detection (FUNC-CYG-014)
   ---------------------------------------------------------------------------

   --  @summary Determine whether a Win32 handle refers to a Cygwin/MSYS2 PTY.
   --  @param Handle  The Win32 handle to inspect.
   --  @return True if Handle is a Cygwin or MSYS2 named-pipe PTY, False
   --          otherwise.  Never propagates an exception (FUNC-CYG-016).
   --  @relation(FUNC-CYG-014): Full detection pipeline
   --  @relation(FUNC-CYG-016): No-exception contract
   function Is_Cygwin_Terminal (Handle : Win32.Winnt.HANDLE) return Boolean
      with SPARK_Mode => Off;

end Termicap.Win32_Cygwin;
