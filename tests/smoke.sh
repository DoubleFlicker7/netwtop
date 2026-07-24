#!/bin/sh
# Fast checks that do not require network access or elevated privileges.

set -u

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1

for shell_file in \
    netwtop \
    install.sh \
    bin/netwtop \
    src/manifest.sh
do
    sh -n "$PROJECT_ROOT/$shell_file" || exit 1
done
. "$PROJECT_ROOT/src/manifest.sh"
for module in $NETWTOP_RUNTIME_MODULES; do
    sh -n "$PROJECT_ROOT/src/$module" || exit 1
done

"$PROJECT_ROOT/netwtop" --help >/dev/null || exit 1
"$PROJECT_ROOT/netwtop" --help | grep -q 'default: 0.5' || exit 1
"$PROJECT_ROOT/netwtop" --help | grep -q -- '--two-column-width' || exit 1
for documented_option in \
    --interval --device --count --mode --two-column-width \
    --format --output --append --help
do
    grep -q -- "$documented_option" "$PROJECT_ROOT/README.md" || {
        printf 'Error: README is missing option %s.\n' "$documented_option" >&2
        exit 1
    }
done
[ -s "$PROJECT_ROOT/docs/README.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/ARCHITECTURE.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/DEVELOPMENT.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/packaging/README.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/packaging/APT_PACKAGING.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/packaging/SELF_HOSTED_APT_REPOSITORY.md" ] || exit 1
[ -s "$PROJECT_ROOT/CHANGELOG.md" ] || exit 1
[ -s "$PROJECT_ROOT/LICENSE" ] || exit 1
if "$PROJECT_ROOT/netwtop" --interval 0.09 --format jsonl --count 1 \
        >/dev/null 2>&1; then
    printf 'Error: An interval faster than 10 Hz was accepted.\n' >&2
    exit 1
fi
NETWTOP_MODULE_ROOT=$PROJECT_ROOT/src
. "$PROJECT_ROOT/src/runtime/runtime.sh"
. "$PROJECT_ROOT/src/backends/common.sh"
. "$PROJECT_ROOT/src/backends/linux.sh"
. "$PROJECT_ROOT/src/core/interfaces.sh"
. "$PROJECT_ROOT/src/core/accounting.sh"
EXPECTED_CURRENT_UID=$(id -u) || exit 1
EXPECTED_CURRENT_USER=$(id -un) || exit 1
ORIGINAL_USER=${USER-}
ORIGINAL_LOGNAME=${LOGNAME-}
USER=stale-developer-user
LOGNAME=stale-developer-user
OS_NAME=$(uname -s) || exit 1
configure_user_scope
[ "$CURRENT_UID" = "$EXPECTED_CURRENT_UID" ] || exit 1
[ "$CURRENT_USER" = "$EXPECTED_CURRENT_USER" ] || exit 1
USER=$ORIGINAL_USER
LOGNAME=$ORIGINAL_LOGNAME
is_valid_interval 0.1 || exit 1
is_valid_interval 0.5 || exit 1
is_valid_interval 1.5 || exit 1
is_valid_interval 0.09 && exit 1
INTERVAL=0.5
normalize_interval
[ "$INTERVAL" = 0.5 ] && [ "$INTERVAL_TENTHS" -eq 5 ] || exit 1
list_available_interfaces() {
    printf '%s\n' docker0 eno1np0 eno2np1 lo
}
configure_interface() {
    refresh_interface_list
}
DEVICE=eno1np0
refresh_interface_list
[ "$INTERFACE_COUNT" -eq 4 ] && [ "$INTERFACE_INDEX" -eq 2 ] || exit 1
[ "$(adjacent_interface_name -1)" = docker0 ] || exit 1
[ "$(adjacent_interface_name 1)" = eno2np1 ] || exit 1
switch_interface 1 || exit 1
[ "$DEVICE" = eno2np1 ] && [ "$INTERFACE_INDEX" -eq 3 ] || exit 1
switch_interface 1 || exit 1
[ "$DEVICE" = lo ] && [ "$INTERFACE_INDEX" -eq 4 ] || exit 1
switch_interface 1 || exit 1
[ "$DEVICE" = docker0 ] && [ "$INTERFACE_INDEX" -eq 1 ] || exit 1
switch_interface -1 || exit 1
[ "$DEVICE" = lo ] && [ "$INTERFACE_INDEX" -eq 4 ] || exit 1
INTERFACE_SWITCH_PENDING=0
INTERFACE_SWITCH_DIRECTION=0
request_interface_switch -1
[ "$INTERFACE_SWITCH_PENDING" -eq 1 ] \
    && [ "$INTERFACE_SWITCH_DIRECTION" -eq -1 ] || exit 1
if "$PROJECT_ROOT/netwtop" --mode invalid >/dev/null 2>&1; then
    printf 'Error: Invalid display mode was accepted.\n' >&2
    exit 1
fi
if "$PROJECT_ROOT/netwtop" --two-column-width 0 --format jsonl --count 1 \
        >/dev/null 2>&1; then
    printf 'Error: An invalid two-column width was accepted.\n' >&2
    exit 1
fi
if "$PROJECT_ROOT/netwtop" --device definitely-not-an-interface \
        --format jsonl --count 1 >/dev/null 2>&1; then
    printf 'Error: Invalid network interface was accepted.\n' >&2
    exit 1
fi

