#!/usr/bin/env node
// Conformance shim for `kleur` (Node).
//
// kleur exposes binary color detection via its default export's `enabled`
// property (computed once at module-load time from FORCE_COLOR / NO_COLOR /
// NODE_DISABLE_COLORS / TERM / isTTY). It does not measure depth.
//
// Mapping policy:
//   enabled == true  -> color_depth='ansi16'  (the floor of "any color")
//   enabled == false -> color_depth='none'
//
// Divergence vs supports-color (truecolor) is expected and meaningful: it
// surfaces the gap between binary-only detection (kleur, colorette,
// picocolors-style libs) and depth-aware detection.

import kleur from 'kleur';
import { readFileSync, writeFileSync } from 'node:fs';
import { argv, env, exit } from 'node:process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SCHEMA_VERSION = '0.1.0';
const LIB_NAME = 'kleur';
const _pkgPath = join(
  dirname(fileURLToPath(import.meta.url)),
  'node_modules',
  'kleur',
  'package.json',
);
const LIB_VERSION = JSON.parse(readFileSync(_pkgPath, 'utf8')).version;

const envelopePath = env.CONFORMANCE_ENVELOPE;
if (!envelopePath) {
  console.error('kleur-shim: $CONFORMANCE_ENVELOPE not set');
  exit(2);
}
const envelope = JSON.parse(readFileSync(envelopePath, 'utf8'));
const outputPath = argv[2] || 'kleur.json';

const enabled = Boolean(kleur.enabled);
const colorValue = enabled ? 'ansi16' : 'none';

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
      method: 'kleur.enabled (binary FORCE_COLOR / NO_COLOR / NODE_DISABLE_COLORS / TERM check); maps true -> ansi16 floor',
      raw: { enabled, mapping_note: 'kleur does not measure depth; ansi16 is the floor when enabled' },
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
console.error(`kleur-shim: wrote ${outputPath} (color_depth=${colorValue})`);
