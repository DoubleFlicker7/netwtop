#!/bin/sh
# Install netwtop and its module tree into a user-controlled prefix.

set -u

SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
SOURCE_MODULE_ROOT=$SOURCE_ROOT/src

if [ ! -r "$SOURCE_MODULE_ROOT/manifest.sh" ]; then
    printf 'Error: Source module manifest not found: %s\n' \
        "$SOURCE_MODULE_ROOT/manifest.sh" >&2
    exit 1
fi
. "$SOURCE_MODULE_ROOT/manifest.sh"

if [ -n "${NETWTOP_PREFIX:-}" ]; then
    INSTALL_PREFIX=$NETWTOP_PREFIX
elif [ -n "${HOME:-}" ]; then
    INSTALL_PREFIX=$HOME/.local
else
    printf 'Error: HOME is not set; provide NETWTOP_PREFIX.\n' >&2
    exit 1
fi

BIN_DEST=$INSTALL_PREFIX/bin
MODULE_DEST=$INSTALL_PREFIX/lib/netwtop

mkdir -p "$BIN_DEST" "$MODULE_DEST" || {
    printf 'Error: Unable to create installation directories under %s.\n' \
        "$INSTALL_PREFIX" >&2
    exit 1
}

cp "$SOURCE_ROOT/bin/netwtop" "$BIN_DEST/netwtop" \
    && cp "$SOURCE_MODULE_ROOT/manifest.sh" "$MODULE_DEST/manifest.sh" \
    || {
        printf 'Error: Unable to copy netwtop entry point or manifest.\n' >&2
        exit 1
    }

for module in $NETWTOP_RUNTIME_MODULES $NETWTOP_RESOURCE_FILES; do
    source_file=$SOURCE_MODULE_ROOT/$module
    destination_file=$MODULE_DEST/$module
    destination_dir=$MODULE_DEST/${module%/*}
    mkdir -p "$destination_dir" \
        && cp "$source_file" "$destination_file" \
        && chmod 644 "$destination_file" \
        || {
            printf 'Error: Unable to install netwtop module: %s\n' "$module" >&2
            exit 1
        }
done

chmod 755 "$BIN_DEST/netwtop" \
    && chmod 644 "$MODULE_DEST/manifest.sh" || {
        printf 'Error: Unable to set installed file permissions.\n' >&2
        exit 1
    }

# Releases before the responsibility-based source layout installed these
# modules directly below lib/netwtop. The new executable ignores them; remove
# only the exact obsolete installer-owned paths after the new tree is complete.
for obsolete_module in \
    runtime.sh accounting.sh history.sh interfaces.sh formats.sh
do
    rm -f "$MODULE_DEST/$obsolete_module" || {
        printf 'Error: Unable to remove obsolete netwtop module: %s\n' \
            "$obsolete_module" >&2
        exit 1
    }
done

printf 'Installed netwtop to %s\n' "$BIN_DEST/netwtop"
case :${PATH:-}: in
    *:"$BIN_DEST":*) ;;
    *) printf 'Add %s to PATH before invoking netwtop.\n' "$BIN_DEST" ;;
esac