LC_ALL=C awk -F '\t' \
    -v elapsed=1 -v refresh_interval=1 -v display_mode=auto \
    -v backend=test -v scope=test -v ui_width=80 -v ui_height=24 \
    -v interface_name=test0 -v interface_rx_delta=0 \
    -v interface_tx_delta=0 -v attribution_device_scoped=1 \
    -v history_limit=120 \
    -v host_name=test -v session_label=test -v display_time=test \
    -f "$PROJECT_ROOT/src/ui/table.awk" \
    /dev/null /dev/null /dev/null /dev/null >/dev/null || exit 1

SMOKE_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/netwtop-smoke.XXXXXX") || exit 1
HISTORY_TEST=$(mktemp "${TMPDIR:-/tmp}/netwtop-history.XXXXXX") || exit 1
NEXT_HISTORY=${HISTORY_TEST}.next
HITMAP_TEST=$(mktemp "${TMPDIR:-/tmp}/netwtop-hitmap.XXXXXX") || exit 1
LAYOUT_TEST=$(mktemp "${TMPDIR:-/tmp}/netwtop-layout.XXXXXX") || exit 1
INSTALL_TEST=$(mktemp -d "${TMPDIR:-/tmp}/netwtop-install.XXXXXX") || exit 1
trap 'rm -f "$SMOKE_OUTPUT" "$HISTORY_TEST" "$NEXT_HISTORY" "$HITMAP_TEST" "$LAYOUT_TEST"; rm -rf "$INSTALL_TEST"' 0 HUP INT TERM
mkdir -p "$INSTALL_TEST/lib/netwtop" || exit 1
: >"$INSTALL_TEST/lib/netwtop/runtime.sh"
NETWTOP_PREFIX=$INSTALL_TEST "$PROJECT_ROOT/install.sh" >/dev/null || exit 1
"$INSTALL_TEST/bin/netwtop" --help >/dev/null || exit 1
[ -s "$INSTALL_TEST/lib/netwtop/manifest.sh" ] || exit 1
[ -s "$INSTALL_TEST/lib/netwtop/core/accounting.sh" ] || exit 1
[ -s "$INSTALL_TEST/lib/netwtop/runtime/runtime.sh" ] || exit 1
[ -s "$INSTALL_TEST/lib/netwtop/output/formats.sh" ] || exit 1
[ ! -e "$INSTALL_TEST/lib/netwtop/runtime.sh" ] || exit 1

UID_NAMES=$INSTALL_TEST/runtime-uid-names.tsv
RAW=$INSTALL_TEST/runtime-identity.tmp
build_uid_names
LC_ALL=C awk -F '\t' \
    -v expected_uid="$EXPECTED_CURRENT_UID" \
    -v expected_user="$EXPECTED_CURRENT_USER" '
    $1 == expected_uid { matched = ($2 == expected_user); exit }
    END { exit !matched }
' "$UID_NAMES" || exit 1

ROWS=$INSTALL_TEST/visible-user-rows.tsv
COMMAND_ROWS=$INSTALL_TEST/visible-command-rows.tsv
RAW=$INSTALL_TEST/visible-user-filter.tmp
LOGIN_UID_MIN=1000
CURRENT_UID=1011
INVOKING_UID=1011
SHOW_ALL_COMMANDS=0
printf '0\t1\t1\t1\t1\t1\n101\t1\t1\t1\t1\t1\n105\t1\t1\t1\t1\t1\n1000\t1\t1\t1\t1\t1\n1011\t1\t1\t1\t1\t1\n' >"$ROWS"
printf '0\t1\troot-cmd\t1\t1\t1\t1\t1\n101\t2\tresolver-cmd\t1\t1\t1\t1\t1\n105\t3\tapt-cmd\t1\t1\t1\t1\t1\n1000\t4\tother-user-cmd\t1\t1\t1\t1\t1\n1011\t5\tcurrent-user-cmd\t1\t1\t1\t1\t1\n' >"$COMMAND_ROWS"
filter_visible_user_rows
LC_ALL=C awk -F '\t' '
    $1 == 101 || $1 == 105 { invalid = 1 }
    $1 == 0 || $1 == 1000 || $1 == 1011 { seen[$1] = 1 }
    END { exit invalid || !(seen[0] && seen[1000] && seen[1011]) }
' "$ROWS" || exit 1
LC_ALL=C awk -F '\t' '
    $1 != 1011 { invalid = 1 }
    $1 == 1011 && $3 == "current-user-cmd" { current = 1 }
    END { exit invalid || !current }
' "$COMMAND_ROWS" || exit 1

CURRENT_UID=0
INVOKING_UID=1011
SHOW_ALL_COMMANDS=1
printf '0\t1\t1\t1\t1\t1\n101\t1\t1\t1\t1\t1\n1000\t1\t1\t1\t1\t1\n1011\t1\t1\t1\t1\t1\n' >"$ROWS"
printf '0\t1\troot-cmd\t1\t1\t1\t1\t1\n101\t2\tresolver-cmd\t1\t1\t1\t1\t1\n1000\t4\tother-user-cmd\t1\t1\t1\t1\t1\n1011\t5\tinvoking-user-cmd\t1\t1\t1\t1\t1\n' >"$COMMAND_ROWS"
filter_visible_user_rows
LC_ALL=C awk -F '\t' '
    $1 == 101 { invalid = 1 }
    $1 == 0 || $1 == 1000 || $1 == 1011 { seen[$1] = 1 }
    END { exit invalid || !(seen[0] && seen[1000] && seen[1011]) }
' "$ROWS" || exit 1
LC_ALL=C awk -F '\t' '
    $1 == 101 { invalid = 1 }
    $1 == 0 || $1 == 1000 || $1 == 1011 { seen[$1] = 1 }
    END { exit invalid || !(seen[0] && seen[1000] && seen[1011]) }
