# netwtop

![POSIX Shell](https://img.shields.io/badge/shell-POSIX-brightgreen)
![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue)
[![GitHub stars](https://img.shields.io/github/stars/DoubleFlicker7/netwtop?label=stars&logo=github)](https://github.com/DoubleFlicker7/netwtop/stargazers)
[![License](https://img.shields.io/badge/license-Apache--2.0%20OR%20GPL--3.0-blue)](#license)

An interactive per-user network traffic monitor for Unix terminals.

`netwtop` combines authoritative interface counters with best-effort user and
command attribution. It continuously displays Upload and Download rates,
rolling history, traffic rankings, PIDs, and command lines in a responsive
terminal UI inspired by [nvitop](https://github.com/XuehaiPan/nvitop).

The runtime is implemented with POSIX shell, `awk`, and operating-system
interfaces. It contains no Python code, installs no dependencies, does not run
another third-party network monitor, and never elevates its own privileges.
All program output is in English.

### Table of Contents

- [netwtop](#netwtop)
    - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Requirements](#requirements)
    - [Linux](#linux)
    - [macOS](#macos)
    - [Terminal](#terminal)
  - [Installation](#installation)
    - [Run from a checkout](#run-from-a-checkout)
    - [Install for the current user](#install-for-the-current-user)
    - [Install to another prefix](#install-to-another-prefix)
  - [Usage](#usage)
    - [Resource monitor](#resource-monitor)
    - [Command-line options](#command-line-options)
    - [Keybindings](#keybindings)
    - [Machine-readable output](#machine-readable-output)
  - [Understanding the dashboard](#understanding-the-dashboard)
    - [Interface traffic](#interface-traffic)
    - [User and command traffic](#user-and-command-traffic)
    - [Responsive layout](#responsive-layout)
  - [Privileges](#privileges)
  - [Accounting model](#accounting-model)
    - [Interface counters](#interface-counters)
    - [Linux attribution](#linux-attribution)
    - [macOS attribution](#macos-attribution)
    - [Comparison with nload](#comparison-with-nload)
  - [Limitations](#limitations)
  - [Troubleshooting](#troubleshooting)
    - [Interval validation fails](#interval-validation-fails)
    - [`ss` is missing on Linux](#ss-is-missing-on-linux)
    - [Other users are unattributed](#other-users-are-unattributed)
    - [nload reports more traffic than user rows](#nload-reports-more-traffic-than-user-rows)
    - [A short window hides users](#a-short-window-hides-users)
    - [The installed command still shows an old UI](#the-installed-command-still-shows-an-old-ui)
  - [Development](#development)
  - [Changelog](#changelog)
  - [License](#license)

------

## Features

- **Authoritative interface rates:** reads kernel-maintained RX/TX byte
  counters rather than estimating total traffic from visible processes.
- **Live interface selection:** use Left/Right to cycle physical, virtual,
  bridge, and loopback interfaces without restarting the monitor.
- **Per-user attribution:** groups observable traffic by regular local account,
  excludes system service UIDs, and keeps `root` pinned above a stable lexical
  user order.
- **Permission-aware command detail:** displays PID, command line, active-entry
  count, and current Upload/Download rates for the current user, or for every
  visible regular user when `netwtop` runs as root.
- **Traffic ranks:** shows `[rank/users]` independently of the fixed user order.
- **Rolling history:** draws Braille graphs for the selected interface, every
  user, and accounted application traffic.
- **Interactive navigation:** supports keyboard and mouse selection, scrolling,
  fixed command viewports, and a checked-user mode that reveals all commands
  retained for one user during the session.
- **Responsive UI:** automatically adapts graph height and switches between
  compact and side-by-side Upload/Download layouts at a configurable width.
- **Efficient repainting:** updates changed terminal rows in place, including
  after a resize, instead of continuously printing new tables.
- **Automation formats:** emits CSV or JSONL reports in addition to the live
  terminal dashboard.
- **Fast sampling:** accepts 0.1-second steps, up to a maximum refresh rate of
  10 Hz; the default interval is 0.5 seconds.
- **Portable implementation:** uses POSIX shell and `awk`, with separate Linux
  and macOS collectors and no Python runtime or external monitoring library.

------

## Requirements

`netwtop` supports Linux and macOS. Interface accounting is necessarily
platform-specific because Unix kernels do not expose a single portable network
counter API.

### Linux

Required facilities:

- A POSIX-compatible shell.
- Standard commands including `awk`, `sort`, `cut`, `ps`, `date`, `sleep`,
  `mktemp`, `wc`, `stty`, and `dd`.
- `ss` from iproute2 for socket and process attribution.
- Readable `/sys/class/net/<interface>/statistics/{rx,tx}_bytes`, with
  `/proc/net/dev` used as the interface-counter fallback.

Linux interface totals come from the same kernel counter class commonly used
by tools such as nload. User and command detail comes from TCP counters visible
through `ss` in the current network namespace.

### macOS

Required facilities:

- A POSIX-compatible shell and standard Unix utilities.
- Built-in `/usr/sbin/netstat`, `/sbin/route`, and `/sbin/ifconfig` commands.
- Built-in `/usr/bin/nettop` for per-process TCP/UDP counters.

The project command is named `netwtop` with a `w`, so it does not conflict with
the macOS system command `nettop`.

### Terminal

The interactive monitor requires at least 78 columns and 20 rows. A smaller
terminal shows a resize message rather than a clipped or malformed frame.
Unicode and ANSI color support are recommended for graphs and highlighting.

------

## Installation

### Run from a checkout

No installation is required for development or evaluation:

```sh
git clone https://github.com/DoubleFlicker7/netwtop.git
cd netwtop
./netwtop
```

### Install for the current user

The installer uses `$HOME/.local` by default:

```sh
./install.sh
netwtop
```

Installed files:

```text
$HOME/.local/bin/netwtop
$HOME/.local/lib/netwtop/
```

If the command is not found, add the executable directory to `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
hash -r
```

### Install to another prefix

Set `NETWTOP_PREFIX` to a writable installation prefix:

```sh
NETWTOP_PREFIX=/opt/netwtop ./install.sh
```

Installing into a system-owned prefix may require an administrator shell.
Normal user-level installation does not require root.

For Debian package construction and distribution planning, see the
[packaging documentation](docs/packaging/README.md).

------

## Usage

### Resource monitor

Start the interactive monitor:

```sh
netwtop
```

Common examples:

```sh
# Start on a specific interface
netwtop --device eth0

# Refresh every 0.1 seconds (10 Hz)
netwtop --interval 0.1

# Produce five reports and exit
netwtop --interval 1 --count 5

# Force a compact or full UI
netwtop --mode compact
netwtop --mode full

# Use the wide Upload/Download layout at 120 columns
netwtop --two-column-width 120

# Save machine-readable samples
netwtop --format csv --output network-usage.csv
netwtop --format jsonl --output network-usage.jsonl
```

For the most complete cross-user attribution on Linux, run the installed
command with administrator privileges only when this access is required:

```sh
sudo "$HOME/.local/bin/netwtop"
```

An absolute path is reliable when `sudo` does not preserve the user's `PATH`.

### Command-line options

Type `netwtop --help` to display the built-in reference.

| Short option | Long option | Default | Description |
| --- | --- | --- | --- |
| `-i SECONDS` | `--interval SECONDS` | `0.5` | Sampling interval in 0.1-second steps. The minimum is `0.1`, equivalent to 10 Hz. |
| `-d INTERFACE` | `--device INTERFACE` | Default-route interface | Initial interface for authoritative RX/TX counters. Left/Right can switch interfaces in the live UI. |
| `-n NUMBER` | `--count NUMBER` | Unlimited | Stop after a positive number of reports. The initial baseline is not a report. |
| `-m MODE` | `--mode MODE` | `auto` | Display mode: `auto`, `compact`, or `full`. |
| — | `--two-column-width N` | `100` | Width at which each user's Upload and Download panels become side by side. Users always remain one vertical list. |
| `-f FORMAT` | `--format FORMAT` | `table` | Output format: `table`, `csv`, or `jsonl`. |
| `-o FILE` | `--output FILE` | Standard output | Write reports to `FILE`. Table mode replaces the file with the latest frame; CSV/JSONL preserve samples from the run. |
| — | `--append` | Disabled | Append CSV/JSONL records to an existing output file. Requires `--output` and is invalid for table output. |
| `-V` | `--version` | — | Show the installed netwtop version and exit. |
| `-h` | `--help` | — | Show options, keys, backend details, and privilege guidance, then exit. |

Invalid values are rejected before sampling. This includes intervals below
`0.1`, zero counts, unknown modes or formats, nonexistent interfaces, and
`--append` without an appropriate output file.

### Keybindings

Interactive keys do not require Enter.

| Key or action | Effect |
| --- | --- |
| `q`, `Q` | Quit and restore the previous screen, cursor, mouse mode, and terminal input settings. |
| `r`, `R` | Refresh immediately. |
| `+`, `=` | Reduce the interval by 0.1 seconds, down to 0.1 seconds. |
| `-` | Increase the interval by 0.1 seconds. |
| `a`, `c`, `f` | Select Auto, Compact, or Full display mode. |
| `Left`, `Right` | Select the previous or next detected network interface; selection wraps at both ends. |
| `Up`, `Down` | Move the current user highlight, or move within the highlighted user's command list. |
| `k`, `j` | Scroll the user table; in checked-user mode, scroll that user's commands. |
| `PageUp`, `PageDown` | Scroll by the visible user or command page. |
| `[`, `]` | Scroll the selected user's fixed command viewport. |
| `Space`, `x` | Check or uncheck the selected user. |
| Mouse click | Select a command, or check/uncheck a user from the user row. |
| Mouse wheel | Scroll the command area under the pointer, otherwise scroll the user table. |

Only one user can be checked at a time. Checked-user mode gives the complete
lower panel to that user and includes commands observed earlier in the current
session. Pressing `Space`/`x` again, or clicking the checked `[x]` row, restores
the normal multi-user view.

Up/Down follows the current highlight. Use `j`/`k`, PageUp/PageDown, or the
mouse wheel when the intention is to scroll without changing the selected
object.

### Machine-readable output

CSV output writes one interface row followed by one row per session user for
every sample:

```sh
netwtop --format csv --output network-usage.csv
netwtop --format csv --output network-usage.csv --append
```

CSV fields are:

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

JSONL writes one object per sample, including the selected interface, its
authoritative rates, backend metadata, and a `users` array:

```sh
netwtop --format jsonl --output network-usage.jsonl
netwtop --format jsonl --output network-usage.jsonl --append
```

Cumulative application totals begin at zero when `netwtop` starts. They are
available in CSV and JSONL but intentionally omitted from the live dashboard.

Table output without `--output` uses a controlling terminal and repaints one
frame in place. With `--output`, the file is replaced on every sample so that
it contains only the latest table, never an append-only stream of frames.

------

## Understanding the dashboard

### Interface traffic

The top panel reports:

- Hostname and selected interface, including its position in the detected list.
- Backend name and current refresh interval.
- Current interface Upload and Download rates.
- Independent rate bars with a fixed 128 MiB/s display scale.
- Rolling directional history and visible maximum rates.
- Observed user/command counts and PID attribution percentage.

When a rate exceeds 128 MiB/s, the bar remains full and the displayed value is
`MAX`. Machine-readable output is not capped.

Left/Right changes the selected interface, rebaselines both collectors, and
clears only interface history. This prevents cross-interface subtraction and a
false rate spike after switching.

Common Linux interfaces are independent counter domains:

- `eno1np0`, `eno2np1`, and similar names normally represent physical ports.
- `docker0` is a virtual bridge and does not represent all physical traffic.
- `lo` contains host-local traffic such as `127.0.0.1` and `::1`.

A packet can cross both a virtual interface and a physical interface, so their
rates must not be added as though the interfaces were disjoint.

### User and command traffic

The Linux `ss` backend cannot reliably map cumulative socket bytes to the
selected interface. The lower panel is therefore an explicitly separate,
all-interface data domain. In this mode the UI displays:

```text
USER DATA: ALL INTERFACES
ALL-INTERFACE USER TRAFFIC
ACCOUNTED (ALL IFACES)
```

Switching the top interface does not filter these user rows. The explicit scope
labels prevent global application traffic from being mistaken for traffic on a
down or idle selected interface.

User presentation is stable:

1. `root` is first when present.
2. Other users are sorted by username in the C locale.
3. `[rank/users]` changes with current combined traffic without moving rows.

The effective identity comes from `id -u` and `id -un`, not from the `USER` or
`LOGNAME` environment variables. The current user always has a row, including
samples with no observable network entry; in that case its rates and `ACTIVE`
value are zero. A root invocation through `sudo` also retains the invoking
user's row.

The default account scope includes `root`, the current/invoking user, and UIDs
at or above the platform's regular-user threshold. Linux reads `UID_MIN` from
`/etc/login.defs` (normally `1000`); macOS defaults to `500`. Consequently,
service identities such as `_apt` and `systemd-resolve` do not appear as users
when root exposes their sockets. Their bytes remain part of the authoritative
interface totals but are intentionally excluded from user rows and
`ACCOUNTED`.

Each user block contains username, UID, current directional rates, rolling
history, `ACTIVE`, and a fixed command viewport. `ACTIVE` is the number of
socket/process entries currently reported for that user; it is not a rate.

Each command row contains PID, command line, Upload/Download rates, and active
entry count. `PID -` and `[unattributed]` mean the backend observed traffic but
the operating system did not expose a usable process owner or command.

Command visibility is deliberately narrower than aggregate visibility. A
normal invocation retains the Upload/Download totals and histories of every
visible regular user, but emits command rows only for its own effective UID.
The fixed viewport of another user says that command details are hidden. A
root invocation emits the command rows of every visible regular user for which
the backend can resolve ownership.

`ACCOUNTED (ALL IFACES)` is the sum of displayed application-attribution
traffic. It is not the total of the selected interface and should not be used
as a replacement for its kernel counters.

### Responsive layout

Width and height are evaluated independently.

At or above the default 100-column breakpoint, users remain a single vertical
list while each user gets side-by-side Upload and Download panels. Below the
breakpoint, both directions use separate columns in a compact full-width row.
Change the threshold with `--two-column-width N`.

Auto mode first reduces per-user graph detail and then top-level graph detail
when height is limited. If fixed user blocks still do not fit, the title shows
the visible range (for example, `Users 1-6/12`) and the rest remain reachable
through scrolling.

The monitor retains 120 samples. Braille cells encode two time samples
horizontally and four sub-levels vertically. Visible graph bounds follow the
visible peak and remain between 64 KiB/s and 128 MiB/s. History exists only for
the current process.

------

## Privileges

`netwtop` never invokes `sudo`, prompts for a password, or changes privileges.

Without root:

- Interface totals are normally fully readable.
- The invoking user's attributable PIDs and commands are normally visible.
- Other regular users retain aggregate Upload/Download rates and histories,
  but their PID and command rows are intentionally hidden.
- Hardened systems can restrict additional socket or process details.

With root on Linux, `ss -p` can normally expose socket owners for all users in
the current network namespace, so `netwtop` displays command detail for all
visible regular users. When a PID is resolved, its effective process UID takes
precedence over the socket UID. A network command executed through `sudo` is
therefore charged to `root`. Root does not eliminate sampling gaps, resolve
shared sockets perfectly, or expose other network namespaces automatically.

Command lines can contain tokens, URLs, or other sensitive arguments. Treat
terminal recordings and exported CSV/JSONL files accordingly.

------

## Accounting model

### Interface counters

The top panel computes rates from consecutive kernel byte snapshots:

```text
rate = (current counter - previous counter) / actual elapsed time
```

Counter rollbacks or resets produce a zero delta for that sample.

### Linux attribution

Linux samples `ss -tinepH` cumulative TCP values:

- Upload uses acknowledged application bytes.
- Download uses received application bytes.
- `ss -p` supplies process ownership where permitted.
- `ps` resolves command lines and effective process UIDs. The process UID is
  authoritative whenever the PID is visible; otherwise attribution falls back
  to the UID reported for the socket.
- The scope is visible TCP connections across all interfaces in the current
  network namespace.

This data is not wire-equivalent to interface RX/TX counters.

### macOS attribution

macOS uses the built-in `nettop` command in per-process CSV mode and samples
its `bytes_in`/`bytes_out` counters for TCP and UDP. Command lines are resolved
with `ps`. Because these counters cannot be reliably restricted to the selected
interface, they are also presented as all-interface application detail.

### Comparison with nload

Compare the same interface, units, and interval:

```sh
nload -t 1000 -u B eth0
netwtop --interval 1 --device eth0
```

Both tools derive their top-level Linux rates from kernel interface counters.
Instantaneous values can differ because sample times are not synchronized;
sustained-transfer rates should converge. Compare nload with the top interface
panel or `interface_*_bytes_per_second` fields, not with `ACCOUNTED`.

------

## Limitations

- Linux application attribution is TCP-focused; interface totals include all
  traffic counted by the interface.
- Connections that exist entirely between snapshots can be missed.
- Only the current Linux network namespace is visible.
- Shared sockets cannot always be divided exactly among processes.
- The selected interface and application attribution can have different scopes.
- Root improves owner visibility but cannot turn sampled shell accounting into
  complete eBPF, cgroup, or firewall accounting.
- The regular-user UID threshold is a platform convention; unusual deployments
  with human accounts below `UID_MIN` are represented only when that account is
  the current user or the original user recorded by `sudo`.
- Other Unix families require dedicated interface and application backends.

Complete wire-level accounting by UID—including headers, retransmissions,
every UDP flow, and every short-lived process—is not reliably available to an
unprivileged cross-platform shell program.

------

## Troubleshooting

### Interval validation fails

Intervals use 0.1-second steps and cannot be faster than 10 Hz:

```sh
netwtop --interval 0.5
```

### `ss` is missing on Linux

Expose the iproute2 `ss` command through `PATH`. `netwtop` deliberately does
not install operating-system dependencies itself.

### Other users are unattributed

The current account cannot inspect their socket owners. Run with root only if
complete cross-user visibility is required and permitted.

### nload reports more traffic than user rows

Compare nload with the selected-interface panel. User rows and `ACCOUNTED`
exclude traffic the application backend cannot see or attribute.

### A short window hides users

Read the visible range in the lower title and scroll with `j`/`k`,
PageUp/PageDown, or the mouse wheel. Up/Down moves the current highlight.
Compact mode can show more users:

```sh
netwtop --mode compact
```

### The installed command still shows an old UI

Reinstall the current checkout and clear the shell command cache:

```sh
./install.sh
hash -r
netwtop
```

------

## Development

The repository keeps installable runtime code separate from documentation and
test fixtures:

```text
.
├── bin/
│   └── netwtop                    Main executable and sampling loop
├── docs/
│   ├── README.md                  Documentation index
│   ├── ARCHITECTURE.md            Data flow and renderer invariants
│   ├── DEVELOPMENT.md             Contributor workflow
│   └── packaging/                 Debian and APT publication guides
├── src/
│   ├── backends/                  Linux and macOS attribution collectors
│   ├── core/                      Counters, aggregation, and history
│   ├── output/                    CSV and JSONL serialization
│   ├── runtime/                   CLI, terminal, and input handling
│   ├── ui/                        Terminal renderer and frame commit logic
│   └── manifest.sh                Ordered install and module-load manifest
├── tests/
│   ├── fixtures/                  Deterministic renderer data
│   └── smoke.sh                   Offline regression suite
├── CHANGELOG.md
├── COPYING                        GNU GPL version 3
├── LICENSE                        Apache License version 2.0
├── install.sh                     Prefix installer
└── netwtop                        Run-from-checkout launcher
```

The repository uses `src/` for responsibility-based source organization. The
installer maps this tree to `$PREFIX/lib/netwtop/`, preserving normal Unix
installation conventions without forcing the source checkout to imitate an
installed filesystem. The root launcher only connects a development checkout
to `bin/netwtop`.

Run all offline checks without root or network access:

```sh
./tests/smoke.sh
```

See the [documentation index](docs/README.md),
[architecture](docs/ARCHITECTURE.md), and
[development guide](docs/DEVELOPMENT.md) for module boundaries, test coverage,
staged installation, coding conventions, and backend extension instructions.

The terminal design is inspired by nvitop, while the implementation is
independent and does not import or invoke nvitop. Interface-counter behavior is
validated against the accounting model used by nload; netwtop does not invoke
nload at runtime.

------

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes. The project follows
[Semantic Versioning](https://semver.org/) and maintains entries in the
[Keep a Changelog](https://keepachangelog.com/) format.

------

## License

`netwtop` is dual-licensed under your choice of:

- [Apache License 2.0](LICENSE)
- [GNU General Public License version 3](COPYING)
