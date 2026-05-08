// Conformance shim for the `go-isatty` Go package.
//
// Single-purpose lib: isatty.IsTerminal(fd uintptr) -> bool, plus
// IsCygwinTerminal for Windows MSYS2/Cygwin PTY detection.
//
// This shim measures TTY status for all three standard streams.
// The Cygwin flag is recorded under tty_stdout's `raw` slot.

package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/mattn/go-isatty"
)

const (
	schemaVersion = "0.1.0"
	libName       = "go-isatty"
	libVersion    = "0.0.20"
)

func ttyCap(fd uintptr, name string) map[string]any {
	v := isatty.IsTerminal(fd)
	cygwin := isatty.IsCygwinTerminal(fd)
	cap := map[string]any{
		"supported": true,
		"value":     v,
		"method":    fmt.Sprintf("isatty.IsTerminal(%s.Fd()) (ioctl(TCGETS) on Unix, GetConsoleMode on Windows)", name),
	}
	if cygwin {
		cap["raw"] = map[string]any{"is_cygwin_terminal": true}
	}
	return cap
}

func main() {
	envelopePath := os.Getenv("CONFORMANCE_ENVELOPE")
	if envelopePath == "" {
		fmt.Fprintln(os.Stderr, "go-isatty-shim: $CONFORMANCE_ENVELOPE not set")
		os.Exit(2)
	}
	envelopeBytes, err := os.ReadFile(envelopePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "go-isatty-shim: read envelope: %v\n", err)
		os.Exit(2)
	}
	var envelope json.RawMessage = envelopeBytes

	outputPath := "go-isatty.json"
	if len(os.Args) > 1 {
		outputPath = os.Args[1]
	}

	result := map[string]any{
		"schema_version": schemaVersion,
		"run":            envelope,
		"lib": map[string]any{
			"name":     libName,
			"version":  libVersion,
			"language": "go",
			"tier":     "passive",
		},
		"capabilities": map[string]any{
			"tty_stdin":             ttyCap(os.Stdin.Fd(), "Stdin"),
			"tty_stdout":            ttyCap(os.Stdout.Fd(), "Stdout"),
			"tty_stderr":            ttyCap(os.Stderr.Fd(), "Stderr"),
			"color_depth":           map[string]any{"supported": false},
			"windows_console_color": map[string]any{"supported": false},
			"dimensions":            map[string]any{"supported": false},
			"unicode":               map[string]any{"supported": false},
			"terminal_kind":         map[string]any{"supported": false},
			"multiplexer":           map[string]any{"supported": false},
			"theme":                 map[string]any{"supported": false},
			"background":            map[string]any{"supported": false},
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
		fmt.Fprintf(os.Stderr, "go-isatty-shim: marshal: %v\n", err)
		os.Exit(1)
	}
	if err := os.WriteFile(outputPath, append(out, '\n'), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "go-isatty-shim: write: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "go-isatty-shim: wrote %s\n", outputPath)
}
