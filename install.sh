#!/bin/sh
# Install netwtop and its modules into a user-controlled prefix.

set -u

SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
if [ -n "${NETWTOP_PREFIX:-}" ]; then
    INSTALL_PREFIX=$NETWTOP_PREFIX
elif [ -n "${HOME:-}" ]; then
    INSTALL_PREFIX=$HOME/.local
else
    printf 'Error: HOME is not set; provide NETWTOP_PREFIX.\n' >&2
    exit 1
fi

BIN_DEST=$INSTALL_PREFIX/bin
LIB_DEST=$INSTALL_PREFIX/lib/netwtop

mkdir -p "$BIN_DEST" "$LIB_DEST/backends" "$LIB_DEST/ui" || {
    printf 'Error: Unable to create installation directories under %s.\n' \
        "$INSTALL_PREFIX" >&2
    exit 1
}

cp "$SOURCE_ROOT/bin/netwtop" "$BIN_DEST/netwtop" \
    && cp "$SOURCE_ROOT/lib/netwtop/runtime.sh" "$LIB_DEST/runtime.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/accounting.sh" "$LIB_DEST/accounting.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/formats.sh" "$LIB_DEST/formats.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/backends/common.sh" "$LIB_DEST/backends/common.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/backends/linux.sh" "$LIB_DEST/backends/linux.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/backends/macos.sh" "$LIB_DEST/backends/macos.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/interfaces.sh" "$LIB_DEST/interfaces.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/history.sh" "$LIB_DEST/history.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/ui/table.sh" "$LIB_DEST/ui/table.sh" \
    && cp "$SOURCE_ROOT/lib/netwtop/ui/table.awk" "$LIB_DEST/ui/table.awk" \
    || {
        printf 'Error: Unable to copy netwtop files.\n' >&2
        exit 1
    }

chmod 755 "$BIN_DEST/netwtop" || {
    printf 'Error: Unable to make %s executable.\n' "$BIN_DEST/netwtop" >&2
    exit 1
}
chmod 644 "$LIB_DEST/runtime.sh" "$LIB_DEST/accounting.sh" \
    "$LIB_DEST/formats.sh" "$LIB_DEST/interfaces.sh" "$LIB_DEST/history.sh" \
    "$LIB_DEST/backends/common.sh" \
    "$LIB_DEST/backends/linux.sh" "$LIB_DEST/backends/macos.sh" \
    "$LIB_DEST/ui/table.sh" "$LIB_DEST/ui/table.awk" || {
        printf 'Error: Unable to set module permissions.\n' >&2
        exit 1
    }

printf 'Installed netwtop to %s\n' "$BIN_DEST/netwtop"
case :${PATH:-}: in
    *:"$BIN_DEST":*) ;;
    *) printf 'Add %s to PATH before invoking netwtop.\n' "$BIN_DEST" ;;
esac
