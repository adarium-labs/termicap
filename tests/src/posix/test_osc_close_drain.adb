-------------------------------------------------------------------------------
--  Test_OSC_Close_Drain - Unit Tests for Trailing Drain on Probe_Session Close
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases; use AUnit.Test_Cases.Registration;

with Interfaces.C;
with System;

with Termicap;     use Termicap;
with Termicap.OSC; use Termicap.OSC;

package body Test_OSC_Close_Drain is

   use type Interfaces.C.int;

   ---------------------------------------------------------------------------
   --  Minimal libc bindings (test-local; the production code already binds
   --  read/write via termicap_osc.c).
   ---------------------------------------------------------------------------

   type Pipe_FDs is array (0 .. 1) of aliased Interfaces.C.int;
   pragma Convention (C, Pipe_FDs);

   function C_Pipe (FDs : access Pipe_FDs) return Interfaces.C.int;
   pragma Import (C, C_Pipe, "pipe");

   function C_Write
     (FD : Interfaces.C.int; Buf : System.Address; Count : Interfaces.C.size_t) return Interfaces.C.long;
   pragma Import (C, C_Write, "write");

   function C_Close (FD : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Close, "close");

   --  Simulated DA1 reply: ESC [ ? 1 ; 2 c (7 bytes).
   Simulated_Reply : constant Byte_Array (1 .. 7) :=
     [16#1B#, 16#5B#, 16#3F#, 16#31#, 16#3B#, 16#32#, 16#63#];

   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   procedure Write_All (FD : Interfaces.C.int; Bytes : Byte_Array) is
      N : Interfaces.C.long;
   begin
      if Bytes'Length = 0 then
         return;
      end if;
      N := C_Write (FD, Bytes (Bytes'First)'Address, Interfaces.C.size_t (Bytes'Length));
      pragma Unreferenced (N);
   end Write_All;

   procedure Make_Pipe (Read_End, Write_End : out File_Descriptor; OK : out Boolean) is
      FDs    : aliased Pipe_FDs := [others => 0];
      Status : Interfaces.C.int;
   begin
      Status := C_Pipe (FDs'Access);
      if Status /= 0 then
         Read_End := INVALID_FD;
         Write_End := INVALID_FD;
         OK := False;
         return;
      end if;
      Read_End := File_Descriptor (FDs (0));
      Write_End := File_Descriptor (FDs (1));
      OK := True;
   end Make_Pipe;

   procedure Close_FD (FD : in out File_Descriptor) is
      Status : Interfaces.C.int;
   begin
      if FD = INVALID_FD then
         return;
      end if;
      Status := C_Close (Interfaces.C.int (FD));
      pragma Unreferenced (Status);
      FD := INVALID_FD;
   end Close_FD;

   --  Delayed writer task: waits Delay_Ms milliseconds, then writes
   --  Simulated_Reply to the given FD once.
   task type Delayed_Writer is
      entry Start (FD : Interfaces.C.int; Delay_Ms : Natural);
   end Delayed_Writer;

   task body Delayed_Writer is
      My_FD       : Interfaces.C.int;
      My_Delay_Ms : Natural;
   begin
      accept Start (FD : Interfaces.C.int; Delay_Ms : Natural) do
         My_FD := FD;
         My_Delay_Ms := Delay_Ms;
      end Start;

      delay Duration (My_Delay_Ms) / 1_000.0;
      Write_All (My_FD, Simulated_Reply);
   end Delayed_Writer;

   ---------------------------------------------------------------------------
   --  Test registration
   ---------------------------------------------------------------------------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.OSC (Close trailing drain)");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      Register_Routine
        (T,
         Test_Drain_Input_Absorbs_Preloaded'Access,
         "FUNC-OSC-020: Drain_Input absorbs pre-loaded bytes on a pipe");
      Register_Routine
        (T,
         Test_Timed_Read_Catches_Delayed_Reply'Access,
         "FUNC-OSC-020: Timed_Read with 50 ms grace catches a delayed reply");
      Register_Routine
        (T,
         Test_Grace_Then_NonBlocking_Loop'Access,
         "FUNC-OSC-020: Grace-then-non-blocking loop drains delayed reply to empty");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Test bodies
   ---------------------------------------------------------------------------

   procedure Test_Drain_Input_Absorbs_Preloaded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Read_End, Write_End : File_Descriptor;
      Pipe_OK             : Boolean;
      Probe_Buf           : Byte_Array (1 .. 32);
      Bytes_Read          : Natural;
      Timed_Out           : Boolean;
   begin
      Make_Pipe (Read_End, Write_End, Pipe_OK);
      Assert (Pipe_OK, "pipe(2) failed; cannot run pipe-based drain test");

      --  Pre-load the read end with reply bytes.
      Write_All (Interfaces.C.int (Write_End), Simulated_Reply);

      --  Run the open-side drain.
      Drain_Input (Read_End);

      --  Verify nothing remains queued.
      Timed_Read (Read_End, Probe_Buf, Bytes_Read, 0, Timed_Out);
      Assert
        (Bytes_Read = 0,
         "Drain_Input left" & Natural'Image (Bytes_Read) & " bytes in the pipe queue (expected 0)");

      Close_FD (Write_End);
      Close_FD (Read_End);
   end Test_Drain_Input_Absorbs_Preloaded;

   procedure Test_Timed_Read_Catches_Delayed_Reply (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Read_End, Write_End : File_Descriptor;
      Pipe_OK             : Boolean;
      Probe_Buf           : Byte_Array (1 .. 32);
      Bytes_Read          : Natural;
      Timed_Out           : Boolean;
      Writer              : Delayed_Writer;
   begin
      Make_Pipe (Read_End, Write_End, Pipe_OK);
      Assert (Pipe_OK, "pipe(2) failed; cannot run delayed-reply timing test");

      Writer.Start (Interfaces.C.int (Write_End), 20);

      Timed_Read (Read_End, Probe_Buf, Bytes_Read, 50, Timed_Out);

      Assert
        (Bytes_Read > 0,
         "Timed_Read with 50 ms grace returned 0 bytes; expected the delayed reply");
      Assert
        (not Timed_Out,
         "Timed_Read with 50 ms grace timed out before the delayed reply arrived");

      while not Writer'Terminated loop
         delay 0.001;
      end loop;

      Close_FD (Write_End);
      Close_FD (Read_End);
   end Test_Timed_Read_Catches_Delayed_Reply;

   procedure Test_Grace_Then_NonBlocking_Loop (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Read_End, Write_End  : File_Descriptor;
      Pipe_OK              : Boolean;
      Drain_Buf            : Byte_Array (1 .. 256);
      Bytes_Read           : Natural;
      Timed_Out            : Boolean;
      Wait_Ms              : Natural := 50;  --  matches CLOSE_DRAIN_GRACE_MS
      Total                : Natural := 0;
      Writer               : Delayed_Writer;
      MAX_DRAIN_ITERATIONS : constant := 16;
   begin
      Make_Pipe (Read_End, Write_End, Pipe_OK);
      Assert (Pipe_OK, "pipe(2) failed; cannot run grace-loop test");

      Writer.Start (Interfaces.C.int (Write_End), 20);

      for Iter in 1 .. MAX_DRAIN_ITERATIONS loop
         Timed_Read (Read_End, Drain_Buf, Bytes_Read, Wait_Ms, Timed_Out);
         exit when Bytes_Read = 0;
         Total := Total + Bytes_Read;
         Wait_Ms := 0;
      end loop;

      Assert
        (Total = Simulated_Reply'Length,
         "Grace-loop drained" & Natural'Image (Total) & " bytes; expected" & Natural'Image (Simulated_Reply'Length));

      Timed_Read (Read_End, Drain_Buf, Bytes_Read, 0, Timed_Out);
      Assert
        (Bytes_Read = 0,
         "Grace-loop left" & Natural'Image (Bytes_Read) & " bytes in the pipe queue (expected 0)");

      while not Writer'Terminated loop
         delay 0.001;
      end loop;

      Close_FD (Write_End);
      Close_FD (Read_End);
   end Test_Grace_Then_NonBlocking_Loop;

end Test_OSC_Close_Drain;
