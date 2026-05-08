// Conformance shim for Spectre.Console (C# / .NET).
//
// Spectre.Console exposes detection via AnsiConsole.Profile.Capabilities:
//   ColorSystem (NoColors / Standard / EightBit / TrueColor)
//   Ansi  (bool)         — overall ANSI support gate
//   Links (bool)         — hyperlinks (OSC 8) support
//   Unicode (bool)       — Unicode rendering
//   Interactive (bool)   — TTY-like detection
//   Width / Height       — terminal size
//
// Detection mechanism: env-var allowlist + isatty + Windows VT-mode probe.
// Different implementation lineage from chalk/supports-color → cross-impl
// agreement on hyperlinks here is meaningful (4th source, currently 2).

using System;
using System.IO;
using System.Text;
using System.Text.Json;
using Spectre.Console;

namespace SpectreConsoleShim;

internal static class Program
{
    private const string SchemaVersion = "0.1.0";
    private const string LibName = "spectre-console";
    private const string LibVersion = "0.55.0";

    private static string ColorSystemToCanonical(ColorSystem c) => c switch
    {
        ColorSystem.NoColors => "none",
        ColorSystem.Legacy   => "ansi16",
        ColorSystem.Standard => "ansi16",
        ColorSystem.EightBit => "ansi256",
        ColorSystem.TrueColor => "truecolor",
        _ => "none",
    };

    private static int Main(string[] args)
    {
        var envelopePath = Environment.GetEnvironmentVariable("CONFORMANCE_ENVELOPE");
        if (string.IsNullOrEmpty(envelopePath))
        {
            Console.Error.WriteLine("spectre-console-shim: $CONFORMANCE_ENVELOPE not set");
            return 2;
        }
        var envelopeJson = File.ReadAllText(envelopePath).Trim();
        var outputPath = args.Length > 0 ? args[0] : "spectre-console.json";

        var profile = AnsiConsole.Profile;
        var caps = profile.Capabilities;

        var colorValue = ColorSystemToCanonical(caps.ColorSystem);
        var hyperlinkValue = caps.Links ? "supported" : "unsupported";
        var unicodeValue = caps.Unicode ? "extended" : "none";

        // Build JSON manually to control ordering and avoid escaping the envelope.
        var sb = new StringBuilder(2048);
        sb.AppendLine("{");
        sb.AppendLine($"  \"schema_version\": {JsonString(SchemaVersion)},");
        sb.AppendLine($"  \"run\": {envelopeJson},");
        sb.AppendLine($"  \"lib\": {{\"name\": {JsonString(LibName)}, \"version\": {JsonString(LibVersion)}, \"language\": \"csharp\", \"tier\": \"passive\"}},");
        sb.AppendLine("  \"capabilities\": {");
        sb.AppendLine("    \"tty_stdin\":  {\"supported\": false},");
        sb.AppendLine($"    \"tty_stdout\": {{\"supported\": true, \"value\": {LowerBool(caps.Interactive)}, \"method\": \"Spectre.Console Profile.Capabilities.Interactive (TTY-like detection)\"}},");
        sb.AppendLine("    \"tty_stderr\": {\"supported\": false},");
        sb.AppendLine($"    \"color_depth\": {{\"supported\": true, \"value\": {JsonString(colorValue)}, \"method\": \"Spectre.Console Profile.Capabilities.ColorSystem mapping\", \"raw\": {{\"ColorSystem\": {JsonString(caps.ColorSystem.ToString())}, \"Ansi\": {LowerBool(caps.Ansi)}}}}},");
        sb.AppendLine("    \"windows_console_color\": {\"supported\": false},");
        sb.AppendLine($"    \"dimensions\": {{\"supported\": true, \"value\": {{\"cols\": {profile.Width}, \"rows\": {profile.Height}, \"pixel_width\": 0, \"pixel_height\": 0}}, \"method\": \"Spectre.Console Profile.Width / Profile.Height\"}},");
        sb.AppendLine($"    \"unicode\": {{\"supported\": true, \"value\": {JsonString(unicodeValue)}, \"method\": \"Spectre.Console Profile.Capabilities.Unicode (binary -> extended/none)\", \"raw\": {{\"Unicode\": {LowerBool(caps.Unicode)}}}}},");
        sb.AppendLine("    \"terminal_kind\": {\"supported\": false},");
        sb.AppendLine("    \"multiplexer\": {\"supported\": false},");
        sb.AppendLine("    \"theme\": {\"supported\": false},");
        sb.AppendLine("    \"background\": {\"supported\": false},");
        sb.AppendLine($"    \"hyperlinks\": {{\"supported\": true, \"value\": {JsonString(hyperlinkValue)}, \"method\": \"Spectre.Console Profile.Capabilities.Links (binary -> supported/unsupported)\"}},");
        sb.AppendLine("    \"mouse\": {\"supported\": false},");
        sb.AppendLine("    \"keyboard\": {\"supported\": false},");
        sb.AppendLine("    \"clipboard_osc52\": {\"supported\": false},");
        sb.AppendLine("    \"graphics_sixel\": {\"supported\": false},");
        sb.AppendLine("    \"graphics_kitty\": {\"supported\": false},");
        sb.AppendLine("    \"xtversion\": {\"supported\": false},");
        sb.AppendLine("    \"da1_attributes\": {\"supported\": false},");
        sb.AppendLine("    \"ci_detected\": {\"supported\": false}");
        sb.AppendLine("  }");
        sb.AppendLine("}");
        File.WriteAllText(outputPath, sb.ToString());

        Console.Error.WriteLine($"spectre-console-shim: wrote {outputPath} (color={colorValue} hyperlinks={hyperlinkValue} unicode={unicodeValue} cols={profile.Width})");
        return 0;
    }

    private static string JsonString(string s) => JsonSerializer.Serialize(s);
    private static string LowerBool(bool b) => b ? "true" : "false";
}
