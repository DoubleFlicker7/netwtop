# Interface-level byte accounting used for the dashboard totals.

select_linux_interface() {
    selected=$(LC_ALL=C awk '
        NR > 1 && $2 == "00000000" { print $1; exit }
    ' /proc/net/route 2>/dev/null || true)
    if [ -n "$selected" ]; then
        printf '%s\n' "$selected"
        return
    fi

    LC_ALL=C awk -F: '
        NR > 2 {
            name = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (first == "") first = name
            if (name != "lo") { print name; found = 1; exit }
        }
        END { if (!found && first != "") print first }
    ' /proc/net/dev 2>/dev/null
}

select_macos_interface() {
    selected=$($MACOS_ROUTE -n get default 2>/dev/null \
        | LC_ALL=C awk '$1 == "interface:" { print $2; exit }')
    if [ -n "$selected" ]; then
        printf '%s\n' "$selected"
        return
    fi

    interface_list=$($MACOS_IFCONFIG -l 2>/dev/null || true)
    first_interface=
    for candidate in $interface_list; do
        [ -n "$first_interface" ] || first_interface=$candidate
        if [ "$candidate" != lo0 ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    [ -z "$first_interface" ] || printf '%s\n' "$first_interface"
}

list_linux_interfaces() {
    LC_ALL=C awk -F: '
        NR > 2 {
            name = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (name != "") print name
        }
    ' /proc/net/dev 2>/dev/null | LC_ALL=C sort -u
}

list_macos_interfaces() {
    $MACOS_IFCONFIG -l 2>/dev/null \
        | LC_ALL=C awk '{ for (field = 1; field <= NF; field++) print $field }' \
        | LC_ALL=C sort -u
}

list_available_interfaces() {
    case $OS_NAME in
        Linux) list_linux_interfaces ;;
        Darwin) list_macos_interfaces ;;
    esac
}

refresh_interface_list() {
    INTERFACE_NAMES=$(list_available_interfaces)
    INTERFACE_COUNT=$(printf '%s\n' "$INTERFACE_NAMES" \
        | LC_ALL=C awk 'NF { count++ } END { print count + 0 }')
    INTERFACE_INDEX=$(printf '%s\n' "$INTERFACE_NAMES" \
        | LC_ALL=C awk -v device="$DEVICE" '
            NF { count++ }
            $0 == device { print count; found = 1; exit }
            END { if (!found) print 0 }
        ')

    # A successfully configured device should normally be present in the OS
    # list. Retain it without hiding the other choices if enumeration races
    # with a rename or temporarily omits the active device.
    if [ "$INTERFACE_INDEX" -eq 0 ]; then
        INTERFACE_NAMES=$(printf '%s\n%s\n' "$INTERFACE_NAMES" "$DEVICE" \
            | LC_ALL=C awk 'NF' | LC_ALL=C sort -u)
        INTERFACE_COUNT=$(printf '%s\n' "$INTERFACE_NAMES" \
            | LC_ALL=C awk 'NF { count++ } END { print count + 0 }')
        INTERFACE_INDEX=$(printf '%s\n' "$INTERFACE_NAMES" \
            | LC_ALL=C awk -v device="$DEVICE" '
                NF { count++ }
                $0 == device { print count; exit }
            ')
    fi
}

adjacent_interface_name() {
    interface_direction=$1
    [ "$INTERFACE_COUNT" -gt 1 ] || return 1
    case $interface_direction in
        -1)
            interface_target_index=$((INTERFACE_INDEX - 1))
            [ "$interface_target_index" -ge 1 ] \
                || interface_target_index=$INTERFACE_COUNT
            ;;
        1)
            interface_target_index=$((INTERFACE_INDEX + 1))
            [ "$interface_target_index" -le "$INTERFACE_COUNT" ] \
                || interface_target_index=1
            ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$INTERFACE_NAMES" | LC_ALL=C awk \
        -v target="$interface_target_index" '
            NF { count++ }
            count == target { print; exit }
        '
}

switch_interface() {
    interface_direction=$1
    refresh_interface_list
    interface_candidate=$(adjacent_interface_name "$interface_direction") \
        || return 1
    [ -n "$interface_candidate" ] && [ "$interface_candidate" != "$DEVICE" ] \
        || return 1
    DEVICE=$interface_candidate
    configure_interface
    return 0
}

configure_interface() {
    if [ -z "$DEVICE" ]; then
        case $OS_NAME in
            Linux) DEVICE=$(select_linux_interface) ;;
            Darwin) DEVICE=$(select_macos_interface) ;;
        esac
    fi

    case $DEVICE in
        ''|.|..|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-]*)
            fail "Unable to select a valid network interface; use --device INTERFACE"
            ;;
    esac

    case $OS_NAME in
        Linux)
            INTERFACE_RX_PATH=/sys/class/net/$DEVICE/statistics/rx_bytes
            INTERFACE_TX_PATH=/sys/class/net/$DEVICE/statistics/tx_bytes
            if [ -r "$INTERFACE_RX_PATH" ] && [ -r "$INTERFACE_TX_PATH" ]; then
                INTERFACE_COUNTER_METHOD=sysfs
                INTERFACE_SOURCE='Linux sysfs RX/TX counters'
                BACKEND='Linux sysfs + ss'
            elif [ -r /proc/net/dev ] && LC_ALL=C awk -F: -v device="$DEVICE" '
                    NR > 2 {
                        name = $1
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                        if (name == device) found = 1
                    }
                    END { exit !found }
                ' /proc/net/dev; then
                INTERFACE_COUNTER_METHOD=procfs
                INTERFACE_SOURCE='Linux /proc/net/dev RX/TX counters'
                BACKEND='Linux procfs + ss'
            else
                fail "Network interface not found or unreadable: $DEVICE"
            fi
            ;;
        Darwin)
            $MACOS_IFCONFIG "$DEVICE" >/dev/null 2>&1 \
                || fail "Network interface not found or unreadable: $DEVICE"
            INTERFACE_SOURCE='macOS interface byte counters'
            ;;
    esac
    refresh_interface_list
}

