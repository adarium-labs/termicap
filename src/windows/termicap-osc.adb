-------------------------------------------------------------------------------
--  Termicap.OSC - OSC Probe Session and Terminal I/O (Windows Stub Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows stub for OSC probe sessions.  /dev/tty does not exist on Windows;
--  all session operations return failure / no-op results.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-008): Session open returns Session_No_Terminal on Windows

pragma SPARK_Mode (Off);

package body Termicap.OSC is

   ---------------------------------------------------------------------------
   --  Session Lifecycle
   ---------------------------------------------------------------------------

   procedure Open
     (Session : in out Probe_Session; Status : out Session_Status) is
      pragma Unreferenced (Session);
   begin
      --  /dev/tty does not exist on Windows
      Status := Session_No_Terminal;
   end Open;

   function Is_Open (Session : Probe_Session) return Boolean is
   begin
      return Session.FD /= INVALID_FD and then Session.Is_Raw;
   end Is_Open;

   procedure Close (Session : in out Probe_Session) is
   begin
      Session.FD     := INVALID_FD;
      Session.Is_Raw := False;
   end Close;

   overriding
   procedure Finalize (Session : in out Probe_Session) is
   begin
      Close (Session);
   end Finalize;

   ---------------------------------------------------------------------------
   --  Query Operations (no-op stubs)
   ---------------------------------------------------------------------------

   procedure Sentinel_Query
     (Session     : Probe_Session;
      Query       : Byte_Array;
      Response    : out Response_Buffer;
      Resp_Length : out Natural;
      Timeout_Ms  : Natural;
      Timed_Out   : out Boolean;
      Retry       : Boolean := False)
   is
      pragma Unreferenced (Session, Query, Timeout_Ms, Retry);
   begin
      Response    := [others => 0];
      Resp_Length := 0;
      Timed_Out   := True;
   end Sentinel_Query;

   procedure Timeout_Query
     (Session     : Probe_Session;
      Query       : Byte_Array;
      Response    : out Response_Buffer;
      Resp_Length : out Natural;
      Timeout_Ms  : Natural;
      Timed_Out   : out Boolean)
   is
      pragma Unreferenced (Session, Query, Timeout_Ms);
   begin
      Response    := [others => 0];
      Resp_Length := 0;
      Timed_Out   := True;
   end Timeout_Query;

   ---------------------------------------------------------------------------
   --  Low-Level I/O Stubs
   ---------------------------------------------------------------------------

   procedure Write_Query
     (Session : Probe_Session;
      Query   : Byte_Array;
      Written : out Natural;
      Success : out Boolean)
   is
      pragma Unreferenced (Session, Query);
   begin
      Written := 0;
      Success := False;
   end Write_Query;

   procedure Timed_Read
     (FD         : File_Descriptor;
      Buffer     : out Byte_Array;
      Bytes_Read : out Natural;
      Timeout_Ms : Natural;
      Timed_Out  : out Boolean)
   is
      pragma Unreferenced (FD, Timeout_Ms);
   begin
      Buffer     := [others => 0];
      Bytes_Read := 0;
      Timed_Out  := True;
   end Timed_Read;

   function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
      pragma Unreferenced (FD);
   begin
      return True;
   end Is_Foreground_Process;

   function Open_Terminal return File_Descriptor is
   begin
      return INVALID_FD;
   end Open_Terminal;

   procedure Close_Terminal (FD : in out File_Descriptor) is
   begin
      FD := INVALID_FD;
   end Close_Terminal;

   procedure Save_Termios
     (FD : File_Descriptor; State : out Termios_State; OK : out Boolean)
   is
      pragma Unreferenced (FD);
   begin
      --  Termios_State is a limited record; initialize fields individually.
      for I in State.Data'Range loop
         State.Data (I) := 0;
      end loop;
      State.Size := 0;
      OK         := False;
   end Save_Termios;

   procedure Restore_Termios
     (FD : File_Descriptor; State : Termios_State; OK : out Boolean)
   is
      pragma Unreferenced (FD, State);
   begin
      OK := False;
   end Restore_Termios;

   procedure Set_Raw_Mode
     (FD : File_Descriptor; State : Termios_State; OK : out Boolean)
   is
      pragma Unreferenced (FD, State);
   begin
      OK := False;
   end Set_Raw_Mode;

   procedure Drain_Input (FD : File_Descriptor) is
      pragma Unreferenced (FD);
   begin
      null;
   end Drain_Input;

end Termicap.OSC;
