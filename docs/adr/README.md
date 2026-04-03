# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the Termicap library.

## What is an ADR?

An Architecture Decision Record captures an important architectural decision made along with its context and consequences.

## Format

We use the [MADR](https://adr.github.io/madr/) (Markdown Any Decision Records) format.

## Naming Convention

ADRs are numbered sequentially:
- `0001-record-architecture-decisions.md`
- `0002-spark-silver-target.md`
- etc.

## Status

Each ADR has a status:
- **proposed**: Under discussion
- **accepted**: Decision has been made
- **deprecated**: Decision has been superseded
- **superseded**: Replaced by another ADR

## Index

| ID | Title | Status |
|----|-------|--------|
| [0001](0001-environment-snapshot-storage-strategy.md) | Use sparklib Unbounded_Hashed_Maps for environment snapshot storage | proposed |
| [0002](0002-multi-candidate-matching-spark-boundary.md) | Place multi-candidate matching outside the SPARK boundary | proposed |
| [0003](0003-tty-detection-package-structure.md) | TTY detection as single package with SPARK spec / Ada body | accepted |
| [0004](0004-color-detection-decomposed-helpers.md) | Color detection decomposed helpers | proposed |
| [0005](0005-force-color-value-parsing-strategy.md) | FORCE_COLOR value parsing strategy | proposed |
| [0006](0006-c-wrapper-for-ioctl-tiocgwinsz.md) | C wrapper for ioctl TIOCGWINSZ | proposed |
| [0007](0007-unicode-level-three-value-enum.md) | Unicode level three-value enum | proposed |
| [0008](0008-terminal-id-string-representation-spark-boundary.md) | Terminal ID string representation SPARK boundary | proposed |
| [0009](0009-downsampling-return-type.md) | Downsampling return type | proposed |
| [0010](0010-override-mode-flat-enum.md) | Five-literal flat enum for Override_Mode | proposed |
