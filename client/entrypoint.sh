#!/bin/bash
# Entry point inside the 1C client container.
# Usage (podman run AND podman exec -d): entrypoint.sh <bin> [1C args...]
#   bin: 1cv8c | 1cv8 | 1cestart  - launched as is
#   anything else - launched as 1cv8 (args passed through)
# Examples:
#   entrypoint.sh 1cv8c /IBConnectionString 'File="/home/ubuntu/Documents/InfoBase"'
#   entrypoint.sh 1cv8 DESIGNER /IBConnectionString 'File="..."'
#   entrypoint.sh ENTERPRISE ...   (unknown word -> 1cv8 ENTERPRISE ...)
# The container lives while any client process is running.
#
# PID-1 branch requires NO --init (the PID-1 check relies on it).

set -u

PLATFORM_VERSION="${PLATFORM_VERSION:?PLATFORM_VERSION env var is required}"
BIN_DIR="/opt/1cv8/x86_64/${PLATFORM_VERSION}"
COMMON_DIR="/opt/1cv8/common"

# Russian UI for all 1C processes: LC_ALL covers every category; the
# platform reads it for its interface language. See adr/0005.
export LC_ALL=ru_RU.UTF-8

# Route GTK file dialogs through the desktop portal: the host session bus
# is mounted, so 1C gets native KDE dialogs instead of GTK ones. Requires
# the bus mount (bin/1c-run.sh); falls back to plain GTK dialogs without it.
export GTK_USE_PORTAL=1

launch_client() {
    local bin="${1-}"; shift || true
    # Empty first argument (plain `podman run image`) = plain 1cv8.
    case "$bin" in
        "")       "$BIN_DIR/1cv8" "$@" & ;;
        1cv8c)    "$BIN_DIR/1cv8c" "$@" & ;;
        1cv8)     "$BIN_DIR/1cv8" "$@" & ;;
        1cestart) "$COMMON_DIR/1cestart" "$@" & ;;
        *)        "$BIN_DIR/1cv8" "$@" & ;;
    esac
}

launch_client "$@"

# Non-PID-1 (podman exec) branch: fire and forget.
if [ "$$" != "1" ]; then
    exit 0
fi

# PID-1 branch: react to SIGTERM immediately, exit when the last client
# is gone. `read -t` is a builtin: SIGTERM is not blocked by a child wait.
term_handler() {
    exit 0
}
trap term_handler SIGTERM INT

have_clients() {
    # pgrep without -x matches the pattern as a substring of the process
    # name: '1cv8' hits 1cv8, 1cv8c, 1cv8s. Anything 1C spawned counts as
    # a client - if it keeps the container up a bit longer, that is fine.
    pgrep -l 1cv8 >/dev/null 2>&1
}

while true; do
    # Reap exited background children (launched clients): pgrep counts
    # zombies, and a zombie client would keep the container alive forever.
    wait -n 2>/dev/null || true
    have_clients || exit 0
    read -t 2 _ < /dev/null || true
done