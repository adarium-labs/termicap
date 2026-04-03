# arc42 Section 3: System Context

## Business Context

Termicap is a lightweight Ada/SPARK library for terminal capability detection. It answers
questions such as "Does this terminal support color?", "How many columns wide is it?", and
"Is stdout connected to a TTY?" so that CLI applications can adapt their output accordingly.

### External Actors

| Actor | Interaction |
|-------|-------------|
| **CLI application** | Calls Termicap's detection API to query terminal capabilities. Passes an environment snapshot and receives pure data (enums, records, Booleans). |
| **Operating system** | Provides environment variables, `isatty()`, `ioctl(TIOCGWINSZ)`, and signal delivery (`SIGWINCH`). Accessed only through thin Ada FFI or C wrapper boundaries. |
| **Terminal emulator** | The runtime environment that determines actual capabilities. Termicap never communicates with it directly in its current feature set (passive detection only). |
| **Alire package manager** | Builds, resolves dependencies (`sparklib`), and distributes the library crate. |

### Scope

Termicap is a **detection-only** library. It does not emit escape sequences, render styled text,
or provide a TUI framework. Applications consume detected capabilities to make their own output
decisions.

## Technical Context

```
  +-----------------+       Environment snapshot        +-------------------+
  | CLI Application |  --------------------------------> |     Termicap      |
  |                 |  <-- Color_Level, Boolean, etc. -- | (Ada/SPARK lib)   |
  +-----------------+                                    +-------------------+
                                                                |
                                                          FFI boundary
                                                                |
                                                         +------v-------+
                                                         |   POSIX / OS |
                                                         |  isatty()    |
                                                         |  ioctl()     |
                                                         |  sigaction() |
                                                         +--------------+
```

### Key Technical Interfaces

| Interface | Direction | Protocol |
|-----------|-----------|----------|
| `Termicap.Environment.Capture` | Termicap -> OS | `Ada.Environment_Variables.Iterate` |
| `Termicap.TTY.Is_TTY` | Termicap -> OS | `pragma Import (C, ..., "isatty")` |
| `Termicap.Dimensions` | Termicap -> OS | C wrapper around `ioctl(TIOCGWINSZ)` |
| `Termicap.Sigwinch` | OS -> Termicap | `sigaction(SIGWINCH, ...)` via C wrapper |
| Detection functions | Application -> Termicap | Pure Ada function calls, `Global => null` |
