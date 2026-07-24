# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

------

## [Unreleased]

### Added

- Add live Left/Right interface switching with stable interface enumeration,
  wraparound navigation, and a visible `[current/total]` device index.
- Add explicit `USER DATA: ALL INTERFACES`,
  `ALL-INTERFACE USER TRAFFIC`, and `ACCOUNTED (ALL IFACES)` labels when the
  process backend cannot filter application counters by the selected device.
- Add regression coverage for interface switching, safe rebaselining,
  all-interface scope labels, responsive frame widths, and white table borders.
- Add a documentation index and a dedicated `docs/packaging/` section.

### Changed

- Reorganize runtime sources into responsibility-based `src/core/`,
  `src/runtime/`, `src/backends/`, `src/output/`, and `src/ui/` directories.
- Add `src/manifest.sh` as the single ordered inventory shared by the module
  loader, installer, and test suite while retaining `$PREFIX/lib/netwtop/` as
  the installed module location.
- Rewrite the README around Features, Requirements, Installation, Usage,
  Keybindings, Dashboard Semantics, Accounting, Development, Changelog, and
  License sections.
- Standardize the Apache license filename from `LICENCE` to `LICENSE`.
- Render table borders and the Upload/Download divider in white while retaining
  the existing colors for titles, rates, warnings, and highlighted rows.
- Reset selected-interface history and refresh both collector baselines after
  an interface switch so global process deltas are not inflated by the extra
  wait interval.
- Remove only the known obsolete flat module files after a successful install
  of the new responsibility-based module tree.

### Fixed

- Prevent a false interface-rate spike caused by subtracting counters from two
  different devices after live switching.
- Prevent a down or idle selected interface from visually implying that the
  all-interface user rows belong to that device.

------

## [0.1.0] - 2026-07-23

### Added

- Add the initial POSIX shell and `awk` implementation for Linux and macOS.
- Add authoritative per-interface Upload/Download rates from operating-system
  byte counters.
- Add Linux TCP user/command attribution through `ss` and macOS process
  attribution through the built-in `nettop` command.
- Add a responsive nvitop-inspired terminal dashboard with in-place repainting,
  rolling Braille histories, fixed per-user command viewports, and compact,
  full, and automatic display modes.
- Add stable lexical user ordering, `root`-first placement, live traffic ranks,
  PID/command rows, checked-user mode, keyboard navigation, mouse navigation,
  and user/command scrolling.
- Add decimal sampling intervals from 0.1 seconds, with a 0.5-second default.
- Add CSV and JSONL output, bounded session totals, output-file replacement,
  and explicit append mode for machine-readable formats.
- Add a user-prefix installer, compatibility launcher, modular executable and
  runtime tree, architecture/development documentation, and an
  offline fixture-driven smoke-test suite.
- Add detailed Debian package and self-hosted APT repository guidance.
- Add dual licensing under Apache-2.0 or GPL-3.0.

------

[Unreleased]: https://github.com/DoubleFlicker7/netwtop/compare/63b5d2d...HEAD
[0.1.0]: https://github.com/DoubleFlicker7/netwtop/tree/63b5d2d
