# Runtime, option validation, terminal lifecycle, and temporary state.

usage() {
    cat <<EOF
Usage: $PROGRAM [options]

Monitor network upload and download usage grouped by local user.

Options:
  -i, --interval SECONDS  Sampling interval in 0.1-second steps (default: 0.5)
  -d, --device INTERFACE  Monitor this interface (default: default route)
  -n, --count NUMBER      Stop after NUMBER reports (default: run continuously)
  -m, --mode MODE         Display mode: auto, compact, or full (default: auto)
      --two-column-width N Split upload/download at N columns (default: 100)
  -f, --format FORMAT     Output format: table, csv, or jsonl (default: table)
  -o, --output FILE       Write reports to FILE instead of standard output
      --append            Append to FILE instead of replacing it
  -h, --help              Show this help and exit

Interactive keys:
  q / Q                   Quit and restore the terminal
  r / R                   Refresh immediately
  + / -                   Decrease / increase the refresh interval
  a / c / f               Auto / compact / full display mode
  Up / Down, j / k        Scroll the user table
  PageUp / PageDown       Scroll users, or commands for a checked user
  [ / ]                   Scroll the selected user's command area
  Space / x               Check or uncheck the selected user
  Mouse click / wheel     Highlight rows and scroll table or command areas

Backends:
  Linux   sysfs interface counters; ss for user/command attribution
  macOS   interface counters; nettop for user/command attribution

No privilege escalation is attempted. Root is normally not required, but a
hardened host may restrict access to system-wide network statistics. On Linux,
root is required for complete command attribution across all users; inaccessible
socket owners are grouped under [unattributed].
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

is_positive_integer() {
    case $1 in
        ''|*[!0-9]*|0) return 1 ;;
        *) return 0 ;;
    esac
}

is_valid_interval() {
    LC_ALL=C awk -v value="$1" 'BEGIN {
        valid = value ~ /^([0-9]+([.][0-9])?|[.][0-9])$/
        exit !(valid && (value + 0) >= 0.1)
    }'
}

set_interval_tenths() {
    INTERVAL_TENTHS=$1
    INTERVAL=$(LC_ALL=C awk -v tenths="$INTERVAL_TENTHS" 'BEGIN {
        if (tenths % 10 == 0) printf "%d", tenths / 10
        else printf "%.1f", tenths / 10.0
    }')
}

normalize_interval() {
    interval_tenths=$(LC_ALL=C awk -v value="$INTERVAL" \
        'BEGIN { printf "%.0f", (value + 0) * 10 }')
    set_interval_tenths "$interval_tenths"
}

parse_options() {
    while [ "$#" -gt 0 ]; do
        case $1 in
            -d|--device)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                DEVICE=$2
                shift 2
                ;;
            -i|--interval)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                INTERVAL=$2
                shift 2
                ;;
            -n|--count)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                COUNT=$2
                shift 2
                ;;
            -f|--format)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                FORMAT=$2
                shift 2
                ;;
            -m|--mode)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                DISPLAY_MODE=$2
                shift 2
                ;;
            --two-column-width)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                TWO_COLUMN_WIDTH=$2
                shift 2
                ;;
            -o|--output)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                OUTPUT=$2
                shift 2
                ;;
            --append)
                APPEND=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                [ "$#" -eq 0 ] || fail "Unexpected positional arguments: $*"
                ;;
            -*) fail "Unknown option: $1" ;;
            *) fail "Unexpected positional argument: $1" ;;
        esac
    done
}

validate_options() {
    is_valid_interval "$INTERVAL" \
        || fail "Interval must be at least 0.1 seconds in 0.1-second steps (maximum 10 Hz)"
    normalize_interval
    if [ -n "$COUNT" ]; then
        is_positive_integer "$COUNT" || fail "Count must be a positive integer"
    fi
    case $FORMAT in
        table|csv|jsonl) ;;
        *) fail "Format must be table, csv, or jsonl" ;;
    esac
    case $DISPLAY_MODE in
        auto|compact|full) ;;
        *) fail "Display mode must be auto, compact, or full" ;;
    esac
    is_positive_integer "$TWO_COLUMN_WIDTH" \
        || fail "Two-column width must be a positive integer"
    [ "$APPEND" -eq 0 ] || [ -n "$OUTPUT" ] || fail "--append requires --output"
    [ "$FORMAT" != table ] || [ "$APPEND" -eq 0 ] \
        || fail "--append is only available with csv or jsonl output"
}

validate_commands() {
    for required_command in uname awk sort cut ps date sleep mktemp wc cat mv rm rmdir; do
        command -v "$required_command" >/dev/null 2>&1 \
            || fail "Required command not found: $required_command"
    done
}

