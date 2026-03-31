--  Compatibility shim: exposes AUnit.Test_Cases.Registration as a child
--  package. In AUnit 26 this functionality lives in a nested package inside
--  AUnit.Test_Cases; this child-package facade re-exports the same API so
--  that test files can use "with AUnit.Test_Cases.Registration".

package AUnit.Test_Cases.Registration is

   procedure Register_Routine
      (Test    : in out AUnit.Test_Cases.Test_Case'Class;
       Routine : AUnit.Test_Cases.Test_Routine;
       Name    : String);

end AUnit.Test_Cases.Registration;
