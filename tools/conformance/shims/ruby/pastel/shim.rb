#!/usr/bin/env ruby
# Conformance shim for `pastel` (Ruby).
#
# pastel exposes only a binary signal:
#   Pastel.new.enabled?  -> Boolean
#
# It calls tty-color internally for detection. Including pastel as a second
# Ruby shim acts as a *port-coupling sanity check*: pastel.enabled? must agree
# with tty-color.support? -- if they disagree, pastel's wrapper logic broke.
#
# Mapping: same as kleur/colorette (binary -> ansi16 floor).

require 'json'
require 'pastel'

SCHEMA_VERSION = '0.1.0'
LIB_NAME = 'pastel'
LIB_VERSION = Pastel::VERSION
LIB_LANGUAGE = 'ruby'
LIB_TIER = 'passive'

envelope_path = ENV['CONFORMANCE_ENVELOPE']
if envelope_path.nil? || envelope_path.empty?
  warn 'pastel-shim: $CONFORMANCE_ENVELOPE not set'
  exit 2
end
envelope = JSON.parse(File.read(envelope_path))
output_path = ARGV[0] || 'pastel.json'

pastel = Pastel.new
enabled = pastel.enabled?

color_value = enabled ? 'ansi16' : 'none'

color_cap = {
  supported: true,
  value: color_value,
  method: 'Pastel.new.enabled? (binary; delegates to tty-color); ansi16 floor when enabled',
  raw: { enabled: enabled, mapping_note: 'pastel is binary-only' },
}

result = {
  schema_version: SCHEMA_VERSION,
  run: envelope,
  lib: { name: LIB_NAME, version: LIB_VERSION, language: LIB_LANGUAGE, tier: LIB_TIER },
  capabilities: {
    tty_stdin: { supported: false },
    tty_stdout: { supported: false },
    tty_stderr: { supported: false },
    color_depth: color_cap,
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
}

File.write(output_path, JSON.pretty_generate(result) + "\n")
warn "pastel-shim: wrote #{output_path} (color_depth=#{color_value} enabled=#{enabled})"
