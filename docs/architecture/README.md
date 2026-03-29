# Architecture Documentation

This directory contains architecture documentation for Termicap following arc42 (lite) template.

## Structure

| Document | arc42 Section | Description |
|----------|---------------|-------------|
| [01-context.md](01-context.md) | Section 3 | System context, scope, and ecosystem position |
| [02-constraints.md](02-constraints.md) | Section 2 | Technical and organizational constraints |
| [03-building-blocks.md](03-building-blocks.md) | Section 5 | Static structure, packages, SPARK boundary layers |
| [04-runtime-view.md](04-runtime-view.md) | Section 6 | Runtime behavior, detection flow, FFI boundaries |
| [05-deployment-view.md](05-deployment-view.md) | Section 7 | Alire packages, build system, CI/CD |

## About arc42

[arc42](https://arc42.org/) is a template for architecture documentation. We use a "lite" version with 5 key sections instead of the full 12.

## Related Documentation

- **Requirements**: See `../requirements/` for what the library must do
- **ADRs**: See `../adr/` for why architectural decisions were made
- **User Guide**: See `../guide/` for how to use the library
