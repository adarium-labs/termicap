# Explanation

Explanation documentation is **understanding-oriented** and provides background, context, and design rationale.

## Design & Philosophy

- **[Design Philosophy](design-philosophy.md)**
  Why Termicap exists and its guiding principles

- **[Comparison with Other Libraries](comparison.md)**
  How Termicap differs from ncurses bindings, AnsiAda, etc.

## Architecture

- **[Detection Algorithm](detection-algorithm.md)**
  How the 15-step capability detection works

- **[Package Hierarchy](package-hierarchy.md)**
  How packages are organized (detection, environment, platform)

- **[Platform Abstraction](platform-abstraction.md)**
  How Unix and Windows backends are separated

## SPARK & Verification

- **[SPARK Boundaries](spark-boundaries.md)**
  Why and how we use SPARK for detection logic with Ada FFI for OS calls

- **[Proven Properties](proofs.md)**
  What properties are formally verified (Silver level)
