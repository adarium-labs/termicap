-------------------------------------------------------------------------------
--  Termicap.Wcwidth - wcwidth() Probing for Unicode Level (POSIX Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  POSIX implementation of wcwidth() probing for Unicode version detection.
--
--  @description
--  This body is annotated with SPARK_Mode => Off because it uses C FFI
--  (pragma Import) for wcwidth() and setlocale(), and a protected object
--  for cache concurrency.  The public spec remains SPARK On.
--
--  The probe tests sentinel codepoints in descending Unicode version order
--  (16 -> 13 -> 3) for early exit on modern systems.  A locale guard checks
--  that the current LC_CTYPE locale is not "C" or "POSIX" before calling
--  wcwidth(); if it is, Unknown is returned immediately (FUNC-WCW-006).
--
--  Requirements Coverage:
--    - @relation(FUNC-WCW-001): C wcwidth() FFI binding
--    - @relation(FUNC-WCW-003): Sentinel probing algorithm
--    - @relation(FUNC-WCW-005): Refine_Unicode_Level implementation
--    - @relation(FUNC-WCW-006): Locale guard before probe
--    - @relation(FUNC-WCW-007): Graceful handling of wcwidth() returning -1
--    - @relation(FUNC-WCW-008): SPARK_Mode => Off for FFI boundary
--    - @relation(FUNC-WCW-009): Thread safety via protected cache object
--    - @relation(FUNC-WCW-010): Cached probe result (protected object)
--    - @relation(FUNC-WCW-011): Fallback to Unknown on all failure paths

with Ada.Unchecked_Conversion;
with Interfaces.C.Strings;

package body Termicap.Wcwidth
  with SPARK_Mode => Off
is

   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;

   --  wchar_t on Linux is a 32-bit type (Standard'Wchar_T_Size = 32) but it
   --  is derived from Wide_Character (16-bit range), so Wide_Character'Val
   --  cannot represent supplementary-plane codepoints (> 16#FFFF#).
   --  Unchecked_Conversion from a 32-bit unsigned integer is the safe way to
   --  construct a wchar_t value for supplementary-plane sentinels.
   subtype Wchar_Int is Interfaces.C.unsigned;
   function To_Wchar is new
     Ada.Unchecked_Conversion (Wchar_Int, Interfaces.C.wchar_t);

   ---------------------------------------------------------------------------
   --  C FFI Bindings (FUNC-WCW-001, FUNC-WCW-006)
   ---------------------------------------------------------------------------

   --  @summary Binding to the POSIX C library wcwidth() function.
   --  @description Returns the number of terminal columns needed to display
   --  the wide character Wc, or -1 if the character is non-printable or
   --  not supported in the current locale.
   --  @relation(FUNC-WCW-001): C wcwidth() FFI binding
   function C_Wcwidth (Wc : Interfaces.C.wchar_t) return Interfaces.C.int;
   pragma Import (C, C_Wcwidth, "wcwidth");

   --  @summary Binding to the POSIX C library setlocale() function.
   --  @description When called with a null Locale pointer, returns the current
   --  locale string for the given category without changing it.
   --  @relation(FUNC-WCW-006): setlocale() binding for locale guard
   function C_Setlocale
     (Category : Interfaces.C.int; Locale : Interfaces.C.Strings.chars_ptr)
      return Interfaces.C.Strings.chars_ptr;
   pragma Import (C, C_Setlocale, "setlocale");

   --  @summary C helper returning the platform-specific LC_CTYPE constant.
   --  @description Defined in src/c/termicap_wcwidth.c.  Returns the numeric
   --  value of LC_CTYPE on the current platform (0 on Linux/glibc,
   --  2 on macOS/FreeBSD), avoiding a hardcoded assumption.
   --  @relation(FUNC-WCW-006): Portable LC_CTYPE value
   function C_LC_CTYPE return Interfaces.C.int;
   pragma Import (C, C_LC_CTYPE, "termicap_lc_ctype");

   ---------------------------------------------------------------------------
   --  Probe Cache (FUNC-WCW-010)
   ---------------------------------------------------------------------------

   --  @summary Protected object guarding the probe result cache.
   --  @description The cache is populated on the first call to
   --  Probe_Wcwidth_Level and returned on subsequent calls, avoiding
   --  redundant wcwidth() FFI calls.  The protected object ensures that
   --  concurrent first-call initialisations are safe.
   --  @relation(FUNC-WCW-010): Cached probe result
   protected Wcwidth_Cache is
      procedure Store (Level : Wcwidth_Level);
      function Get return Optional_Wcwidth_Level;
   private
      Value : Optional_Wcwidth_Level := (Is_Set => False);
   end Wcwidth_Cache;

   protected body Wcwidth_Cache is
      procedure Store (Level : Wcwidth_Level) is
      begin
         Value := (Is_Set => True, Level => Level);
      end Store;

      function Get return Optional_Wcwidth_Level is
      begin
         return Value;
      end Get;
   end Wcwidth_Cache;

   ---------------------------------------------------------------------------
   --  Probe_Wcwidth_Level (FUNC-WCW-003)
   ---------------------------------------------------------------------------

   function Probe_Wcwidth_Level return Wcwidth_Level is
      Cached : constant Optional_Wcwidth_Level := Wcwidth_Cache.Get;
      Locale : Interfaces.C.Strings.chars_ptr;
      Result : Wcwidth_Level;
   begin
      --  Step 0: Return cached result if available (FUNC-WCW-010)
      if Cached.Is_Set then
         return Cached.Level;
      end if;

      --  Step 1: Locale guard (FUNC-WCW-006)
      --  Check that LC_CTYPE is not "C" or "POSIX" before calling wcwidth().
      Locale := C_Setlocale (C_LC_CTYPE, Interfaces.C.Strings.Null_Ptr);
      if Locale = Interfaces.C.Strings.Null_Ptr then
         Wcwidth_Cache.Store (Unknown);
         return Unknown;
      end if;

      declare
         Locale_Str : constant String := Interfaces.C.Strings.Value (Locale);
      begin
         if Locale_Str = "C" or else Locale_Str = "POSIX" then
            Wcwidth_Cache.Store (Unknown);
            return Unknown;
         end if;
      end;

      --  Step 2: Probe Unicode 16 (FUNC-WCW-003)
      if C_Wcwidth (To_Wchar (Wchar_Int (WCW_SENTINEL_UNI16))) >= 1 then
         Result := Unicode_16;
         Wcwidth_Cache.Store (Result);
         return Result;
      end if;

      --  Step 3: Probe Unicode 13 (FUNC-WCW-003)
      if C_Wcwidth (To_Wchar (Wchar_Int (WCW_SENTINEL_UNI13))) >= 1 then
         Result := Unicode_13;
         Wcwidth_Cache.Store (Result);
         return Result;
      end if;

      --  Step 4: Probe Unicode 3 (FUNC-WCW-003)
      if C_Wcwidth (To_Wchar (Wchar_Int (WCW_SENTINEL_UNI3))) >= 1 then
         Result := Unicode_3;
         Wcwidth_Cache.Store (Result);
         return Result;
      end if;

      --  Step 5: All probes failed Ã¢ÂÂ return Unknown (FUNC-WCW-007, FUNC-WCW-011)
      Wcwidth_Cache.Store (Unknown);
      return Unknown;
   end Probe_Wcwidth_Level;

   ---------------------------------------------------------------------------
   --  Refine_Unicode_Level (FUNC-WCW-005)
   ---------------------------------------------------------------------------

   function Refine_Unicode_Level
     (Env_Level : Termicap.Unicode.Unicode_Level; Wcw_Level : Wcwidth_Level)
      return Termicap.Unicode.Unicode_Level is
   begin
      case Wcw_Level is
         when Unknown                =>
            return Env_Level;

         when Unicode_3 | Unicode_13 =>
            return
              Termicap.Unicode.Unicode_Level'Max
                (Env_Level, Termicap.Unicode.Basic);

         when Unicode_16             =>
            return
              Termicap.Unicode.Unicode_Level'Max
                (Env_Level, Termicap.Unicode.Extended);
      end case;
   end Refine_Unicode_Level;

end Termicap.Wcwidth;
