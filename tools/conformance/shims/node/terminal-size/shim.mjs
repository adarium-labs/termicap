#!/usr/bin/env node
// Conformance shim for the `terminal-size` Node package.
//
// Single-purpose API: terminalSize() -> { columns, rows }
// terminal-size has no notion of pixel dimensions; canonical pixel_*
// fields are emitted as 0 (the schema's "unknown" sentinel).
// Defaults to 80x24 when no signal is available.

import terminalSize from 'terminal-size';
import { readFileSync, writeFileSync } from 'node:fs';
import { argv, env, exit } from 'node:process';

const SCHEMA_VERSION = '0.1.0';
const LIB_NAME = 'terminal-size';
const LIB_VERSION = '4.0.1';

const envelopePath = env.CONFORMANCE_ENVELOPE;
if (!envelopePath) {
  console.error('terminal-size-shim: $CONFORMANCE_ENVELOPE not set');
  exit(2);
}

const envelope = JSON.parse(readFileSync(envelopePath, 'utf8'));
const outputPath = argv[2] || 'terminal-size.json';

const size = terminalSize();

const result = {
  schema_version: SCHEMA_VERSION,
  run: envelope,
  lib: {
    name: LIB_NAME,
    version: LIB_VERSION,
    language: 'node',
    tier: 'mixed',
  },
  capabilities: {
    tty_stdin:  { supported: false },
    tty_stdout: { supported: false },
    tty_stderr: { supported: false },
    color_depth: { supported: false },
    windows_console_color: { supported: false },
    dimensions: {
      supported: true,
      value: {
        cols: size.columns,
        rows: size.rows,
        pixel_width: 0,
        pixel_height: 0,
      },
      method: 'terminalSize() (TTY API -> /dev/tty -> tput/resize -> COLUMNS/LINES env -> 80x24 default)',
      raw: size,
    },
    unicode: { supported: false },
    terminal_kind: { supported: false },
    multiplexer: { supported: false },
    theme: { supported: false },
    background: { supported: false },
    hyperlinks: { supported: false },
    mouse: { supported: false },
    keyboard: { supported: false },
    clipboard_osc52: { supported: false },
    graphics_sixel: { supported: false },
    graphics_kitty: { supported: false },
    xtversion: { supported: false },
    da1_attributes: { supported: false },
    ci_detected: { supported: false },
  },
};

writeFileSync(outputPath, JSON.stringify(result, null, 2) + '\n');
console.error(
  `terminal-size-shim: wrote ${outputPath} (${size.columns}x${size.rows})`,
);
