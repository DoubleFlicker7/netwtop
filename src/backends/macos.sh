# macOS process snapshot backend based on the built-in nettop command.

snapshot_macos() {
    destination=$1
    build_process_map

    if ! LC_ALL=C "$MACOS_NETTOP" -P -L 1 -x -J bytes_in,bytes_out \
            >"$RAW" 2>"$ERROR_LOG"; then
        detail=$(awk 'NF { print; exit }' "$ERROR_LOG")
        [ -n "$detail" ] || detail='nettop failed without an error message'
        fail "Unable to read macOS network statistics: $detail"
    fi

    LC_ALL=C awk -F, '
        FILENAME == ARGV[1] {
            split($0, fields, "\t")
            pid_uid[fields[1]] = fields[2]
            pid_command[fields[1]] = fields[3]
            next
        }

        FILENAME == ARGV[2] {
            sub(/\r$/, "")
            if ($1 == "time") {
                for (i = 1; i <= NF; i++) {
                    heading = $i
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", heading)
                    if (heading == "bytes_in") bytes_in_column = i
                    else if (heading == "bytes_out") bytes_out_column = i
                }
                found_header = 1
                next
            }

            label = $1
            pid = label
            sub(/^.*\./, "", pid)
            if (pid !~ /^[0-9]+$/ || !bytes_in_column || !bytes_out_column) next

            if (pid == 0) uid = 0
            else if (pid in pid_uid) uid = pid_uid[pid]
            else next

            if (pid == 0) process_command = "[kernel]"
            else if (pid in pid_command) process_command = pid_command[pid]
            else process_command = label

            upload = $(bytes_out_column) + 0
            download = $(bytes_in_column) + 0
            printf "%s\t%s\t%s\t%s\t%.0f\t%.0f\n", label, uid, pid,
                process_command, upload, download
        }

        END {
            if (!found_header || !bytes_in_column || !bytes_out_column) exit 2
        }
    ' "$PID_COMMANDS" "$RAW" >"$destination" \
        || fail "Unable to parse nettop CSV output; this macOS version may use a different format"
}
