# Reference

Reference documentation is **information-oriented** and provides technical descriptions of the API and specifications.

## API Reference

- **[Detection API](api-detection.md)**
  Core detection functions (Detect, Is_Terminal, Color_Level, Size)

- **[Termicap.Color](termicap-color.md)**
  Color level detection — `Color_Level` type, `Detect_Color_Level` function, 11-step cascade, environment variable reference

- **[Termicap.Dimensions](termicap-dimensions.md)**
  Terminal dimensions detection — `Terminal_Size` type, `Get_Size` function, ioctl/env-var/default fallback chain

- **[Termicap.Environment](termicap-environment.md)**
  Environment snapshot type, query/builder API, SPARK contracts, and the `Capture` child package

- **[Environment API](api-environment.md)**
  Environment variable parsing and query (legacy placeholder)

- **[Standards API](api-standards.md)**
  NO_COLOR / FORCE_COLOR compliance functions

- **[Platform API](api-platform.md)**
  Platform-specific backends (Unix, Windows)

## Types

- **[Core Types](types.md)**
  Color_Support, Terminal_Size, Capabilities, Stream_Kind

- **[Result Types](results.md)**
  Functional Result types for error handling

## Specifications

- **[Supported Standards](standards.md)**
  NO_COLOR, FORCE_COLOR, ECMA-48 SGR compliance

- **[Detection Priority](detection-priority.md)**
  The 15-step detection algorithm reference

## Configuration

- **[Alire Configuration](alire.md)**
  Package configuration and dependencies

- **[SPARK Configuration](spark-config.md)**
  Formal verification setup (Silver target)
