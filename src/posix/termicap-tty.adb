-------------------------------------------------------------------------------
--  Termicap.TTY - Terminal Teletype Detection (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implementation of TTY detection using POSIX isatty() via C FFI.
--
--  @description
--  This body has SPARK_Mode => Off because it uses pragma Import to bind
--  to the C library function isatty(). The spec remains SPARK-annotated
--  for type safety and contract documentation.
--
--  Requirements Coverage:
--    - @relation(FUNC-TTY-003): POSIX isatty() binding
--    - @relation(FUNC-TTY-004): Safe error-to-False mapping
--    - @relation(FUNC-TTY-005): SPARK_Mode => Off for FFI boundary

with Interfaces.C;

package body Termicap.TTY
  with SPARK_Mode => Off
is

   use type Interfaces.C.int;

   ---------------------------------------------------------------------------
   --  C Binding (FUNC-TTY-003)
   ---------------------------------------------------------------------------

   function C_Isatty (Fd : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Isatty, "isatty");

   ---------------------------------------------------------------------------
   --  File descriptor mapping
   ---------------------------------------------------------------------------

   FD_MAP : constant array (Stream_Kind) of Interfaces.C.int := [Stdin => 0, Stdout => 1, Stderr => 2];

   ---------------------------------------------------------------------------
   --  Is_TTY (FUNC-TTY-002, FUNC-TTY-003, FUNC-TTY-004)
   ---------------------------------------------------------------------------

   function Is_TTY (Stream : Stream_Kind) return Boolean is
   begin
      --  @relation(FUNC-OVR-005)
      case Termicap.Override.Get_Override is
         when Termicap.Override.Force_Basic | Termicap.Override.Force_256 | Termicap.Override.Force_True_Color =>
            return True;

         when Termicap.Override.Force_None =>
            return False;

         when Termicap.Override.Auto =>
            null;
      end case;
      return C_Isatty (FD_MAP (Stream)) = 1;
   end Is_TTY;

   ---------------------------------------------------------------------------
   --  Query_All (FUNC-TTY-006)
   ---------------------------------------------------------------------------

   function Query_All return TTY_Status is
   begin
      return (Stdin => Is_TTY (Stdin), Stdout => Is_TTY (Stdout), Stderr => Is_TTY (Stderr));
   end Query_All;

end Termicap.TTY;
