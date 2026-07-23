# Non-interactive CSV/JSONL output and output-file preparation.

output_target() {
    if [ -n "$OUTPUT" ]; then
        printf '%s' "$OUTPUT"
    else
        printf '%s' /dev/stdout
    fi
}

write_csv_header() {
    target=$(output_target)
    printf '%s\n' 'timestamp,interval_seconds,backend,scope,username,uid,upload_bytes_per_second,download_bytes_per_second,upload_bytes_total,download_bytes_total,active_entries,record_type,device,interface_upload_bytes_per_second,interface_download_bytes_per_second' >>"$target"
}

report_csv() {
    timestamp=$1
    elapsed=$2
    active_entries=$3
    target=$(output_target)
    LC_ALL=C awk -F '\t' \
        -v timestamp="$timestamp" -v elapsed="$elapsed" \
        -v backend="$BACKEND" -v scope="$SCOPE" -v device="$DEVICE" \
        -v interface_upload="$INTERFACE_TX_DELTA" \
        -v interface_download="$INTERFACE_RX_DELTA" \
        -v active_entries="$active_entries" '
        function csv_quote(text) {
            gsub(/"/, "\"\"", text)
            return "\"" text "\""
        }
        BEGIN {
            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%.3f,%.3f\n",
                csv_quote(timestamp), elapsed, csv_quote(backend), csv_quote(scope),
                csv_quote(""), "", "", "", "", "", active_entries,
                csv_quote("interface"), csv_quote(device),
                interface_upload / elapsed, interface_download / elapsed
        }
        FILENAME == ARGV[1] { names[$1] = $2; next }
        FILENAME == ARGV[2] {
            uid = $1
            username = (uid in names) ? names[uid] : "uid-" uid
            printf "%s,%s,%s,%s,%s,%s,%.3f,%.3f,%.0f,%.0f,%s,%s,%s,%.3f,%.3f\n",
                csv_quote(timestamp), elapsed, csv_quote(backend), csv_quote(scope),
                csv_quote(username), uid, $2 / elapsed, $3 / elapsed, $4, $5, $6,
                csv_quote("user"), csv_quote(device),
                interface_upload / elapsed, interface_download / elapsed
        }
    ' "$UID_NAMES" "$SORTED_ROWS" >>"$target"
}

report_jsonl() {
    timestamp=$1
    elapsed=$2
    active_entries=$3
    target=$(output_target)
    LC_ALL=C awk -F '\t' \
        -v timestamp="$timestamp" -v elapsed="$elapsed" \
        -v backend="$BACKEND" -v scope="$SCOPE" \
        -v active_entries="$active_entries" -v device="$DEVICE" \
        -v interface_upload="$INTERFACE_TX_DELTA" \
        -v interface_download="$INTERFACE_RX_DELTA" '
        function json_escape(text) {
            gsub(/\\/, "\\\\", text)
            gsub(/"/, "\\\"", text)
            gsub(/\t/, "\\t", text)
            gsub(/\r/, "\\r", text)
            gsub(/\n/, "\\n", text)
            return text
        }
        BEGIN {
            printf "{\"timestamp\":\"%s\",\"interval_seconds\":%s,", json_escape(timestamp), elapsed
            printf "\"backend\":\"%s\",\"scope\":\"%s\",", json_escape(backend), json_escape(scope)
            printf "\"device\":\"%s\",", json_escape(device)
            printf "\"interface_upload_bytes_per_second\":%.3f,", interface_upload / elapsed
            printf "\"interface_download_bytes_per_second\":%.3f,", interface_download / elapsed
            printf "\"active_entries\":%s,\"users\":[", active_entries
        }
        FILENAME == ARGV[1] { names[$1] = $2; next }
        FILENAME == ARGV[2] {
            uid = $1
            username = (uid in names) ? names[uid] : "uid-" uid
            if (row_count++) printf ","
            printf "{\"username\":\"%s\",\"uid\":%s,", json_escape(username), uid
            printf "\"upload_bytes_per_second\":%.3f,\"download_bytes_per_second\":%.3f,", $2 / elapsed, $3 / elapsed
            printf "\"upload_bytes_total\":%.0f,\"download_bytes_total\":%.0f,\"active_entries\":%s}", $4, $5, $6
        }
        END { print "]}" }
    ' "$UID_NAMES" "$SORTED_ROWS" >>"$target"
}

prepare_output() {
    if [ -n "$OUTPUT" ]; then
        if [ "$APPEND" -eq 0 ]; then
            : >"$OUTPUT" || fail "Unable to write output file: $OUTPUT"
        elif [ ! -e "$OUTPUT" ]; then
            : >"$OUTPUT" || fail "Unable to create output file: $OUTPUT"
        fi
    fi

    if [ "$FORMAT" = csv ]; then
        if [ -z "$OUTPUT" ] || [ "$APPEND" -eq 0 ] || [ ! -s "$OUTPUT" ]; then
            write_csv_header
        fi
    fi
}
