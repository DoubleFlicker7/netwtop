#!/bin/sh
# Legacy development launcher retained for users of the original command name.

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
NETWTOP_PROGRAM_NAME=${0##*/}
export NETWTOP_PROGRAM_NAME
exec "$PROJECT_ROOT/bin/netwtop" "$@"
