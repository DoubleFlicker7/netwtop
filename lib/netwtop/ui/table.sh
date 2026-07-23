# Table-mode terminal setup and frame rendering.

detect_table_dimensions() {
    if [ "$LAST_UI_WIDTH" -gt 0 ] && [ "$LAST_UI_HEIGHT" -gt 0 ]; then
        DETECTED_UI_WIDTH=$LAST_UI_WIDTH
        DETECTED_UI_HEIGHT=$LAST_UI_HEIGHT
    else
        DETECTED_UI_WIDTH=80
        DETECTED_UI_HEIGHT=24
    fi

    if [ -n "$OUTPUT" ]; then
        DETECTED_UI_WIDTH=120
        DETECTED_UI_HEIGHT=0
        return
    fi

    if [ "$INTERACTIVE_TABLE" -eq 1 ]; then
        detected_size=$(stty size </dev/tty 2>/dev/null || true)
        set -- $detected_size
        if [ "$#" -eq 2 ]; then
            case $1 in ''|*[!0-9]*|0) ;; *) DETECTED_UI_HEIGHT=$1 ;; esac
            case $2 in ''|*[!0-9]*|0) ;; *) DETECTED_UI_WIDTH=$2 ;; esac
        elif [ -n "${TERM:-}" ] && command -v tput >/dev/null 2>&1; then
            detected_width=$(tput cols </dev/tty 2>/dev/null || printf '%s' 80)
            detected_height=$(tput lines </dev/tty 2>/dev/null || printf '%s' 24)
            case $detected_width in
                ''|*[!0-9]*|0) ;;
                *) DETECTED_UI_WIDTH=$detected_width ;;
            esac
            case $detected_height in
                ''|*[!0-9]*|0) ;;
                *) DETECTED_UI_HEIGHT=$detected_height ;;
            esac
        fi
    fi
}

