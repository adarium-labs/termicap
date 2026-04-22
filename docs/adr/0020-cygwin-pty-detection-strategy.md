# Two-path API strategy for Cygwin/MSYS2 pipe-name retrieval

* Status: Accepted
* Deciders: Termicap Contributors
* Date: 2026-04-22

## Context and Problem Statement

Cygwin and MSYS2 pseudo-terminals on Windows are represented as pairs of named pipes rather than kernel console objects. Consequently `GetConsoleMode` — the standard Win32 TTY predicate used in FUNC-WIN-003 — returns `FALSE` for every handle that points to a Cygwin or MSYS2 shell's stdin/stdout/stderr. The only reliable way to distinguish a Cygwin/MSYS2 PTY handle from an unrelated named pipe (such as a file-share endpoint or an application-defined IPC channel) is to retrieve the **kernel object name** of the pipe and match it against the Cygwin/MSYS2 naming grammar (`\cygwin-XXXX-ptyN-{from,to}-master` or the `\Device\NamedPipe\` long form).

Two Win32 APIs can retrieve a pipe handle's object name:

1. `kernel32!GetFileInformationByHandleEx` with the `FileNameInfo` information class (value `2`) — documented in the Windows SDK, introduced in **Windows Vista**.
2. `ntdll!NtQueryObject` with the `ObjectNameInformation` class (value `1`) — undocumented but stable since **Windows NT 3.5**.

How should Termicap invoke these APIs? Commit to a single entry point, or implement both?

## Decision Drivers

* Termicap targets **Windows 10 Build 10586+** (FUNC-WIN-001). All officially supported targets ship `GetFileInformationByHandleEx`.
* Termicap runs in compatibility environments — Wine, ReactOS, Windows-on-ARM emulators — where either API may be missing or stubbed.
* `GetFileInformationByHandleEx` is **not** exported by the win32ada Alire crate (verified against version `26.0.0`), so using it requires a manual `LoadLibraryA` + `GetProcAddress` probe regardless.
* `NtQueryObject` is also not in win32ada; the project already loads `ntdll.dll` dynamically to call `RtlGetNtVersionNumbers` (FUNC-WIN-006), so the infrastructure is already present.
* The no-exception contract (FUNC-CYG-016) requires graceful degradation: a missing API must downgrade `Is_Cygwin_Terminal` to `False`, never raise or crash.
* Cross-language consensus: **go-isatty**, the most widely deployed Cygwin detection library, implements **both** paths with availability-based dispatch.
* Each Cygwin/MSYS2 launch fires three `Is_TTY` calls (stdin, stdout, stderr). The cost of `LoadLibrary`/`GetProcAddress` must not be incurred per call.

## Considered Options

* **Option A**: **Two-path dispatch** — probe `GetFileInformationByHandleEx` once at elaboration; use it when present, fall back to `NtQueryObject` when absent.
* **Option B**: **Single path (primary only)** — always use `GetFileInformationByHandleEx`; return `False` if the probe fails.
* **Option C**: **Single path (ntdll only)** — always use `NtQueryObject`; skip `GetFileInformationByHandleEx` entirely.
* **Option D**: **Runtime failure fallback** — call `GetFileInformationByHandleEx` first on every invocation; if it returns `FALSE`, call `NtQueryObject` as a second attempt.

## Decision Outcome

Chosen option: **Option A** (two-path availability dispatch), because it matches the established cross-language idiom (go-isatty, supports-color on Node), incurs the `LoadLibraryA`/`GetProcAddress` cost exactly once per process, and gracefully degrades when either API is missing.

