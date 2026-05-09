# Termicap

Lightweight, cross-platform terminal capability detection for Ada/SPARK.

Termicap answers the questions a CLI or TUI application has to ask before it emits a single byte of output:

- Is stdin / stdout / stderr a TTY?
- How many colors does the terminal support — none, 16, 256, or 24-bit?
- How wide and how tall is the window, right now?
- Does the locale and terminal emulator render Unicode?
- Is this iTerm, kitty, WezTerm, Windows Terminal, ConPTY, tmux, screen, …?
- Does it support hyperlinks (OSC 8), Sixel / Kitty graphics, OSC 52 clipboard, the Kitty / XTerm keyboard protocol, SGR-pixel mouse?
- And — most importantly — has the user said `NO_COLOR`, `FORCE_COLOR`, `--color=never`, or `--color=always`?

Termicap returns plain Ada records and enumerations. It does **not** emit escape sequences, render styled text, or provide a TUI framework. Pair it with whatever output layer you like.

## Highlights

- **SPARK-provable detection.** Pure detection logic is *written* to target SPARK Silver (some Gold); FFI and tasking are isolated behind clearly marked `SPARK_Mode => Off` boundaries. See `docs/architecture/`. **Caveat:** the codebase is not yet verified end-to-end with `gnatprove` — running the prover and discharging any remaining VCs is planned future work.
- **Cross-platform.** Linux, macOS, BSD, and Windows (Win32 console + ConPTY + Cygwin / MSYS2 PTY detection via named-pipe inspection).
- **Standards-aware.** Implements the [no-color.org] convention, the [force-color.org] convention, BSD `CLICOLOR` / `CLICOLOR_FORCE`, an 11-step color cascade synthesised from `supports-color`, `termenv`, and `rich`.
- **Two performance tiers.** A fast base snapshot (`Get` / `Detect`, sub-50 ms worst case) and a full snapshot with active probes (`Get_Full` / `Detect_Full`, ~6 s worst case, sub-50 ms typical on a local PTY).
- **Cached and fresh APIs.** `Get` is thread-safe, lazily cached per stream; `Detect` always re-runs every sub-detector — useful after `SIGWINCH`, after an override change, or in long-running processes.
- **Application-level override.** A process-wide `Override_Mode` plus a scoped `Scoped_Override` controlled type lets you wire `--color=auto | never | always | 256 | truecolor` straight into the detection engine.
- **No exceptions in library code.** Errors are represented as `Result` variants or safe defaults.
- **Minimal dependencies.** [`sparklib`](https://github.com/AdaCore/sparklib) for SPARK formal containers; [`win32ada`](https://github.com/AdaCore/win32ada) on Windows only.

[no-color.org]: https://no-color.org
[force-color.org]: https://force-color.org

---

## What it detects

| Capability             | Type                                          | Notes                                                       |
| ---------------------- | --------------------------------------------- | ----------------------------------------------------------- |
| TTY                    | `Boolean` per stream                          | stdin / stdout / stderr                                     |
| Color level            | `None / Basic_16 / Extended_256 / True_Color` | 11-step cascade, NO_COLOR / FORCE_COLOR / CLICOLOR aware    |
| Terminal size          | `Columns x Rows`                              | `ioctl(TIOCGWINSZ)` on POSIX, `GetConsoleScreenBufferInfo` on Windows |
| `SIGWINCH` resize      | self-pipe + protected object                  | POSIX only; Windows path is a no-op stub                    |
| Unicode level          | `None / Basic / Extended`                     | locale + CI + terminal heuristics                           |
| Terminal identity      | enum + program name + multiplexer flag        | iTerm, kitty, WezTerm, Windows Terminal, tmux, screen, …    |
| Background / foreground color | OSC 10 / 11 query, `COLORFGBG` fallback | RGB result with hex normalisation                           |
| Dark / light theme     | `Theme_Kind` (Light / Dark / Unknown)         | luminance-based classification                              |
| DA1 device attributes  | VT level + capability flags                   | DEC primary device attributes                               |
| DECRPM mode reports    | `Mode_Status` per mode                        | batched single-sentinel probe                               |
| XTVERSION              | name + version string                         | active probe; informs Sixel and hyperlinks refinement       |
| Hyperlinks (OSC 8)     | passive support + provenance, optionally refined by XTVERSION |                                            |
| Keyboard protocol      | `Kitty / XTerm_CSI / Legacy / Win32`          | platform-dispatched on Windows                              |
| Mouse encoding         | `SGR_Pixels / SGR / URXVT / X10`              | DECRPM-driven cascade                                       |
| Graphics               | Sixel + Kitty graphics flags                  | uses DA1 (`Ps=4`) and XTVERSION name tokens                 |
| OSC 52 clipboard       | `Read / Write / Read_Write / None`            |                                                             |
| `wcwidth` / cell width | Unicode 3 / 13 / 16 tables, binary search     | SPARK Gold, no FFI in the table layer                       |
| Color downsampling     | TrueColor / 256-color downsampling            | SPARK Gold, pure arithmetic                                 |
| Terminfo               | header + boolean / numeric / string lookup    | bounded, pure parser                                        |
| Override               | `Auto / Force_None / Force_Basic / Force_256 / Force_True_Color` | `Scoped_Override` controlled type      |

See [`docs/architecture/03-building-blocks.md`](docs/architecture/03-building-blocks.md) for the full package map and SPARK boundary diagram, and the per-feature reference docs in [`docs/guide/reference/`](docs/guide/reference/).

---

## Installation

### Alire

```toml
[[depends-on]]
termicap = "~1.0.0"
```

Then `alr update && alr build`.

### From source

```bash
git clone <repo-url> termicap
cd termicap
alr build
```

The library is built with `alr build`. Do not invoke `gprbuild` directly — each sub-crate (root, `tests/`, `examples/`) has its own `alire.toml`.

---

## Quick start

The most common pattern: ask for a cached snapshot for stdout.

```ada
with Ada.Text_IO;
with Termicap.Capabilities;
with Termicap.Color;

procedure Hello is
   Caps : constant Termicap.Capabilities.Terminal_Capabilities :=
     Termicap.Capabilities.Get;
begin
   if Caps.TTY_Stdout
     and then Caps.Color >= Termicap.Color.Extended_256
   then
      Ada.Text_IO.Put_Line (ASCII.ESC & "[38;5;208mHello, 256-color world"
                            & ASCII.ESC & "[0m");
   else
      Ada.Text_IO.Put_Line ("Hello, monochrome world");
   end if;
end Hello;
```

### Wiring `--color`

```ada
with Termicap.Override;

--  Parse your CLI flag, then:
case User_Choice is
   when Always   => Termicap.Override.Set_Override (Termicap.Override.Force_True_Color);
   when Never    => Termicap.Override.Set_Override (Termicap.Override.Force_None);
   when Auto     => null;  --  default
end case;

--  All subsequent Detect / Get calls honour the override.
```

Or use the scoped form for a single block of work:

```ada
declare
   Guard : Termicap.Override.Scoped_Override
             (Mode => Termicap.Override.Force_True_Color);
begin
   --  override active here
   ...
end;  --  previous mode automatically restored
```

### Full snapshot (TUI use case)

```ada
with Termicap.Capabilities;
with Termicap.Graphics;
with Termicap.Keyboard;

declare
   use type Termicap.Keyboard.Keyboard_Protocol;
   Caps : constant Termicap.Capabilities.Full_Terminal_Capabilities :=
     Termicap.Capabilities.Get_Full;
begin
   if Caps.Keyboard.Protocol = Termicap.Keyboard.Kitty then
      Enable_Kitty_Keyboard;
   end if;

   if Caps.Graphics.Sixel_Supported then
      Render_Sixel_Image (...);
   end if;
end;
```

`Get_Full` adds XTVERSION, keyboard, mouse, graphics, and OSC 52 clipboard detection at the cost of a higher first-call latency (~6 s worst case, well under 500 ms on a local PTY). Subsequent calls are cache hits.

### Pair detection with `Termicap.Downsampling`

Detection alone tells you what the terminal supports; `Termicap.Downsampling` is the companion package that maps any color you want to emit down to that level — TrueColor → 256-color → ANSI 16 → strip to none — with SPARK Gold idempotency and monotonicity contracts. One pair of overloads dispatches on the source type (`RGB` or `Color_Index_256`) and the result is a discriminated `Downsampled_Color` you can `case`-match to pick the right escape sequence (or skip it entirely).

```ada
with Termicap.Capabilities;
with Termicap.Color;
with Termicap.Downsampling;

-- ...

declare
   Caps   : constant Termicap.Capabilities.Terminal_Capabilities :=
     Termicap.Capabilities.Get;
   Tomato : constant Termicap.Downsampling.RGB :=
     (Red => 255, Green => 99, Blue => 71);
   Result : constant Termicap.Downsampling.Downsampled_Color :=
     Termicap.Downsampling.Downsample (Tomato, Target => Caps.Color);
begin
   case Result.Level is
      when Termicap.Color.True_Color   => Emit_Truecolor (Result.RGB_Value);
      when Termicap.Color.Extended_256 => Emit_256       (Result.Index_256);
      when Termicap.Color.Basic_16     => Emit_16        (Result.Index_16);
      when Termicap.Color.None         => null;  --  no color escape sequences
   end case;
end;
```

The package also exposes the primitive conversions (`Downsample_True_To_256`, `Downsample_True_To_16`, `Downsample_256_To_16`) when you already know the target level and don't need the dispatch wrapper.

More examples — including background-color querying, dark/light theme detection, dimensions, SIGWINCH handling, mouse, hyperlinks, Sixel — live in [`examples/`](examples/) and can be built with `cd examples && alr build`.

---

## Building, testing, formatting

```bash
# Build the library
alr build

# Run the test suite (>95% coverage target)
cd tests && alr build && ./tests/bin/termicap_tests

# Build the example programs
cd examples && alr build

# Format the entire codebase
./tools/format_code.sh

# SPARK verification
alr exec -- gnatprove -P termicap.gpr
```

A cross-language conformance harness lives in [`tools/conformance/`](tools/conformance/) and compares Termicap's results against reference shims in C, Go, Rust, Python, Node.js, Java, Haskell, Ruby, C#, and Swift — see its README for usage.

---

## Documentation

- **Architecture** — [`docs/architecture/`](docs/architecture/): arc42 lite (context, constraints, building blocks, runtime view).
- **User guide** — [`docs/guide/`](docs/guide/): tutorials, how-to, reference, explanation ([Diátaxis](https://diataxis.fr/)).
- **ADRs** — [`docs/adr/`](docs/adr/): MADR-format decision records.
- **Requirements** — [`docs/requirements/`](docs/requirements/): StrictDoc-format functional and non-functional requirements, traced to code and tests.
- **Reference research** — [`reference-frameworks/analysis/`](reference-frameworks/analysis/): cross-language synthesis of 24+ libraries informing the design.

---

## Project layout

```
termicap/
├── alire.toml             root crate manifest
├── src/                   library sources
│   ├── posix/             POSIX platform-dispatched bodies
│   └── windows/           Windows platform-dispatched bodies + Win32 layer
├── tests/                 separate Alire crate, test runner
├── examples/              separate Alire crate, runnable demos
├── tools/
│   ├── conformance/       cross-language conformance harness
│   └── format_code.sh     gnatformat wrapper
├── docs/                  architecture, ADRs, user guide, requirements
└── reference-frameworks/  vendored reference libraries (read-only, for study)
```

---

## AI use in this project

In the interest of transparency: substantial portions of this codebase — Ada source, tests, examples, ADRs, requirements, and most of this README — were drafted with the help of generative-AI tools, primarily **Claude Opus**. The detection algorithms themselves are not invented by the model out of thin air — they are derived from a survey of established terminal-capability libraries across other ecosystems (notably `supports-color` and `terminal-size` in Rust/Node.js, `termenv` in Go, `rich` and `blessed` in Python, `chafa` in C, `JLine` in Java, plus a handful of others) cross-checked against published terminal specifications and consolidated into the StrictDoc requirements set under [`docs/requirements/`](docs/requirements/). AI assistance was used to translate that prior art into idiomatic Ada/SPARK and to scaffold tests and docs around it.

Every committed change is reviewed, tested, and owned by the human maintainer. AI is treated as a power tool, not as an author — the same standard expected of outside contributions (see below).

---

## Contributing

Contributions are welcome — bug reports, fixes, new features, documentation, additional conformance shims. For anything non-trivial please open an issue first so we can align on direction before code is written. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat | fix | docs | test | refactor | perf | chore`); the build, format, test, and SPARK commands are listed under [Building, testing, formatting](#building-testing-formatting).

### AI-assisted contributions

Generative-AI tools (Claude Code, Copilot, Codex, Cursor, …) are allowed when writing code, tests, docs, or commit messages. The rules are simple:

- **You — the human opening the PR — own the code.** You are responsible for understanding every line you submit, for testing it, for making sure it builds and passes the test suite, and for matching the project's coding standard ([`.claude/ada-style-guide.md`](docs/ada-style-guide.md)). *"The model wrote it"* is never an acceptable answer to a review comment.
- **Pull requests opened directly by an AI agent or autonomous bot are not accepted** and will be closed without review. The only exception is automation run on the explicit initiative of a maintainer of this repository.
- **Disclose substantial AI involvement** in the PR description — a one-liner is enough, e.g. *"drafted with Claude Opus, reviewed and adjusted by hand"*. Trivial autocomplete or rename suggestions don't need disclosure; whole functions, architectures, large refactors, or generated tests do.
- **Respect licenses.** Make sure the AI tool's terms and any training-data attribution constraints are compatible with this project's Apache-2.0 WITH LLVM-exception license. If you're unsure, don't submit it.

If a PR cannot survive these rules, please do not open it — it saves everyone time.

---

## License

Apache-2.0 WITH LLVM-exception. See [`LICENSE`](LICENSE) for the full text.

The LLVM exception permits static linking into closed-source binaries without triggering license propagation — important for a library that is, by design, linked into every binary it informs.