' "$COMMAND_ROWS" || exit 1

PROCESS_MAP_TEST=$INSTALL_TEST/linux-process-map.tsv
SOCKET_SNAPSHOT_TEST=$INSTALL_TEST/linux-socket-snapshot.txt
PARSED_SNAPSHOT_TEST=$INSTALL_TEST/linux-parsed-snapshot.tsv
printf '900\t0\t/usr/bin/curl https://example.invalid/file\n901\t1000\t/usr/bin/client\n' \
    >"$PROCESS_MAP_TEST"
printf 'ESTAB 0 0 192.0.2.1:40000 192.0.2.2:443 users:(("curl",pid=900,fd=3)) uid:1000 ino:77 sk:abc\n bbr bytes_acked:2048 bytes_received:4096\nESTAB 0 0 192.0.2.1:40001 192.0.2.2:443 uid:1000 ino:78 sk:def\n bbr bytes_acked:512 bytes_received:1024\n' \
    >"$SOCKET_SNAPSHOT_TEST"
parse_linux_snapshot "$PROCESS_MAP_TEST" "$SOCKET_SNAPSHOT_TEST" \
    "$PARSED_SNAPSHOT_TEST"
LC_ALL=C awk -F '\t' '
    $1 == "abc:77" && $2 == 0 && $3 == 900 &&
        $4 == "/usr/bin/curl https://example.invalid/file" &&
        $5 == 2048 && $6 == 4096 { sudo_command = 1 }
    $1 == "def:78" && $2 == 1000 && $3 == "-" &&
        $4 == "[unattributed]" && $5 == 512 && $6 == 1024 { fallback = 1 }
    END { exit !(sudo_command && fallback) }
' "$PARSED_SNAPSHOT_TEST" || exit 1

PREVIOUS=$INSTALL_TEST/empty-previous.tsv
CURRENT=$INSTALL_TEST/empty-current.tsv
TOTALS=$INSTALL_TEST/empty-user-totals.tsv
COMMAND_TOTALS=$INSTALL_TEST/empty-command-totals.tsv
ROWS=$INSTALL_TEST/seeded-user-rows.tsv
COMMAND_ROWS=$INSTALL_TEST/seeded-command-rows.tsv
SORTED_ROWS=$INSTALL_TEST/seeded-sorted-rows.tsv
SORTED_COMMAND_ROWS=$INSTALL_TEST/seeded-sorted-command-rows.tsv
UID_NAMES=$INSTALL_TEST/seeded-uid-names.tsv
TABLE_ROWS=$INSTALL_TEST/seeded-table-rows.tsv
NEXT_TOTALS=$INSTALL_TEST/seeded-next-totals.tsv
NEXT_COMMAND_TOTALS=$INSTALL_TEST/seeded-next-command-totals.tsv
RAW=$INSTALL_TEST/seeded-accounting.tmp
CURRENT_UID=4242
INVOKING_UID=4242
SHOW_ALL_COMMANDS=0
LOGIN_UID_MIN=1000
: >"$PREVIOUS"
: >"$CURRENT"
: >"$TOTALS"
: >"$COMMAND_TOTALS"
printf '4242\tcurrent-test-user\n' >"$UID_NAMES"
calculate_rows 1
LC_ALL=C awk -F '\t' '
    $1 == 4242 && $2 == 0 && $3 == 0 && $4 == 0 && $5 == 0 && $6 == 0 {
        current_user = 1
    }
    END { exit !current_user }
' "$ROWS" || exit 1
grep -Fq "session_label=\"\$CURRENT_USER@\$HOST_NAME\"" \
    "$PROJECT_ROOT/src/ui/table.sh" || exit 1

grep -Fq "color_border=\$(printf '\\033[37m')" \
    "$PROJECT_ROOT/src/ui/table.sh" || exit 1
grep -Fq "color_user=\$(printf '\\033[90m')" \
    "$PROJECT_ROOT/src/ui/table.sh" || exit 1
WHITE_BORDER=$(printf '\033[37m')
CYAN_TITLE=$(printf '\033[1;36m')
GRAY_USER=$(printf '\033[90m')
GREEN_UPLOAD=$(printf '\033[32m')
BLUE_DOWNLOAD=$(printf '\033[34m')
COLOR_RESET=$(printf '\033[0m')
LC_ALL=C awk -F '\t' \
    -v elapsed=1 -v refresh_interval=1 -v display_mode=compact \
    -v two_column_width=100 -v backend=test -v scope=test \
    -v ui_width=120 -v ui_height=40 -v interface_name=test0 \
    -v interface_index=2 -v interface_count=4 \
    -v interface_rx_delta=0 -v interface_tx_delta=0 \
    -v attribution_device_scoped=0 -v history_limit=120 -v host_name=test \
    -v session_label=test -v display_time=test \
    -v color_border="$WHITE_BORDER" -v color_title="$CYAN_TITLE" \
    -v color_user="$GRAY_USER" -v color_upload="$GREEN_UPLOAD" \
    -v color_download="$BLUE_DOWNLOAD" \
    -v color_reset="$COLOR_RESET" \
    -f "$PROJECT_ROOT/src/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
grep -Fq "${WHITE_BORDER}╒" "$SMOKE_OUTPUT" || exit 1
grep -Fq "${WHITE_BORDER}│${COLOR_RESET} ${CYAN_TITLE}NETWTOP" \
    "$SMOKE_OUTPUT" || exit 1
