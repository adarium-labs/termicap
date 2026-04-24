# GPM Detection Heuristic: TERM=linux + /dev/gpmctl Existence Check

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-23

## Context and Problem Statement

The Linux text console (virtual terminal, where `TERM=linux`) does not implement DEC private mode queries. Sending `CSI ? 1000 $ p` to a Linux console produces no response; the entire MOUSE probe times out (1 s wall clock) and returns `Best_Encoding = None`. Mouse support on the Linux console is provided exclusively by the **GPM** (General Purpose Mouse) daemon, which exposes a Unix domain socket at `/dev/gpmctl` and emits mouse events to clients that connect via libgpm's `Gpm_Open()` / `Gpm_Read()` API.

Termicap's MOUSE feature needs to detect "Linux console with GPM available" so that:

1. Callers know to use a GPM-based mouse path instead of DECSET escape sequences.
2. The mouse probe does not waste 1 s waiting for DECRPM responses that will never arrive.

How should Termicap detect GPM availability?

## Decision Drivers

* **Zero added latency.** The check runs at every cold-start `Detect_Mouse_Protocols` call, before the DECRPM probe. Any added latency hurts every Linux desktop terminal user (where the check fires negatively because `TERM /= "linux"` short-circuits it before any I/O).
* **No new dependencies.** Termicap deliberately does not link `libgpm` (it would force a runtime dependency on a daemon that is uncommon on modern Linux desktops, and require an Alire crate or system-package for `libgpm-dev`).
* **Accurate-enough detection.** False positives (claim GPM, but daemon dead) lead to caller-side errors when they try to connect — recoverable. False negatives (claim no GPM, but daemon alive) lead to silent feature loss — undetectable by the caller.
* **No-exception contract** (FUNC-MSE-014). The check must not raise an exception on any code path, including unusual `/dev` configurations (symlink loops, permission denied).
* **SPARK boundary.** The check happens inside `Termicap.Mouse.IO` (SPARK_Mode Off). It must not violate SPARK constraints in callers. Using `Ada.Directories.Exists` (a standard library function with no SPARK_Mode On wrapper but well-understood semantics) is acceptable.
* **Cross-language reference.** notcurses (`src/lib/gpm.c`) detects GPM by attempting `Gpm_Open()`; on failure it skips the GPM path. tcell and crossterm do not detect GPM at all. blessed does not handle GPM. There is no established cross-language idiom beyond "open-then-fall-back".
* **Future upgrade path.** If a future Termicap version needs more accuracy, it should be able to upgrade the heuristic without breaking the public API.

## Considered Options

* **Option A**: **Existence check** — `TERM = "linux"` AND `Ada.Directories.Exists ("/dev/gpmctl") = True`. No connect, no daemon round-trip.
* **Option B**: **Connect probe** — `TERM = "linux"` AND a successful `connect(2)` on a `socket(AF_UNIX, SOCK_STREAM)` to `/dev/gpmctl`. Closes the socket immediately.
* **Option C**: **`Gpm_Open()` probe** — link `libgpm` at runtime via `dlopen("libgpm.so")` and call `Gpm_Open()`. On success, immediately call `Gpm_Close()`.
* **Option D**: **No GPM detection** — always fall through to the DECRPM probe; let the 1 s timeout drain on Linux console; document the latency.
* **Option E**: **Probe DECRPM with a short timeout, infer GPM on timeout** — send the DECRPM probe with a 200 ms timeout instead of 1 s; if it times out and `TERM = "linux"`, set `GPM_Available = True`.

## Decision Outcome

Chosen option: **Option A** (existence check), because it (1) adds zero round-trip latency on the common (Linux desktop terminal) and uncommon (Linux console + GPM) cases alike, (2) requires no new system calls beyond a stat-equivalent, (3) requires no new external dependency on `libgpm`, and (4) provides "good enough" accuracy: a properly-configured Linux console running GPM has `/dev/gpmctl` present; one without GPM does not.

The implementation is `Is_Linux_Console_With_GPM` in the POSIX body of `Termicap.Mouse.IO` (MOUSE tech spec §G.2):

```ada
function Is_Linux_Console_With_GPM return Boolean is
   Env : Termicap.Environment.Environment;
begin
   Termicap.Environment.Capture.Capture_Current (Env);
   if not Termicap.Environment.Equal_Case_Insensitive
            (Termicap.Environment.Value (Env, "TERM"), "linux")
   then
      return False;
   end if;
   declare
      Exists : Boolean := False;
   begin
      Exists := Ada.Directories.Exists ("/dev/gpmctl");
      return Exists;
   exception
      when others =>
         return False;  --  symlink loops or unusual /dev: treat as absent
   end;
exception
   when others =>
      return False;
end;
```

Two layers of `exception when others => return False` cover both the `Ada.Directories.Exists` call and the surrounding environment-capture path, satisfying FUNC-MSE-014 unconditionally.

The function is **POSIX-body-only** (compile-time absent in the Windows body). The Windows body's `Run_Cascade` skips guard 2 entirely.

### Positive Consequences

* **Zero round-trip latency** on the common case (`TERM /= "linux"` short-circuits; one env-var lookup + one stat-equivalent on the rare Linux-console case).
* **No new dependencies.** No `libgpm`, no `dlopen`, no Alire crate update. The MOUSE feature ships with the same dependency footprint as KKB.
* **Predictable behaviour.** The check is a pure function of `(TERM environment value, /dev/gpmctl filesystem state)`. Easy to mock in tests (set `TERM=linux`, create `/dev/gpmctl` symlink to `/dev/null`).
* **Honest reporting.** When the heuristic fires, we report `GPM_Available = True`; we **do not** report any DECRPM-specific information, because none has been collected. The caller knows to use the GPM API path.
* **Future-upgradable.** A future version can replace `Ada.Directories.Exists` with a `connect(2)` probe (option B) without changing the public API; the function signature stays `function Is_Linux_Console_With_GPM return Boolean`.

