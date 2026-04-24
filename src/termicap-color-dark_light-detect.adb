-------------------------------------------------------------------------------
--  Termicap.Color.Dark_Light.Detect - High-Level Theme Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (Off);

package body Termicap.Color.Dark_Light.Detect is

   function Detect_Theme (Timeout_Ms : Natural := 1_000) return Theme_Result is
      Effective_Timeout : constant Natural := Natural'Min (Timeout_Ms, MAX_TIMEOUT_MS);
      Result            : constant Detection.Detection_Result := Detection.Detect_Background_Color (Effective_Timeout);
   begin
      if Result.Success then
         return (Success => True, Theme => Classify_Theme (Result.Color), Color => Result.Color);
      else
         return (Success => False, Error => Result.Error);
      end if;
   end Detect_Theme;

end Termicap.Color.Dark_Light.Detect;