grep -Fq "${COLOR_RESET}${WHITE_BORDER} │ ${COLOR_RESET}" \
    "$SMOKE_OUTPUT" || exit 1
grep -Fq 'Device: test0 [2/4]' "$SMOKE_OUTPUT" || exit 1
grep -Fq "$GRAY_USER" "$SMOKE_OUTPUT" || exit 1
grep -Fq "$GREEN_UPLOAD" "$SMOKE_OUTPUT" || exit 1
grep -Fq "$BLUE_DOWNLOAD" "$SMOKE_OUTPUT" || exit 1

COMMAND_VISIBILITY_TEST=$INSTALL_TEST/ui-command-visibility.tsv
printf '0\t900\troot-secret-command\t4096\t4096\t4096\t4096\t1\n1000\t123\t/usr/bin/current-user-client\t1024\t2048\t1024\t2048\t1\n' \
    >"$COMMAND_VISIBILITY_TEST"
LC_ALL=C awk -F '\t' \
    -v elapsed=0.5 -v refresh_interval=0.5 -v display_mode=compact \
    -v interactive_ui=1 -v table_scroll=0 -v command_view_size=2 \
    -v show_all_commands=0 -v current_uid=1000 \
    -v two_column_width=100 -v backend=test -v scope=test \
    -v ui_width=120 -v ui_height=28 -v interface_name=test0 \
    -v interface_index=1 -v interface_count=1 \
    -v interface_rx_delta=0 -v interface_tx_delta=0 \
    -v attribution_device_scoped=0 -v history_limit=120 -v host_name=test \
    -v session_label=test -v display_time=test \
    -f "$PROJECT_ROOT/src/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$COMMAND_VISIBILITY_TEST" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
grep -q 'Commands: 1 (self)' "$SMOKE_OUTPUT" || exit 1
grep -q 'Command details hidden; run netwtop as root' "$SMOKE_OUTPUT" || exit 1
grep -q 'PID 123' "$SMOKE_OUTPUT" || exit 1
if grep -q 'root-secret-command' "$SMOKE_OUTPUT"; then exit 1; fi

LC_ALL=C awk -F '\t' \
    -v elapsed=1 -v refresh_interval=1 -v display_mode=compact \
    -v backend=test -v scope=test -v ui_width=80 -v ui_height=24 \
    -v interface_name=test0 -v interface_rx_delta=209715200 \
    -v interface_tx_delta=157286400 -v attribution_device_scoped=0 \
    -v history_limit=60 -v host_name=test -v session_label=test \
    -v display_time=test -v color_user="$GRAY_USER" \
    -v color_upload="$GREEN_UPLOAD" -v color_download="$BLUE_DOWNLOAD" \
    -v color_reset="$COLOR_RESET" -f "$PROJECT_ROOT/src/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1

grep -q '128 MiB/s' "$SMOKE_OUTPUT" || exit 1
grep -q 'MAX' "$SMOKE_OUTPUT" || exit 1
grep -q 'UP HISTORY' "$SMOKE_OUTPUT" || exit 1
grep -q 'HISTORY UP|DN' "$SMOKE_OUTPUT" || exit 1
grep -q 'ACCOUNTED' "$SMOKE_OUTPUT" || exit 1
LC_ALL=C awk -v gray="$GRAY_USER" -v green="$GREEN_UPLOAD" \
    -v blue="$BLUE_DOWNLOAD" '
    index($0, "root") && index($0, gray) && index($0, green) && index($0, blue) {
        correctly_colored_user_row = 1
    }
    END { exit !correctly_colored_user_row }
' "$SMOKE_OUTPUT" || exit 1
[ "$(wc -l <"$SMOKE_OUTPUT")" -le 24 ] || exit 1

LC_ALL=C awk -F '\t' \
    -v elapsed=1 -v refresh_interval=1 -v display_mode=full \
    -v backend=test -v scope=test -v ui_width=120 -v ui_height=50 \
    -v interface_name=test0 -v interface_rx_delta=3145728 \
    -v interface_tx_delta=1572864 -v attribution_device_scoped=0 \
    -v history_limit=120 -v host_name=test -v session_label=test \
    -v display_time=test -f "$PROJECT_ROOT/src/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
grep -q 'NETWORK TRAFFIC MONITOR' "$SMOKE_OUTPUT" || exit 1
grep -q 'UP .*MAX' "$SMOKE_OUTPUT" || exit 1
grep -q 'now' "$SMOKE_OUTPUT" || exit 1
grep -q '⣿' "$SMOKE_OUTPUT" || exit 1

render_responsive_test() {
    responsive_width=$1
    responsive_height=$2
    responsive_breakpoint=$3
    responsive_rows=${4:-$PROJECT_ROOT/tests/fixtures/rows.tsv}
    responsive_scroll=${5:-0}
    : >"$HITMAP_TEST"
    LC_ALL=C awk -F '\t' \
        -v elapsed=0.5 -v refresh_interval=0.5 -v display_mode=auto \
        -v interactive_ui=1 -v table_scroll="$responsive_scroll" -v command_view_size=2 \
        -v two_column_width="$responsive_breakpoint" \
        -v hitmap_file="$HITMAP_TEST" \
        -v backend=test -v scope=test -v ui_width="$responsive_width" \
        -v ui_height="$responsive_height" -v interface_name=test0 \
        -v interface_index=2 -v interface_count=4 \
        -v interface_rx_delta=3145728 -v interface_tx_delta=1572864 \
        -v attribution_device_scoped=0 -v history_limit=120 -v host_name=test \
        -v session_label=test -v display_time=test \
        -f "$PROJECT_ROOT/src/ui/table.awk" \
        "$PROJECT_ROOT/tests/fixtures/names.tsv" \
        "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
        "$responsive_rows" \
        "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
    [ "$(wc -l <"$SMOKE_OUTPUT")" -le "$responsive_height" ] || exit 1
}

