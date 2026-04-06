-------------------------------------------------------------------------------
--  Termicap.DA1.IO - DA1 Primary Device Attributes Query I/O (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Implementation of Query_DA1 (FUNC-DA1-008) and Detect_DA1 (FUNC-DA1-009).
--
--  Query_DA1 differs from all other I/O procedures in that it CANNOT use the
--  Sentinel_Query pattern: the DA1 response IS the capability data being sought.
--  Appending a second CSI c sentinel would produce two overlapping DA1 responses,
--  making boundary detection ambiguous.  Instead, Query_DA1 delegates to
--  Timeout_Query (FUNC-DA1-008, ADR-0017), which writes DA1_QUERY once and then
--  accumulates bytes until Contains_DA1_Response returns True or the elapsed time
--  exceeds Timeout_Ms, without appending any sentinel.
--
--  Requirements Coverage:
--    - @relation(FUNC-DA1-008): Query_DA1 I/O procedure with timeout-only read loop
--    - @relation(FUNC-DA1-009): Detect_DA1 convenience function
--    - @relation(FUNC-DA1-010): Foreground guard via Probe_Session.Open
--    - @relation(FUNC-DA1-011): Not-a-TTY guard via Probe_Session.Open
--    - @relation(FUNC-DA1-012): Multiplexer passthrough selection

pragma SPARK_Mode (Off);

with Termicap.OSC.Parsing;
with Termicap.Terminal_Id;
with Termicap.Environment;
with Termicap.Environment.Capture;

package body Termicap.DA1.IO is

   ---------------------------------------------------------------------------
   --  Query_DA1 (FUNC-DA1-008)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-DA1-008): DA1 I/O procedure with timeout-only read loop
   procedure Query_DA1
     (Timeout_Ms  :     Natural;
      Response    : out Termicap.OSC.Response_Buffer;
      Resp_Length : out Natural;
      Timed_Out   : out Boolean)
   is
      use Termicap.OSC;
      use Termicap.Terminal_Id;

      Env         : Termicap.Environment.Environment;
      Identity    : Termicap.Terminal_Id.Terminal_Identity;
      Passthrough : Termicap.OSC.Parsing.Passthrough_Mode;
   begin
      --  Initialise outputs.
      Response    := [others => 0];
      Resp_Length := 0;
      Timed_Out   := True;

      --  Step 1: Capture environment and detect terminal identity.
      Termicap.Environment.Capture.Capture_Current (Env);
      Identity := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);

      --  Derive passthrough mode from terminal identity (FUNC-DA1-012).
      if not Identity.Is_Multiplexer then
         Passthrough := Termicap.OSC.Parsing.No_Passthrough;
      elsif Identity.Kind = Tmux then
         Passthrough := Termicap.OSC.Parsing.Tmux_Passthrough;
      elsif Identity.Kind = Screen then
         Passthrough := Termicap.OSC.Parsing.Screen_Passthrough;
      else
         --  Any other multiplexer: use tmux passthrough as safe default.
         Passthrough := Termicap.OSC.Parsing.Tmux_Passthrough;
      end if;

      declare
         --  Step 2: Wrap DA1_QUERY for multiplexer passthrough if required.
         Wrapped : constant Termicap.OSC.Byte_Array :=
           Termicap.OSC.Parsing.Wrap_For_Passthrough
             (Termicap.OSC.Byte_Array (DA1_QUERY), Passthrough);

         Session : Termicap.OSC.Probe_Session;
         Status  : Termicap.OSC.Session_Status;
      begin
         --  Step 3: Open a Probe_Session (FUNC-DA1-010, FUNC-DA1-011).
         Termicap.OSC.Open (Session, Status);
         if Status /= Session_OK then
            --  Session failed to open; outputs already set to error defaults.
            return;
         end if;

         --  Steps 4-6: Timeout-only read loop via Timeout_Query (ADR-0017).
         Termicap.OSC.Timeout_Query
           (Session     => Session,
            Query       => Wrapped,
            Response    => Response,
            Resp_Length => Resp_Length,
            Timeout_Ms  => Timeout_Ms,
            Timed_Out   => Timed_Out);

         --  Step 7: Probe_Session closes automatically via RAII Finalize.
      end;
   end Query_DA1;

   ---------------------------------------------------------------------------
   --  Detect_DA1 (FUNC-DA1-009)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-DA1-009): Detect_DA1 convenience function
   function Detect_DA1
     (Timeout_Ms : Natural := 100) return DA1_Capabilities
   is
      Resp_Buffer : Termicap.OSC.Response_Buffer;
      Resp_Length : Natural;
      Timed_Out   : Boolean;
      Params      : Termicap.OSC.Parsing.DA1_Params;
   begin
      --  Step 1: Obtain raw response bytes via the I/O layer.
      Query_DA1
        (Timeout_Ms  => Timeout_Ms,
         Response    => Resp_Buffer,
         Resp_Length => Resp_Length,
         Timed_Out   => Timed_Out);

      --  Step 2: Timed out -> return default (Supported => False).
      if Timed_Out then
         return DA1_Capabilities'
           (Supported => False,
            Level     => Unknown,
            Flags     => [others => False]);
      end if;

      --  Step 3: Parse the raw bytes into DA1_Params.
      Params := Termicap.OSC.Parsing.Parse_DA1_Response (Resp_Buffer, Resp_Length);

      --  Step 4: Interpret the parsed parameters into DA1_Capabilities.
      --  Step 5: Return the result.
      return Interpret_DA1 (Params);
   end Detect_DA1;

end Termicap.DA1.IO;
