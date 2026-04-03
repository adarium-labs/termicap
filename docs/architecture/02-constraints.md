# arc42 Section 2: Constraints

## Technical Constraints

| ID | Constraint | Rationale |
|----|-----------|-----------|
| TC-1 | **Ada 2022 with SPARK 2014 subset** | Target language. GNAT Community or GNAT Pro toolchain. |
| TC-2 | **SPARK Silver provability for detection logic** | All pure detection functions (color, Unicode, terminal ID) must be provable at Silver level (absence of runtime errors, correct data flow). Gold level for pure arithmetic (downsampling). |
| TC-3 | **SPARK_Mode => Off for FFI and tasking boundaries** | C FFI bindings (`isatty`, `ioctl`), protected objects with entries, and interrupt handlers are outside the SPARK 2014 subset. These boundaries are explicitly marked. |
| TC-4 | **Alire build system** | `alr build` is the sole build command. Never invoke `gprbuild` directly. Each sub-crate (root, tests, examples) has its own `alire.toml`. |
| TC-5 | **Dependencies: sparklib only** | The library depends on `sparklib` (SPARK formal containers). No other third-party Ada crates. |
| TC-6 | **Cross-platform POSIX + future Windows** | Primary target: Linux, macOS, BSDs. Windows support via variant bodies and C wrappers is a planned extension. |
| TC-7 | **No automatic command-line parsing** | The library never reads `Ada.Command_Line`. Override installation is the caller's responsibility. |
| TC-8 | **No exceptions in library code** | Error conditions are represented via Result types or safe defaults. Exceptions are permitted only in test code. |

## Organizational Constraints

| ID | Constraint | Rationale |
|----|-----------|-----------|
| OC-1 | **Apache-2.0 WITH LLVM-exception license** | Permissive license allowing static linking without license propagation. |
| OC-2 | **Conventional Commits** | All commit messages follow `type(scope): description` format. |
| OC-3 | **Ada coding standard** | `.claude/ada-style-guide.md` is the authoritative reference for naming, formatting, and documentation conventions. |
| OC-4 | **StrictDoc requirements** | Requirements live in `docs/requirements/*.sdoc` and must be traced to code and tests. |
| OC-5 | **>95% code coverage target** | Test suite must cover nearly all branches in detection logic. |

## Conventions

| Convention | Rule |
|-----------|------|
| File naming | Lowercase with dashes matching package hierarchy (`termicap-color.ads`) |
| Indentation | 3 spaces, no tabs, 120-character line width |
| Constants | `ALL_CAPS_WITH_UNDERSCORES` |
| Package hierarchy | Flat children of `Termicap` (e.g., `Termicap.Color`, `Termicap.TTY`) |
| SPARK boundary | Spec is `SPARK_Mode => On` where possible; body is `SPARK_Mode => Off` only for FFI/tasking |
