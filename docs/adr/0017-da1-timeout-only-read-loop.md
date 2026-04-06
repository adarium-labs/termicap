# DA1 Query Uses Timeout-Only Read Loop (No Sentinel)

* Status: accepted
* Deciders: Termicap contributors
* Date: 2026-04-06

## Context and Problem Statement

The Termicap library uses a sentinel-bounded query pattern for all active terminal probes: the real query is sent followed by a DA1 request (CSI c), and the read loop exits when the DA1 response (ESC [ ? ... c) is detected. This pattern works because the DA1 response is an unambiguous boundary marker that all known terminals respond to.

For querying DA1 itself (FUNC-DA1-008), the DA1 response IS the data being sought. How should Query_DA1 accumulate the response without the sentinel pattern?

## Decision Drivers

* DA1 IS the sentinel used everywhere else -- sending a second CSI c after the first would produce two overlapping DA1 responses in the accumulation buffer, making boundary detection ambiguous.
* All known terminals respond to CSI c, so the response is virtually guaranteed (except for timeouts in non-interactive contexts).
* The existing Contains_DA1_Response function (FUNC-OSC-006) already exists and can detect a complete DA1 response in an accumulation buffer.
* Consistency with reference implementations: notcurses and tcell both use wall-clock timeouts with response pattern matching for DA1.

## Considered Options

* **Option A: Timeout-only read loop with Contains_DA1_Response as exit condition** -- Write DA1_QUERY, then accumulate bytes in a loop, exiting when Contains_DA1_Response detects a complete response or the timeout expires.
* **Option B: Use a different sentinel (e.g., DA2 or DSR)** -- Send DA1 followed by a different escape sequence as a boundary marker, then wait for the second response.
* **Option C: Use Sentinel_Query with the DA1 query itself** -- Send DA1_QUERY as both the query and the sentinel, and let Sentinel_Query handle it.

## Decision Outcome

Chosen option: "Option A: Timeout-only read loop with Contains_DA1_Response as exit condition", because it is the simplest correct approach, avoids introducing a new sentinel dependency, and is consistent with how reference implementations handle DA1 queries.

### Positive Consequences

* No new sentinel dependency -- Query_DA1 does not need to know about DA2, DSR, or any other escape sequence.
* Reuses the existing Contains_DA1_Response function from Termicap.OSC.Parsing.
* Consistent with notcurses and tcell reference implementations.
* The read loop terminates as soon as a complete DA1 response is detected, so typical latency is identical to the sentinel approach (response + parsing overhead).

### Negative Consequences

* If the terminal does not respond to DA1 at all, Query_DA1 must wait for the full timeout period before returning. This is acceptable because non-responding terminals are rare (DA1 is the most universally supported query) and the 100 ms default timeout is short.
* No natural "end of response" marker means that if a terminal sends extra bytes after the DA1 response (e.g., echoed input), those bytes remain in the buffer. This is mitigated by the Drain_Input call at session open and by the fact that raw mode suppresses echo.

## Pros and Cons of the Options

### Option A: Timeout-only read loop

* Good, because it is simple and correct
* Good, because it reuses existing Contains_DA1_Response
* Good, because it matches reference implementation patterns
* Bad, because full timeout wait when terminal does not respond

### Option B: Different sentinel (DA2 or DSR)

* Good, because it restores sentinel-bounded termination
* Bad, because it introduces a dependency on a second escape sequence that not all terminals support
* Bad, because the DA2 response format (CSI > Pp ; Pv ; Pc c) also ends with 'c', creating ambiguity with DA1
* Bad, because it adds complexity without clear benefit

### Option C: Sentinel_Query with DA1 as both query and sentinel

* Good, because it reuses the existing Sentinel_Query infrastructure
* Bad, because Sentinel_Query sends the sentinel AFTER the query, meaning two CSI c sequences are written; the terminal may respond to both, producing two DA1 responses that confuse boundary detection
* Bad, because Sentinel_Query's DA1_Response_Start function would find the first DA1 response and treat everything before it as "pre-sentinel data" -- which would be empty, discarding the actual DA1 response

## Links

* Tech spec: `docs/tech-specs/da1-response-parsing.md`
* Requirements: FUNC-DA1-008 (Query_DA1 I/O Procedure)
* Related: ADR-0015 (Probe Session Limited Controlled)