### Negative Consequences

* **False positive risk.** `/dev/gpmctl` may exist but the daemon may be dead (e.g., `gpm` was started, created the socket, then crashed). The caller will fail when it tries to `Gpm_Open()`. Cost: callers must handle GPM-connection failure gracefully (which they would anyway — daemons can die mid-session). Documented in the User Guide.
* **No detection of GPM on non-`TERM=linux` configurations.** Some users run GPM under `TERM=screen-256color` (when running screen on a Linux console) or `TERM=tmux-256color`. The heuristic correctly does not fire — the multiplexer is the active terminal, not GPM — but a power user expecting "GPM detection on Linux" may be surprised. Mitigation: documented in the User Guide.
* **Does not detect non-Linux GPM-like daemons.** BSD `moused` and similar daemons are not detected. Out of scope (FUNC-MSE-011 is explicit about Linux).
* **`Ada.Directories.Exists` is not SPARK-On.** The check lives in `Termicap.Mouse.IO` body (SPARK_Mode Off), so this is not a barrier.
* **One additional system call** in the cold-start path on Linux. `stat()` is sub-microsecond; cost is negligible.

## Pros and Cons of the Options

### Option A: Existence check (chosen)

`TERM = "linux"` AND `Ada.Directories.Exists ("/dev/gpmctl")`.

* Good, because zero round-trip latency.
* Good, because no new dependency on `libgpm`.
* Good, because pure-function semantics; easy to mock.
* Good, because future-upgradable to option B without API change.
* Bad, because false positives possible if daemon died after creating the socket.
* Bad, because does not catch GPM running under non-`TERM=linux` setups.

### Option B: Connect probe

`socket(AF_UNIX, SOCK_STREAM)` + `connect(2)` to `/dev/gpmctl`; close on success or failure.

* Good, because confirms daemon is responsive.
* Good, because eliminates the "socket exists but daemon dead" false positive.
* Bad, because adds a new C wrapper (`Termicap.Mouse.IO` would need a `connect_to_gpm()` helper) — Tier 4 scope creep.
* Bad, because adds 100s-of-microseconds wall clock for the syscalls (still far below the 1 s DECRPM timeout, but non-zero).
* Bad, because requires careful EAGAIN/EINTR handling; raises the test surface.
* Bad, because a `connect(2)` to a Unix socket that is in a `LISTEN` state but has no `accept(2)` waiting may block; need non-blocking socket setup (more code).

### Option C: `Gpm_Open()` probe

`dlopen("libgpm.so")`, `dlsym("Gpm_Open")`, call it, then `Gpm_Close()`.

* Good, because uses the canonical client API; behaves exactly like a real GPM client.
* Good, because confirms full library compatibility.
* Bad, because adds a runtime `dlopen` cost (~ms on first call, less on subsequent).
* Bad, because requires `libgpm.so` to be installed; absent on most modern Linux desktops.
* Bad, because if `libgpm` is absent, the heuristic returns False — same outcome as option A but with more code.
* Bad, because exposes Termicap to libgpm version skew (the GPM ABI has been stable, but committing to it is a long-tail risk).

### Option D: No GPM detection

Always fall through to the DECRPM probe.

* Good, because simplest possible code (delete the heuristic).
* Bad, because every Linux-console user pays 1 s startup latency on every cold-start `Detect_Mouse_Protocols` call.
* Bad, because the result `Best_Encoding = None` masks the **real** capability (mouse is available, just not via DECRPM). Callers cannot distinguish "no mouse" from "mouse via GPM".
* Bad, because violates FUNC-MSE-011 (which mandates the heuristic).

### Option E: Infer GPM from short DECRPM timeout

Probe DECRPM with a 200 ms timeout; if `TERM = "linux"` and the probe times out, set `GPM_Available = True`.

* Good, because uses the DECRPM probe machinery as a Linux-console detector.
* Bad, because conflates two semantics: "DECRPM timed out" can also mean "slow SSH link" or "non-responsive multiplexer".
* Bad, because a 200 ms timeout is too short for high-latency real terminals; reducing it sacrifices accuracy on legitimate probes.
* Bad, because the heuristic rests on the timeout — any future change to the timeout cascade breaks GPM detection.
* Bad, because still incurs 200 ms latency on every Linux desktop user (whose probe will succeed before timeout, but still pays the budget).

## Links

* Related ADR: [ADR-0022](0022-batched-single-sentinel-decrpm-mouse-probe.md) — The DECRPM probe that the GPM heuristic short-circuits
* Related ADR: [ADR-0026](0026-defer-mouse-capability-integration.md) — Defer integration into `Terminal_Capabilities`
* Tech Spec: [`docs/tech-specs/mouse-protocol.md`](../tech-specs/mouse-protocol.md) §G.2, §I.3 — GPM heuristic implementation and platform behaviour
* Requirements: FUNC-MSE-009 (guard 2), FUNC-MSE-011 (heuristic specification)
* Reference framework: `reference-frameworks/notcurses/src/lib/gpm.c` — `Gpm_Open()`-based detection (option C reference)
* Reference framework: `reference-frameworks/notcurses/src/info/main.c` line 471 — `tinfo_debug_cap (n, "gpm", ti->gpmfd >= 0)` GPM availability flag
* Manual page: `gpm(8)` — *"the GPM daemon listens on `/dev/gpmctl`, a SOCK_STREAM Unix domain socket"* (primary source for the existence-check approach)
