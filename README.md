# netwtop

`netwtop` is an interactive per-user network traffic monitor for Linux and
macOS. It shows authoritative interface Upload/Download rates, rolling history,
traffic attributed to each local user, and the commands responsible for that
traffic.

The implementation uses POSIX shell, `awk`, and operating-system interfaces. It
contains no Python code, installs no packages, does not invoke another
third-party network monitor, and never attempts to elevate its own privileges.
All program output is in English.

## Highlights

- Interface Upload and Download rates derived from kernel-maintained counters.
- Per-user and per-command traffic attribution with PID and command line.
- Stable lexical user order with `root` pinned first and a live traffic rank.
- nvitop-inspired interactive UI with in-place differential repainting.
- Responsive wide and narrow layouts with a configurable width breakpoint.
- Rolling Braille history for interface, per-user, and accounted traffic.
- Keyboard and mouse navigation, fixed command viewports, and checked-user mode.
- CSV and JSONL output for automation.
- 0.1-second minimum interval, equivalent to a maximum refresh rate of 10 Hz.
- User-level installation under `$HOME/.local` by default.

## Contents

- [Platform support and requirements](#platform-support-and-requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Command-line options](#command-line-options)
- [Interactive controls](#interactive-controls)
- [Understanding the dashboard](#understanding-the-dashboard)
- [Responsive layout](#responsive-layout)
- [Privileges and cross-user visibility](#privileges-and-cross-user-visibility)
- [Output formats](#output-formats)
- [Accounting model](#accounting-model)
- [Comparison with nload](#comparison-with-nload)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Project structure and development](#project-structure-and-development)

## Platform support and requirements

`netwtop` explicitly supports Linux and macOS. Network accounting is not fully
portable across Unix families because each kernel exposes different counters.

### Linux

Required commands and interfaces:

- A POSIX-compatible shell.
- `awk`, `sort`, `cut`, `ps`, `date`, `sleep`, `mktemp`, `wc`, `cat`, `mv`,
  `rm`, `rmdir`, `stty`, and `dd` for interactive mode.
- `ss` from iproute2 for socket and process attribution.
- Readable `/sys/class/net/<interface>/statistics/{rx,tx}_bytes`, with
  `/proc/net/dev` as the interface-counter fallback.

Linux interface totals use the same kernel interface-byte sources commonly
used by tools such as nload. Application detail uses visible TCP socket counters
reported by `ss` in the current network namespace.

### macOS

Required commands:

- A POSIX-compatible shell and standard Unix utilities.
- Built-in `/usr/sbin/netstat`, `/sbin/route`, and `/sbin/ifconfig` for interface
  discovery and counters.
- Built-in `/usr/bin/nettop` for per-process TCP/UDP byte counters.

The project command is named `netwtop` with a `w`; it does not conflict with the
macOS system command `nettop`.

### Terminal size

The interactive dashboard requires at least 78 columns and 20 rows. Smaller
terminals show a resize message instead of drawing a partial table.

## Installation

### Run directly from the checkout

No installation is required for development or a quick test:

```sh
./netwtop
```

### Install for the current user

The installer copies the executable and module tree into `$HOME/.local`:

```sh
./install.sh
netwtop
```

If `$HOME/.local/bin` is not already in `PATH`, add it in the startup file for
your shell:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

The installed files are:

```text
$HOME/.local/bin/netwtop
$HOME/.local/lib/netwtop/
```

### Install to another prefix

Set `NETWTOP_PREFIX` to choose another destination:

```sh
NETWTOP_PREFIX=/opt/netwtop ./install.sh
```

The prefix must be writable. Installing to a system directory may require an
administrator shell, but running the installer as root is not required for the
normal user-level installation.

## Quick start

```sh
# Start the live dashboard with the default 0.5-second interval
netwtop

# Monitor a specific interface
netwtop --device eth0

# Refresh at 10 Hz, the supported maximum
netwtop --interval 0.1

# Produce five reports and exit
netwtop --interval 1 --count 5

# Force the compact or full display mode
netwtop --mode compact
netwtop --mode full

# Switch to the wide Upload/Download layout at 120 columns
netwtop --two-column-width 120

# Write machine-readable reports
netwtop --format csv --output network-usage.csv
netwtop --format jsonl --output network-usage.jsonl

# Show the built-in help
netwtop --help
```

For complete cross-user process attribution on Linux, run the installed command
with administrator privileges:

```sh
sudo "$HOME/.local/bin/netwtop"
```

Some `sudo` configurations do not preserve the user's `PATH`, so an absolute
path is more reliable.

## Command-line options

| Option | Default | Description |
| --- | --- | --- |
| `-i SECONDS`, `--interval SECONDS` | `0.5` | Sampling interval in decimal seconds. Values must use 0.1-second steps and be at least `0.1`; the maximum refresh rate is 10 Hz. |
| `-d INTERFACE`, `--device INTERFACE` | Default-route interface | Interface used for the authoritative top-level RX/TX counters. On Linux, the first non-loopback interface is used if no default route is found. macOS uses the interface from the default route, then the first non-loopback interface. |
| `-n NUMBER`, `--count NUMBER` | Unlimited | Stop after this many reports. `NUMBER` must be a positive integer. The initial baseline snapshot is not a report. |
| `-m MODE`, `--mode MODE` | `auto` | Select `auto`, `compact`, or `full`. Auto expands history only when the terminal has enough height. Compact prioritizes visible users and commands. Full requests detailed graphs but safely degrades if the window is too small. |
| `--two-column-width N` | `100` | Terminal-width breakpoint for the wide Upload/Download layout. At or above `N`, each user has separate side-by-side Upload and Download panels. Below `N`, users use the compact table layout. Users themselves always remain one vertical list. |
| `-f FORMAT`, `--format FORMAT` | `table` | Output format: `table`, `csv`, or `jsonl`. Table is interactive when no output file is specified. |
| `-o FILE`, `--output FILE` | Standard output | Write reports to `FILE`. Table mode replaces the file on every sample so it contains only the latest frame. CSV and JSONL write report history for the current run. |
| `--append` | Disabled | Append CSV or JSONL records to an existing output file. This option requires `--output` and is rejected for table output. A CSV header is added only when the target is empty. |
| `-h`, `--help` | — | Print usage, options, interactive keys, backend information, and privilege guidance, then exit. |

Invalid options fail before sampling begins. Examples include an interval below
`0.1`, a zero count, an unknown mode or format, a nonexistent interface, and
`--append` without a CSV/JSONL output file.

## Interactive controls

Interactive controls do not require Enter.

| Key or action | Effect |
| --- | --- |
| `q`, `Q` | Quit and restore the previous terminal screen, cursor, mouse mode, and input settings. |
| `r`, `R` | Refresh immediately. |
| `+`, `=` | Reduce the interval by 0.1 seconds, down to 0.1 seconds. |
| `-` | Increase the interval by 0.1 seconds. |
| `a` | Switch to Auto mode. |
| `c` | Switch to Compact mode. |
| `f` | Switch to Full mode. |
| `Up`, `k` | Scroll the user table up, or scroll commands in checked-user mode. |
| `Down`, `j` | Scroll the user table down, or scroll commands in checked-user mode. |
| `PageUp`, `PageDown` | Move by the current visible user or command page. |
| `[`, `]` | Scroll the selected user's fixed command viewport. |
| `Space`, `x` | Check or uncheck the selected user. |
| Mouse click | Select a command, or check/uncheck a user by clicking its user row. |
| Mouse wheel | Scroll the command viewport under the pointer; otherwise scroll the user table. |

Only one user can be checked at a time. A checked user occupies the complete
lower panel and shows all commands observed for that user during the current
session, including commands that are currently idle. Clicking the `[x]` row or
pressing `Space`/`x` again restores the normal multi-user view.

## Understanding the dashboard

### Interface panel

The top panel reports:

- Hostname and selected network interface.
- Backend and current refresh interval.
- Current interface Upload and Download rates.
- Independent rate bars with a fixed 128 MiB/s scale.
- Rolling directional history and visible maximum rates.
- Number of users and commands observed by the attribution backend.
- PID attribution percentage.

When a current rate exceeds 128 MiB/s, its bar remains full and the value is
shown as `MAX`. The underlying machine-readable rate is not capped.

### User panel

Users are ordered predictably:

1. `root` is pinned to the first row when present.
2. All other users use C-locale lexical username order.
3. Order does not change when traffic changes.

The prefix `[rank/users]` is independent of display order. For example,
`[1/4]` means the user currently ranks first by combined Upload and Download
among four displayed session users.

Each user block includes:

- Username and UID.
- Current Upload and Download rates.
- Per-direction rolling history.
- `ACTIVE`, the number of socket or process entries currently observed for that
  user by the platform backend. It is a count, not a percentage or rate.
- A fixed two-slot command viewport in the normal interactive view.

Each command row includes its PID, command line, current Upload/Download rates,
and active-entry count. Commands with traffic during the current interval are
shown in the normal view. Checked-user mode also includes commands observed
earlier in the current session.

`PID -` means the operating system did not expose a process owner for that
traffic. `[unattributed]` groups traffic that could not be assigned to a visible
command. This is expected for other users when running without root on many
Linux systems.

### ACCOUNTED row

The highlighted `ACCOUNTED` footer is the sum of application traffic assigned
to the displayed user data. It is not the selected interface's total traffic.

The two figures can differ because interface counters also contain protocol
overhead, retransmissions, UDP or non-TCP traffic not exposed by the Linux
backend, short-lived connections, inaccessible processes, and traffic outside
the backend's attribution scope. Compare other interface monitors with the top
panel, not with `ACCOUNTED`.

## Responsive layout

Width and height are evaluated independently.

At the default breakpoint of 100 columns or wider:

- Users remain one full-width vertical list.
- Each user has an identity row followed by an Upload panel on the left and a
  Download panel on the right.
- Compact mode gives each direction a one-line history sparkline.
- Full mode expands both directions into matching multi-line graphs.

Below the breakpoint:

- Each user uses the compact full-width table row.
- Upload and Download remain separate numeric columns.
- Detailed history panels stack vertically when enough height is available.

Use `--two-column-width N` to change the breakpoint. Resizing across it causes a
single geometry rebuild; normal samples continue to update only changed rows.

Auto mode first compacts per-user history, then compacts top-level history if
needed. If every fixed-height user block still cannot fit, the title reports the
visible range, such as `Users 1-6/12`, and the remaining users are available by
keyboard or mouse scrolling. A resize never converts users into a two-user grid.

The monitor retains the latest 120 samples. Braille cells encode two adjacent
time samples horizontally and four sub-levels vertically. The visible graph
bound is 1.25 times the visible peak, clamped between 64 KiB/s and 128 MiB/s.
History exists only for the current `netwtop` session.

## Privileges and cross-user visibility

`netwtop` never runs `sudo`, prompts for a password, or changes its privileges.

Without root:

- Interface totals are usually fully available.
- The invoking user's attributable PIDs and commands are normally visible.
- Hardened systems may restrict even more process or socket information.
- Other users' inaccessible process traffic is grouped under
  `[unattributed]` with `PID -`.

With root on Linux:

- `ss -p` can normally expose process owners for sockets belonging to all users
  in the current network namespace.
- The UI can therefore display substantially more complete cross-user PID and
  command attribution.

Root does not remove fundamental sampling limits: very short-lived connections
can still start and exit between snapshots, shared sockets cannot always be
divided exactly among processes, and other network namespaces remain outside
the current namespace.

Command lines may contain tokens, URLs, or other application arguments. Treat
terminal captures, CSV files, and JSONL files as potentially sensitive.

## Output formats

### Live table

```sh
netwtop --format table
```

With no `--output`, table mode requires a controlling terminal and updates the
same screen in place. It uses an alternate screen when supported and restores
the previous screen on exit. If stdout is captured but `/dev/tty` is available,
the dashboard writes to `/dev/tty`.

To maintain a plain-text file containing only the latest snapshot:

```sh
netwtop --format table --output current-netwtop.txt
```

The file is replaced on every report; table mode never appends historical
frames.

### CSV

```sh
netwtop --format csv --output network-usage.csv
netwtop --format csv --output network-usage.csv --append
```

Each sample starts with one `record_type="interface"` row, followed by one
`record_type="user"` row per session user. The columns are:

```text
timestamp
interval_seconds
backend
scope
username
uid
upload_bytes_per_second
download_bytes_per_second
upload_bytes_total
download_bytes_total
active_entries
record_type
device
interface_upload_bytes_per_second
interface_download_bytes_per_second
```

Interface rows leave user-specific values empty. User rows repeat the interface
rates so a single row remains self-describing.

### JSONL

```sh
netwtop --format jsonl --output network-usage.jsonl
netwtop --format jsonl --output network-usage.jsonl --append
```

JSONL writes one object per sample. Each object contains timestamp, interval,
backend, scope, device, authoritative interface rates, active-entry count, and a
`users` array. Each user object contains username, UID, current rates, cumulative
session bytes, and active-entry count.

Cumulative application byte totals start at zero when `netwtop` starts. Traffic
before the initial snapshot is not counted. Cumulative totals are included in
CSV and JSONL but intentionally omitted from the live dashboard.

## Accounting model

### Interface totals

The top panel and top-level CSV/JSONL fields are derived from consecutive byte
counter snapshots for the selected interface:

```text
rate = (current counter - previous counter) / actual elapsed time
```

Counter resets or rollbacks are treated as a zero delta for that sample.

### Linux application attribution

Linux uses `ss -tinepH` and tracks the cumulative TCP values exposed for visible
sockets:

- Upload uses acknowledged application bytes.
- Download uses received application bytes.
- Process data comes from `ss -p` and command lines are resolved through `ps`.
- Attribution covers visible TCP connections across interfaces in the current
  network namespace; it is therefore labeled `all interfaces` in the UI.

This application view does not include the same byte categories as interface
RX/TX counters and is not presented as selected-interface coverage.

### macOS application attribution

macOS runs the built-in `nettop` in per-process CSV mode and uses its
`bytes_in`/`bytes_out` counters for TCP and UDP. PID command lines are resolved
through `ps` when available. Because this data cannot be reliably restricted to
the selected interface, it is also labeled as all-interface application detail.

## Comparison with nload

Use the same interface, unit, and interval:

```sh
nload -t 1000 -u B eth0
netwtop --interval 1 --device eth0
```

On Linux, both top-level monitors derive rates from kernel interface byte
counters. Instantaneous values can differ briefly because the two programs do
not sample at exactly the same time; sustained-transfer rates should converge.

For automated comparison, use:

- `interface_upload_bytes_per_second`
- `interface_download_bytes_per_second`

Do not compare nload with the lower `ACCOUNTED` row, which is only the
application-attribution subset.

## Known limitations

- Linux application attribution is TCP-focused; authoritative interface totals
  still include all traffic counted by the interface.
- Connections or processes that exist entirely between two snapshots may be
  missed.
- Only the current Linux network namespace is visible.
- A socket shared by several processes may be assigned to the first owner
  reported by the operating system.
- Process attribution and interface totals may cover different interface sets.
- Root improves access to socket owners but cannot make sampled shell-based
  accounting equivalent to administrator-configured eBPF, cgroup, or firewall
  accounting.
- FreeBSD, OpenBSD, AIX, and other Unix families require new interface and
  application backends.

Complete wire-level accounting by UID—including packet headers,
retransmissions, every UDP flow, and very short-lived traffic—cannot be provided
reliably by an unprivileged cross-platform shell program.

## Troubleshooting

### `Error: Interval must be at least 0.1 seconds...`

Use one decimal place and a value of at least `0.1`:

```sh
netwtop --interval 0.5
```

### `Linux backend requires the ss command from iproute2`

Install or expose the operating system's iproute2 `ss` command. `netwtop` does
not install dependencies itself.

### Other users show `[unattributed]` or `PID -`

This normally means the invoking user cannot inspect those socket owners. Run
with root only when complete cross-user attribution is required and permitted.

### nload shows more traffic than user rows

Compare nload with the top interface panel. The lower user rows and `ACCOUNTED`
exclude traffic that the process backend cannot observe or attribute.

### Some users are not visible in a short window

Read the `Users first-last/total` range in the lower title and scroll with
`j`/`k`, the arrow keys, PageUp/PageDown, or the mouse wheel. Compact mode can
fit more users:

```sh
netwtop --mode compact
```

### The command is not found after installation

Run the installed absolute path or add the prefix's `bin` directory to `PATH`:

```sh
$HOME/.local/bin/netwtop
export PATH="$HOME/.local/bin:$PATH"
```

## Project structure and development

```text
.
├── README.md
├── bin/netwtop                  Main orchestration entry point
├── compat/network_monitor.sh    Legacy development launcher
├── docs/
│   ├── ARCHITECTURE.md          Data flow and module boundaries
│   └── DEVELOPMENT.md           Contributor workflow and conventions
├── install.sh                   User-prefix installer
├── lib/netwtop/
│   ├── accounting.sh            Deltas, cumulative totals, and ordering
│   ├── backends/                Linux/macOS application collectors
│   ├── formats.sh               CSV and JSONL output
│   ├── history.sh               Rolling sample history
│   ├── interfaces.sh            Interface selection and RX/TX counters
│   ├── runtime.sh               Options, terminal lifecycle, and input
│   └── ui/                      Responsive frame renderer
├── netwtop                      Run-from-checkout launcher
└── tests/
    ├── fixtures/                Deterministic renderer fixtures
    └── smoke.sh                 Offline regression suite
```

See [Architecture](docs/ARCHITECTURE.md) for the data pipeline and renderer
invariants. See [Development guide](docs/DEVELOPMENT.md) for testing, coding
conventions, staging installation, and backend extension instructions.

Run all offline checks with:

```sh
./tests/smoke.sh
```

The interface is independently implemented and visually inspired by nvitop's
responsive terminal design. Traffic-counter behavior was validated against the
interface-accounting model used by nload. This project does not import or copy
either project's UI implementation and does not invoke them at runtime.
