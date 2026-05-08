#!/usr/bin/env node
// Conformance shim for the `supports-hyperlinks` Node package.
//
// Public API: a default export that is `{stdout: bool, stderr: bool}`.
// Each property reflects whether OSC 8 hyperlinks should be safe to emit
// on that stream, based on TERM_PROGRAM allowlists and version checks.
//
// Mapping: stdout->canonical hyperlinks (extended/likely_supported/unsupported)
//   true  -> "supported"   (the lib is confident)
//   false -> "unsupported" (the lib is confident not)
// supports-hyperlinks has no equivalent of "likely_supported" or "unknown",
// so the shim never emits those values.

import supportsHyperlinks from 'supports-hyperlinks';
import { readFileSync, writeFileSync } from 'node:fs';
import { argv, env, exit } from 'node:process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SCHEMA_VERSION = '0.1.0';
const LIB_NAME = 'supports-hyperlinks';
const _pkgPath = join(
  dirname(fileURLToPath(import.meta.url)),
  'node_modules',
  'supports-hyperlinks',
  'package.json',
);
const LIB_VERSION = JSON.parse(readFileSync(_pkgPath, 'utf8')).version;

const envelopePath = env.CONFORMANCE_ENVELOPE;
if (!envelopePath) {
  console.error('supports-hyperlinks-shim: $CONFORMANCE_ENVELOPE not set');
  exit(2);
}

const envelope = JSON.parse(readFileSync(envelopePath, 'utf8'));
const outputPath = argv[2] || 'supports-hyperlinks.json';

// supports-hyperlinks v4 exports an object with stdout/stderr getters.
const stdoutSupported = supportsHyperlinks.stdout === true;
const stderrSupported = supportsHyperlinks.stderr === true;

const value = stdoutSupported ? 'supported' : 'unsupported';

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
    terminal_kind: { supported: false },
    multiplexer: { supported: false },
    theme: { supported: false },
    background: { supported: false },
    hyperlinks: {
      supported: true,
      value: value,
      method: 'supports-hyperlinks.stdout (TERM_PROGRAM allowlist + version checks)',
      raw: { stdout: stdoutSupported, stderr: stderrSupported },
    },
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
  `supports-hyperlinks-shim: wrote ${outputPath} (hyperlinks=${value})`,
);
