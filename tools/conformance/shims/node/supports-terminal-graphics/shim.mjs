#!/usr/bin/env node
// Conformance shim for `supports-terminal-graphics` (Node).
//
// Detects Kitty graphics, iTerm2 inline images, and Sixel via env-var/TTY
// heuristics — a different algorithm from blessed's APC probe and termicap's
// active probes. When the env-var-based answer disagrees with the active
// probe, that's a meaningful signal: the terminal misadvertises in env vars.
//
// The lib is the detection engine inside `terminal-image`.
//
// Default export shape: { stdout: { kitty, iterm2, sixel }, stderr: {...} }
//
// terminal_kind: emit "iterm2" if iterm2 graphics is supported, since this
// is the same TERM_PROGRAM-allowlist signal viuer's is_iterm_supported uses.

import supportsTerminalGraphics from 'supports-terminal-graphics';
import { readFileSync, writeFileSync } from 'node:fs';
import { argv, env, exit } from 'node:process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SCHEMA_VERSION = '0.1.0';
const LIB_NAME = 'supports-terminal-graphics';
const _pkgPath = join(
  dirname(fileURLToPath(import.meta.url)),
  'node_modules',
  'supports-terminal-graphics',
  'package.json',
);
const LIB_VERSION = JSON.parse(readFileSync(_pkgPath, 'utf8')).version;

const envelopePath = env.CONFORMANCE_ENVELOPE;
if (!envelopePath) {
  console.error('supports-terminal-graphics-shim: $CONFORMANCE_ENVELOPE not set');
  exit(2);
}
const envelope = JSON.parse(readFileSync(envelopePath, 'utf8'));
const outputPath = argv[2] || 'supports-terminal-graphics.json';

const stdoutSupport = supportsTerminalGraphics.stdout;
const stderrSupport = supportsTerminalGraphics.stderr;

const kittyCap = {
  supported: true,
  value: Boolean(stdoutSupport.kitty),
  method: 'supports-terminal-graphics .stdout.kitty (env-var allowlist for kitty/ghostty/wezterm/konsole/iterm2-3.6+/rio/warp)',
  raw: { stderr_kitty: stderrSupport.kitty },
};
const sixelCap = {
  supported: true,
  value: Boolean(stdoutSupport.sixel),
  method: 'supports-terminal-graphics .stdout.sixel (env-var allowlist; lib explicitly notes detection is limited for xterm/foot)',
  raw: { stderr_sixel: stderrSupport.sixel },
};
const kindCap = stdoutSupport.iterm2
  ? {
      supported: true,
      value: 'iterm2',
      method: 'supports-terminal-graphics .stdout.iterm2 (TERM_PROGRAM allowlist for iTerm2/WezTerm/VS Code/Konsole/mintty/Rio)',
      raw: { iterm2_stderr: stderrSupport.iterm2 },
    }
  : {
      supported: false,
      raw: { iterm2: false, note: 'no iTerm2 protocol detected; lib does not classify other terminals' },
    };

const result = {
  schema_version: SCHEMA_VERSION,
  run: envelope,
  lib: {
    name: LIB_NAME,
    version: LIB_VERSION,
    language: 'node',
    tier: 'passive',
  },
  capabilities: {
    tty_stdin:  { supported: false },
    tty_stdout: { supported: false },
    tty_stderr: { supported: false },
    color_depth: { supported: false },
    windows_console_color: { supported: false },
    dimensions: { supported: false },
    unicode: { supported: false },
    terminal_kind: kindCap,
    multiplexer: { supported: false },
    theme: { supported: false },
    background: { supported: false },
    hyperlinks: { supported: false },
    mouse: { supported: false },
    keyboard: { supported: false },
    clipboard_osc52: { supported: false },
    graphics_sixel: sixelCap,
    graphics_kitty: kittyCap,
    xtversion: { supported: false },
    da1_attributes: { supported: false },
    ci_detected: { supported: false },
  },
};

writeFileSync(outputPath, JSON.stringify(result, null, 2) + '\n');
console.error(
  `supports-terminal-graphics-shim: wrote ${outputPath} (kitty=${kittyCap.value} sixel=${sixelCap.value} iterm2=${stdoutSupport.iterm2})`,
);