detect_platform() {
    OS_NAME=$(uname -s 2>/dev/null) || fail "Unable to identify the operating system"
    HOST_NAME=$(uname -n 2>/dev/null) || HOST_NAME=unknown-host
    case $OS_NAME in
        Linux)
            BACKEND='Linux sysfs + ss'
            SCOPE='Selected-interface RX/TX; all-interface TCP attribution'
            ATTRIBUTION_DEVICE_SCOPED=0
            INTERFACE_FORCE_FALLBACK=0
            command -v ss >/dev/null 2>&1 \
                || fail "Linux backend requires the ss command from iproute2"
            ;;
        Darwin)
            BACKEND='macOS netstat + nettop'
            SCOPE='Interface RX/TX; all-interface TCP/UDP attribution'
            ATTRIBUTION_DEVICE_SCOPED=0
            INTERFACE_FORCE_FALLBACK=1
            [ -x /usr/bin/nettop ] \
                || fail "macOS backend requires the built-in /usr/bin/nettop command"
            MACOS_NETTOP=/usr/bin/nettop
            MACOS_NETSTAT=/usr/sbin/netstat
            MACOS_ROUTE=/sbin/route
            MACOS_IFCONFIG=/sbin/ifconfig
            [ -x "$MACOS_NETSTAT" ] && [ -x "$MACOS_ROUTE" ] \
                && [ -x "$MACOS_IFCONFIG" ] \
                || fail "macOS backend requires netstat, route, and ifconfig"
            ;;
        *) fail "Unsupported operating system: $OS_NAME (supported: Linux and macOS)" ;;
    esac
}

configure_table_target() {
    [ "$FORMAT" = table ] && [ -z "$OUTPUT" ] || return 0
    INTERACTIVE_TABLE=1
    if [ -t 1 ]; then
        TABLE_TARGET=/dev/stdout
    elif (: >/dev/tty) 2>/dev/null; then
        TABLE_TARGET=/dev/tty
    else
        fail "Live table output requires an interactive terminal; use --output or select csv/jsonl"
    fi
}

create_workspace() {
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/netwtop.XXXXXX") \
        || fail "Unable to create a temporary directory"
    PREVIOUS=$WORK_DIR/previous.tsv
    CURRENT=$WORK_DIR/current.tsv
    TOTALS=$WORK_DIR/totals.tsv
    NEXT_TOTALS=$WORK_DIR/next-totals.tsv
    COMMAND_TOTALS=$WORK_DIR/command-totals.tsv
    NEXT_COMMAND_TOTALS=$WORK_DIR/next-command-totals.tsv
    ROWS=$WORK_DIR/rows.tsv
    SORTED_ROWS=$WORK_DIR/sorted-rows.tsv
    TABLE_ROWS=$WORK_DIR/table-rows.tsv
    COMMAND_ROWS=$WORK_DIR/command-rows.tsv
    SORTED_COMMAND_ROWS=$WORK_DIR/sorted-command-rows.tsv
    RAW=$WORK_DIR/raw.txt
    ERROR_LOG=$WORK_DIR/error.txt
    PID_COMMANDS=$WORK_DIR/pid-commands.tsv
    UID_NAMES=$WORK_DIR/uid-names.tsv
    FRAME=$WORK_DIR/frame.txt
    PREVIOUS_FRAME=$WORK_DIR/previous-frame.txt
    HITMAP=$WORK_DIR/hitmap.tsv
    LAYOUT_STATE=$WORK_DIR/layout-state.tsv
    INTERFACE_PREVIOUS=$WORK_DIR/interface-previous.tsv
    INTERFACE_CURRENT=$WORK_DIR/interface-current.tsv
    INTERFACE_RAW=$WORK_DIR/interface-raw.txt
    HISTORY=$WORK_DIR/history.tsv
    NEXT_HISTORY=$WORK_DIR/next-history.tsv
}

restore_terminal() {
    if [ "$MOUSE_ENABLED" -eq 1 ]; then
        printf '\033[?1000l\033[?1006l' >/dev/tty 2>/dev/null || true
        MOUSE_ENABLED=0
    fi
    if [ "$CURSOR_HIDDEN" -eq 1 ]; then
        if [ -n "${TERM:-}" ] && command -v tput >/dev/null 2>&1; then
            tput cnorm >/dev/tty 2>/dev/null || printf '\033[?25h' >/dev/tty
        else
            printf '\033[?25h' >/dev/tty 2>/dev/null || true
        fi
        CURSOR_HIDDEN=0
    fi
    if [ "$ALT_SCREEN" -eq 1 ]; then
        if [ -n "${TERM:-}" ] && command -v tput >/dev/null 2>&1; then
            tput rmcup >/dev/tty 2>/dev/null || printf '\033[?1049l' >/dev/tty
        else
            printf '\033[?1049l' >/dev/tty 2>/dev/null || true
        fi
        ALT_SCREEN=0
    fi
    if [ -n "$TTY_STATE" ]; then
        stty "$TTY_STATE" </dev/tty 2>/dev/null || true
        TTY_STATE=
    fi
}

