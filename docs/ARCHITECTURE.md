# Architecture

This document describes how `netwtop` turns operating-system counters into the
interactive dashboard and machine-readable reports.

## Design goals

- Use POSIX shell, `awk`, and commands normally available on the supported OS.
- Keep interface traffic authoritative and separate from process attribution.
- Never elevate privileges automatically.
- Keep platform-specific collection behind small backend modules.
- Repaint a terminal frame in place without producing an append-only stream.
- Preserve a stable user order while updating traffic ranks independently.

## Data flow

```text
Interface counters ──> interface snapshots ──> RX/TX rate ───────┐
                                                                 │
Socket/process data ─> process snapshots ────> per-command delta ├─> history
                                               per-user delta     │
                                                                 v
                                                        table / CSV / JSONL
```

Each report begins with two snapshots separated by the configured sampling
interval. Interface byte differences produce the top-level Upload and Download
rates. Socket or process counter differences are grouped first by command and
then by UID. Those two data sets intentionally remain separate because
per-process counters cannot account for every interface byte.

Runtime identity is resolved once with `id -u` and `id -un`; display code never
uses `USER` or `LOGNAME` as an authority. Accounting seeds the effective UID,
plus the invoking UID for a sudo session, so an idle current user remains
visible with zero rates even when no socket row is observable.

## Modules

| Path | Responsibility |
| --- | --- |
| `bin/netwtop` | Main loop and module loading. |
| `src/manifest.sh` | Ordered runtime-module and resource inventory shared by loading, installation, and tests. |
| `src/runtime/runtime.sh` | CLI parsing, validation, temporary workspace, terminal lifecycle, keyboard and mouse input. |
| `src/core/interfaces.sh` | Interface enumeration, live selection, and authoritative RX/TX snapshots. |
| `src/core/accounting.sh` | Counter deltas, cumulative values, user ordering, and command ordering. |
| `src/core/history.sh` | Bounded rolling history for the interface, users, and accounted traffic. |
| `src/backends/common.sh` | Process command lines and UID-to-name discovery. |
| `src/backends/linux.sh` | Linux socket collection through `ss`. |
| `src/backends/macos.sh` | macOS process traffic collection through `/usr/bin/nettop`. |
| `src/output/formats.sh` | CSV and JSONL serialization. |
| `src/ui/table.sh` | Responsive frame preparation and differential terminal commits. |
| `src/ui/table.awk` | Table sizing, graph rendering, pagination, highlighting, and hit maps. |

In a source checkout, the executable loads the module root from `src/`. The
installer preserves these responsibility subdirectories below
`$PREFIX/lib/netwtop/`; the installed executable discovers that module root
without a source-only wrapper.

## Runtime workspace

`runtime.sh` creates a private directory below `${TMPDIR:-/tmp}` with mode
restricted by `umask 077`. It contains snapshots, cumulative totals, rendered
frames, history, and interaction maps. The exit trap restores terminal state
and removes this directory.

The most important intermediate files are:

- `previous.tsv` and `current.tsv`: platform-backend counter snapshots.
- `rows.tsv`: per-user interval and session totals.
- `command-rows.tsv`: per-command interval and session totals.
- `history.tsv`: the most recent 120 samples.
- `frame.txt` and `previous-frame.txt`: current and committed terminal frames.
- `hitmap.tsv`: screen-row ownership for mouse interactions.
- `layout-state.tsv`: clamped user and command scroll offsets.

## Terminal renderer

The renderer always builds a complete frame before displaying it. On a normal
sample, only rows different from the previous frame are written with absolute
cursor coordinates. A resize invalidates the previous geometry and triggers a
one-time rebuild.

Boxed rows have an exact visual width. UTF-8 Braille cells are tracked by cell
count rather than byte count, and external usernames or command lines are
sanitized before table rendering. The renderer does not erase to the right of a
full-width row because some PowerShell and VT implementations would erase the
right border in the final terminal column.

The width breakpoint controls only the layout inside a user block:

- At or above the breakpoint, Upload and Download are separate side-by-side
  panels.
- Below the breakpoint, a compact full-width user table is used.
- Users always remain one vertical list; root is pinned first.

Height is handled independently. Auto mode progressively compacts history and
then paginates users only when complete fixed-height user blocks cannot fit.

## Platform boundaries

Interface collection is selected by `interfaces.sh`; application collection is
selected by the backend module:

- Interactive Left/Right selection enumerates the interfaces currently exposed
  by the operating system. A switch refreshes both collector baselines and
  clears only the selected-interface history, preventing cross-device counter
  subtraction and rate inflation.

- Linux interface totals use sysfs, with `/proc/net/dev` as fallback. Linux
  application detail uses `ss` TCP counters in the current network namespace.
- macOS interface totals use `netstat`. Application detail uses the built-in
  `nettop` process counters for TCP and UDP.

Before aggregation is exposed to the UI or machine-readable formats, user rows
are restricted to `root`, the current/invoking UID, and regular-account UIDs.
Linux obtains the threshold from `UID_MIN` in `/etc/login.defs` with a fallback
of 1000; macOS uses 500. This prevents system service identities from being
presented as interactive users while keeping their bytes in the authoritative
interface counters.

Command rows pass through a second permission filter. Effective UID 0 retains
commands for every visible regular account. Any other effective UID retains
only its own command rows, while the other users' aggregate rows remain in the
table. On Linux, a PID resolved through `ss -p` is joined to the effective UID
reported by `ps`; that process UID overrides the socket UID so a command
executed through `sudo` is attributed to root.

When an application backend is not device-scoped, the renderer treats it as a
separate global data domain: the top status and lower title explicitly say
`ALL INTERFACES`, and the selected device affects only the authoritative top
panel. The UI must not imply that global socket deltas belong to the selected
interface.

A new Unix platform needs both interface selection/snapshot functions and an
application backend that emits the common snapshot schema expected by
`accounting.sh`.
