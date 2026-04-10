-------------------------------------------------------------------------------
--  Termicap.TTY - Terminal Teletype Detection (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @description
--  Windows implementation of TTY detection using GetConsoleMode().
--  A handle that responds successfully to GetConsoleMode is connected to a
--  Windows console (TTY).  Falls back to CONIN$/CONOUT$ if GetStdHandle fails.
--  Enables VT processing on stdout when it is a TTY.
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-003): GetConsoleMode-based TTY detection

with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;
with Termicap.Win32_VT;

package body Termicap.TTY
  with SPARK_Mode => Off
is

   use type Win32.BOOL;
   use type Win32.Winnt.HANDLE;

   ---------------------------------------------------------------------------
   --  Internal helper: detect TTY for a given Win32 standard handle constant
   ---------------------------------------------------------------------------

   function Is_TTY_Via_Handle
     (Std_Handle_Constant : Win32.DWORD;
      Is_Output           : Boolean) return Boolean
   is
      H    : Win32.Winnt.HANDLE;
      Mode : aliased Win32.DWORD := 0;
      Res  : Win32.BOOL;
   begin
      --  Try the standard handle first
      H := Win32.Winbase.GetStdHandle (Std_Handle_Constant);

      if not Termicap.Win32_VT.Is_Valid_Handle (H) then
         --  Fallback: open CONIN$ or CONOUT$ directly (FUNC-WIN-004)
         if Is_Output then
            H := Termicap.Win32_VT.Open_Console_Output;
         else
            H := Termicap.Win32_VT.Open_Console_Input;
         end if;

         if not Termicap.Win32_VT.Is_Valid_Handle (H) then
            return False;
         end if;

         --  Check whether it is a console handle
         Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
         Termicap.Win32_VT.Close_Handle (H);
         return Res /= Win32.FALSE;
      end if;

      --  GetConsoleMode succeeds iff the handle is attached to a console
      Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);

      if Res /= Win32.FALSE and then Is_Output then
         --  Enable VT processing on stdout (non-fatal if it fails)
         declare
            Dummy : constant Boolean :=
               Termicap.Win32_VT.Enable_VT_Processing (H);
            pragma Unreferenced (Dummy);
         begin
            null;
         end;
      end if;

      return Res /= Win32.FALSE;
   end Is_TTY_Via_Handle;

   ---------------------------------------------------------------------------
   --  Is_TTY (FUNC-WIN-003)
   ---------------------------------------------------------------------------

   function Is_TTY (Stream : Stream_Kind) return Boolean is
   begin
      --  Respect Force override first (FUNC-OVR-002, FUNC-TTY-002)
      case Termicap.Override.Get_Override is
         when Termicap.Override.Force_Basic
            | Termicap.Override.Force_256
            | Termicap.Override.Force_True_Color =>
            return True;
         when Termicap.Override.Force_None =>
            return False;
         when Termicap.Override.Auto =>
            null;
      end case;

      --  Map Stream_Kind to the appropriate Win32 standard handle constant
      --  and delegate to the handle-based detector
      case Stream is
         when Stdin =>
            return Is_TTY_Via_Handle
              (Win32.Winbase.STD_INPUT_HANDLE, Is_Output => False);
         when Stdout =>
            return Is_TTY_Via_Handle
              (Win32.Winbase.STD_OUTPUT_HANDLE, Is_Output => True);
         when Stderr =>
            return Is_TTY_Via_Handle
              (Win32.Winbase.STD_ERROR_HANDLE, Is_Output => True);
      end case;
   end Is_TTY;

   ---------------------------------------------------------------------------
   --  Query_All (FUNC-TTY-006)
   ---------------------------------------------------------------------------

   function Query_All return TTY_Status is
   begin
      return
        (Stdin  => Is_TTY (Stdin),
         Stdout => Is_TTY (Stdout),
         Stderr => Is_TTY (Stderr));
   end Query_All;

end Termicap.TTY;
