-------------------------------------------------------------------------------
--  Termicap.Wcwidth - wcwidth() Probing for Unicode Level (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows stub for wcwidth() Unicode level probing.
--
--  @description
--  wcwidth() is not available on Windows without a POSIX compatibility layer.
--  This stub unconditionally returns Unknown from Probe_Wcwidth_Level, causing
--  Refine_Unicode_Level to leave the env-var-based Unicode_Level unchanged.
--
--  Requirements Coverage:
--    - @relation(FUNC-WCW-008): SPARK_Mode => Off for FFI boundary
--    - @relation(FUNC-WCW-011): Fallback to Unknown when probe unavailable

package body Termicap.Wcwidth
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Probe_Wcwidth_Level (FUNC-WCW-011 -- Windows stub)
   ---------------------------------------------------------------------------

   function Probe_Wcwidth_Level return Wcwidth_Level is
   begin
      --  wcwidth() is not available on Windows; return Unknown unconditionally.
      --  Refine_Unicode_Level will return Env_Level unchanged (FUNC-WCW-005).
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
