# Development guide

## Repository layout

```text
.
├── README.md
├── bin/                       Executable entry point
├── compat/                    Legacy development launchers
├── docs/                      Architecture and contributor documentation
├── install.sh                 User-prefix installer
├── lib/netwtop/               Shell and awk implementation modules
│   ├── backends/              OS-specific process attribution
│   └── ui/                    Interactive table renderer
├── netwtop                    Run-from-checkout launcher
└── tests/
    ├── fixtures/              Deterministic TSV renderer inputs
    └── smoke.sh               Offline regression suite
```

The layout mirrors the installed prefix: `bin/netwtop` loads modules from
`lib/netwtop`. The root `netwtop` file only points a development checkout at
that install-style tree.

Packaging and repository publication are documented separately in
[`APT_PACKAGING.md`](APT_PACKAGING.md).

## Running from a checkout

```sh
./netwtop
./netwtop --help
```

The legacy pre-rename entry point is kept under `compat/`:

```sh
./compat/network_monitor.sh --help
```

New documentation and examples should use `netwtop`.

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
`q`. Verify that the previous terminal screen, cursor, mouse mode, and line
wrapping are restored.

Root is optional for UI development. Use it only for a final Linux attribution
check when access to other users' socket owners matters:

```sh
sudo ./netwtop
```

## Installation testing

The installer supports a staging prefix, which avoids modifying the normal
user installation:

```sh
staging_dir=$(mktemp -d)
NETWTOP_PREFIX=$staging_dir ./install.sh
$staging_dir/bin/netwtop --help
```

The installed `bin/netwtop` expects its modules in
`../lib/netwtop`. If a new runtime module is added, update all three places:

1. The module list in `bin/netwtop`.
2. The copy and permission lists in `install.sh`.
3. The shell-file list in `tests/smoke.sh`.

## Coding conventions

- Keep executable logic compatible with POSIX `sh`; do not add Bash-only
  arrays, process substitution, or `[[ ... ]]`.
- Use `LC_ALL=C` where parsing depends on stable command output or byte-oriented
  text processing.
- Keep all runtime messages and UI labels in English.
- Treat usernames and command lines as untrusted terminal input.
- Preserve the distinction between authoritative interface traffic and the
  lower application-attribution subset.
- Never invoke `sudo` or silently elevate privileges.
- Keep OS-specific parsing inside `backends/` or `interfaces.sh`.
- Avoid adding third-party runtime dependencies.

## Adding a backend

An application backend must emit one tab-separated row per observable network
entry using the common fields consumed by `accounting.sh`: stable entry key,
UID, PID, command, cumulative upload bytes, and cumulative download bytes.

When adding support for another OS:

1. Add platform detection and dependency validation in `runtime.sh`.
2. Implement default-interface selection and counter snapshots in
   `interfaces.sh`.
3. Add the application collector below `lib/netwtop/backends/`.
4. Load and install the module through `bin/netwtop` and `install.sh`.
5. Add fixture-driven parser and renderer tests.
6. Document the accounting semantics and known gaps in `README.md`.
