# Delta calculation, cumulative state, display ordering, and live ranking input.

calculate_rows() {
    elapsed=$1
    : >"$COMMAND_ROWS"
    LC_ALL=C awk -F '\t' -v command_rows="$COMMAND_ROWS" '
        FILENAME == ARGV[1] {
            key = $1
            uid = $2
            pid = $3
            process_command = $4
            previous_uid[key] = uid
            previous_pid[key] = pid
            previous_command[key] = process_command
            previous_upload[key] = $5
            previous_download[key] = $6
            seen_uid[uid] = 1
            seen_command[uid SUBSEP pid SUBSEP process_command] = 1
            next
        }

        FILENAME == ARGV[2] {
            key = $1
            uid = $2
            pid = $3
            process_command = $4
            upload = $5
            download = $6
            active[uid]++
            seen_uid[uid] = 1
            command_key = uid SUBSEP pid SUBSEP process_command
            command_active[command_key]++
            seen_command[command_key] = 1

            if ((key in previous_upload) && previous_uid[key] == uid &&
                    previous_pid[key] == pid && previous_command[key] == process_command &&
                    upload >= previous_upload[key] && download >= previous_download[key]) {
                current_upload_delta = upload - previous_upload[key]
                current_download_delta = download - previous_download[key]
            } else {
                current_upload_delta = upload
                current_download_delta = download
            }
            upload_delta[uid] += current_upload_delta
            download_delta[uid] += current_download_delta
            command_upload_delta[command_key] += current_upload_delta
            command_download_delta[command_key] += current_download_delta
            next
        }

        FILENAME == ARGV[3] {
            total_upload[$1] = $2
            total_download[$1] = $3
            seen_uid[$1] = 1
            next
        }

        FILENAME == ARGV[4] {
            command_key = $1 SUBSEP $2 SUBSEP $3
            command_total_upload[command_key] = $4
            command_total_download[command_key] = $5
            seen_command[command_key] = 1
            next
        }

        END {
            for (uid in seen_uid) {
                total_upload[uid] += upload_delta[uid]
                total_download[uid] += download_delta[uid]
                printf "%s\t%.0f\t%.0f\t%.0f\t%.0f\t%d\n", uid,
                    upload_delta[uid], download_delta[uid],
                    total_upload[uid], total_download[uid], active[uid]
            }
            for (command_key in seen_command) {
                split(command_key, command_parts, SUBSEP)
                uid = command_parts[1]
                pid = command_parts[2]
                process_command = command_parts[3]
                command_total_upload[command_key] += command_upload_delta[command_key]
                command_total_download[command_key] += command_download_delta[command_key]
                printf "%s\t%s\t%s\t%.0f\t%.0f\t%.0f\t%.0f\t%d\n", uid,
                    pid, process_command, command_upload_delta[command_key],
                    command_download_delta[command_key],
                    command_total_upload[command_key],
                    command_total_download[command_key],
                    command_active[command_key] > command_rows
            }
        }
    ' "$PREVIOUS" "$CURRENT" "$TOTALS" "$COMMAND_TOTALS" >"$ROWS" \
        || fail "Unable to calculate usage deltas"

    LC_ALL=C awk -F '\t' '{ printf "%.0f\t%s\n", $2 + $3, $0 }' "$ROWS" \
        | LC_ALL=C sort -t '	' -k1,1nr \
        | cut -f2- >"$SORTED_ROWS"

    LC_ALL=C awk -F '\t' '{ printf "%s\t%.0f\t%s\n", $1, -($4 + $5), $0 }' "$COMMAND_ROWS" \
        | LC_ALL=C sort -t '	' -k1,1n -k2,2n \
        | cut -f3- >"$SORTED_COMMAND_ROWS"

    LC_ALL=C awk -F '\t' '
        FILENAME == ARGV[1] { names[$1] = $2; next }
        FILENAME == ARGV[2] {
            username = ($1 in names) ? names[$1] : "uid-" $1
            priority = ($1 + 0 == 0) ? 0 : 1
            print priority "\t" username "\t" $0
        }
    ' "$UID_NAMES" "$ROWS" \
        | LC_ALL=C sort -t '	' -k1,1n -k2,2 -k3,3n \
        | cut -f3- >"$TABLE_ROWS"

    LC_ALL=C awk -F '\t' '{ print $1 "\t" $4 "\t" $5 }' "$ROWS" >"$NEXT_TOTALS"
    mv "$NEXT_TOTALS" "$TOTALS"
    LC_ALL=C awk -F '\t' \
        '{ print $1 "\t" $2 "\t" $3 "\t" $6 "\t" $7 }' "$COMMAND_ROWS" \
        >"$NEXT_COMMAND_TOTALS"
    mv "$NEXT_COMMAND_TOTALS" "$COMMAND_TOTALS"
}
