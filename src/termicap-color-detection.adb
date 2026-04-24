-------------------------------------------------------------------------------
--  Termicap.Color.Detection - High-Level Color Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (Off);

with Termicap.Color.BG_Query.IO;
with Termicap.Environment;
with Termicap.Environment.Capture;

package body Termicap.Color.Detection is

   MAX_TIMEOUT : constant := 30_000;

   function Detect_Background_Color (Timeout_Ms : Natural := 1_000) return Detection_Result is
      Effective_Timeout : constant Natural := Natural'Min (Timeout_Ms, MAX_TIMEOUT);
      Resp_Buffer       : BG_Query.Byte_Array (1 .. BG_Query.MAX_RESPONSE_SIZE);
      Resp_Len          : Natural;
      Timed_Out         : Boolean;
   begin
      if Effective_Timeout > 0 then
         BG_Query.IO.Query_Color
           (Kind        => BG_Query.Background,
            Timeout_Ms  => Effective_Timeout,
            Response    => Resp_Buffer,
            Resp_Length => Resp_Len,
            Timed_Out   => Timed_Out);

         if not Timed_Out and then Resp_Len > 0 then
            declare
               Strip : constant BG_Query.Strip_Result :=
                 BG_Query.Strip_OSC_Header (Resp_Buffer, Resp_Len, BG_Query.Background);
            begin
               if Strip.Success then
                  declare
                     Parse : constant BG_Query.Parse_Result :=
                       BG_Query.Parse_RGB_Response
                         (Resp_Buffer (Strip.Offset .. Strip.Offset + Strip.Payload_Length - 1), Strip.Payload_Length);
                  begin
                     if Parse.Success then
                        return (Success => True, Color => Parse.Color);
                     end if;
                  end;
               end if;
            end;
         end if;
      end if;

      --  COLORFGBG fallback
      declare
         Env : Termicap.Environment.Environment;
      begin
         Termicap.Environment.Capture.Capture_Current (Env);
         declare
            Val : constant String := Termicap.Environment.Value (Env, "COLORFGBG");
         begin
            if Val'Length > 0 and then Val'Length <= BG_Query.MAX_COLORFGBG_LENGTH then
               declare
                  CFGBG : constant BG_Query.Colorfgbg_Result := BG_Query.Parse_Colorfgbg (Val);
               begin
                  if CFGBG.Success then
                     return (Success => True, Color => BG_Query.Ansi_To_RGB (CFGBG.Background));
                  end if;
               end;
            end if;
         end;
      end;

      return (Success => False, Error => No_Fallback);
   end Detect_Background_Color;

   function Detect_Foreground_Color (Timeout_Ms : Natural := 1_000) return Detection_Result is
      Effective_Timeout : constant Natural := Natural'Min (Timeout_Ms, MAX_TIMEOUT);
      Resp_Buffer       : BG_Query.Byte_Array (1 .. BG_Query.MAX_RESPONSE_SIZE);
      Resp_Len          : Natural;
      Timed_Out         : Boolean;
   begin
      if Effective_Timeout > 0 then
         BG_Query.IO.Query_Color
           (Kind        => BG_Query.Foreground,
            Timeout_Ms  => Effective_Timeout,
            Response    => Resp_Buffer,
            Resp_Length => Resp_Len,
            Timed_Out   => Timed_Out);

         if not Timed_Out and then Resp_Len > 0 then
            declare
               Strip : constant BG_Query.Strip_Result :=
                 BG_Query.Strip_OSC_Header (Resp_Buffer, Resp_Len, BG_Query.Foreground);
            begin
               if Strip.Success then
                  declare
                     Parse : constant BG_Query.Parse_Result :=
                       BG_Query.Parse_RGB_Response
                         (Resp_Buffer (Strip.Offset .. Strip.Offset + Strip.Payload_Length - 1), Strip.Payload_Length);
                  begin
                     if Parse.Success then
                        return (Success => True, Color => Parse.Color);
                     end if;
                  end;
               end if;
            end;
         end if;
      end if;

      --  COLORFGBG fallback
      declare
         Env : Termicap.Environment.Environment;
      begin
         Termicap.Environment.Capture.Capture_Current (Env);
         declare
            Val : constant String := Termicap.Environment.Value (Env, "COLORFGBG");
         begin
            if Val'Length > 0 and then Val'Length <= BG_Query.MAX_COLORFGBG_LENGTH then
               declare
                  CFGBG : constant BG_Query.Colorfgbg_Result := BG_Query.Parse_Colorfgbg (Val);
               begin
                  if CFGBG.Success then
                     return (Success => True, Color => BG_Query.Ansi_To_RGB (CFGBG.Foreground));
                  end if;
               end;
            end if;
         end;
      end;

      return (Success => False, Error => No_Fallback);
   end Detect_Foreground_Color;

end Termicap.Color.Detection;
