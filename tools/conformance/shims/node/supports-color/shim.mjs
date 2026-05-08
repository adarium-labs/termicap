#!/usr/bin/env node
// Conformance shim for chalk's `supports-color` Node package.
//
// Default export is { stdout, stderr } where each value is `false` (no
// color) or { level: 1|2|3, hasBasic, has256, has16m }. Same level
// vocabulary as rust-supports-color (the Rust port of this exact lib).
//
// We canonicalise the stdout side. The stderr value is preserved in
// color_depth.raw.stderr_level so cross-stream divergence (a quirk of
// chalk's per-stream detection) is not lost.

import supportsColorModule from 'supports-color';
import { readFileSync, writeFileSync } from 'node:fs';
import { argv, env, exit } from 'node:process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SCHEMA_VERSION = '0.1.0';
const LIB_NAME = 'supports-color-node';
const _pkgPath = join(
  dirname(fileURLToPath(import.meta.url)),
  'node_modules',
  'supports-color',
  'package.json',
);
const LIB_VERSION = JSON.parse(readFileSync(_pkgPath, 'utf8')).version;

const envelopePath = env.CONFORMANCE_ENVELOPE;
if (!envelopePath) {
  console.error('supports-color-node-shim: $CONFORMANCE_ENVELOPE not set');
  exit(2);
}
const envelope = JSON.parse(readFileSync(envelopePath, 'utf8'));
const outputPath = argv[2] || 'supports-color-node.json';

function levelToCanonical(level) {
  // 0 = no color; 1 = basic; 2 = 256; 3 = truecolor
  switch (level) {
    case 0: return 'none';
    case 1: return 'ansi16';
    case 2: return 'ansi256';
    case 3: return 'truecolor';
    default: return 'none';
  }
}

function describe(streamSupport) {
  if (streamSupport === false || streamSupport == null) {
    return { value: 'none', raw: { level: 0 } };
  }
  return {
    value: levelToCanonical(streamSupport.level),
    raw: {
      level: streamSupport.level,
      hasBasic: streamSupport.hasBasic,
      has256: streamSupport.has256,
      has16m: streamSupport.has16m,
    },
  };
}

const stdout = describe(supportsColorModule.stdout);
const stderr = describe(supportsColorModule.stderr);

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
    color_depth: {
      supported: true,
      value: stdout.value,
      method: 'supports-color (chalk) -> .stdout level mapping',
      raw: {
        stdout: stdout.raw,
        stderr_level: stderr.raw.level,
        stderr_value: stderr.value,
      },
    },
    windows_console_color: { supported: false },
    dimensions: { supported: false },
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
  `supports-color-node-shim: wrote ${outputPath} (color_depth=${stdout.value})`,
);