render_responsive_test 99 24 100
grep -q 'UP HISTORY' "$SMOKE_OUTPUT" || exit 1
grep -q 'UPLOAD/s' "$SMOKE_OUTPUT" || exit 1
grep -q 'USER DATA: ALL INTERFACES' "$SMOKE_OUTPUT" || exit 1
grep -q 'ALL-INTERFACE USER TRAFFIC' "$SMOKE_OUTPUT" || exit 1
if grep -q 'UID / ACTIVE' "$SMOKE_OUTPUT"; then exit 1; fi
if grep -Eq 'UP .*MAX .*DN .*MAX' "$SMOKE_OUTPUT"; then exit 1; fi
render_responsive_test 100 28 100
grep -Eq 'UP .*MAX .*DN .*MAX' "$SMOKE_OUTPUT" || exit 1
grep -q 'RANK USER' "$SMOKE_OUTPUT" || exit 1
grep -q 'UID / ACTIVE' "$SMOKE_OUTPUT" || exit 1
grep -q 'UPLOAD .*│ DOWNLOAD ' "$SMOKE_OUTPUT" || exit 1
grep -q 'root' "$SMOKE_OUTPUT" || exit 1
grep -q 'alice' "$SMOKE_OUTPUT" || exit 1
wide_user_row=$(LC_ALL=C awk -F '\t' '$2 == "user" && $3 == 1000 { print $1; exit }' \
    "$HITMAP_TEST")
root_user_row=$(LC_ALL=C awk -F '\t' '$2 == "user" && $3 == 0 { print $1; exit }' \
    "$HITMAP_TEST")
[ -n "$wide_user_row" ] && [ -n "$root_user_row" ] \
    && [ "$wide_user_row" -gt "$root_user_row" ] || exit 1
LC_ALL=C awk -F '\t' -v alice_row="$wide_user_row" -v root_row="$root_user_row" '
    $1 == root_row && $2 == "user" && $3 == 0 && $6 == 1 && $7 == 100 { root = 1 }
    $1 == alice_row && $2 == "user" && $3 == 1000 && $6 == 1 && $7 == 100 { alice = 1 }
    END { exit !(root && alice) }
' "$HITMAP_TEST" || exit 1
HITMAP=$HITMAP_TEST
TABLE_SCROLL=0
COMMAND_SCROLL_UID=
COMMAND_SCROLL_OFFSET=0
SELECTED_UID=
SELECTED_PID=
EXPANDED_UID=
pressed_key=$(printf '\033[<0;75;%sM' "$wide_user_row")
handle_mouse_event
[ "$SELECTED_UID" = 1000 ] && [ "$EXPANDED_UID" = 1000 ] || exit 1
pressed_key=$(printf '\033[<0;75;%sM' "$wide_user_row")
handle_mouse_event
[ -z "$EXPANDED_UID" ] || exit 1
pressed_key=$(printf '\033[<0;10;%sM' "$root_user_row")
handle_mouse_event
[ "$SELECTED_UID" = 0 ] && [ "$EXPANDED_UID" = 0 ] || exit 1
pressed_key=$(printf '\033[<0;10;%sM' "$root_user_row")
handle_mouse_event
[ -z "$EXPANDED_UID" ] || exit 1
render_responsive_test 99 70 100
grep -Eq 'UPLOAD .*MAX' "$SMOKE_OUTPUT" || exit 1
grep -Eq 'DOWNLOAD .*MAX' "$SMOKE_OUTPUT" || exit 1
if grep -Eq 'UP .*MAX .*DN .*MAX' "$SMOKE_OUTPUT"; then exit 1; fi
render_responsive_test 100 50 100
grep -Eq 'UP .*MAX .*DN .*MAX' "$SMOKE_OUTPUT" || exit 1
grep -q 'RANK USER' "$SMOKE_OUTPUT" || exit 1
grep -q 'UID / ACTIVE' "$SMOKE_OUTPUT" || exit 1
render_responsive_test 100 24 120
grep -q 'UP HISTORY' "$SMOKE_OUTPUT" || exit 1
grep -q 'RANK USER' "$SMOKE_OUTPUT" || exit 1
grep -q 'UPLOAD/s' "$SMOKE_OUTPUT" || exit 1
if grep -q 'UID / ACTIVE' "$SMOKE_OUTPUT"; then exit 1; fi
render_responsive_test 160 40 100 "$PROJECT_ROOT/tests/fixtures/rows_three.tsv"
grep -q 'Users 1-3/3' "$SMOKE_OUTPUT" || exit 1
grep -q 'UPLOAD .*│ DOWNLOAD ' "$SMOKE_OUTPUT" || exit 1
grep -q 'root' "$SMOKE_OUTPUT" || exit 1
grep -q 'alice' "$SMOKE_OUTPUT" || exit 1
grep -q 'bob' "$SMOKE_OUTPUT" || exit 1
bob_user_row=$(LC_ALL=C awk -F '\t' '$2 == "user" && $3 == 1001 { print $1; exit }' \
    "$HITMAP_TEST")
[ -n "$bob_user_row" ] || exit 1
LC_ALL=C awk -F '\t' -v row="$bob_user_row" '
    $1 == row && $2 == "user" { count++ }
    END { exit !(count == 1) }
