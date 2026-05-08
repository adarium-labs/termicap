// Conformance shim for charm.land/lipgloss/v2 (Go).
//
// Public detection surface used here:
//
//	lipgloss.BackgroundColor(stdin, stdout) -> (color.Color, error)   (OSC 11 via raw-mode + restore)
//	lipgloss.HasDarkBackground(stdin, stdout) -> bool                 (luminance over above; defaults true on err)
//
// Capability mapping:
//
//	background : OSC 11 RGB triple -> {rgb:[r,g,b]} 0-255
//	theme      : derived from luminance of the same RGB; we explicitly call BackgroundColor
//	             first to distinguish "actual dark" from HasDarkBackground's default-true-on-error.
//
// Output path: argv[1], default "lipgloss.json".
package main

import (
	"encoding/json"
	"fmt"
	"image/color"
	"os"

	"charm.land/lipgloss/v2"
)

const (
	schemaVersion = "0.1.0"
	libName       = "lipgloss"
	libVersion    = "2.0.0-beta"
	libLanguage   = "go"
	libTier       = "active"
)

// rgb8 reduces a color.Color (RGBA returns 0..0xffff per channel) to 0..255 ints.
func rgb8(c color.Color) (int, int, int) {
	r, g, b, _ := c.RGBA()
	return int(r >> 8), int(g >> 8), int(b >> 8)
}

func main() {
	envelopePath := os.Getenv("CONFORMANCE_ENVELOPE")
	if envelopePath == "" {
		fmt.Fprintln(os.Stderr, "lipgloss-shim: $CONFORMANCE_ENVELOPE not set")
		os.Exit(2)
	}

	envelopeBytes, err := os.ReadFile(envelopePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "lipgloss-shim: read envelope: %v\n", err)
		os.Exit(2)
	}
	var envelope json.RawMessage = envelopeBytes

	outputPath := "lipgloss.json"
	if len(os.Args) > 1 {
		outputPath = os.Args[1]
	}

	bgCap := map[string]any{"supported": false, "raw": "no OSC 11 response (or stdin/stdout not a tty)"}
	themeCap := map[string]any{"supported": false, "raw": "background not measured"}

	bg, err := lipgloss.BackgroundColor(os.Stdin, os.Stdout)
	if err == nil && bg != nil {
		r, g, b := rgb8(bg)
		bgCap = map[string]any{
			"supported": true,
			"value":     map[string]any{"rgb": []int{r, g, b}},
			"method":    "lipgloss.BackgroundColor (OSC 11 via raw-mode + Restore)",
		}
		// HasDarkBackground returns true on error; we already gated on err==nil here.
		isDark := lipgloss.HasDarkBackground(os.Stdin, os.Stdout)
		themeValue := "light"
		if isDark {
			themeValue = "dark"
		}
		themeCap = map[string]any{
			"supported": true,
			"value":     themeValue,
			"method":    "lipgloss.HasDarkBackground (ITU-R BT.601 luminance over OSC 11)",
		}
	} else if err != nil {
		bgCap["raw"] = err.Error()
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
			"tty_stdin":             map[string]any{"supported": false},
			"tty_stdout":            map[string]any{"supported": false},
			"tty_stderr":            map[string]any{"supported": false},
			"color_depth":           map[string]any{"supported": false},
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
			"ci_detected":           map[string]any{"supported": false},
		},
	}

	out, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "lipgloss-shim: marshal: %v\n", err)
		os.Exit(1)
	}
	if err := os.WriteFile(outputPath, append(out, '\n'), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "lipgloss-shim: write: %v\n", err)
		os.Exit(1)
	}
	bgRaw := "n/a"
	if v, ok := bgCap["value"].(map[string]any); ok {
		bgRaw = fmt.Sprintf("%v", v["rgb"])
	}
	themeRaw := "n/a"
	if v, ok := themeCap["value"].(string); ok {
		themeRaw = v
	}
	fmt.Fprintf(os.Stderr, "lipgloss-shim: wrote %s (background=%s theme=%s)\n",
		outputPath, bgRaw, themeRaw)
}
