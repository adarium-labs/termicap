// Conformance shim for the termenv (Go) library.
//
// Reads the conformance envelope from $CONFORMANCE_ENVELOPE, calls the
// termenv detection APIs that are public (ColorProfile, BackgroundColor,
// HasDarkBackground), maps to canonical values, and writes one JSON
// document conforming to tools/conformance/schema/canonical.schema.json.
//
// Output path: argv[1], default "termenv.json".

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/muesli/termenv"
)

const (
	schemaVersion = "0.1.0"
	libName       = "termenv"
	libVersion    = "0.16.0"
	libLanguage   = "go"
	libTier       = "mixed"
)

func profileToCanonical(p termenv.Profile) (string, string) {
	switch p {
	case termenv.Ascii:
		return "none", "Ascii"
	case termenv.ANSI:
		return "ansi16", "ANSI"
	case termenv.ANSI256:
		return "ansi256", "ANSI256"
	case termenv.TrueColor:
		return "truecolor", "TrueColor"
	}
	return "none", "unknown"
}

// parseHexColor accepts strings like "#272822" or "rgb:2727/2828/2222" and
// returns r,g,b as integers in 0..255. Returns (0,0,0,false) on parse error.
func parseHexColor(s string) (int, int, int, bool) {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "#") && len(s) == 7 {
		r, e1 := strconv.ParseInt(s[1:3], 16, 32)
		g, e2 := strconv.ParseInt(s[3:5], 16, 32)
		b, e3 := strconv.ParseInt(s[5:7], 16, 32)
		if e1 == nil && e2 == nil && e3 == nil {
			return int(r), int(g), int(b), true
		}
	}
	return 0, 0, 0, false
}

func envIsCI() bool {
	keys := []string{"CI", "GITHUB_ACTIONS", "GITLAB_CI", "CIRCLECI",
		"TRAVIS", "BUILDKITE", "APPVEYOR", "TF_BUILD"}
	for _, k := range keys {
		if _, ok := os.LookupEnv(k); ok {
			return true
		}
	}
	return false
}

func main() {
	envelopePath := os.Getenv("CONFORMANCE_ENVELOPE")
	if envelopePath == "" {
		fmt.Fprintln(os.Stderr, "termenv-shim: $CONFORMANCE_ENVELOPE not set")
		os.Exit(2)
	}

	envelopeBytes, err := os.ReadFile(envelopePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "termenv-shim: read envelope: %v\n", err)
		os.Exit(2)
	}
	var envelope json.RawMessage = envelopeBytes // splice verbatim

	outputPath := "termenv.json"
	if len(os.Args) > 1 {
		outputPath = os.Args[1]
	}

	output := termenv.NewOutput(os.Stdout)
	colorValue, colorRaw := profileToCanonical(output.Profile)

	// Background + theme: only meaningful when termenv could actually probe.
	// When stdout is not a TTY or the probe didn't return a parseable color,
	// surface the slot as supported:false.
	bgCap := map[string]any{"supported": false}
	themeCap := map[string]any{"supported": false}

	bgColor := output.BackgroundColor()
	if rgb, ok := bgColor.(termenv.RGBColor); ok {
		hex := string(rgb)
		if r, g, b, ok2 := parseHexColor(hex); ok2 {
			bgCap = map[string]any{
				"supported": true,
				"value":     map[string]any{"rgb": []int{r, g, b}},
				"method":    "termenv.BackgroundColor() -> OSC 11 probe (when TTY)",
				"raw":       hex,
			}
			themeCap = map[string]any{
				"supported": true,
				"value": func() string {
					if output.HasDarkBackground() {
						return "dark"
					}
					return "light"
				}(),
				"method": "termenv.HasDarkBackground() -> ITU-R BT.601 luminance",
				"raw":    map[string]any{"has_dark_background": output.HasDarkBackground()},
			}
		}
	}

	result := map[string]any{
		"schema_version": schemaVersion,
		"run":            envelope,
		"lib": map[string]any{
			"name":     libName,
			"version":  libVersion,
			"language": libLanguage,
			"tier":     libTier,
		},
		"capabilities": map[string]any{
			"tty_stdin":  map[string]any{"supported": false},
			"tty_stdout": map[string]any{"supported": false},
			"tty_stderr": map[string]any{"supported": false},
			"color_depth": map[string]any{
				"supported": true,
				"value":     colorValue,
				"method":    "termenv.NewOutput(stdout).Profile (env+TTY heuristic)",
				"raw":       colorRaw,
			},
			"windows_console_color": map[string]any{"supported": false},
			"dimensions":            map[string]any{"supported": false},
			"unicode":               map[string]any{"supported": false},
			"terminal_kind":         map[string]any{"supported": false},
			"multiplexer":           map[string]any{"supported": false},
			"theme":                 themeCap,
			"background":            bgCap,
			"hyperlinks":            map[string]any{"supported": false},
			"mouse":                 map[string]any{"supported": false},
			"keyboard":              map[string]any{"supported": false},
			"clipboard_osc52":       map[string]any{"supported": false},
			"graphics_sixel":        map[string]any{"supported": false},
			"graphics_kitty":        map[string]any{"supported": false},
			"xtversion":             map[string]any{"supported": false},
			"da1_attributes":        map[string]any{"supported": false},
			"ci_detected": map[string]any{
				"supported": true,
				"value":     envIsCI(),
				"method":    "shim-side env-var allowlist scan",
			},
		},
	}

	out, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "termenv-shim: marshal: %v\n", err)
		os.Exit(1)
	}
	if err := os.WriteFile(outputPath, append(out, '\n'), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "termenv-shim: write: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "termenv-shim: wrote %s (color_depth=%s)\n",
		outputPath, colorValue)
}
