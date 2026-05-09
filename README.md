# Termicap

Terminal capability detection for Ada/SPARK. Cross-platform, dependency-light, no rendering layer attached.

Before printing a single byte, most CLI and TUI programs have to ask the same handful of questions: is this stream a TTY, how many colors does the terminal handle, how wide is the window right now, can the locale render Unicode, *which* terminal is this anyway (iTerm, kitty, WezTerm, Windows Terminal, ConPTY, tmux, screen…), does it understand OSC 8 hyperlinks or Sixel graphics or the Kitty keyboard protocol, and the one question that trumps all the others: did the user already pass `NO_COLOR`, `FORCE_COLOR`, or `--color=never`?

Termicap answers those questions and hands the answers back as plain Ada records and enums. It does not emit escape sequences, draw widgets, or pretend to be a TUI framework. Pair it with whatever output layer you already have.

> **A note about SPARK.** The code is *written* against SPARK Silver (with a few Gold spots), and the FFI and tasking surfaces are isolated behind clearly-marked `SPARK_Mode => Off` boundaries. It has not yet been verified end-to-end with `gnatprove` though. Running the prover and discharging whatever VCs remain is on the to-do list, not a finished claim.

## Highlights

Detection covers the four canonical color levels (`None`, `Basic_16`, `Extended_256`, `True_Color`) through an 11-step cascade modelled on `supports-color`, `termenv`, and `rich`, and it respects the no-color.org and force-color.org conventions plus the BSD `CLICOLOR` / `CLICOLOR_FORCE` knobs. Linux, macOS, BSD, and Windows are all supported; on Windows that includes the modern Win32 console, ConPTY, and Cygwin/MSYS2 PTY detection by inspecting the underlying named-pipe name through `NtQueryObject`.

There are two API tiers. `Get` and `Detect` give you a fast snapshot (sub-50 ms in the worst case). `Get_Full` and `Detect_Full` add active probes (XTVERSION, keyboard, mouse, graphics, OSC 52 clipboard) at the cost of up to roughly 6 s if every probe times out. A local PTY normally answers in well under 50 ms. `Get` is cached per stream and thread-safe; `Detect` always re-runs everything, which is what you want after `SIGWINCH`, after the override changes, or in a long-running process that can't trust a stale snapshot.

