# Shared process discovery and backend dispatch.

build_process_map() {
    case $OS_NAME in
        Linux)
            if ! LC_ALL=C ps -eww -o pid=,uid=,args= >"$RAW" 2>"$ERROR_LOG"; then
                fail "Unable to read the Linux process command list"
            fi
            ;;
        Darwin)
            if ! LC_ALL=C ps -axww -o pid=,uid=,command= >"$RAW" 2>"$ERROR_LOG"; then
                fail "Unable to read the macOS process command list"
            fi
            ;;
    esac
    LC_ALL=C awk '
        NF >= 2 {
            pid = $1
            uid = $2
            $1 = ""
            $2 = ""
            sub(/^[[:space:]]+/, "")
            process_command = $0
            gsub(/\t/, " ", process_command)
            gsub(/[[:cntrl:]]/, "?", process_command)
            if (process_command == "") process_command = "[pid " pid "]"
            print pid "\t" uid "\t" process_command
        }
    ' "$RAW" >"$PID_COMMANDS" || fail "Unable to parse the process command list"
}

take_snapshot() {
    case $OS_NAME in
        Linux) snapshot_linux "$1" ;;
        Darwin) snapshot_macos "$1" ;;
    esac
}

build_uid_names() {
    : >"$UID_NAMES"
    if [ -r /etc/passwd ]; then
        LC_ALL=C awk -F: 'NF >= 3 { print $3 "\t" $1 }' /etc/passwd >>"$UID_NAMES"
    fi
    LC_ALL=C ps -axo uid=,user= 2>/dev/null \
        | LC_ALL=C awk 'NF >= 2 { print $1 "\t" $2 }' >>"$UID_NAMES"
    LC_ALL=C awk -F '\t' '!seen[$1]++ { print $1 "\t" $2 }' "$UID_NAMES" >"$RAW"
    mv "$RAW" "$UID_NAMES"
}
