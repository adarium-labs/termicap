module termenv-shim

go 1.21

require github.com/muesli/termenv v0.16.0

require (
	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
	github.com/lucasb-eyer/go-colorful v1.3.0 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/rivo/uniseg v0.4.7 // indirect
	golang.org/x/sys v0.30.0 // indirect
)

replace github.com/muesli/termenv => ../../../../../reference-frameworks/termenv
