# Linux socket snapshot backend based on ss TCP counters.

parse_linux_snapshot() {
    process_map=$1
    socket_snapshot=$2
    destination=$3
    LC_ALL=C awk '
        function value_after_colon(text) {
            sub(/^[^:]*:/, "", text)
            return text
        }

        FILENAME == ARGV[1] {
            split($0, process_fields, "\t")
            pid_uid[process_fields[1]] = process_fields[2]
            pid_command[process_fields[1]] = process_fields[3]
            next
        }

        FILENAME == ARGV[2] && /^[^[:space:]]/ {
            uid = 0
            inode = "0"
            socket_key = ""
            pid = ""
            have_socket = 1
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^uid:[0-9]+$/) uid = value_after_colon($i)
                else if ($i ~ /^ino:[0-9]+$/) inode = value_after_colon($i)
                else if ($i ~ /^sk:/) socket_key = value_after_colon($i)
            }
            if (match($0, /pid=[0-9]+/)) {
                pid = substr($0, RSTART, RLENGTH)
                sub(/^pid=/, "", pid)
            }
            if (pid != "" && pid in pid_command) {
                # The process effective UID is authoritative when a PID is
                # visible. In particular, a command launched through sudo must
                # be charged to root rather than to the invoking account.
                uid = pid_uid[pid]
                process_command = pid_command[pid]
            } else {
                pid = "-"
                process_command = "[unattributed]"
            }
            next
        }

        FILENAME == ARGV[2] && /^[[:space:]]/ && have_socket {
            upload = 0
            download = 0
            found_counter = 0
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^bytes_acked:[0-9]+$/) {
                    upload = value_after_colon($i)
                    found_counter = 1
                } else if ($i ~ /^bytes_received:[0-9]+$/) {
                    download = value_after_colon($i)
                    found_counter = 1
                }
            }
            if (found_counter && socket_key != "") {
                printf "%s:%s\t%s\t%s\t%s\t%s\t%s\n", socket_key, inode, uid,
                    pid, process_command, upload, download
            }
            have_socket = 0
        }
    ' "$process_map" "$socket_snapshot" >"$destination" \
        || fail "Unable to parse Linux socket statistics"
}

snapshot_linux() {
    destination=$1
    build_process_map
    if ! LC_ALL=C ss -tinepH >"$RAW" 2>"$ERROR_LOG"; then
        detail=$(awk 'NF { print; exit }' "$ERROR_LOG")
        [ -n "$detail" ] || detail='ss failed without an error message'
        fail "Unable to read Linux socket statistics: $detail"
    fi

    parse_linux_snapshot "$PID_COMMANDS" "$RAW" "$destination"
}
