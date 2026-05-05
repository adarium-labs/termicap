--  Compatibility shim body: implements AUnit.Test_Cases.Registration as a
--  true Ada child package.  Delegates to AUnit.Test_Cases.Add_Routine, which
--  is the underlying implementation now that the nested Registration package
--  has been removed from AUnit.Test_Cases to avoid a name conflict.

with AUnit;

package body AUnit.Test_Cases.Registration is

   procedure Register_Routine
     (Test    : in out AUnit.Test_Cases.Test_Case'Class;
      Routine : AUnit.Test_Cases.Test_Routine;
      Name    : String)
   is
      Val : constant AUnit.Test_Cases.Routine_Spec :=
        (Routine      => Routine,
         Routine_Name => AUnit.Format (Name));
   begin
      AUnit.Test_Cases.Add_Routine (Test, Val);
   end Register_Routine;

end AUnit.Test_Cases.Registration;
