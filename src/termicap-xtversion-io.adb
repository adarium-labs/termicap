-------------------------------------------------------------------------------
--  Termicap.XTVERSION.IO - XTVERSION Query I/O Procedure
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (Off);

with Termicap.OSC;
with Termicap.OSC.Parsing;
with Termicap.Terminal_Id;
with Termicap.Environment;
with Termicap.Environment.Capture;

package body Termicap.XTVERSION.IO is

   ---------------------------------------------------------------------------
   --  Internal helper: derive passthrough mode from terminal identity.
   ---------------------------------------------------------------------------

   function Passthrough_For_Identity
     (Identity : Termicap.Terminal_Id.Terminal_Identity) return Termicap.OSC.Parsing.Passthrough_Mode
   is
      use Termicap.Terminal_Id;
      use Termicap.OSC.Parsing;
   begin
      if Identity.Kind = Tmux then
         return Tmux_Passthrough;
      elsif Identity.Kind = Screen then
         return Screen_Passthrough;
      else
         return No_Passthrough;
      end if;
   end Passthrough_For_Identity;

   procedure Query_XTVERSION
     (Timeout_Ms : Natural; Response : out Byte_Array; Resp_Length : out Natural; Timed_Out : out Boolean)
   is
      use Termicap.OSC;
      use Termicap.Terminal_Id;

      Env          : Termicap.Environment.Environment;
      Identity     : Termicap.Terminal_Id.Terminal_Identity;
      Passthrough  : Termicap.OSC.Parsing.Passthrough_Mode;
      OSC_Response : Termicap.OSC.Response_Buffer;
      OSC_Length   : Natural;
      OSC_Timeout  : Boolean;
   begin
      --  Capture environment and detect terminal identity for multiplexer check
      Termicap.Environment.Capture.Capture_Current (Env);
      Identity    := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);
      Passthrough := Passthrough_For_Identity (Identity);

      declare
         Wrapped : constant Byte_Array :=
           Termicap.OSC.Parsing.Wrap_For_Passthrough (CSI_XTVERSION_QUERY, Passthrough);
         Session : Termicap.OSC.Probe_Session;
         Status  : Termicap.OSC.Session_Status;
      begin
         Termicap.OSC.Open (Session, Status);
         if Status /= Session_OK then
            Resp_Length := 0;
            Timed_Out := True;
            Response := [others => 0];
            return;
         end if;

         Termicap.OSC.Sentinel_Query
           (Session     => Session,
            Query       => Wrapped,
            Response    => OSC_Response,
            Resp_Length => OSC_Length,
            Timeout_Ms  => Timeout_Ms,
            Timed_Out   => OSC_Timeout,
            Retry       => False);

         Resp_Length := OSC_Length;
         Timed_Out := OSC_Timeout;
         for I in 1 .. OSC_Length loop
            Response (I) := OSC_Response (I);
         end loop;
      end;
   end Query_XTVERSION;

   function Query_And_Identify (Timeout_Ms : Natural := 100) return XTVERSION_Result is
      Resp_Buffer : Byte_Array (1 .. MAX_RESPONSE_SIZE);
      Resp_Len    : Natural;
      Timed_Out   : Boolean;
   begin
      Query_XTVERSION
        (Timeout_Ms => Timeout_Ms, Response => Resp_Buffer, Resp_Length => Resp_Len, Timed_Out => Timed_Out);

      if Timed_Out then
         return (Status => Timeout);
      end if;

      return Parse_XTVERSION_Response (Resp_Buffer, Resp_Len);
   end Query_And_Identify;

end Termicap.XTVERSION.IO;
