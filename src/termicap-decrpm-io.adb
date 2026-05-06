-------------------------------------------------------------------------------
--  Termicap.DECRPM.IO - DECRPM Private Mode Query I/O (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (Off);

with Termicap.OSC.Parsing;
with Termicap.Terminal_Id;
with Termicap.Environment;
with Termicap.Environment.Capture;

package body Termicap.DECRPM.IO is

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

   ---------------------------------------------------------------------------
   --  Query_Mode (FUNC-RPM-008)
   ---------------------------------------------------------------------------

   procedure Query_Mode
     (Mode        : Mode_Id;
      Timeout_Ms  : Natural;
      Response    : out Termicap.OSC.Response_Buffer;
      Resp_Length : out Natural;
      Timed_Out   : out Boolean)
   is
      use Termicap.OSC;

      Env         : Termicap.Environment.Environment;
      Identity    : Termicap.Terminal_Id.Terminal_Identity;
      Passthrough : Termicap.OSC.Parsing.Passthrough_Mode;
      Query_Bytes : constant Byte_Array := DECRPM_Query (Mode);
   begin
      Response := [others => 0];
      Resp_Length := 0;
      Timed_Out := True;

      Termicap.Environment.Capture.Capture_Current (Env);
      Identity := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);
      Passthrough := Passthrough_For_Identity (Identity);

      declare
         Wrapped : constant Byte_Array :=
           Termicap.OSC.Parsing.Wrap_For_Passthrough (Query_Bytes, Passthrough);
         Session : Termicap.OSC.Probe_Session;
         Status  : Termicap.OSC.Session_Status;
      begin
         Termicap.OSC.Open (Session, Status);
         if Status /= Session_OK then
            return;
         end if;

         Termicap.OSC.Sentinel_Query
           (Session     => Session,
            Query       => Wrapped,
            Response    => Response,
            Resp_Length => Resp_Length,
            Timeout_Ms  => Timeout_Ms,
            Timed_Out   => Timed_Out,
            Retry       => False);
      end;
   end Query_Mode;

   ---------------------------------------------------------------------------
   --  Detect_Mode (FUNC-RPM-009)
   ---------------------------------------------------------------------------

   function Detect_Mode (Mode : Mode_Id; Timeout_Ms : Natural := 100) return Mode_Query_Result is
      Resp_Buffer : Termicap.OSC.Response_Buffer;
      Resp_Length : Natural;
      Timed_Out   : Boolean;
      Report      : Mode_Report;
   begin
      Query_Mode (Mode, Timeout_Ms, Resp_Buffer, Resp_Length, Timed_Out);

      if Timed_Out then
         return (Success => False, Error => Query_Timeout);
      end if;

      Report := Parse_DECRPM_Response (Byte_Array (Resp_Buffer), Resp_Length);

      if Report.Mode = 0 then
         return (Success => False, Error => Parse_Failed);
      end if;

      return (Success => True, Report => Report);
   end Detect_Mode;

   ---------------------------------------------------------------------------
   --  Detect_Modes (FUNC-RPM-011)
   ---------------------------------------------------------------------------

   function Detect_Modes
     (Modes : Mode_Id_Array; Count : Positive; Timeout_Ms : Natural := 200) return Batch_Query_Result
   is
      use Termicap.OSC;

      MIN_PER_QUERY : constant Natural := 50;
      Results       : Mode_Report_Array := [others => (Mode => 0, Status => Not_Recognized)];
      Env           : Termicap.Environment.Environment;
      Identity      : Termicap.Terminal_Id.Terminal_Identity;
      Passthrough   : Termicap.OSC.Parsing.Passthrough_Mode;
      Per_Timeout   : Natural;
      Resp_Buffer   : Termicap.OSC.Response_Buffer;
      Resp_Length   : Natural;
      Timed_Out     : Boolean;
      Report        : Mode_Report;
      Session       : Termicap.OSC.Probe_Session;
      Status        : Termicap.OSC.Session_Status;
   begin
      Termicap.Environment.Capture.Capture_Current (Env);
      Identity := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);
      Passthrough := Passthrough_For_Identity (Identity);

      Termicap.OSC.Open (Session, Status);
      if Status /= Session_OK then
         return (Success => False, Error => Not_A_Terminal);
      end if;

      Per_Timeout := Natural'Max (MIN_PER_QUERY, Timeout_Ms / Count);

      for I in 1 .. Count loop
         declare
            Query_Bytes : constant Byte_Array := DECRPM_Query (Modes (I));
            Wrapped     : constant Byte_Array :=
              Termicap.OSC.Parsing.Wrap_For_Passthrough (Query_Bytes, Passthrough);
         begin
            Resp_Buffer := [others => 0];
            Resp_Length := 0;
            Timed_Out := True;

            Termicap.OSC.Sentinel_Query
              (Session     => Session,
               Query       => Wrapped,
               Response    => Resp_Buffer,
               Resp_Length => Resp_Length,
               Timeout_Ms  => Per_Timeout,
               Timed_Out   => Timed_Out,
               Retry       => False);

            if not Timed_Out then
               Report := Parse_DECRPM_Response (Byte_Array (Resp_Buffer), Resp_Length);
               if Report.Mode > 0 then
                  Results (I) := Report;
               else
                  Results (I) := (Mode => Modes (I), Status => Not_Recognized);
               end if;
            else
               Results (I) := (Mode => Modes (I), Status => Not_Recognized);
            end if;
         end;
      end loop;

      return (Success => True, Reports => Results, Count => Count);
   end Detect_Modes;

end Termicap.DECRPM.IO;
