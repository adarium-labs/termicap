-------------------------------------------------------------------------------
--  Termicap.Hyperlinks - OSC 8 Hyperlink Support Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Types, constants, and functions for two-tier OSC 8 hyperlink support
--  detection: passive heuristic (SPARK Silver) and XTVERSION refinement.
--
--  @description
--  Tier 1 — Passive classification (FUNC-HYP-007):
--    Classify_Hyperlinks_Support is a pure SPARK Silver function that inspects
--    the TERM environment variable and Terminal_Identity.Kind.  It classifies
--    the terminal into one of four Hyperlinks_Support values using:
--      Step 1: TERM legacy-prefix exclusion (FUNC-HYP-004)
--      Step 2: Terminal_Kind hard exclusion (FUNC-HYP-005b)
--      Step 3: Terminal_Kind known-good list (FUNC-HYP-005)
--
--  Tier 2 — XTVERSION refinement (FUNC-HYP-011):
--    Refine_With_XTVERSION is a pure value-to-value Ada function (SPARK_Mode Off
--    because of Unbounded_String in XTVERSION_Result) that promotes
--    Likely_Supported -> Supported or demotes to Unsupported based on a
--    known-good version table and the XTVERSION result already collected by
--    Detect_Full Step 9 (ADR-0038).  No new probe session is opened.
--
--  SPARK boundary:
--    The package spec carries SPARK_Mode On.  Classify_Hyperlinks_Support is
--    annotated Global => null.  Refine_With_XTVERSION carries a per-declaration
--    SPARK_Mode => Off aspect because its signature references XTVERSION_Result,
--    which contains Unbounded_String.
--
--  Known-good version database (body-private constants):
--    Emulator name tokens (case-insensitive), minimum versions, and "any" flags
--    for: iTerm2 (3.1.0), kitty (0.19.0), WezTerm (any), VTE (0.50.0),
--    foot (any), Alacritty (0.11.0), mintty (3.4.0), xterm (357),
--    Windows_Terminal (1.4.0), VSCode (1.72.0), Ghostty (any), Konsole (any).
--    See tech spec §7 and FUNC-HYP-009 / FUNC-HYP-010 for the full table.
--
--  This is a single mixed-SPARK package with no .IO child package (ADR-0038).
--  No platform-specific body files are required (FUNC-HYP-017).
--
--  Requirements Coverage:
--    - @relation(FUNC-HYP-001): Hyperlinks_Support enumeration
--    - @relation(FUNC-HYP-002): Hyperlinks_Result record
--    - @relation(FUNC-HYP-003): Hyperlinks_Provenance enumeration
--    - @relation(FUNC-HYP-004): TERM legacy-prefix exclusion constants
--    - @relation(FUNC-HYP-005): Known-good Terminal_Kind list
--    - @relation(FUNC-HYP-005b): Terminal_Kind hard exclusion
--    - @relation(FUNC-HYP-006): Named TERM_PREFIX_* constants
--    - @relation(FUNC-HYP-007): Classify_Hyperlinks_Support signature
--    - @relation(FUNC-HYP-008): No global state in passive function
--    - @relation(FUNC-HYP-009): XTVERSION promotion to Supported
--    - @relation(FUNC-HYP-010): XTVERSION demotion to Unsupported
--    - @relation(FUNC-HYP-011): Refine_With_XTVERSION signature
--    - @relation(FUNC-HYP-012): Complete state-transition table
--    - @relation(FUNC-HYP-016): Package structure — single mixed-SPARK package
--    - @relation(FUNC-HYP-017): No platform-specific body files
--    - @relation(FUNC-HYP-018): SPARK Silver provability of Classify_Hyperlinks_Support

with Termicap.Environment;
with Termicap.Terminal_Id;
with Termicap.XTVERSION;