cleanup() {
    restore_terminal
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -f "$PREVIOUS" "$CURRENT" "$TOTALS" "$NEXT_TOTALS" \
            "$COMMAND_TOTALS" "$NEXT_COMMAND_TOTALS" "$ROWS" "$SORTED_ROWS" \
            "$TABLE_ROWS" "$COMMAND_ROWS" "$SORTED_COMMAND_ROWS" "$RAW" \
            "$ERROR_LOG" "$PID_COMMANDS" "$UID_NAMES" "$FRAME" \
            "$PREVIOUS_FRAME" "$HITMAP" "$LAYOUT_STATE" \
            "$INTERFACE_PREVIOUS" "$INTERFACE_CURRENT" "$INTERFACE_RAW" \
            "$HISTORY" "$NEXT_HISTORY"
        rmdir "$WORK_DIR" 2>/dev/null || true
    fi
}

request_stop() {
    STOPPING=1
}

request_resize() {
    RESIZE_PENDING=1
}

enable_interactive_terminal() {
    [ "$INTERACTIVE_TABLE" -eq 1 ] || return 0
    command -v stty >/dev/null 2>&1 \
        || fail "Interactive table mode requires the stty command"
    command -v dd >/dev/null 2>&1 \
        || fail "Interactive table mode requires the dd command"
    TTY_STATE=$(stty -g </dev/tty 2>/dev/null) \
        || fail "Unable to read terminal input settings"
    stty -echo -icanon min 0 time 1 </dev/tty 2>/dev/null \
        || fail "Unable to enable single-key terminal input"

    if [ -n "${TERM:-}" ] && command -v tput >/dev/null 2>&1; then
        terminal_sequence=$(tput smcup 2>/dev/null || true)
        if [ -n "$terminal_sequence" ]; then
            printf '%s' "$terminal_sequence" >"$TABLE_TARGET"
            ALT_SCREEN=1
        fi
        terminal_sequence=$(tput civis 2>/dev/null || true)
        if [ -n "$terminal_sequence" ]; then
            printf '%s' "$terminal_sequence" >"$TABLE_TARGET"
            CURSOR_HIDDEN=1
        fi
    else
        printf '\033[?1049h\033[?25l' >"$TABLE_TARGET"
        ALT_SCREEN=1
        CURSOR_HIDDEN=1
    fi

    case ${TERM:-} in
        ''|dumb) ;;
        *)
            printf '\033[?1000h\033[?1006h' >"$TABLE_TARGET"
            MOUSE_ENABLED=1
            ;;
    esac
}

scroll_user_table() {
    scroll_delta=$1
    if [ -n "${EXPANDED_UID:-}" ]; then
        SELECTED_UID=$EXPANDED_UID
        scroll_selected_commands "$scroll_delta"
        return
    fi
    TABLE_SCROLL=$((TABLE_SCROLL + scroll_delta))
    [ "$TABLE_SCROLL" -ge 0 ] || TABLE_SCROLL=0
}

toggle_selected_user() {
    [ -n "$SELECTED_UID" ] || return
    if [ "${EXPANDED_UID:-}" = "$SELECTED_UID" ]; then
        EXPANDED_UID=
    else
        EXPANDED_UID=$SELECTED_UID
        COMMAND_SCROLL_UID=$SELECTED_UID
        COMMAND_SCROLL_OFFSET=0
    fi
    SELECTED_PID=
}

scroll_selected_commands() {
    scroll_delta=$1
    [ -n "$SELECTED_UID" ] || return
    if [ "$COMMAND_SCROLL_UID" != "$SELECTED_UID" ]; then
        COMMAND_SCROLL_UID=$SELECTED_UID
        COMMAND_SCROLL_OFFSET=0
    fi
    COMMAND_SCROLL_OFFSET=$((COMMAND_SCROLL_OFFSET + scroll_delta))
    [ "$COMMAND_SCROLL_OFFSET" -ge 0 ] || COMMAND_SCROLL_OFFSET=0
}

