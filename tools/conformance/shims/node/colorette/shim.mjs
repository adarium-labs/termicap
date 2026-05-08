#!/usr/bin/env node
// Conformance shim for `colorette` (Node).
//
// Exposes a single binary detection signal: `isColorSupported`. It checks
// FORCE_COLOR, NO_COLOR, --color/--no-color argv flags, and TTY status.
// Same binary-only mapping as the kleur shim:
//   true  -> ansi16   (floor of any color)
//   false -> none
//
// Pairing kleur + colorette + supports-color-node tests *binary detector
// agreement* (do they all decide "color is on"?) independent of *depth
// detector agreement* (truecolor vs ansi16, which only depth-aware libs do).

import { isColorSupported } from 'colorette';
import { readFileSync, writeFileSync } from 'node:fs';
import { argv, env, exit } from 'node:process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SCHEMA_VERSION = '0.1.0';
const LIB_NAME = 'colorette';
const _pkgPath = join(
  dirname(fileURLToPath(import.meta.url)),
  'node_modules',
  'colorette',
  'package.json',
);
const LIB_VERSION = JSON.parse(readFileSync(_pkgPath, 'utf8')).version;

const envelopePath = env.CONFORMANCE_ENVELOPE;
if (!envelopePath) {
  console.error('colorette-shim: $CONFORMANCE_ENVELOPE not set');
  exit(2);
}
const envelope = JSON.parse(readFileSync(envelopePath, 'utf8'));
const outputPath = argv[2] || 'colorette.json';

const colorValue = isColorSupported ? 'ansi16' : 'none';

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
      value: colorValue,
      method: 'colorette.isColorSupported (binary FORCE_COLOR/NO_COLOR/--color flag/TTY check); maps true -> ansi16 floor',
      raw: { isColorSupported, mapping_note: 'colorette does not measure depth; ansi16 is the floor when enabled' },
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
console.error(`colorette-shim: wrote ${outputPath} (color_depth=${colorValue})`);
