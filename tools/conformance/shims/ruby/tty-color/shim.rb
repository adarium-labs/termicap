#!/usr/bin/env ruby
# Conformance shim for `tty-color` (Ruby).
#
# Public detection surface used here:
#   TTY::Color.support?   -> Boolean (binary "any color")
#   TTY::Color.mode       -> Integer (0/8/16/256/16777216 -> none/ansi16/ansi16/ansi256/truecolor)
#
# tty-color does its detection by querying tput (terminfo) for `tput colors`,
# falling back to TERM-name heuristics, and respecting NO_COLOR. This is a
# fundamentally different mechanism than supports-color (env-var allowlist)
# or anstyle-query (composed predicates) -- terminfo-database backed.

require 'json'
require 'tty-color'

SCHEMA_VERSION = '0.1.0'
LIB_NAME = 'tty-color'
LIB_VERSION = TTY::Color::VERSION
LIB_LANGUAGE = 'ruby'
LIB_TIER = 'passive'

envelope_path = ENV['CONFORMANCE_ENVELOPE']
if envelope_path.nil? || envelope_path.empty?
  warn 'tty-color-shim: $CONFORMANCE_ENVELOPE not set'
  exit 2
end
envelope = JSON.parse(File.read(envelope_path))
output_path = ARGV[0] || 'tty-color.json'

# TTY::Color.mode returns 0/8/16/256/16777216
mode = TTY::Color.mode
support = TTY::Color.support?

color_value =
  case mode
  when 0          then 'none'
  when 1..15      then 'ansi16'
  when 16..255    then 'ansi256'
  when 256        then 'ansi256'
  when 257..65535 then 'ansi256'
  else                 'truecolor'
  end

# Edge-case: tty-color reports 16 as ansi16, not ansi256
color_value = 'ansi16' if mode == 16
color_value = 'none' unless support

color_cap = {
  supported: true,
  value: color_value,
  method: 'TTY::Color.mode (tput colors -> terminfo) + .support? gating',
  raw: { mode: mode, support: support },
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
warn "tty-color-shim: wrote #{output_path} (color_depth=#{color_value} mode=#{mode})"
