# Reference

Reference documentation is **information-oriented** and provides technical descriptions of the API and specifications.

## API Reference

- **[Detection API](api-detection.md)**
  Core detection functions (Detect, Is_Terminal, Color_Level, Size)

- **[Termicap.Capabilities](termicap-capabilities.md)**
  Aggregated capability record — `Terminal_Capabilities` type, `Assemble` (pure, SPARK Silver), `Detect` (fresh), `Get` (cached, thread-safe)

- **[Termicap.Color](termicap-color.md)**
  Color level detection — `Color_Level` type, `Detect_Color_Level` function, 11-step cascade, environment variable reference

- **[Termicap.Downsampling](downsampling.md)**
  Color downsampling — `RGB`, `Color_Index_256`, `Color_Index_16`, `Downsampled_Color` types; `Downsample` dispatch functions; SPARK Gold

- **[Termicap.OSC / Termicap.OSC.Parsing](osc.md)**
  OSC probe session lifecycle — `Probe_Session` (RAII), `Sentinel_Query`, `Timed_Read`, DA1 parsing (`Parse_DA1_Response`), multiplexer passthrough wrapping (`Wrap_For_Passthrough`)

- **[Termicap.XTVERSION / Termicap.XTVERSION.IO](xtversion.md)**
  Active terminal identification via XTVERSION — `XTVERSION_Result` discriminated record, `CSI_XTVERSION_QUERY` constant, DCS response parsing (`Parse_XTVERSION_Response`), I/O procedure (`Query_XTVERSION`), convenience function (`Query_And_Identify`)

- **[Termicap.Keyboard / Termicap.Keyboard.IO](keyboard.md)**
  Kitty Keyboard Protocol detection — `Keyboard_Protocol` enum, `Kitty_Flags` record, `Keyboard_Capability` result; pure SPARK Silver parsers (`Parse_Kitty_Response`, `Parse_Kitty_Flags`, `Parse_XTerm_Keyboard_Response`); cached entry point (`Detect_Keyboard_Protocol`) and uncached variant (`Probe_Keyboard_Protocol`) implementing the Win32 → Kitty → XTerm → Legacy cascade

- **[Termicap.Terminfo / Termicap.Terminfo.IO](terminfo.md)**
  Terminfo database parsing — `Terminfo_Snapshot` result record, `Terminfo_Result` discriminated type, SPARK Silver binary parser (`Parse_Buffer`, `Detect_Format`, `Parse_Header`, `Get_Numeric`, `Get_String`, `Extract_Truecolor_Flags`), POSIX file I/O entry point (`Parse_Terminfo`, `Read_File`)

- **[Termicap.Wcwidth](termicap-wcwidth.md)**
  wcwidth() probing for Unicode level — `Wcwidth_Level` enumeration (`Unknown`, `Unicode_3`, `Unicode_13`, `Unicode_16`), `Optional_Wcwidth_Level` cache type, sentinel constants (`WCW_SENTINEL_UNI3/13/16`), `Probe_Wcwidth_Level` (FFI, cached, locale guard), pure `Refine_Unicode_Level` (SPARK Silver, upgrade-only)

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
