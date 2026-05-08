// Conformance shim for Vapor's console-kit (Swift).
//
// ConsoleKitTerminal exposes the `Terminal` class which provides:
//   Terminal().supportsANSICommands  -> isatty(STDOUT) > 0   (default impl)
//
// That's a fairly minimal detection surface; we supplement it with
// Foundation/Darwin-level isatty(3) for stdin/stderr to give the harness
// a third Swift-language data point on tty_*.
//
// Capabilities reported:
//   tty_stdin/stdout/stderr : isatty(0/1/2)            (Darwin/Glibc syscall)
//   color_depth             : env-var heuristic + ConsoleKit.supportsANSICommands
//                              when supportsANSICommands == false -> 'none'
//                              when COLORTERM == truecolor / 24bit -> 'truecolor'
//                              when TERM contains 256color -> 'ansi256'
//                              when TERM contains color -> 'ansi16'
//                              else -> 'ansi16' (the ANSI floor when ConsoleKit allows ANSI)
//   terminal_kind           : TERM_PROGRAM env mapping (kitty/iterm2/wezterm/...)

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif
import ConsoleKitTerminal

#if canImport(WinSDK)
// Windows ucrt exposes _isatty rather than the POSIX isatty.
private func isatty(_ fd: Int32) -> Int32 { _isatty(fd) }
#endif

let SCHEMA_VERSION = "0.1.0"
let LIB_NAME = "console-kit"
let LIB_VERSION = "4.16.0" // approximate; matches reference-framework state at integration time

func jsonEscape(_ s: String) -> String {
    var out = "\""
    for c in s.unicodeScalars {
        switch c {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if c.value < 0x20 {
                out += String(format: "\\u%04x", c.value)
            } else {
                out += String(c)
            }
        }
    }
    out += "\""
    return out
}

func capBool(_ value: Bool, method: String) -> String {
    return "{\"supported\": true, \"value\": \(value), \"method\": \(jsonEscape(method))}"
}

func capColorDepth(_ value: String, method: String, raw: String) -> String {
    return "{\"supported\": true, \"value\": \(jsonEscape(value)), \"method\": \(jsonEscape(method)), \"raw\": \(raw)}"
}

func capNotMeasured(_ raw: String) -> String {
    return "{\"supported\": false, \"raw\": \(jsonEscape(raw))}"
}

guard let envelopePath = ProcessInfo.processInfo.environment["CONFORMANCE_ENVELOPE"] else {
    FileHandle.standardError.write("console-kit-shim: $CONFORMANCE_ENVELOPE not set\n".data(using: .utf8)!)
    exit(2)
}
let envelopeData = try Data(contentsOf: URL(fileURLWithPath: envelopePath))
let envelopeStr = String(data: envelopeData, encoding: .utf8) ?? "{}"

let outputPath: String = {
    let args = CommandLine.arguments
    return args.count > 1 ? args[1] : "console-kit.json"
}()

let env = ProcessInfo.processInfo.environment

let stdinTty  = isatty(0) != 0
let stdoutTty = isatty(1) != 0
let stderrTty = isatty(2) != 0

let term = Terminal()
let supportsAnsi = term.supportsANSICommands

let colorTerm = env["COLORTERM"]?.lowercased() ?? ""
let termVar = env["TERM"]?.lowercased() ?? ""

let colorValue: String = {
    if !supportsAnsi { return "none" }
    if colorTerm == "truecolor" || colorTerm == "24bit" { return "truecolor" }
    if termVar.contains("256color") { return "ansi256" }
    if termVar.contains("color") { return "ansi16" }
    return "ansi16" // floor when ANSI is supported
}()

let colorRaw = "{\"supportsAnsi\": \(supportsAnsi), \"COLORTERM\": \(jsonEscape(colorTerm)), \"TERM\": \(jsonEscape(termVar))}"

let termProgram = env["TERM_PROGRAM"]?.lowercased() ?? ""
let kindValue: String? = {
    switch true {
    case termProgram.contains("kitty"): return "kitty"
    case termProgram.contains("ghostty"): return "ghostty"
    case termProgram.contains("wezterm"): return "wezterm"
    case termProgram.contains("alacritty"): return "alacritty"
    case termProgram.contains("iterm"): return "iterm2"
    case termProgram.contains("apple_terminal"): return "apple_terminal"
    case termProgram.contains("vscode"): return "vscode"
    case termProgram.contains("warpterminal") || termProgram == "warp": return "warp"
    default: return nil
    }
}()
let kindCap: String = {
    if let v = kindValue {
        return "{\"supported\": true, \"value\": \(jsonEscape(v)), \"method\": \"TERM_PROGRAM allowlist (Swift / ConsoleKit shim-side)\", \"raw\": {\"TERM_PROGRAM\": \(jsonEscape(env["TERM_PROGRAM"] ?? ""))}}"
    } else {
        return capNotMeasured("TERM_PROGRAM=\(env["TERM_PROGRAM"] ?? "<unset>") not in shim allowlist")
    }
}()

var out = ""
out += "{\n"
out += "  \"schema_version\": \(jsonEscape(SCHEMA_VERSION)),\n"
out += "  \"run\": \(envelopeStr),\n"
out += "  \"lib\": {\"name\": \(jsonEscape(LIB_NAME)), \"version\": \(jsonEscape(LIB_VERSION)), \"language\": \"swift\", \"tier\": \"passive\"},\n"
out += "  \"capabilities\": {\n"
out += "    \"tty_stdin\": \(capBool(stdinTty, method: "Swift Darwin.isatty(0)")),\n"
out += "    \"tty_stdout\": \(capBool(stdoutTty, method: "Swift Darwin.isatty(1) (also via ConsoleKit.Terminal.supportsANSICommands)")),\n"
out += "    \"tty_stderr\": \(capBool(stderrTty, method: "Swift Darwin.isatty(2)")),\n"
out += "    \"color_depth\": \(capColorDepth(colorValue, method: "ConsoleKit.supportsANSICommands + COLORTERM/TERM env-var cascade", raw: colorRaw)),\n"
out += "    \"windows_console_color\": {\"supported\": false},\n"
out += "    \"dimensions\": {\"supported\": false},\n"
out += "    \"unicode\": {\"supported\": false},\n"
out += "    \"terminal_kind\": \(kindCap),\n"
out += "    \"multiplexer\": {\"supported\": false},\n"
out += "    \"theme\": {\"supported\": false},\n"
out += "    \"background\": {\"supported\": false},\n"
out += "    \"hyperlinks\": {\"supported\": false},\n"
out += "    \"mouse\": {\"supported\": false},\n"
out += "    \"keyboard\": {\"supported\": false},\n"
out += "    \"clipboard_osc52\": {\"supported\": false},\n"
out += "    \"graphics_sixel\": {\"supported\": false},\n"
out += "    \"graphics_kitty\": {\"supported\": false},\n"
out += "    \"xtversion\": {\"supported\": false},\n"
out += "    \"da1_attributes\": {\"supported\": false},\n"
out += "    \"ci_detected\": {\"supported\": false}\n"
out += "  }\n"
out += "}\n"

try out.write(toFile: outputPath, atomically: true, encoding: .utf8)
FileHandle.standardError.write("console-kit-shim: wrote \(outputPath) (color=\(colorValue) kind=\(kindValue ?? "?") stdin=\(stdinTty) stdout=\(stdoutTty) stderr=\(stderrTty))\n".data(using: .utf8)!)
