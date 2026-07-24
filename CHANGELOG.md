# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

------

## [Unreleased]

### Changed

- Use gray for user identity fields while preserving green Upload and blue
  Download values and histories in both responsive table layouts.
- Restrict aggregate attribution to `root`, the current/invoking user, and UIDs
  at or above the platform's regular-user threshold.
- Show command details for all visible regular users only when running as root;
  normal users now see their own commands while retaining other users' totals.
- Prefer the effective process UID over the socket UID whenever Linux exposes a
  PID, so commands launched through `sudo` are charged to root.

### Fixed

- Prevent system service accounts such as `_apt` and `systemd-resolve` from
  appearing as users when root can inspect their sockets.
- Prevent normal users from seeing other users' command lines or misleading
  cross-user `[unattributed]` command rows.
- Resolve the session label from the effective identity instead of a possibly
  stale `USER` variable, and retain the current user's zero-traffic row when no
  observable socket exists.

------

## [0.1.0] - 2026-07-24

### Added

- Add the first public release of `netwtop`.
- Add the POSIX shell and `awk` implementation for Linux and macOS.
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
- Add live Left/Right interface switching with stable interface enumeration,
  wraparound navigation, and a visible `[current/total]` device index.
- Add explicit `USER DATA: ALL INTERFACES`,
  `ALL-INTERFACE USER TRAFFIC`, and `ACCOUNTED (ALL IFACES)` labels when the
  process backend cannot filter application counters by the selected device.
- Add a user-prefix installer, modular executable and runtime tree,
  architecture/development documentation, and an offline fixture-driven
  smoke-test suite.
- Add regression coverage for interface switching, safe rebaselining,
  all-interface scope labels, responsive frame widths, and white table borders.
- Add a documentation index and a dedicated `docs/packaging/` section.
- Add detailed Debian package and self-hosted APT repository guidance.
- Add dual licensing under Apache-2.0 or GPL-3.0.

### Changed

- Reorganize runtime sources into responsibility-based `src/core/`,
  `src/runtime/`, `src/backends/`, `src/output/`, and `src/ui/` directories.
- Add `src/manifest.sh` as the single ordered inventory shared by the module
  loader, installer, and test suite while retaining `$PREFIX/lib/netwtop/` as
  the installed module location.
- Rewrite the README around Features, Requirements, Installation, Usage,
  Keybindings, Dashboard Semantics, Accounting, Development, Changelog, and
  License sections.
- Reformat the README badges and expand its table of contents for easier
  navigation.
- Split the command-line option reference into separate `Short option` and
  `Long option` columns.
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

### Removed

- Remove the legacy `compat/network_monitor.sh` launcher; `netwtop` is now the
  only supported command name.

------

[Unreleased]: https://github.com/DoubleFlicker7/netwtop/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DoubleFlicker7/netwtop/releases/tag/v0.1.0
