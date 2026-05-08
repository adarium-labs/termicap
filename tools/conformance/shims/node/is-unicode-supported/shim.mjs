#!/usr/bin/env node
// Conformance shim for the `is-unicode-supported` Node package.
//
// is-unicode-supported's entire public API is one boolean function:
//     isUnicodeSupported() -> boolean
// It uses env-var heuristics only — no probing.
//
// Mapping: true -> canonical "extended", false -> canonical "none".
// is-unicode-supported has no concept of "basic" Unicode (Latin-1), so
// the shim never emits that. This is a documented vocabulary mismatch
// vs termicap (which has three levels).

import isUnicodeSupported from 'is-unicode-supported';
import { readFileSync, writeFileSync } from 'node:fs';
import { argv, env, exit } from 'node:process';

const SCHEMA_VERSION = '0.1.0';
const LIB_NAME = 'is-unicode-supported';
const LIB_VERSION = '2.1.0';

const envelopePath = env.CONFORMANCE_ENVELOPE;
if (!envelopePath) {
  console.error('is-unicode-supported-shim: $CONFORMANCE_ENVELOPE not set');
  exit(2);
}

const envelope = JSON.parse(readFileSync(envelopePath, 'utf8'));
const outputPath = argv[2] || 'is-unicode-supported.json';

const supported = isUnicodeSupported();

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
    unicode: {
      supported: true,
      value: supported ? 'extended' : 'none',
      method: 'isUnicodeSupported() (env-var allowlist)',
      raw: { boolean: supported },
    },
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
  `is-unicode-supported-shim: wrote ${outputPath} (unicode=${supported ? 'extended' : 'none'})`,
);
