-------------------------------------------------------------------------------
--  Test_OSC_Close_Drain - Unit Tests for Trailing Drain on Probe_Session Close
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the trailing-drain pattern used by
--  Termicap.OSC.Close (FUNC-OSC-020) to prevent terminal response bytes
--  arriving after a query timeout from leaking into the controlling shell.
--
--  @description
--  The actual Drain_Input_With_Grace helper is body-local to
--  src/posix/termicap-osc.adb, so these tests exercise the same primitive
--  it composes (Termicap.OSC.Timed_Read) against a POSIX pipe pair, using
--  an Ada task to inject delayed bytes that simulate a slow terminal reply.
--  The third test re-implements the helper's grace-then-non-blocking loop
--  with public APIs and verifies the algorithm absorbs the delayed bytes
--  and leaves the read end empty.
--
--  A full PTY-based behavioural test of Close itself (open a Probe_Session
--  against a controlled PTY, send a delayed DA1 reply, Close, verify no
--  bytes left on the parent side) is deferred to tools/conformance/ since
--  adding a fork + PTY harness is out of scope for the AUnit suite.
--
--  POSIX-only: relies on pipe(2) / write(2) / close(2).
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-020): Trailing input drain on session close

with AUnit.Test_Cases;

package Test_OSC_Close_Drain is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-OSC-020: Trailing input drain on Close
   ---------------------------------------------------------------------------

   --  FUNC-OSC-020: Drain_Input on a pipe pair with pre-loaded bytes
   --  absorbs every byte and leaves the read end empty (verifies the
   --  open-side primitive the trailing drain composes on).
   procedure Test_Drain_Input_Absorbs_Preloaded (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-020: Timed_Read with a 50 ms grace window absorbs bytes
   --  that arrive ~20 ms after the call starts (simulates a DA1 reply
   --  still in flight when Close is invoked).
   procedure Test_Timed_Read_Catches_Delayed_Reply (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-OSC-020: Grace-then-non-blocking loop (the algorithm used by
   --  Drain_Input_With_Grace) catches a delayed reply on the first
   --  iteration and then drains the queue to empty.
   procedure Test_Grace_Then_NonBlocking_Loop (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_OSC_Close_Drain;
