#!/bin/sh
# Fast checks that do not require network access or elevated privileges.

set -u

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1

for shell_file in \
    netwtop \
    install.sh \
    bin/netwtop \
    compat/network_monitor.sh \
    lib/netwtop/runtime.sh \
    lib/netwtop/accounting.sh \
    lib/netwtop/formats.sh \
    lib/netwtop/interfaces.sh \
    lib/netwtop/history.sh \
    lib/netwtop/backends/common.sh \
    lib/netwtop/backends/linux.sh \
    lib/netwtop/backends/macos.sh \
    lib/netwtop/ui/table.sh
do
    sh -n "$PROJECT_ROOT/$shell_file" || exit 1
done

"$PROJECT_ROOT/netwtop" --help >/dev/null || exit 1
"$PROJECT_ROOT/compat/network_monitor.sh" --help >/dev/null || exit 1
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
[ -s "$PROJECT_ROOT/docs/ARCHITECTURE.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/APT_PACKAGING.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/DEVELOPMENT.md" ] || exit 1
[ -s "$PROJECT_ROOT/docs/SELF_HOSTED_APT_REPOSITORY.md" ] || exit 1
if "$PROJECT_ROOT/netwtop" --interval 0.09 --format jsonl --count 1 \
        >/dev/null 2>&1; then
    printf 'Error: An interval faster than 10 Hz was accepted.\n' >&2
    exit 1
fi
. "$PROJECT_ROOT/lib/netwtop/runtime.sh"
is_valid_interval 0.1 || exit 1
is_valid_interval 0.5 || exit 1
is_valid_interval 1.5 || exit 1
is_valid_interval 0.09 && exit 1
INTERVAL=0.5
normalize_interval
[ "$INTERVAL" = 0.5 ] && [ "$INTERVAL_TENTHS" -eq 5 ] || exit 1
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
    -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
    /dev/null /dev/null /dev/null /dev/null >/dev/null || exit 1

SMOKE_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/netwtop-smoke.XXXXXX") || exit 1
HISTORY_TEST=$(mktemp "${TMPDIR:-/tmp}/netwtop-history.XXXXXX") || exit 1
NEXT_HISTORY=${HISTORY_TEST}.next
HITMAP_TEST=$(mktemp "${TMPDIR:-/tmp}/netwtop-hitmap.XXXXXX") || exit 1
LAYOUT_TEST=$(mktemp "${TMPDIR:-/tmp}/netwtop-layout.XXXXXX") || exit 1
trap 'rm -f "$SMOKE_OUTPUT" "$HISTORY_TEST" "$NEXT_HISTORY" "$HITMAP_TEST" "$LAYOUT_TEST"' 0 HUP INT TERM
LC_ALL=C awk -F '\t' \
    -v elapsed=1 -v refresh_interval=1 -v display_mode=compact \
    -v backend=test -v scope=test -v ui_width=80 -v ui_height=24 \
    -v interface_name=test0 -v interface_rx_delta=209715200 \
    -v interface_tx_delta=157286400 -v attribution_device_scoped=0 \
    -v history_limit=60 -v host_name=test -v session_label=test \
    -v display_time=test -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1

grep -q '128 MiB/s' "$SMOKE_OUTPUT" || exit 1
grep -q 'MAX' "$SMOKE_OUTPUT" || exit 1
grep -q 'UP HISTORY' "$SMOKE_OUTPUT" || exit 1
grep -q 'HISTORY UP|DN' "$SMOKE_OUTPUT" || exit 1
grep -q 'ACCOUNTED' "$SMOKE_OUTPUT" || exit 1
[ "$(wc -l <"$SMOKE_OUTPUT")" -le 24 ] || exit 1

LC_ALL=C awk -F '\t' \
    -v elapsed=1 -v refresh_interval=1 -v display_mode=full \
    -v backend=test -v scope=test -v ui_width=120 -v ui_height=50 \
    -v interface_name=test0 -v interface_rx_delta=3145728 \
    -v interface_tx_delta=1572864 -v attribution_device_scoped=0 \
    -v history_limit=120 -v host_name=test -v session_label=test \
    -v display_time=test -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
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
        -v interface_rx_delta=3145728 -v interface_tx_delta=1572864 \
        -v attribution_device_scoped=0 -v history_limit=120 -v host_name=test \
        -v session_label=test -v display_time=test \
        -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
        "$PROJECT_ROOT/tests/fixtures/names.tsv" \
        "$PROJECT_ROOT/tests/fixtures/commands.tsv" \
        "$responsive_rows" \
        "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
    [ "$(wc -l <"$SMOKE_OUTPUT")" -le "$responsive_height" ] || exit 1
}

render_responsive_test 99 24 100
grep -q 'UP HISTORY' "$SMOKE_OUTPUT" || exit 1
grep -q 'UPLOAD/s' "$SMOKE_OUTPUT" || exit 1
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
    -v display_time=test -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
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
    -v display_time=test -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" \
    "$PROJECT_ROOT/tests/fixtures/commands_scroll.tsv" \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" \
    "$PROJECT_ROOT/tests/fixtures/history.tsv" >"$SMOKE_OUTPUT" || exit 1
[ "$(wc -l <"$SMOKE_OUTPUT")" -eq 24 ] || exit 1
grep -q 'CHECKED  Commands 4-8/8  alice' "$SMOKE_OUTPUT" || exit 1
grep -q '\[x\].*alice' "$SMOKE_OUTPUT" || exit 1
grep -q 'PID 126' "$SMOKE_OUTPUT" || exit 1
grep -q 'PID 130.*UP 0 B/s  DN 0 B/s' "$SMOKE_OUTPUT" || exit 1
grep -q 'command.*1000.*130' "$HITMAP_TEST" || exit 1
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
        -v display_time=test -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
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
                -v display_time=test -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
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
. "$PROJECT_ROOT/lib/netwtop/history.sh"
HISTORY=$HISTORY_TEST
TABLE_ROWS=$PROJECT_ROOT/tests/fixtures/rows.tsv
HISTORY_SAMPLE=0
HISTORY_LIMIT=120
INTERFACE_TX_DELTA=1572864
INTERFACE_RX_DELTA=3145728
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
    -v display_time=test -f "$PROJECT_ROOT/lib/netwtop/ui/table.awk" \
    "$PROJECT_ROOT/tests/fixtures/names.tsv" /dev/null \
    "$PROJECT_ROOT/tests/fixtures/rows.tsv" "$HISTORY" >"$SMOKE_OUTPUT" || exit 1
grep -q '120/120' "$SMOKE_OUTPUT" || exit 1
if [ "$VISUAL_WIDTH_CHECK" -eq 1 ]; then
    [ "$(LC_ALL="$UTF8_TEST_LOCALE" wc -L <"$SMOKE_OUTPUT")" -le 78 ] || exit 1
fi

printf 'Smoke tests passed.\n'
