-------------------------------------------------------------------------------
--  Termicap.Color.BG_Query.IO - OSC Color Query I/O (Body)
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

package body Termicap.Color.BG_Query.IO is

   procedure Query_Color
     (Kind        :     BG_Query.Query_Kind;
      Timeout_Ms  :     Natural;
      Response    : out BG_Query.Byte_Array;
      Resp_Length : out Natural;
      Timed_Out   : out Boolean)
   is
      use Termicap.OSC;
      use Termicap.Terminal_Id;

      Query_Bytes : constant BG_Query.Byte_Array :=
        BG_Query.Query_Sequence (Kind);
      Env         : Termicap.Environment.Environment;
      Identity    : Termicap.Terminal_Id.Terminal_Identity;
      Passthrough : Termicap.OSC.Parsing.Passthrough_Mode;
      OSC_Response : Termicap.OSC.Response_Buffer;
      OSC_Length   : Natural;
      OSC_Timeout  : Boolean;
   begin
      --  Capture environment and detect terminal identity for multiplexer check
      Termicap.Environment.Capture.Capture_Current (Env);
      Identity := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);

      --  Determine passthrough mode from terminal identity
      if Identity.Kind = Tmux then
         Passthrough := Termicap.OSC.Parsing.Tmux_Passthrough;
      elsif Identity.Kind = Screen then
         Passthrough := Termicap.OSC.Parsing.Screen_Passthrough;
      else
         Passthrough := Termicap.OSC.Parsing.No_Passthrough;
      end if;

      declare
         Wrapped : constant Termicap.OSC.Byte_Array :=
           Termicap.OSC.Parsing.Wrap_For_Passthrough
             (Termicap.OSC.Byte_Array (Query_Bytes), Passthrough);
         Session : Termicap.OSC.Probe_Session;
         Status  : Termicap.OSC.Session_Status;
      begin
         Termicap.OSC.Open (Session, Status);
         if Status /= Session_OK then
            Resp_Length := 0;
            Timed_Out   := True;
            Response    := [others => 0];
            return;
         end if;

         Termicap.OSC.Sentinel_Query
           (Session     => Session,
            Query       => Wrapped,
            Response    => OSC_Response,
            Resp_Length => OSC_Length,
            Timeout_Ms  => Timeout_Ms,
            Timed_Out   => OSC_Timeout);

         Resp_Length := OSC_Length;
         Timed_Out   := OSC_Timeout;
         for I in 1 .. OSC_Length loop
            Response (I) := BG_Query.Byte (OSC_Response (I));
         end loop;
      end;
   end Query_Color;

end Termicap.Color.BG_Query.IO;
