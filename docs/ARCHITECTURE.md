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

## Modules

| Path | Responsibility |
| --- | --- |
| `bin/netwtop` | Main loop and module loading. |
| `lib/netwtop/runtime.sh` | CLI parsing, validation, temporary workspace, terminal lifecycle, keyboard and mouse input. |
| `lib/netwtop/interfaces.sh` | Default-interface selection and authoritative RX/TX snapshots. |
| `lib/netwtop/backends/common.sh` | Process command lines and UID-to-name discovery. |
| `lib/netwtop/backends/linux.sh` | Linux socket collection through `ss`. |
| `lib/netwtop/backends/macos.sh` | macOS process traffic collection through `/usr/bin/nettop`. |
| `lib/netwtop/accounting.sh` | Counter deltas, cumulative values, user ordering, and command ordering. |
| `lib/netwtop/history.sh` | Bounded rolling history for the interface, users, and accounted traffic. |
| `lib/netwtop/formats.sh` | CSV and JSONL serialization. |
| `lib/netwtop/ui/table.sh` | Responsive frame preparation and differential terminal commits. |
| `lib/netwtop/ui/table.awk` | Table sizing, graph rendering, pagination, highlighting, and hit maps. |

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

- Linux interface totals use sysfs, with `/proc/net/dev` as fallback. Linux
  application detail uses `ss` TCP counters in the current network namespace.
- macOS interface totals use `netstat`. Application detail uses the built-in
  `nettop` process counters for TCP and UDP.

A new Unix platform needs both interface selection/snapshot functions and an
application backend that emits the common snapshot schema expected by
`accounting.sh`.

