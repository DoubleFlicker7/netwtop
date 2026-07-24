# Shared process discovery and backend dispatch.

configure_user_scope() {
    case $OS_NAME in
        Linux) LOGIN_UID_MIN=1000 ;;
        Darwin) LOGIN_UID_MIN=500 ;;
    esac

    if [ "$OS_NAME" = Linux ] && [ -r /etc/login.defs ]; then
        configured_uid_min=$(LC_ALL=C awk '
            $1 == "UID_MIN" && $2 ~ /^[0-9]+$/ { print $2; exit }
        ' /etc/login.defs)
        if [ -n "$configured_uid_min" ]; then
            LOGIN_UID_MIN=$configured_uid_min
        fi
    fi

    CURRENT_UID=$(id -u 2>/dev/null) \
        || fail "Unable to identify the current user ID"
    case $CURRENT_UID in
        ''|*[!0-9]*) fail "Unable to identify the current user ID" ;;
    esac
    CURRENT_USER=$(id -un 2>/dev/null) \
        || CURRENT_USER=uid-$CURRENT_UID
    [ -n "$CURRENT_USER" ] || CURRENT_USER=uid-$CURRENT_UID

    INVOKING_UID=$CURRENT_UID
    if [ "$CURRENT_UID" -eq 0 ]; then
        SHOW_ALL_COMMANDS=1
        case ${SUDO_UID:-} in
            ''|*[!0-9]*) ;;
            *) INVOKING_UID=$SUDO_UID ;;
        esac
    else
        SHOW_ALL_COMMANDS=0
    fi
}

build_process_map() {
    case $OS_NAME in
        Linux)
            if ! LC_ALL=C ps -eww -o pid=,euid=,args= >"$RAW" 2>"$ERROR_LOG"; then
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
    # The effective identity detected by id is authoritative. Environment
    # variables such as USER and LOGNAME can remain stale after su, sudo, or a
    # scheduler changes credentials.
    printf '%s\t%s\n' "$CURRENT_UID" "$CURRENT_USER" >"$UID_NAMES"
    if [ -r /etc/passwd ]; then
        LC_ALL=C awk -F: 'NF >= 3 { print $3 "\t" $1 }' /etc/passwd >>"$UID_NAMES"
    fi
    LC_ALL=C ps -axo uid=,user= 2>/dev/null \
        | LC_ALL=C awk 'NF >= 2 { print $1 "\t" $2 }' >>"$UID_NAMES"
    LC_ALL=C awk -F '\t' '!seen[$1]++ { print $1 "\t" $2 }' "$UID_NAMES" >"$RAW"
    mv "$RAW" "$UID_NAMES"
}
