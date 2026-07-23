# Rolling in-memory history for interface, accounted, and per-user rates.

record_history() {
    elapsed=$1
    HISTORY_SAMPLE=$((HISTORY_SAMPLE + 1))

    LC_ALL=C awk -F '\t' \
        -v sample="$HISTORY_SAMPLE" -v elapsed="$elapsed" \
        -v interface_upload="$INTERFACE_TX_DELTA" \
        -v interface_download="$INTERFACE_RX_DELTA" '
        BEGIN {
            printf "%d\tI\t%.3f\t%.3f\n", sample,
                interface_upload / elapsed, interface_download / elapsed
        }
        {
            upload += $2
            download += $3
            printf "%d\tU:%s\t%.3f\t%.3f\n", sample, $1,
                $2 / elapsed, $3 / elapsed
        }
        END {
            printf "%d\tA\t%.3f\t%.3f\n", sample,
                upload / elapsed, download / elapsed
        }
    ' "$TABLE_ROWS" >>"$HISTORY" || fail "Unable to record traffic history"

    if [ "$HISTORY_SAMPLE" -gt "$HISTORY_LIMIT" ]; then
        oldest_sample=$((HISTORY_SAMPLE - HISTORY_LIMIT + 1))
        LC_ALL=C awk -F '\t' -v oldest="$oldest_sample" \
            '$1 >= oldest' "$HISTORY" >"$NEXT_HISTORY" \
            || fail "Unable to trim traffic history"
        mv "$NEXT_HISTORY" "$HISTORY"
    fi
}