handle_mouse_event() {
    mouse_payload=${pressed_key#???}
    mouse_body=${mouse_payload%?}
    mouse_suffix=${mouse_payload#"$mouse_body"}
    previous_ifs=$IFS
    IFS=';'
    set -- $mouse_body
    IFS=$previous_ifs
    [ "$#" -eq 3 ] || return
    mouse_button=$1
    mouse_column=$2
    mouse_row=$3
    case $mouse_button:$mouse_column:$mouse_row in
        *[!0-9:]*|:*|*::*|*:) return ;;
    esac
    [ "$mouse_suffix" != m ] || return

    hit_type=
    hit_uid=
    hit_pid=
    if [ -r "$HITMAP" ]; then
        hit_record=$(LC_ALL=C awk -F '\t' -v row="$mouse_row" \
            -v column="$mouse_column" '
                $1 == row && (NF < 7 || (column >= $6 && column <= $7)) {
                    print $2 "\t" $3 "\t" $4
                    exit
                }
            ' "$HITMAP")
        if [ -n "$hit_record" ]; then
            previous_ifs=$IFS
            IFS=$(printf '\t')
            set -- $hit_record
            IFS=$previous_ifs
            hit_type=${1:-}
            hit_uid=${2:-}
            hit_pid=${3:-}
        fi
    fi

    case $mouse_button in
        0)
            if [ -n "$hit_uid" ]; then
                if [ "$COMMAND_SCROLL_UID" != "$hit_uid" ]; then
                    COMMAND_SCROLL_UID=$hit_uid
                    COMMAND_SCROLL_OFFSET=0
                fi
                SELECTED_UID=$hit_uid
                case $hit_type in
                    command) SELECTED_PID=$hit_pid ;;
                    user)
                        SELECTED_PID=
                        toggle_selected_user
                        ;;
                    *) SELECTED_PID= ;;
                esac
            fi
            ;;
        64)
            case $hit_type in
                command|command_zone)
                    SELECTED_UID=$hit_uid
                    scroll_selected_commands -1
                    ;;
                *) scroll_user_table -1 ;;
            esac
            ;;
        65)
            case $hit_type in
                command|command_zone)
                    SELECTED_UID=$hit_uid
                    scroll_selected_commands 1
                    ;;
                *) scroll_user_table 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
    return 0
}

read_escape_sequence() {
    key_tail=
    escape_byte_count=0
    while [ "$escape_byte_count" -lt 64 ]; do
        escape_tail_byte=$(dd if=/dev/tty bs=1 count=1 2>/dev/null || true)
        [ -n "$escape_tail_byte" ] || break
        key_tail=$key_tail$escape_tail_byte
        escape_byte_count=$((escape_byte_count + 1))
        case $key_tail in
            '[<'*M|'[<'*m|'['*'~'|'['*[A-Za-z]|O[A-Za-z]) break ;;
        esac
    done
}

wait_interval_or_key() {
    if [ "$INTERACTIVE_TABLE" -ne 1 ]; then
        sleep "$INTERVAL" || true
        return
    fi

    wait_ticks=$INTERVAL_TENTHS
    wait_tick=0
    while [ "$STOPPING" -eq 0 ] && [ "$wait_tick" -lt "$wait_ticks" ]; do
        if [ "$RESIZE_PENDING" -eq 1 ]; then
            return
        fi
        pressed_key=$(dd if=/dev/tty bs=1 count=1 2>/dev/null || true)
        if [ "$pressed_key" = "$ESCAPE_SEQUENCE" ]; then
            read_escape_sequence
            pressed_key=$pressed_key$key_tail
        fi
        case $pressed_key in
            q|Q) STOPPING=1 ;;
            r|R) return ;;
            +|=)
                if [ "$INTERVAL_TENTHS" -gt 1 ]; then
                    set_interval_tenths "$((INTERVAL_TENTHS - 1))"
                fi
                return
                ;;
            -|_)
                set_interval_tenths "$((INTERVAL_TENTHS + 1))"
                return
                ;;
            a|A) DISPLAY_MODE=auto; return ;;
            c|C) DISPLAY_MODE=compact; return ;;
            f|F) DISPLAY_MODE=full; return ;;
            j|J|"${ESCAPE_SEQUENCE}[B"|"${ESCAPE_SEQUENCE}OB")
                scroll_user_table 1; return ;;
            k|K|"${ESCAPE_SEQUENCE}[A"|"${ESCAPE_SEQUENCE}OA")
                scroll_user_table -1; return ;;
            "${ESCAPE_SEQUENCE}[5~")
                scroll_user_table "$((-TABLE_PAGE_SIZE))"; return ;;
            "${ESCAPE_SEQUENCE}[6~")
                scroll_user_table "$TABLE_PAGE_SIZE"; return ;;
            '[') scroll_selected_commands -1; return ;;
            ']') scroll_selected_commands 1; return ;;
            ' '|x|X) toggle_selected_user; return ;;
            "${ESCAPE_SEQUENCE}[<"*M|"${ESCAPE_SEQUENCE}[<"*m)
                if handle_mouse_event; then
                    return
                fi
                ;;
            '') wait_tick=$((wait_tick + 1)) ;;
        esac
    done
}
