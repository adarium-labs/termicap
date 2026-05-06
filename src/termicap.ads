-------------------------------------------------------------------------------
--  Termicap - Root Package
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

pragma SPARK_Mode (On);

with Interfaces.C;

package Termicap
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Shared Byte Types
   ---------------------------------------------------------------------------

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   --  @description Shared by all child packages that exchange raw escape sequence
   --  bytes with the terminal.  Placing it here avoids re-defining the subtype
   --  in every SPARK On child package just to sidestep the Termicap.OSC
   --  (SPARK Off) dependency.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for terminal queries and responses.
   --  @description Used for escape sequence query constants and raw response buffers
   --  in all probe and parsing packages.
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Shared Capacity Constant
   ---------------------------------------------------------------------------

   --  @summary Maximum number of response bytes accumulated by any probe query.
   --  @description All probe packages bound their response buffers to this value.
   --  4 KiB is a conservative ceiling: the largest known terminal response
   --  (DA1 with many extended parameters) is well under 256 bytes.
   MAX_RESPONSE_SIZE : constant := 4_096;

end Termicap;