snapshot_interface_linux_sysfs() {
    target=$1
    LC_ALL=C awk '
        FILENAME == ARGV[1] { rx = $1; next }
        FILENAME == ARGV[2] { tx = $1; next }
        FILENAME == ARGV[3] {
            split($1, clock_parts, ".")
            fraction = substr(clock_parts[2] "00", 1, 2)
            ticks = (clock_parts[1] * 100) + fraction
        }
        END { printf "%.0f\t%.0f\t%.0f\n", rx, tx, ticks }
    ' "$INTERFACE_RX_PATH" "$INTERFACE_TX_PATH" /proc/uptime >"$target" \
        || fail "Unable to read counters for network interface: $DEVICE"
}

snapshot_interface_linux_procfs() {
    target=$1
    LC_ALL=C awk -v device="$DEVICE" '
        FILENAME == ARGV[1] && index($0, ":") {
            name = substr($0, 1, index($0, ":") - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (name != device) next
            counters = substr($0, index($0, ":") + 1)
            gsub(/^[[:space:]]+/, "", counters)
            split(counters, fields, /[[:space:]]+/)
            rx = fields[1]
            tx = fields[9]
            found = 1
            next
        }
        FILENAME == ARGV[2] {
            split($1, clock_parts, ".")
            fraction = substr(clock_parts[2] "00", 1, 2)
            ticks = (clock_parts[1] * 100) + fraction
        }
        END {
            if (!found) exit 1
            printf "%.0f\t%.0f\t%.0f\n", rx, tx, ticks
        }
    ' /proc/net/dev /proc/uptime >"$target" \
        || fail "Unable to read counters for network interface: $DEVICE"
}

snapshot_interface_linux() {
    case $INTERFACE_COUNTER_METHOD in
        sysfs) snapshot_interface_linux_sysfs "$1" ;;
        procfs) snapshot_interface_linux_procfs "$1" ;;
    esac
}

snapshot_interface_macos() {
    target=$1
    if ! LC_ALL=C "$MACOS_NETSTAT" -ibn -I "$DEVICE" \
            >"$INTERFACE_RAW" 2>"$ERROR_LOG"; then
        fail "Unable to read counters for network interface: $DEVICE"
    fi
    snapshot_epoch=$(date +%s) || fail "Unable to read the system clock"
    LC_ALL=C awk -v device="$DEVICE" -v ticks="${snapshot_epoch}00" '
        NR == 1 {
            for (column = 1; column <= NF; column++) {
                if ($column == "Ibytes") rx_column = column
                if ($column == "Obytes") tx_column = column
            }
            next
        }
        $1 == device && rx_column && tx_column {
            printf "%.0f\t%.0f\t%.0f\n", $rx_column, $tx_column, ticks
            found = 1
            exit
        }
        END {
            if (!found) exit 1
        }
    ' "$INTERFACE_RAW" >"$target" \
        || fail "Unable to parse counters for network interface: $DEVICE"
}

snapshot_interface() {
    case $OS_NAME in
        Linux) snapshot_interface_linux "$1" ;;
        Darwin) snapshot_interface_macos "$1" ;;
    esac
}

calculate_interface_delta() {
    delta_values=$(LC_ALL=C awk -F '\t' \
        -v fallback_ticks="$((INTERVAL_TENTHS * 10))" \
        -v force_fallback="${INTERFACE_FORCE_FALLBACK:-0}" '
        FILENAME == ARGV[1] {
            previous_rx = $1
            previous_tx = $2
            previous_ticks = $3
            next
        }
        FILENAME == ARGV[2] {
            current_rx = $1
            current_tx = $2
            current_ticks = $3
        }
        END {
            rx_delta = current_rx >= previous_rx ? current_rx - previous_rx : 0
            tx_delta = current_tx >= previous_tx ? current_tx - previous_tx : 0
            elapsed_ticks = current_ticks - previous_ticks
            if (force_fallback || elapsed_ticks <= 0) elapsed_ticks = fallback_ticks
            printf "%.0f %.0f %.0f\n", rx_delta, tx_delta, elapsed_ticks
        }
    ' "$INTERFACE_PREVIOUS" "$INTERFACE_CURRENT") \
        || fail "Unable to calculate interface traffic deltas"
    set -- $delta_values
    INTERFACE_RX_DELTA=$1
    INTERFACE_TX_DELTA=$2
    ELAPSED_TICKS=$3
    ELAPSED=$(LC_ALL=C awk -v ticks="$ELAPSED_TICKS" \
        'BEGIN { printf "%.2f", ticks / 100.0 }')
}
