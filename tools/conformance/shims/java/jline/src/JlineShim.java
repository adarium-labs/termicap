// Conformance shim for JLine 3 (Java).
//
// JLine builds a Terminal abstraction using:
//   - terminal type (TERM env var)
//   - infocmp / terminfo database for capabilities (Capability.max_colors, etc.)
//   - native isatty / GetConsoleMode for TTY detection
//   - ioctl(TIOCGWINSZ) for size
//
// Capability mapping:
//   color_depth   : Capability.max_colors -> none/ansi16/ansi256/truecolor
//                   (truecolor inferred when COLORTERM=truecolor; JLine itself
//                    only reports terminfo's max_colors which caps at 256)
//   dimensions    : terminal.getSize() -> {cols, rows}
//   tty_stdout    : terminal class is not DumbTerminal
//   terminal_kind : TERM/TERM_PROGRAM env mapping (JLine doesn't classify this directly)
//   keyboard      : Capability.key_enter and similar are present;
//                   for canonical purposes we don't report this (JLine doesn't
//                   measure Kitty progressive enhancement)

import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Map;
import java.util.Properties;

import org.jline.terminal.Size;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.utils.InfoCmp.Capability;

public class JlineShim {

    private static final String SCHEMA_VERSION = "0.1.0";
    private static final String LIB_NAME = "jline";
    private static final String LIB_VERSION = "3.30.4";

