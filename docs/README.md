# netwtop documentation

This directory contains design, contributor, and packaging documentation for
`netwtop`.

## User documentation

The project [README](../README.md) is the primary user guide. It covers
requirements, installation, command-line options, interactive keys, dashboard
semantics, privileges, output formats, accounting behavior, and troubleshooting.

## Maintainer documentation

- [Architecture](ARCHITECTURE.md) describes the data pipeline, module
  boundaries, terminal renderer, backend scope, and interface switching model.
- [Development](DEVELOPMENT.md) describes checkout execution, offline tests,
  manual terminal checks, staged installation, coding conventions, and backend
  extension requirements.
- [Packaging](packaging/README.md) indexes Debian package and project-owned APT
  repository procedures.

All runtime UI labels and diagnostics must remain in English. Documentation may
be translated independently as long as commands, paths, and accounting
semantics remain consistent with the implementation.