' "$HITMAP_TEST" || exit 1
LC_ALL=C awk -F '\t' '
    $2 == "user" && $3 == 0 { root_row = $1; root_count++ }
    $2 == "user" && $3 == 1000 { alice_row = $1; alice_count++ }
    $2 == "user" && $3 == 1001 { bob_row = $1; bob_count++ }
    END {
        exit !(root_count == 1 && alice_count == 1 && bob_count == 1 &&
            root_row < alice_row && alice_row < bob_row)
    }
' "$HITMAP_TEST" || exit 1
render_responsive_test 99 24 100 "$PROJECT_ROOT/tests/fixtures/rows_many.tsv" 0
grep -q 'Users 1-2/7' "$SMOKE_OUTPUT" || exit 1
grep -q 'root' "$SMOKE_OUTPUT" || exit 1
grep -q 'alice' "$SMOKE_OUTPUT" || exit 1
render_responsive_test 99 24 100 "$PROJECT_ROOT/tests/fixtures/rows_many.tsv" 2
grep -q 'Users 3-4/7' "$SMOKE_OUTPUT" || exit 1
grep -q 'bob' "$SMOKE_OUTPUT" || exit 1
grep -q 'carol' "$SMOKE_OUTPUT" || exit 1
render_responsive_test 99 24 100 "$PROJECT_ROOT/tests/fixtures/rows_many.tsv" 4
grep -q 'Users 5-6/7' "$SMOKE_OUTPUT" || exit 1
grep -q 'dave' "$SMOKE_OUTPUT" || exit 1
grep -q 'erin' "$SMOKE_OUTPUT" || exit 1
render_responsive_test 99 24 100 "$PROJECT_ROOT/tests/fixtures/rows_many.tsv" 6
grep -q 'Users 6-7/7' "$SMOKE_OUTPUT" || exit 1
grep -q 'erin' "$SMOKE_OUTPUT" || exit 1
grep -q 'frank' "$SMOKE_OUTPUT" || exit 1

TABLE_ROWS=$PROJECT_ROOT/tests/fixtures/rows_many.tsv
SORTED_COMMAND_ROWS=$PROJECT_ROOT/tests/fixtures/commands_scroll.tsv
TABLE_SCROLL=0
TABLE_PAGE_SIZE=2
COMMAND_VIEW_SIZE=2
COMMAND_SCROLL_UID=
COMMAND_SCROLL_OFFSET=0
SELECTED_UID=
SELECTED_PID=
EXPANDED_UID=
move_highlight 1
[ "$SELECTED_UID" = 0 ] && [ -z "$SELECTED_PID" ] \
    && [ "$TABLE_SCROLL" -eq 0 ] || exit 1
move_highlight 1
[ "$SELECTED_UID" = 1000 ] && [ "$TABLE_SCROLL" -eq 0 ] || exit 1
move_highlight 1
[ "$SELECTED_UID" = 1001 ] && [ "$TABLE_SCROLL" -eq 1 ] || exit 1
move_highlight -1
[ "$SELECTED_UID" = 1000 ] && [ -z "$SELECTED_PID" ] || exit 1

SELECTED_UID=1000
SELECTED_PID=125
COMMAND_SCROLL_UID=1000
COMMAND_SCROLL_OFFSET=2
move_highlight 1
[ "$SELECTED_PID" = 126 ] && [ "$COMMAND_SCROLL_OFFSET" -eq 2 ] || exit 1
move_highlight 1
[ "$SELECTED_PID" = 127 ] && [ "$COMMAND_SCROLL_OFFSET" -eq 3 ] || exit 1
SELECTED_PID=129
COMMAND_SCROLL_OFFSET=5
move_highlight 1
[ "$SELECTED_PID" = 129 ] || exit 1
EXPANDED_UID=1000
TABLE_PAGE_SIZE=5
COMMAND_SCROLL_OFFSET=3
move_highlight 1
[ "$SELECTED_PID" = 130 ] && [ "$COMMAND_SCROLL_OFFSET" -eq 3 ] || exit 1
move_highlight -1
[ "$SELECTED_PID" = 129 ] || exit 1
INTERACTIVE_TABLE=1
EXPANDED_UID=
SELECTED_PID=130
sync_highlight_visibility
[ -z "$SELECTED_PID" ] || exit 1
EXPANDED_UID=1000
SELECTED_PID=130
sync_highlight_visibility
[ "$SELECTED_PID" = 130 ] || exit 1

: >"$HITMAP_TEST"
: >"$LAYOUT_TEST"
LC_ALL=C awk -F '\t' \
    -v elapsed=0.5 -v refresh_interval=0.5 -v display_mode=compact \
    -v interactive_ui=1 -v table_scroll=0 -v command_view_size=2 \
    -v command_scroll_uid=1000 -v command_scroll_offset=2 \
    -v selected_uid=1000 -v selected_pid=125 -v expanded_uid='' \
    -v hitmap_file="$HITMAP_TEST" \
    -v layout_state_file="$LAYOUT_TEST" -v backend=test -v scope=test \
    -v ui_width=80 -v ui_height=24 -v interface_name=test0 \
    -v interface_rx_delta=0 -v interface_tx_delta=0 \
    -v attribution_device_scoped=0 -v history_limit=120 -v host_name=test \
    -v session_label='[q] [j/k/Pg] Users [[/]] Cmd [mouse]' \
    -v display_time=test -f "$PROJECT_ROOT/src/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$PROJECT_ROOT/tests/fixtures/commands_scroll.tsv" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
