# Development guide

## Repository layout

```text
.
├── README.md
├── bin/                       Executable entry point
├── docs/                      User, architecture, and contributor documentation
│   └── packaging/            Debian and APT publication guides
├── install.sh                 User-prefix installer
├── src/                       Shell and awk implementation modules
│   ├── backends/              OS-specific process attribution
│   ├── core/                  Counters, aggregation, and history
│   ├── output/                Machine-readable serializers
│   ├── runtime/               CLI, terminal lifecycle, and input
│   ├── ui/                    Interactive table renderer
│   └── manifest.sh            Ordered module and resource manifest
├── netwtop                    Run-from-checkout launcher
└── tests/
    ├── fixtures/              Deterministic TSV renderer inputs
    └── smoke.sh               Offline regression suite
```

The source tree is grouped by responsibility rather than by its eventual FHS
destination. In a checkout, `bin/netwtop` discovers `src/manifest.sh`. After
installation it discovers the same manifest below `../lib/netwtop`. The root
`netwtop` file is only a development launcher.

Packaging is documented in
[`packaging/APT_PACKAGING.md`](packaging/APT_PACKAGING.md).

## Running from a checkout

```sh
./netwtop
./netwtop --help
```

The supported command name is `netwtop`; no legacy command alias is installed
or maintained.

## Automated tests

Run the complete offline suite without root or network access:

```sh
./tests/smoke.sh
```

The suite checks:

- POSIX shell syntax and option validation.
- The 0.1-second minimum interval and 0.5-second default.
- Compact, Full, and Auto layouts.
- The Upload/Download width breakpoint.
- Exact frame width across terminal sizes from 78 to 240 columns.
- User pagination, command scrolling, mouse hit maps, and checked-user mode.
- Context-aware Up/Down highlight navigation for users and commands.
- Left/Right interface switching and safe counter rebaselining.
- Terminal-safe command text and UTF-8 graph alignment.
- Rolling-history retention and CSV/JSONL behavior.

Files in `tests/fixtures/` are the common tab-separated schemas consumed by the
AWK renderer. Prefer adding a small deterministic fixture and assertion for a
layout regression instead of depending on live traffic.

## Manual terminal checks

Automated frame tests cannot fully emulate every terminal. For renderer changes,
also verify these cases in a real terminal:

```sh
./netwtop --interval 0.5
./netwtop --mode compact
./netwtop --mode full
./netwtop --two-column-width 120
```

Resize across the breakpoint, shrink below the available user height, scroll
both the table and command viewports, check and uncheck a user, and quit with
`q`. Use Left/Right to cycle physical, virtual, and loopback interfaces and
verify that the device index and interface history reset without a rate spike.
Verify that the previous terminal screen, cursor, mouse mode, and line
wrapping are restored.

Root is optional for UI development. Use it only for a final Linux attribution
check when access to other users' socket owners matters:

```sh
sudo ./netwtop
```

Compare both permission modes before a release. A normal run must retain other
regular users' aggregate rows without exposing their commands. A root run must
retain commands for all visible regular users, and a transfer process launched
through `sudo` must appear under UID 0.

## Installation testing

The installer supports a staging prefix, which avoids modifying the normal
user installation:

```sh
staging_dir=$(mktemp -d)
NETWTOP_PREFIX=$staging_dir ./install.sh
$staging_dir/bin/netwtop --help
```

The installed `bin/netwtop` expects its module tree in `../lib/netwtop`.
`src/manifest.sh` is the single ordered inventory used by the loader, installer,
and syntax tests. When adding a module, add its relative path to
`NETWTOP_RUNTIME_MODULES`; non-shell renderer resources belong in
`NETWTOP_RESOURCE_FILES`.

## Coding conventions

- Keep executable logic compatible with POSIX `sh`; do not add Bash-only
  arrays, process substitution, or `[[ ... ]]`.
- Use `LC_ALL=C` where parsing depends on stable command output or byte-oriented
  text processing.
- Keep all runtime messages and UI labels in English.
- Treat usernames and command lines as untrusted terminal input.
- Preserve the distinction between authoritative interface traffic and the
  lower application-attribution subset.
- Preserve both visibility filters: aggregate rows include `root`, the
  current/invoking UID, and regular-account UIDs; command rows include all of
  those only for root and otherwise include the current effective UID alone.
- Resolve runtime identity through `id`; do not use inherited `USER`, `LOGNAME`,
  or home-directory names for attribution or session labels.
- Never invoke `sudo` or silently elevate privileges.
- Keep OS-specific process parsing inside `src/backends/` and interface-counter
  logic inside `src/core/interfaces.sh`.
- Avoid adding third-party runtime dependencies.

## Adding a backend

An application backend must emit one tab-separated row per observable network
entry using the common fields consumed by `accounting.sh`: stable entry key,
UID, PID, command, cumulative upload bytes, and cumulative download bytes.

When adding support for another OS:

1. Add platform detection and dependency validation in
   `src/runtime/runtime.sh`.
2. Implement default-interface selection and counter snapshots in
   `src/core/interfaces.sh`.
3. Add the application collector below `src/backends/`.
4. Add the module to `src/manifest.sh` in dependency order.
5. Add fixture-driven parser and renderer tests.
6. Document the accounting semantics and known gaps in `README.md`.