The probe runs at package body elaboration time (`Termicap.Win32_Cygwin`'s body-level `begin ... end;` block). Package-level variables `Has_Get_File_Info : Boolean` and `Get_File_Info_Fn : Get_File_Info_Fn_Ptr` are populated once and read on every `Is_Cygwin_Terminal` call. `NtQueryObject` is not probed in advance — it is simply called when the primary path is unavailable, and its own NTSTATUS return value determines success.

Failure of `GetFileInformationByHandleEx` on a particular handle (**not** its absence at the library level) does **not** trigger a fallback to `NtQueryObject`. This matches go-isatty's design: the two paths are **availability alternatives**, not runtime retries. A handle that the primary API rejects is almost always one on which the fallback would also fail (permissions, revoked handle, etc.); burning two FFI calls on every miss would be wasteful with no correctness benefit.

### Positive Consequences

* Correct behaviour on all Windows versions Termicap targets, plus older systems and compatibility environments.
* `LoadLibraryA` / `GetProcAddress` cost is paid **once** at elaboration, not per `Is_TTY` call.
* The decision mirrors go-isatty, enabling direct port of its 14-vector acceptance test suite without behavioural drift.
* The fallback path reuses `Termicap.Win32_Ntdll`'s existing `LoadLibraryA` infrastructure — no new custom FFI infrastructure is introduced.
* Degraded mode (both APIs missing) returns `False` silently, preserving FUNC-CYG-016's no-exception contract.

### Negative Consequences

* Two code paths must be maintained and tested — roughly 30 lines of Ada each.
* `NtQueryObject` is undocumented; a major Windows revision could in principle change its behaviour or remove it. Mitigated by the fact that it has been stable for 30+ years and is relied upon by large portions of the Windows ecosystem.
* Integration testing the fallback path requires either a pre-Vista Windows (unavailable in standard CI) or manual proc-pointer nulling. The 14 vectors in FUNC-CYG-013 verify only the pipe-name **predicate**, not the retrieval pipeline; retrieval is covered by manual testing under `git-bash` and `MSYS2 bash`.

## Pros and Cons of the Options

### Option A: Two-path dispatch (chosen)

At elaboration, probe `kernel32!GetFileInformationByHandleEx`. If present, it is the primary path; if absent, fall back to `ntdll!NtQueryObject`.

* Good, because matches go-isatty's industry-standard pattern — the same code shape is battle-tested in thousands of Go CLIs.
* Good, because the elaboration-time probe avoids repeated `LoadLibraryA` overhead.
* Good, because graceful degradation is automatic: both probes failing yields `Is_Cygwin_Terminal = False`, preserving the no-exception contract.
* Good, because the fallback path reuses `Termicap.Win32_Ntdll`'s already-tested dynamic-load infrastructure.
* Bad, because two implementations double the surface area and testing burden for the pipe-name retrieval step.
* Bad, because on pre-Vista Windows (unsupported) the fallback path's `UNICODE_STRING` interpretation is harder to audit than the documented `FILE_NAME_INFO` layout.

### Option B: Single path (`GetFileInformationByHandleEx` only)

Always call `GetFileInformationByHandleEx`; return `False` if the probe fails.

* Good, because fewer code paths to maintain.
* Good, because the `FILE_NAME_INFO` layout is fully documented in the Windows SDK.
* Bad, because Wine and ReactOS may not export this function or may stub it, downgrading Termicap's Cygwin detection in those environments.
* Bad, because `Termicap.Win32_Ntdll` is already used for `RtlGetNtVersionNumbers` — the infrastructure for an ntdll fallback is essentially free.
* Bad, because this diverges from the well-understood go-isatty pattern, making future maintenance and cross-reference harder.

### Option C: Single path (`NtQueryObject` only)

Always call `NtQueryObject` as in go-isatty's Windows XP path.

* Good, because a single implementation — simpler code.
* Good, because the `LoadLibraryA` infrastructure is already shared with `Get_Build_Number`, so marginal cost is minimal.
* Bad, because `NtQueryObject` is undocumented; relying on it exclusively forfeits the benefits of the documented SDK API on all modern Windows targets.
* Bad, because the `UNICODE_STRING` layout is more error-prone to audit than `FILE_NAME_INFO` (the `Buffer` field is an absolute pointer into the same allocation, requiring explicit `System.Address` arithmetic).
* Bad, because forgoes alignment with go-isatty's explicit preference for the SDK API on Vista+.

### Option D: Runtime failure fallback

Call `GetFileInformationByHandleEx` first on every invocation; on `FALSE`, retry with `NtQueryObject`.

* Good, because gives the best chance of retrieving a name from any valid handle.
* Bad, because doubles the expected FFI cost on non-Cygwin handles — which is the **majority** case under redirected I/O (files, anonymous pipes). Every build's CI logs, for example, would pay for two failed name queries per stream.
* Bad, because diverges from go-isatty's documented design; no reference framework uses this pattern.
* Bad, because a handle that `GetFileInformationByHandleEx` rejects is nearly always rejected by `NtQueryObject` as well, so the added cost buys essentially zero correctness.
* Bad, because retrying after a real failure (as opposed to an absence at the library level) risks masking permission or lifetime bugs that would otherwise surface as `False`.

## Links

* Related ADR: [ADR-0019](0019-win32ada-as-ffi-layer.md) — win32ada as primary FFI (explains why `GetFileInformationByHandleEx` needs a custom dynamic load)
* Related ADR: [ADR-0018](0018-platform-dispatch-via-source-dirs.md) — platform dispatch (how the Windows body is selected)
* Tech Spec: [CYGWIN Cygwin/MSYS2 PTY detection](../tech-specs/cygwin-pty.md)
* Requirements: FUNC-CYG-001, FUNC-CYG-002, FUNC-CYG-003, FUNC-CYG-004, FUNC-CYG-014
* Reference implementation: `reference-frameworks/go-isatty/isatty_windows.go` — lines 20–34 (probe), 100–125 (dispatch)
* Cross-language analysis: `reference-frameworks/analysis/go-isatty-analysis.md` — sections "Cygwin/MSYS2 PTY Detection" and "Undocumented NT API Fallback"
* Microsoft docs: [`GetFileInformationByHandleEx`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfileinformationbyhandleex) (primary API)
* Informal docs (ntdll): [NtQueryObject on Stack Overflow](https://stackoverflow.com/a/18792477) — the canonical reference cited by go-isatty's comments