[ "$(wc -l <"$SMOKE_OUTPUT")" -eq 24 ] || exit 1
grep -q 'Users 1-2/2' "$SMOKE_OUTPUT" || exit 1
grep -q 'PID 125' "$SMOKE_OUTPUT" || exit 1
grep -q 'PID 126' "$SMOKE_OUTPUT" || exit 1
grep -q 'command.*1000.*125' "$HITMAP_TEST" || exit 1
grep -q "$(printf 'table\t0\t2')" "$LAYOUT_TEST" || exit 1
grep -q "$(printf 'command\t1000\t2')" "$LAYOUT_TEST" || exit 1

HITMAP=$HITMAP_TEST
TABLE_SCROLL=0
COMMAND_SCROLL_UID=
COMMAND_SCROLL_OFFSET=0
SELECTED_UID=
SELECTED_PID=
EXPANDED_UID=
mouse_row=$(LC_ALL=C awk -F '\t' '$2 == "command" && $4 == 125 { print $1; exit }' \
    "$HITMAP_TEST")
pressed_key=$(printf '\033[<0;10;%sM' "$mouse_row")
handle_mouse_event
[ "$SELECTED_UID" = 1000 ] && [ "$SELECTED_PID" = 125 ] || exit 1
pressed_key=$(printf '\033[<65;10;%sM' "$mouse_row")
handle_mouse_event
[ "$COMMAND_SCROLL_OFFSET" -eq 1 ] || exit 1
pressed_key=$(printf '\033[<65;10;1M')
handle_mouse_event
[ "$TABLE_SCROLL" -eq 1 ] || exit 1

user_row=$(LC_ALL=C awk -F '\t' '$2 == "user" && $3 == 1000 { print $1; exit }' \
    "$HITMAP_TEST")
pressed_key=$(printf '\033[<0;10;%sM' "$user_row")
handle_mouse_event
[ "$SELECTED_UID" = 1000 ] && [ "$EXPANDED_UID" = 1000 ] || exit 1
pressed_key=$(printf '\033[<0;10;%sM' "$user_row")
handle_mouse_event
[ -z "$EXPANDED_UID" ] || exit 1
pressed_key=$(printf '\033[<0;10;%sm' "$user_row")
if handle_mouse_event; then
    printf 'Error: A mouse-release event requested a table refresh.\n' >&2
    exit 1
fi

SELECTED_UID=1000
SELECTED_PID=130
EXPANDED_UID=
COMMAND_SCROLL_UID=
COMMAND_SCROLL_OFFSET=4
toggle_selected_user
[ "$EXPANDED_UID" = 1000 ] || exit 1
[ "$COMMAND_SCROLL_UID" = 1000 ] || exit 1
[ "$COMMAND_SCROLL_OFFSET" -eq 0 ] || exit 1
[ -z "$SELECTED_PID" ] || exit 1
toggle_selected_user
[ -z "$EXPANDED_UID" ] || exit 1

: >"$HITMAP_TEST"
: >"$LAYOUT_TEST"
LC_ALL=C awk -F '\t' \
    -v elapsed=0.5 -v refresh_interval=0.5 -v display_mode=compact \
    -v interactive_ui=1 -v table_scroll=0 -v command_view_size=2 \
    -v command_scroll_uid=1000 -v command_scroll_offset=3 \
    -v selected_uid=1000 -v selected_pid=130 -v expanded_uid=1000 \
    -v hitmap_file="$HITMAP_TEST" -v layout_state_file="$LAYOUT_TEST" \
    -v backend=test -v scope=test -v ui_width=80 -v ui_height=24 \
    -v interface_name=test0 -v interface_rx_delta=0 -v interface_tx_delta=0 \
    -v attribution_device_scoped=0 -v history_limit=120 -v host_name=test \
    -v session_label='[q] [j/k/Pg] [x] [[/]] [mouse]' \
    -v display_time=test -f "$PROJECT_ROOT/src/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$PROJECT_ROOT/tests/fixtures/commands_scroll.tsv" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
[ "$(wc -l <"$SMOKE_OUTPUT")" -eq 24 ] || exit 1
grep -q 'ALL-INTERFACE CHECKED' "$SMOKE_OUTPUT" || exit 1
grep -q '\[x\].*alice' "$SMOKE_OUTPUT" || exit 1
grep -q 'PID 126' "$SMOKE_OUTPUT" || exit 1
grep -q 'PID 130.*UP 0 B/s  DN 0 B/s' "$SMOKE_OUTPUT" || exit 1
grep -q 'command.*1000.*130' "$HITMAP_TEST" || exit 1
grep -q 'ACCOUNTED (ALL IFA' "$SMOKE_OUTPUT" || exit 1
grep -q "$(printf 'expanded\t1000')" "$LAYOUT_TEST" || exit 1
grep -q "$(printf 'table\t0\t5')" "$LAYOUT_TEST" || exit 1
grep -q "$(printf 'command\t1000\t3')" "$LAYOUT_TEST" || exit 1

for RESIZE_HEIGHT in 34 35 36 37 38; do
    LC_ALL=C awk -F '\t' \
        -v elapsed=0.5 -v refresh_interval=0.5 -v display_mode=auto \
        -v backend=test -v scope=test -v ui_width=120 -v ui_height="$RESIZE_HEIGHT" \
        -v interface_name=test0 -v interface_rx_delta=3145728 \
        -v interface_tx_delta=1572864 -v attribution_device_scoped=0 \
        -v history_limit=120 -v host_name=test -v session_label=test \
        -v display_time=test -f "$PROJECT_ROOT/src/ui/table.awk" \
        "$PROJECT_ROOT/tests/fixtures/names.tsv" \
        "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
        "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
        "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
    [ "$(wc -l <"$SMOKE_OUTPUT")" -le "$RESIZE_HEIGHT" ] || {
        printf 'Error: Auto layout exceeded resized terminal height %s.\n' \
            "$RESIZE_HEIGHT" >&2
        exit 1
    }