report_table() {
    timestamp=$1
    elapsed=$2
    active_entries=$3
    if [ -n "$OUTPUT" ]; then
        target=$OUTPUT
    else
        target=$TABLE_TARGET
    fi

    color_border=
    color_title=
    color_header=
    color_user=
    color_upload=
    color_download=
    color_warning=
    color_dim=
    color_total=
    color_selected=
    color_reset=

    if [ -z "$OUTPUT" ]; then
        render_target=$FRAME
        color_border=$(printf '\033[36m')
        color_title=$(printf '\033[1;36m')
        color_header=$(printf '\033[1m')
        color_user=$(printf '\033[1;32m')
        color_upload=$(printf '\033[32m')
        color_download=$(printf '\033[34m')
        color_warning=$(printf '\033[1;33m')
        color_dim=$(printf '\033[2m')
        color_total=$(printf '\033[1;36m')
        color_selected=$(printf '\033[7m')
        color_reset=$(printf '\033[0m')
    else
        render_target=$target
    fi

    display_time=$(LC_ALL=C date '+%a %b %d %T %Y')
    session_label="${USER:-user}@$HOST_NAME"
    if [ "$INTERACTIVE_TABLE" -eq 1 ]; then
        session_label="[q] [Up/Dn] [j/k/Pg] [x] [mouse]"
    fi

    # A resize can arrive while a frame is being built. Render again with the
    # new dimensions before committing so no line is allowed to wrap into the
    # gap between panels.
    render_attempt=0
    while :; do
        detect_table_dimensions
        ui_width=$DETECTED_UI_WIDTH
        ui_height=$DETECTED_UI_HEIGHT
        : >"$render_target" || fail "Unable to prepare the terminal frame"
        : >"$HITMAP" || fail "Unable to prepare the interaction map"
        : >"$LAYOUT_STATE" || fail "Unable to prepare the layout state"

        LC_ALL=C awk -F '\t' \
            -v timestamp="$timestamp" -v display_time="$display_time" \
            -v elapsed="$elapsed" -v refresh_interval="$INTERVAL" \
            -v display_mode="$DISPLAY_MODE" -v backend="$BACKEND" \
            -v two_column_width="$TWO_COLUMN_WIDTH" \
            -v scope="$SCOPE" -v active_entries="$active_entries" \
            -v interface_name="$DEVICE" \
            -v interface_rx_delta="$INTERFACE_RX_DELTA" \
            -v interface_tx_delta="$INTERFACE_TX_DELTA" \
            -v attribution_device_scoped="$ATTRIBUTION_DEVICE_SCOPED" \
            -v history_limit="$HISTORY_LIMIT" \
            -v interactive_ui="$INTERACTIVE_TABLE" \
            -v table_scroll="$TABLE_SCROLL" \
            -v command_view_size="$COMMAND_VIEW_SIZE" \
            -v command_scroll_uid="$COMMAND_SCROLL_UID" \
            -v command_scroll_offset="$COMMAND_SCROLL_OFFSET" \
            -v selected_uid="$SELECTED_UID" -v selected_pid="$SELECTED_PID" \
            -v expanded_uid="$EXPANDED_UID" \
            -v hitmap_file="$HITMAP" -v layout_state_file="$LAYOUT_STATE" \
            -v ui_width="$ui_width" -v ui_height="$ui_height" \
            -v host_name="$HOST_NAME" -v session_label="$session_label" \
            -v color_border="$color_border" -v color_title="$color_title" \
            -v color_header="$color_header" -v color_user="$color_user" \
            -v color_upload="$color_upload" -v color_download="$color_download" \
            -v color_warning="$color_warning" -v color_dim="$color_dim" \
            -v color_total="$color_total" -v color_selected="$color_selected" \
            -v color_reset="$color_reset" \
            -f "$NETWTOP_LIB_DIR/ui/table.awk" \
            "$UID_NAMES" "$SORTED_COMMAND_ROWS" "$TABLE_ROWS" "$HISTORY" \
            >>"$render_target" \
            || fail "Unable to render the live table"

        [ -z "$OUTPUT" ] || break
        detect_table_dimensions
        if [ "$DETECTED_UI_WIDTH" -eq "$ui_width" ] \
                && [ "$DETECTED_UI_HEIGHT" -eq "$ui_height" ]; then
            break
        fi
        RESIZE_PENDING=1
        render_attempt=$((render_attempt + 1))
        [ "$render_attempt" -lt 3 ] || break
    done

    if [ "$INTERACTIVE_TABLE" -eq 1 ] && [ -s "$LAYOUT_STATE" ]; then
        while IFS=$(printf '\t') read -r state_type state_value state_page state_extra; do
            case $state_type in
                table)
                    TABLE_SCROLL=$state_value
                    TABLE_PAGE_SIZE=$state_page
                    ;;
                command)
                    if [ "$state_value" = "$COMMAND_SCROLL_UID" ]; then
                        COMMAND_SCROLL_OFFSET=$state_page
                    fi
                    ;;
                expanded)
                    if [ "$state_value" = - ]; then
                        EXPANDED_UID=
                    else
                        EXPANDED_UID=$state_value
                    fi
                    ;;
            esac
        done <"$LAYOUT_STATE"
    fi

    if [ -z "$OUTPUT" ]; then
        # Boxed rows occupy the terminal's final column. Erasing to end-of-line
        # after drawing them clears that last cell on some VT/PowerShell
        # implementations, so only explicitly erase rows that are blank.
        if [ ! -s "$PREVIOUS_FRAME" ] \
                || [ "$RESIZE_PENDING" -eq 1 ] \
                || [ "$LAST_UI_WIDTH" -ne "$ui_width" ] \
                || [ "$LAST_UI_HEIGHT" -ne "$ui_height" ]; then
            LC_ALL=C awk '
                BEGIN { printf "\033[2J" }
                {
                    printf "\033[%d;1H", FNR
                    if ($0 == "") printf "\033[2K"
                    else printf "%s", $0
                    line_count = FNR
                }
                END {
                    printf "\033[%d;1H\033[J\033[H", line_count + 1
                }
            ' "$FRAME" >"$target" \
                || fail "Unable to rebuild the terminal frame"
        else
            LC_ALL=C awk '
                NR == FNR {
                    previous[FNR] = $0
                    previous_count = FNR
                    next
                }
                {
                    current_count = FNR
                    if (!(FNR in previous) || previous[FNR] != $0) {
                        printf "\033[%d;1H", FNR
                        if ($0 == "") printf "\033[2K"
                        else printf "%s", $0
                    }
                }
                END {
                    if (previous_count > current_count) {
                        printf "\033[%d;1H\033[J", current_count + 1
                    }
                    printf "\033[H"
                }
            ' "$PREVIOUS_FRAME" "$FRAME" >"$target" \
                || fail "Unable to update the terminal frame"
        fi
        mv "$FRAME" "$PREVIOUS_FRAME" \
            || fail "Unable to retain the previous terminal frame"
        LAST_UI_WIDTH=$ui_width
        LAST_UI_HEIGHT=$ui_height
        RESIZE_PENDING=0
    fi
}
