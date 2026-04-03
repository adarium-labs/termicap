-------------------------------------------------------------------------------
--  Termicap.Override - Global Enable/Disable Override
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Process-wide color output override for --color flag support.
--
--  @description
--  Provides a five-literal Override_Mode enumeration, a thread-safe protected
--  object for storing and retrieving the current override, a convenience
--  Reset_Override procedure, a pure Parse_Color_Flag function for mapping CLI
--  flag strings to Override_Mode values, and a Scoped_Override RAII type for
--  temporarily installing an override within a lexical scope.
--
--  The override state is process-wide and protected via an Ada protected
--  object (FUNC-OVR-006).  Set_Override and Get_Override delegate to that
--  object; their bodies are compiled with SPARK_Mode => Off.  The package
--  spec and all pure functions are compiled with SPARK_Mode => On (Silver).
--
--  No FFI, no OS calls, no Ada.Command_Line access (FUNC-OVR-009,
--  FUNC-OVR-014).
--
--  Requirements Coverage:
--    - @relation(FUNC-OVR-001): Override_Mode enumeration type
--    - @relation(FUNC-OVR-002): Set_Override procedure
--    - @relation(FUNC-OVR-003): Get_Override function
--    - @relation(FUNC-OVR-004): Override-to-Color_Level mapping (inline in Termicap.Color body)
--    - @relation(FUNC-OVR-006): Thread safety via protected object
--    - @relation(FUNC-OVR-007): Scoped_Override controlled type
--    - @relation(FUNC-OVR-008): Scoped_Override exception safety / Limited
--    - @relation(FUNC-OVR-009): No FFI dependency
--    - @relation(FUNC-OVR-010): SPARK Silver / Gold provability targets
--    - @relation(FUNC-OVR-011): Reset_Override convenience procedure
--    - @relation(FUNC-OVR-013): Parse_Color_Flag pure function
--    - @relation(FUNC-OVR-014): No automatic command-line parsing

with Ada.Finalization;

package Termicap.Override
  with
    SPARK_Mode,
    Abstract_State =>
      (Override_State with External => (Async_Readers, Async_Writers))
is

   pragma Elaborate_Body;

   ---------------------------------------------------------------------------
   --  Types (FUNC-OVR-001)
   ---------------------------------------------------------------------------

   --  @summary Process-wide color output override mode.
   --  @description Five-literal flat enumeration mapping directly onto the
   --  conventional --color flag values.  Auto means no override is active;
   --  the detection functions perform their normal logic.  The four Force_*
   --  literals map directly onto Color_Level values and bypass all detection.
   --  @relation(FUNC-OVR-001): Five-literal enumeration ÃÂ¢ÃÂÃÂ no other values representable
   type Override_Mode is
     (Auto, Force_None, Force_Basic, Force_256, Force_True_Color);

   ---------------------------------------------------------------------------
   --  Global State Access (FUNC-OVR-002, FUNC-OVR-003, FUNC-OVR-011)
   ---------------------------------------------------------------------------

   --  @summary Set the process-wide color override.
   --  @param Mode The override value to install.  Pass Auto to remove any
   --         previously installed override and restore normal detection.
   --  @relation(FUNC-OVR-002): Process-wide override setter; initial state is Auto
   procedure Set_Override (Mode : Override_Mode)
   with Global => (In_Out => Override_State);

   --  @summary Retrieve the current process-wide color override.
   --  @return The Override_Mode most recently supplied to Set_Override, or
   --          Auto if Set_Override has never been called.
   --  @relation(FUNC-OVR-003): Thread-safe getter; never raises an exception
   function Get_Override return Override_Mode
   with Global => (Input => Override_State);

   --  @summary Remove any previously installed override, restoring Auto.
   --  @description Semantically equivalent to Set_Override (Auto); provided
   --  as a self-documenting convenience for the common "clear override" case.
   --  @relation(FUNC-OVR-011): Convenience wrapper; equivalent to Set_Override (Auto)
   procedure Reset_Override
   with Global => (In_Out => Override_State), Post => Get_Override = Auto;

   ---------------------------------------------------------------------------
   --  CLI Flag Parsing (FUNC-OVR-013)
   ---------------------------------------------------------------------------

   --  @summary Parse a --color flag value string into an Override_Mode.
   --  @description Case-insensitive mapping.  Recognised values:
   --    "never"  | "false" | "off"       | "0"   -> Force_None
   --    "true"   | "1"     | "16"                 -> Force_Basic
   --    "2"      | "256"                           -> Force_256
   --    "always" | "truecolor" | "16m"  | "3"    -> Force_True_Color
   --    "auto"   | (anything else)                 -> Auto
   --  An unrecognised value returns Auto so that callers can treat unknown
   --  strings as "no override" rather than raising an exception.
   --  @param Value The raw flag value string (e.g. "always", "256").
   --  @return The Override_Mode corresponding to Value, or Auto for unknowns.
   --  @relation(FUNC-OVR-013): Pure, case-insensitive, total over all String inputs
   function Parse_Color_Flag (Value : String) return Override_Mode
   with Global => null;

   ---------------------------------------------------------------------------
   --  Scoped Override (FUNC-OVR-007, FUNC-OVR-008)
   ---------------------------------------------------------------------------

   --  @summary RAII scoped override guard.
   --  @description On declaration, captures the current override (via
   --  Get_Override) and installs Mode (via Set_Override).  On finalization
   --  (scope exit, including exception propagation), restores the previously
   --  captured mode.  Any exception raised during finalization is suppressed
   --  to comply with Ada stack-unwinding rules (FUNC-OVR-008).
   --
   --  The type is Limited_Controlled (not Controlled) to prevent copying:
   --  a copy would create two objects with the same Saved state, causing a
   --  double-restore when both finalize (FUNC-OVR-008).
   --
   --  @relation(FUNC-OVR-007): Initialize saves current mode, installs Mode discriminant
   --  @relation(FUNC-OVR-008): Finalize suppresses exceptions; non-copyable
   type Scoped_Override (Mode : Override_Mode) is
     new Ada.Finalization.Limited_Controlled with private;

private

   ---------------------------------------------------------------------------
   --  Private: Scoped_Override completion
   ---------------------------------------------------------------------------

   type Scoped_Override (Mode : Override_Mode) is
     new Ada.Finalization.Limited_Controlled
   with record
      Saved : Override_Mode := Auto;
   end record;

   --  Initialize: captures Get_Override into Saved, then calls Set_Override (Mode).
   --  Finalize  : calls Set_Override (Saved); suppresses any exception.
   --  Both procedures are implemented in the body with SPARK_Mode => Off
   --  because Ada.Finalization is outside the SPARK 2014 subset.

   overriding
   procedure Initialize (Self : in out Scoped_Override);
   overriding
   procedure Finalize (Self : in out Scoped_Override);

   --  The protected object and its Ada type are declared entirely in the
   --  package body (SPARK_Mode => Off section), since Ada protected types are
   --  outside the SPARK 2014 subset.  The Abstract_State annotation on the
   --  package spec (Override_State, External) allows SPARK-annotated callers
   --  to reference Override_State in their own Global aspects without the
   --  prover needing to reason about tasking.

end Termicap.Override;