    private static String jsonStr(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '\\': b.append("\\\\"); break;
                case '"':  b.append("\\\""); break;
                case '\n': b.append("\\n");  break;
                case '\r': b.append("\\r");  break;
                case '\t': b.append("\\t");  break;
                default:
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
            }
        }
        return b.append('"').toString();
    }

    private static String capNotMeasured(String reason) {
        return "{\"supported\": false, \"raw\": " + jsonStr(reason) + "}";
    }

    private static String capBool(boolean value, String method) {
        return "{\"supported\": true, \"value\": " + value + ", \"method\": " + jsonStr(method) + "}";
    }

    private static String capColorDepth(String value, String method, String raw) {
        return "{\"supported\": true, \"value\": " + jsonStr(value)
                + ", \"method\": " + jsonStr(method)
                + ", \"raw\": " + raw + "}";
    }

    private static String capDimensions(int cols, int rows, String method) {
        return "{\"supported\": true, \"value\": "
                + "{\"cols\": " + cols + ", \"rows\": " + rows + ", \"pixel_width\": 0, \"pixel_height\": 0}, "
                + "\"method\": " + jsonStr(method) + "}";
    }

    public static void main(String[] args) throws Exception {
        String envelopePath = System.getenv("CONFORMANCE_ENVELOPE");
        if (envelopePath == null || envelopePath.isEmpty()) {
            System.err.println("jline-shim: $CONFORMANCE_ENVELOPE not set");
            System.exit(2);
        }
        String envelopeJson = new String(Files.readAllBytes(Paths.get(envelopePath))).trim();

        String outputPath = args.length > 0 ? args[0] : "jline.json";

        // Build a system terminal. JLine will either return a real (TTY) backend
        // or fall back to DumbTerminal when stdin/stdout is not a TTY.
        Terminal terminal = TerminalBuilder.builder()
                .system(true)
                .dumb(true) // never throw; produce DumbTerminal in non-TTY contexts
                .build();

        boolean isDumb = terminal.getClass().getSimpleName().equals("DumbTerminal");
        String terminalKind = terminal.getType();

        Size size = terminal.getSize();
        String dimCap = (size != null && size.getColumns() > 0 && size.getRows() > 0)
                ? capDimensions(size.getColumns(), size.getRows(),
                        "JLine Terminal.getSize() (ioctl(TIOCGWINSZ) when TTY; else terminfo+default)")
                : capNotMeasured("JLine size unavailable (likely DumbTerminal)");

        // color_depth: combine Capability.max_colors with COLORTERM env hint.
        Integer maxColors = terminal.getNumericCapability(Capability.max_colors);
        String colorTerm = System.getenv("COLORTERM");

        String colorValue;
        StringBuilder colorRaw = new StringBuilder("{");
        colorRaw.append("\"max_colors\": ").append(maxColors == null ? "null" : maxColors)
                .append(", \"COLORTERM\": ").append(jsonStr(colorTerm));
        colorRaw.append(", \"terminal_class\": ").append(jsonStr(terminal.getClass().getSimpleName()));
        colorRaw.append("}");

        if (isDumb) {
            colorValue = "none";
        } else if (colorTerm != null && (colorTerm.equalsIgnoreCase("truecolor") || colorTerm.equals("24bit"))) {
            colorValue = "truecolor";
        } else if (maxColors == null) {
            colorValue = "none";
        } else if (maxColors >= 256) {
            colorValue = "ansi256";
        } else if (maxColors >= 8) {
            colorValue = "ansi16";
        } else {
            colorValue = "none";
        }

        String colorCap = capColorDepth(colorValue,
                "JLine Capability.max_colors + COLORTERM=truecolor override",
                colorRaw.toString());

        // tty_stdout: DumbTerminal is the contract for "no TTY"
        String ttyCap = capBool(!isDumb,
                "JLine TerminalBuilder.system(true).build() != DumbTerminal");

        // terminal_kind: derive from $TERM_PROGRAM (JLine doesn't classify;
        // use TERM_PROGRAM env-var heuristic instead, similar to most env-var libs).
        String termProgram = System.getenv("TERM_PROGRAM");
        String kindValue = null;
        if (termProgram != null) {
            String tp = termProgram.toLowerCase();
            if (tp.contains("kitty")) kindValue = "kitty";
            else if (tp.contains("ghostty")) kindValue = "ghostty";
            else if (tp.contains("wezterm")) kindValue = "wezterm";
            else if (tp.contains("alacritty")) kindValue = "alacritty";
            else if (tp.contains("iterm")) kindValue = "iterm2";
            else if (tp.contains("apple_terminal")) kindValue = "apple_terminal";
            else if (tp.contains("vscode")) kindValue = "vscode";
            else if (tp.contains("warpterminal") || tp.equals("warp")) kindValue = "warp";
            else if (tp.contains("xterm")) kindValue = "xterm";
        }
        String kindCap = (kindValue != null)
                ? "{\"supported\": true, \"value\": " + jsonStr(kindValue)
                  + ", \"method\": \"JLine + TERM_PROGRAM env-var allowlist\""
                  + ", \"raw\": {\"TERM_PROGRAM\": " + jsonStr(termProgram)
                  + ", \"jline_term_type\": " + jsonStr(terminalKind) + "}}"
                : capNotMeasured("TERM_PROGRAM=" + termProgram + " not in JLine shim allowlist");

        StringBuilder out = new StringBuilder(2048);
        out.append("{\n");
        out.append("  \"schema_version\": ").append(jsonStr(SCHEMA_VERSION)).append(",\n");
        out.append("  \"run\": ").append(envelopeJson).append(",\n");
        out.append("  \"lib\": {\"name\": ").append(jsonStr(LIB_NAME))
                .append(", \"version\": ").append(jsonStr(LIB_VERSION))
                .append(", \"language\": \"java\", \"tier\": \"passive\"},\n");
        out.append("  \"capabilities\": {\n");
        out.append("    \"tty_stdin\":  {\"supported\": false},\n");
        out.append("    \"tty_stdout\": ").append(ttyCap).append(",\n");
        out.append("    \"tty_stderr\": {\"supported\": false},\n");
        out.append("    \"color_depth\": ").append(colorCap).append(",\n");
        out.append("    \"windows_console_color\": {\"supported\": false},\n");
        out.append("    \"dimensions\": ").append(dimCap).append(",\n");
        out.append("    \"unicode\": {\"supported\": false},\n");
        out.append("    \"terminal_kind\": ").append(kindCap).append(",\n");
        out.append("    \"multiplexer\": {\"supported\": false},\n");
        out.append("    \"theme\": {\"supported\": false},\n");
        out.append("    \"background\": {\"supported\": false},\n");
        out.append("    \"hyperlinks\": {\"supported\": false},\n");
        out.append("    \"mouse\": {\"supported\": false},\n");
        out.append("    \"keyboard\": {\"supported\": false},\n");
        out.append("    \"clipboard_osc52\": {\"supported\": false},\n");
        out.append("    \"graphics_sixel\": {\"supported\": false},\n");
        out.append("    \"graphics_kitty\": {\"supported\": false},\n");
        out.append("    \"xtversion\": {\"supported\": false},\n");
        out.append("    \"da1_attributes\": {\"supported\": false},\n");
        out.append("    \"ci_detected\": {\"supported\": false}\n");
        out.append("  }\n");
        out.append("}\n");

        try (FileWriter w = new FileWriter(outputPath)) {
            w.write(out.toString());
        }

        System.err.println("jline-shim: wrote " + outputPath
                + " (color=" + colorValue + " cols=" + (size != null ? size.getColumns() : "?")
                + " kind=" + kindValue + " tty=" + (!isDumb) + ")");

        terminal.close();
    }
}
