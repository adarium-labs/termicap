-------------------------------------------------------------------------------
--  Termicap.Environment.Capture - OS Environment Capture
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Captures the current process environment into an Environment snapshot.
--
--  @description
--  This package is the sole OS interaction point for environment variable
--  access.  It reads the live process environment via
--  Ada.Environment_Variables and produces an immutable Environment snapshot.
--
--  This package has SPARK_Mode => Off because Ada.Environment_Variables
--  performs OS calls that cannot be verified by GNATprove.  All downstream
--  detection logic operates on the captured snapshot, which is fully
--  SPARK-provable.
--
--  Requirements Coverage:
--    - @relation(FUNC-ENV-004): Capture current process environment

package Termicap.Environment.Capture
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Capture Operation (FUNC-ENV-004)
   ---------------------------------------------------------------------------

   --  @summary Capture the current process environment into a snapshot.
   --  @param Env  Output parameter that receives the populated snapshot.
   --              Any previous content is discarded.
   --  @relation(FUNC-ENV-004): FFI boundary — sole point of OS env interaction
   procedure Capture_Current (Env : out Environment);

end Termicap.Environment.Capture;