An `Override_Mode` lets you wire `--color=auto | never | always | 256 | truecolor` straight into the detection engine, with a `Scoped_Override` controlled type for RAII-style scopes. Errors come back as `Result` variants or safe defaults; no exceptions are raised by library code. Dependencies stay minimal: [`sparklib`](https://github.com/AdaCore/sparklib) for the SPARK formal containers, plus [`win32ada`](https://github.com/AdaCore/win32ada) on Windows only.

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

The full package map and SPARK boundary diagram is in [`docs/architecture/03-building-blocks.md`](docs/architecture/03-building-blocks.md), and the per-feature reference docs live under [`docs/guide/reference/`](docs/guide/reference/).

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

Always go through `alr build`; `gprbuild` is not the right entry point here, and each sub-crate (root, `tests/`, `examples/`) carries its own `alire.toml`.

---

## Quick start

The common case: ask for the cached snapshot for stdout and branch on what comes back.

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

If you only want the override active for a single block of work, the controlled-type form takes care of restoring the previous mode for you:

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

`Get_Full` adds XTVERSION, keyboard, mouse, graphics, and OSC 52 clipboard detection. The first call is the slow one (up to ~6 s if every active probe times out, well under 50 ms on a local PTY); subsequent calls are cache hits.

### Pair detection with `Termicap.Downsampling`

Detection only tells you what the terminal can show. Picking a color the terminal can actually display is a separate problem, and that's what `Termicap.Downsampling` is for: it maps any color you want to emit down to the level the terminal supports (TrueColor → 256-color → ANSI 16, or strip to none) with SPARK Gold idempotency and monotonicity contracts. One overloaded `Downsample` dispatch handles `RGB` or `Color_Index_256` sources; the result is a discriminated `Downsampled_Color` you `case`-match on to pick the right escape sequence, or to skip emitting one altogether.

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

The primitive conversions (`Downsample_True_To_256`, `Downsample_True_To_16`, `Downsample_256_To_16`) are also exposed when you already know the target level and don't need the dispatcher.

More demos sit in [`examples/`](examples/) (background-color querying, dark/light theme, dimensions, SIGWINCH, mouse, hyperlinks, Sixel, and so on) and build with `cd examples && alr build`.

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

There's also a cross-language conformance harness under [`tools/conformance/`](tools/conformance/) that compares Termicap's results to reference shims in C, Go, Rust, Python, Node.js, Java, Haskell, Ruby, C#, and Swift. Its own README has the details.

---

## Documentation

* Architecture lives in [`docs/architecture/`](docs/architecture/) and follows arc42 lite (context, constraints, building blocks, runtime view).
* The user guide in [`docs/guide/`](docs/guide/) is split tutorials / how-to / reference / explanation, [Diátaxis](https://diataxis.fr/)-style.
* Design decisions are in [`docs/adr/`](docs/adr/), MADR format.
* Functional and non-functional requirements are tracked under [`docs/requirements/`](docs/requirements/) in StrictDoc, traced to code and tests.

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
└── docs/                  architecture, ADRs, user guide, requirements
```

---

## AI use in this project

For transparency: a substantial part of this codebase, including Ada source, tests, examples, ADRs, requirements, and most of this README, was drafted with the help of generative-AI tools, primarily Claude Opus. The detection algorithms themselves aren't model inventions; they come from a survey of established terminal-capability libraries in other ecosystems (`supports-color` and `terminal-size` in Rust/Node.js, `termenv` in Go, `rich` and `blessed` in Python, `chafa` in C, `JLine` in Java, plus a few more), cross-checked against published terminal specifications and consolidated into the StrictDoc requirements set under [`docs/requirements/`](docs/requirements/). What the AI was used for is the translation of that prior art into idiomatic Ada/SPARK and the scaffolding of tests and docs around it.

Every committed change is reviewed, tested, and owned by a human. The AI is treated as a power tool, not as an author. The same standard is expected from outside contributions; see below.

---

## Contributing

Contributions are welcome: bug reports, fixes, new features, documentation, more conformance shims. For anything non-trivial please open an issue first so we can agree on the direction before code is written. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat | fix | docs | test | refactor | perf | chore`); the build, format, test, and SPARK commands are listed in [Building, testing, formatting](#building-testing-formatting) above.

### AI-assisted contributions

You may use generative-AI tools (Claude Code, Copilot, Codex, Cursor, anything else) when writing code, tests, docs, or commit messages. The rules are short:

1. **You own the code you submit.** If you opened the PR, you're on the hook for understanding every line of it, for testing it, for getting it past the test suite and the project's coding standard ([`.docs/ada-style-guide.md`](docs/ada-style-guide.md)). *"The model wrote it"* is not an answer to a review comment.
2. **PRs opened directly by an AI agent or autonomous bot will be closed without review.** The only exception is automation a maintainer of this repository runs on their own initiative.
3. **Disclose substantial AI involvement** in the PR description. A one-line note is enough, e.g. *"drafted with Claude Opus, reviewed and adjusted by hand"*. Trivial autocomplete or rename suggestions don't need disclosure; whole functions, generated tests, large refactors, or new architecture do.
4. **Watch the licensing.** Make sure the AI tool's terms and any training-data attribution constraints are compatible with the project's Apache-2.0 WITH LLVM-exception license. If you're unsure, don't submit it.

If a PR can't survive these rules, please don't open it. It saves everyone time.

---

## License

Apache-2.0 WITH LLVM-exception. The full text is in [`LICENSE`](LICENSE).

The LLVM exception makes the license safe for static linking into closed-source binaries without forcing license propagation, which matters for a library that, by design, is linked into pretty much every binary it informs.