done

UTF8_TEST_LOCALE=
VISUAL_WIDTH_CHECK=0
if command -v locale >/dev/null 2>&1; then
    UTF8_TEST_LOCALE=$(locale -a 2>/dev/null | LC_ALL=C awk '
        tolower($0) == "c.utf8" || tolower($0) == "c.utf-8" { print; exit }
    ')
fi
if [ -n "$UTF8_TEST_LOCALE" ] \
        && LC_ALL="$UTF8_TEST_LOCALE" wc -L </dev/null >/dev/null 2>&1; then
    VISUAL_WIDTH_CHECK=1
    assert_exact_frame_width() {
        expected_frame_width=$1
        exact_width_failed=0
        while IFS= read -r frame_line; do
            [ -n "$frame_line" ] || continue
            frame_line_width=$(printf '%s\n' "$frame_line" \
                | LC_ALL="$UTF8_TEST_LOCALE" wc -L \
                | LC_ALL=C awk '{ print $1 + 0 }')
            if [ "$frame_line_width" -ne "$expected_frame_width" ]; then
                exact_width_failed=1
                break
            fi
        done <"$SMOKE_OUTPUT"
        [ "$exact_width_failed" -eq 0 ] || {
            printf 'Error: A table row did not fill width %s.\n' \
                "$expected_frame_width" >&2
            exit 1
        }
    }
    render_responsive_test 100 28 100 "$PROJECT_ROOT/tests/fixtures/rows_three.tsv"
    assert_exact_frame_width 100
    if grep -q '测试' "$SMOKE_OUTPUT"; then exit 1; fi
    render_responsive_test 120 40 100
    assert_exact_frame_width 120
    for WIDTH_MODE in compact auto full; do
        for RESIZE_WIDTH in 78 79 80 120 160 200 240; do
            LC_ALL=C awk -F '\t' \
                -v elapsed=0.1 -v refresh_interval=0.1 \
                -v display_mode="$WIDTH_MODE" -v backend=test -v scope=test \
                -v ui_width="$RESIZE_WIDTH" -v ui_height=24 \
                -v interface_name=test0 -v interface_rx_delta=0 \
                -v interface_tx_delta=0 -v attribution_device_scoped=0 \
                -v history_limit=120 -v host_name=test -v session_label=test \
                -v display_time=test -f "$PROJECT_ROOT/src/ui/table.awk" \
                "$PROJECT_ROOT/tests/fixtures/names.tsv" \
                "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
                "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
                "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
            [ "$(LC_ALL="$UTF8_TEST_LOCALE" wc -L <"$SMOKE_OUTPUT")" \
                -le "$RESIZE_WIDTH" ] || {
                printf 'Error: %s layout exceeded resized terminal width %s.\n' \
                    "$WIDTH_MODE" "$RESIZE_WIDTH" >&2
                exit 1
            }
            [ "$(wc -l <"$SMOKE_OUTPUT")" -le 24 ] || exit 1
        done
    done
fi

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}
. "$PROJECT_ROOT/src/core/history.sh"
HISTORY=$HISTORY_TEST
TABLE_ROWS=$PROJECT_ROOT/tests/fixtures/rows.tsv
HISTORY_SAMPLE=0
HISTORY_LIMIT=120
INTERFACE_TX_DELTA=1572864
INTERFACE_RX_DELTA=3145728
printf '1\tI\t1\t2\n1\tU:1000\t3\t4\n1\tA\t3\t4\n' >"$HISTORY"
reset_interface_history
if LC_ALL=C awk -F '\t' '$2 == "I" { found = 1 } END { exit !found }' \
        "$HISTORY"; then
    exit 1
fi
grep -Fq "$(printf '1\tU:1000\t3\t4')" "$HISTORY" || exit 1
grep -Fq "$(printf '1\tA\t3\t4')" "$HISTORY" || exit 1
: >"$HISTORY"
history_test_sample=0
while [ "$history_test_sample" -lt 125 ]; do
    record_history 1
    history_test_sample=$((history_test_sample + 1))
done
LC_ALL=C awk -F '\t' '
    $2 == "I" {
        if (!count || $1 < oldest) oldest = $1
        newest = $1
        count++
    }
    END { exit !(count == 120 && oldest == 6 && newest == 125) }
' "$HISTORY" || exit 1

LC_ALL=C awk -F '\t' \
    -v elapsed=0.1 -v refresh_interval=0.1 -v display_mode=compact \
    -v backend=test -v scope=test -v ui_width=78 -v ui_height=24 \
    -v interface_name=test0 -v interface_rx_delta=0 \
    -v interface_tx_delta=0 -v attribution_device_scoped=0 \
    -v history_limit=120 -v host_name=test -v session_label=test \
    -v display_time=test -f "$PROJECT_ROOT/src/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" /dev/null \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" "$HISTORY" >"$SMOKE_OUTPUT" || exit 1
grep -q '120/120' "$SMOKE_OUTPUT" || exit 1
if [ "$VISUAL_WIDTH_CHECK" -eq 1 ]; then
    [ "$(LC_ALL="$UTF8_TEST_LOCALE" wc -L <"$SMOKE_OUTPUT")" -le 78 ] || exit 1
fi

printf 'Smoke tests passed.\n'
