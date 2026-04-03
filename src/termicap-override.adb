-------------------------------------------------------------------------------
--  Termicap.Override - Global Enable/Disable Override (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements the process-wide override state via an Ada protected object,
--  thin wrappers, a pure CLI flag parser, and a Scoped_Override RAII guard.
--
--  @description
--  The body is SPARK_Mode => Off throughout because it uses Ada protected
--  objects (Ada tasking) and Ada.Finalization, both of which are outside the
--  SPARK 2014 subset.  The Abstract_State annotation on the spec is enough
--  for SPARK-annotated callers to reference Override_State in their own
--  Global aspects.
--
--  Note on early-call-region: SPARK requires that the first freezing point of
--  Scoped_Override (a tagged type with primitives declared in the spec) appears
--  within the early call region of each primitive body.  To satisfy this, the
--  protected object is accessed via a subtype and object declared after the
--  Scoped_Override primitive bodies, so those bodies compile before the
--  protected declaration could freeze Scoped_Override.
--
--  Requirements Coverage:
--    - @relation(FUNC-OVR-002): Set_Override implementation
--    - @relation(FUNC-OVR-003): Get_Override implementation
--    - @relation(FUNC-OVR-006): Thread-safe protected object
--    - @relation(FUNC-OVR-007): Scoped_Override Initialize / Finalize
--    - @relation(FUNC-OVR-008): Exception suppression in Finalize
--    - @relation(FUNC-OVR-011): Reset_Override convenience wrapper
--    - @relation(FUNC-OVR-013): Parse_Color_Flag pure function

with Ada.Characters.Handling;

package body Termicap.Override
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Forward declarations for protected operations (FUNC-OVR-006)
   --
   --  Declaring these stubs before the Scoped_Override primitive bodies
   --  ensures those bodies compile before the protected object declaration
   --  (which would otherwise freeze Scoped_Override).
   ---------------------------------------------------------------------------

   procedure Protected_Set (Mode : Override_Mode);
   function Protected_Get return Override_Mode;

   ---------------------------------------------------------------------------
   --  Scoped_Override: Initialize (FUNC-OVR-007)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-007)
   overriding
   procedure Initialize (Self : in out Scoped_Override) is
   begin
      Self.Saved := Protected_Get;
      Protected_Set (Self.Mode);
   end Initialize;

   ---------------------------------------------------------------------------
   --  Scoped_Override: Finalize (FUNC-OVR-007, FUNC-OVR-008)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-007)
   --  @relation(FUNC-OVR-008)
   overriding
   procedure Finalize (Self : in out Scoped_Override) is
   begin
      Protected_Set (Self.Saved);
   exception
      when others =>
         null;  --  Suppress all exceptions (FUNC-OVR-008)
   end Finalize;

   ---------------------------------------------------------------------------
   --  Protected object (FUNC-OVR-006)
   ---------------------------------------------------------------------------

   protected Override_Object is
      procedure Set (Mode : Override_Mode);
      function Get return Override_Mode;
   private
      State : Override_Mode := Auto;
   end Override_Object;

   protected body Override_Object is

      procedure Set (Mode : Override_Mode) is
      begin
         State := Mode;
      end Set;

      function Get return Override_Mode is
      begin
         return State;
      end Get;

   end Override_Object;

   ---------------------------------------------------------------------------
   --  Protected stub bodies (FUNC-OVR-006)
   ---------------------------------------------------------------------------

   procedure Protected_Set (Mode : Override_Mode) is
   begin
      Override_Object.Set (Mode);
   end Protected_Set;

   function Protected_Get return Override_Mode is
   begin
      return Override_Object.Get;
   end Protected_Get;

   ---------------------------------------------------------------------------
   --  Set_Override (FUNC-OVR-002)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-002)
   procedure Set_Override (Mode : Override_Mode) is
   begin
      Override_Object.Set (Mode);
   end Set_Override;

   ---------------------------------------------------------------------------
   --  Get_Override (FUNC-OVR-003)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-003)
   function Get_Override return Override_Mode is
   begin
      return Override_Object.Get;
   end Get_Override;

   ---------------------------------------------------------------------------
   --  Reset_Override (FUNC-OVR-011)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-011)
   procedure Reset_Override is
   begin
      Override_Object.Set (Auto);
   end Reset_Override;

   ---------------------------------------------------------------------------
   --  Parse_Color_Flag (FUNC-OVR-013)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-013)
   function Parse_Color_Flag (Value : String) return Override_Mode is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Value);
   begin
      if Lower = "never"
        or else Lower = "false"
        or else Lower = "off"
        or else Lower = "0"
      then
         return Force_None;
      elsif Lower = "true" or else Lower = "1" or else Lower = "16" then
         return Force_Basic;
      elsif Lower = "2" or else Lower = "256" then
         return Force_256;
      elsif Lower = "always"
        or else Lower = "truecolor"
        or else Lower = "16m"
        or else Lower = "3"
      then
         return Force_True_Color;
      else
         return Auto;
      end if;
   end Parse_Color_Flag;

end Termicap.Override;