package Termicap.Hyperlinks
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Hyperlinks_Support Enumeration (FUNC-HYP-001)
   ---------------------------------------------------------------------------

   --  @summary Four-value classification of OSC 8 hyperlink support.
   --  @description
   --    Unsupported      -- The terminal is known not to support OSC 8, or
   --                        sending OSC 8 sequences would render as visible
   --                        garbage.  Callers MUST NOT emit OSC 8.
   --    Likely_Supported -- The terminal is likely to support OSC 8 based on
   --                        passive heuristics (known-good Terminal_Kind or no
   --                        legacy-TERM exclusion fired).  Callers MAY emit
   --                        OSC 8 safely; at worst, the terminal silently ignores
   --                        the sequence.
   --    Supported        -- The terminal is known to support OSC 8 at the
   --                        confirmed minimum version (XTVERSION-gated).
   --                        Callers SHOULD emit OSC 8.
   --    Unknown          -- No evidence either way.  The terminal was not on the
   --                        known-good list and no XTVERSION refinement was
   --                        available.  Callers MAY treat this as Likely_Supported
   --                        for output purposes (see FUNC-HYP-001 note below).
   --
   --  Note: positional ordering (Unsupported < Likely_Supported < Supported <
   --  Unknown) is NOT semantic for Unknown.  Unknown is placed last only to keep
   --  the three confirmed states contiguous.  Callers comparing with >= should
   --  handle Unknown explicitly.
   --  @relation(FUNC-HYP-001): Hyperlinks_Support enumeration
   type Hyperlinks_Support is (Unsupported, Likely_Supported, Supported, Unknown);

   ---------------------------------------------------------------------------
   --  Hyperlinks_Provenance Enumeration (FUNC-HYP-003)
   ---------------------------------------------------------------------------

   --  @summary Seven-value linear provenance chain for Hyperlinks_Result.
   --  @description Records the detection step that last updated Support.
   --    Default            -- Not yet classified; initial / uninitialised state.
   --    Env_Excluded       -- Legacy TERM prefix exclusion (FUNC-HYP-004) or
   --                          Terminal_Kind hard exclusion (FUNC-HYP-005b) fired.
   --    Env_Known_Good     -- Terminal_Kind was on the known-good list
   --                          (FUNC-HYP-005), yielding Likely_Supported.
   --    Env_Unknown        -- Terminal_Kind was not on any list; fallback.
   --    XTVERSION_Confirmed -- XTVERSION lookup found a matching entry and the
   --                           reported version met or exceeded the minimum;
   --                           Support promoted to Supported.
   --    XTVERSION_Rejected  -- XTVERSION lookup found a matching entry but the
   --                           reported version was below the minimum; Support
   --                           demoted to Unsupported (FUNC-HYP-010).
   --    XTVERSION_Unresolved -- XTVERSION result was not Success, or the terminal
   --                            name was not found in the known-good table.
   --  @relation(FUNC-HYP-003): Hyperlinks_Provenance enumeration
   type Hyperlinks_Provenance is
     (Default,
      Env_Excluded,
      Env_Known_Good,
      Env_Unknown,
      XTVERSION_Confirmed,
      XTVERSION_Rejected,
      XTVERSION_Unresolved);

   ---------------------------------------------------------------------------
   --  Hyperlinks_Result Record (FUNC-HYP-002)
   ---------------------------------------------------------------------------

   --  @summary Flat result record aggregating the hyperlink detection outcome.
   --  @description Flat record (ADR-0037): all fields are unconditionally
   --  meaningful for every Support value.  There is no per-variant payload,
   --  so a discriminated record would add overhead without safety benefit.
   --
   --  Fields:
   --    Support                -- Coarse classification (see Hyperlinks_Support).
   --    Provenance             -- Which detection step last set Support.
   --    Terminal_Version_Known -- True when the XTVERSION refinement matched a
   --                              terminal name in the known-good table (even if
   --                              the version was unparseable, or the match led
   --                              to demotion).
   --  @relation(FUNC-HYP-002): Hyperlinks_Result flat record
   type Hyperlinks_Result is record
      Support                : Hyperlinks_Support := Unknown;
      Provenance             : Hyperlinks_Provenance := Default;
      Terminal_Version_Known : Boolean := False;
   end record;

   ---------------------------------------------------------------------------
   --  Default Constant (FUNC-HYP-002)
   ---------------------------------------------------------------------------

   --  @summary Canonical default / uninitialised Hyperlinks_Result value.
   --  @description Used as the initial value for the Hyperlinks field in
   --  Terminal_Capabilities and Full_Terminal_Capabilities, and as the default
   --  argument for Assemble / Assemble_Full.
   --  @relation(FUNC-HYP-002): DEFAULT_HYPERLINKS_RESULT constant
   DEFAULT_HYPERLINKS_RESULT : constant Hyperlinks_Result :=
     (Support => Unknown, Provenance => Default, Terminal_Version_Known => False);

   ---------------------------------------------------------------------------
   --  Named TERM Constants (FUNC-HYP-006)
   ---------------------------------------------------------------------------
   --  Legacy TERM values / prefixes that identify terminals known NOT to support
   --  OSC 8 (or to render it as visible text garbage).  Derived from the tcell
   --  exclusion list and GLOBAL-SYNTHESIS §2.8.

   --  @summary TERM prefix for the VT-family of terminals.
   --  @description Terminals whose TERM starts with "vt" (e.g. "vt100", "vt220",
   --  "vt52") do not support OSC 8.  Prefix match (FUNC-HYP-004, step 1).
   --  @relation(FUNC-HYP-006): TERM_PREFIX_VT constant
   TERM_PREFIX_VT : constant String := "vt";

   --  @summary TERM exact value for ANSI terminals.
   --  @description Terminals with TERM="ansi" are legacy and do not support OSC 8.
   --  @relation(FUNC-HYP-006): TERM_PREFIX_ANSI constant
   TERM_PREFIX_ANSI : constant String := "ansi";

   --  @summary TERM exact value for the Linux virtual console.
   --  @description The Linux VT (TERM="linux") does not support OSC 8.
   --  @relation(FUNC-HYP-006): TERM_LINUX constant
   TERM_LINUX : constant String := "linux";

   --  @summary TERM prefix for Sun terminals.
   --  @description Terminals whose TERM starts with "sun" (e.g. "sun", "sun-color")
   --  do not support OSC 8.  Prefix match.
   --  @relation(FUNC-HYP-006): TERM_PREFIX_SUN constant
   TERM_PREFIX_SUN : constant String := "sun";

   --  @summary TERM exact value for dumb terminals.
   --  @description TERM="dumb" indicates a minimal terminal with no capability
   --  for escape sequences including OSC 8.
   --  @relation(FUNC-HYP-006): TERM_DUMB constant
   TERM_DUMB : constant String := "dumb";

   ---------------------------------------------------------------------------
   --  Passive Classification Function (FUNC-HYP-007, FUNC-HYP-008)
   ---------------------------------------------------------------------------

   --  @summary Classify OSC 8 hyperlink support using passive heuristics only.
   --  @description Pure SPARK Silver function.  Reads the TERM variable from Env
   --  and inspects Identity.Kind.  Applies three steps in normative order:
   --
   --    Step 1 — TERM legacy-prefix exclusion (FUNC-HYP-004):
   --      If TERM starts with "vt" or "sun", equals "ansi", "linux", or "dumb",
   --      return (Unsupported, Env_Excluded, False).
   --
   --    Step 2 — Terminal_Kind hard exclusion (FUNC-HYP-005b):
   --      Apple_Terminal, Dumb, Linux_Console => (Unsupported, Env_Excluded, False).
   --
   --    Step 3 — Terminal_Kind known-good list (FUNC-HYP-005):
   --      Alacritty, Foot, Ghostty, ITerm2, JediTerm, Kitty, Konsole,
   --      Mintty, VSCode, VTE, WarpTerminal, WezTerm, Windows_Terminal, Xterm
   --        => (Likely_Supported, Env_Known_Good, False).
   --      All other kinds (Rxvt, Screen, Tmux, Unknown, …)
   --        => (Unknown, Env_Unknown, False).
   --
   --  Has no global state (FUNC-HYP-008).
   --  SPARK Silver provability target (FUNC-HYP-018): the function is total,
   --  terminating, and Global => null.
   --
   --  @param Env      Immutable environment variable snapshot (read for TERM).
   --  @param Identity Passively identified terminal kind and metadata.
   --  @return Hyperlinks_Result with Support, Provenance, Terminal_Version_Known.
   --  @relation(FUNC-HYP-007): Passive classification function signature
   --  @relation(FUNC-HYP-008): No global state
   --  @relation(FUNC-HYP-018): SPARK Silver provability
   function Classify_Hyperlinks_Support
     (Env : Termicap.Environment.Environment; Identity : Termicap.Terminal_Id.Terminal_Identity)
      return Hyperlinks_Result
   with SPARK_Mode => On, Global => null;

   ---------------------------------------------------------------------------
   --  XTVERSION Refinement Function (FUNC-HYP-011)
   ---------------------------------------------------------------------------

   --  @summary Refine the passive hyperlink classification using the XTVERSION result.
   --  @description Pure value-to-value transformation (no I/O).  Consumes the
   --  already-fetched XTVERSION_Result from Detect_Full Step 9 (ADR-0038).
   --  SPARK_Mode Off because XTVERSION_Result contains Unbounded_String
   --  (FUNC-HYP-011).
   --
   --  State-transition rules (exhaustive, FUNC-HYP-012):
   --    Passive.Support = Unsupported, Provenance = Env_Excluded:
   --      Return Passive unchanged.  "Unsupported is terminal" invariant.
   --    XTV.Status /= Success:
   --      Return (Passive.Support, XTVERSION_Unresolved, Passive.Terminal_Version_Known).
   --    Terminal name found in known-good table, version >= minimum:
   --      Return (Supported, XTVERSION_Confirmed, True).
   --    Terminal name found, version < minimum:
   --      Return (Unsupported, XTVERSION_Rejected, True).
   --    Terminal name found, version unparseable:
   --      Return (Passive.Support, Env_Known_Good, True).
   --    Terminal name found, "any" minimum (treat any parsed version as good):
   --      Return (Supported, XTVERSION_Confirmed, True).
   --    Terminal name not found in table:
   --      Return (Passive.Support, XTVERSION_Unresolved, False).
   --
   --  The outer exception handler `when others => return Passive` guarantees
   --  no exception propagation (defence in depth; the body should not raise
   --  because it does no I/O and Compare is total).
   --
   --  @param Passive The Hyperlinks_Result from Classify_Hyperlinks_Support.
   --  @param XTV     The XTVERSION_Result from Detect_Full Step 9.
   --  @return Refined Hyperlinks_Result.
   --  @relation(FUNC-HYP-009): XTVERSION promotion path
   --  @relation(FUNC-HYP-010): XTVERSION demotion path
   --  @relation(FUNC-HYP-011): Refine_With_XTVERSION signature
   --  @relation(FUNC-HYP-012): Complete state-transition table
   function Refine_With_XTVERSION
     (Passive : Hyperlinks_Result; XTV : Termicap.XTVERSION.XTVERSION_Result) return Hyperlinks_Result
   with SPARK_Mode => Off;

end Termicap.Hyperlinks;
