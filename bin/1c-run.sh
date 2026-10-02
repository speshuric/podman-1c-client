#!/bin/bash
# Lifecycle for the 1C client container (rootless podman, host = KDE Wayland).
#
# Usage: 1c-run.sh [command] [args...]
#   start        (default) launch a 1C client: the first argument is the 1C
#                binary (1cv8c, 1cv8, 1cestart), the rest go to it as
#                arguments. Any other first word (e.g. ENTERPRISE, DESIGNER,
#                a connection string) is treated as an argument of 1cv8.
#                Without arguments it launches 1cv8 with no arguments - the
#                1C startup dialog.
#   stop         stop the container
#   status       container state + number of 1C processes
#   build        build the regular image
#   build+test   build the image with debug tooling (MODE=test)
#   build+breeze build the regular image + Breeze GTK theme
#   build+start  build the regular image, then `start`
#   help         this help
#
# Unknown words fall back to `start`: `1c-run.sh` == `1c-run.sh start`.
# Examples:
#   1c-run.sh start 1cv8c /IBConnectionString 'File="/home/ubuntu/Documents/InfoBase"'
#   1c-run.sh start 1cv8 DESIGNER /IBConnectionString 'File="..."'
#
# Platform version selects the image and container name:
#   env PLATFORM_VERSION=8.3.27.2342 (default)

set -u

PLATFORM_VERSION="${PLATFORM_VERSION:-8.3.27.2342}"
IMAGE="localhost/1c-client:${PLATFORM_VERSION}"
CONTAINER="1c-client-${PLATFORM_VERSION}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
V="$PROJECT_DIR/volumes"

# X11 socket + xauth of the host session (XWayland).
X11_SOCKET="${X11_SOCKET:-/tmp/.X11-unix}"
DISPLAY_VALUE="${DISPLAY:-:0}"
XAUTH_VALUE="${XAUTHORITY:-$HOME/.Xauthority}"

# Host session bus (D-Bus): desktop notifications from 1C clients. The
# socket lives in the runtime dir; the bus address matches because
# --userns=keep-id maps uid 1:1. See adr/0008-host-dbus-portals.md.
BUS_SOCKET="/run/user/$(id -u)/bus"

warn() { echo "WARNING: $*" >&2; }

container_running() {
    podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"
}

# ---- commands -------------------------------------------------------------

cmd_help() {
    # Help text lives in the header comment; print it without the "# "
    # prefix, up to (not including) the "Platform version" line.
    sed -n '/^# Usage:/,/^# Platform/p' "$0" | sed '$d' | cut -c3-
}

cmd_build() {
    local mode="${1:-run}" breeze="${2:-0}"
    local tag="$IMAGE"
    # Test image gets a separate tag so it never replaces the run image.
    [ "$mode" = test ] && tag="${IMAGE}-test"
    # Breeze image gets its own tag too: it is opt-in, do not overwrite
    # the theme-less default image silently.
    [ "$breeze" = 1 ] && tag="${IMAGE}-breeze"
    mkdir -p "$V"
    podman build \
        --build-arg DISTR_CLIENT="distr/1c-${PLATFORM_VERSION}" \
        --build-arg PLATFORM_VERSION="${PLATFORM_VERSION}" \
        --build-arg MODE="${mode}" \
        --build-arg BREEZE="${breeze}" \
        -t "$tag" \
        -f client/Containerfile "$PROJECT_DIR" || { warn "build failed"; exit 1; }
}

cmd_stop() {
    podman stop "$CONTAINER" >/dev/null 2>&1 || warn "container $CONTAINER is not running"
    echo stopped
}

cmd_status() {
    if ! container_running; then
        echo "container: not running"
        return 0
    fi
    local n
    n=$(podman exec "$CONTAINER" bash -c "pgrep -l -f 1cv8 2>/dev/null | grep -v -e pgrep -e entrypoint | wc -l" 2>/dev/null || echo 0)
    echo "container: running, 1C processes: ${n}"
}

cmd_start() {
    if ! podman image exists "$IMAGE" 2>/dev/null; then
        warn "image $IMAGE not found, build it first: 1c-run.sh build"
        exit 1
    fi

    mkdir -p "$V/home" "$V/exchange" "$V/techjournal" "$V/client-profile" "$V/licenses" "$V/logconf"

    local mounts=(
        -v "$V/home:/home/ubuntu"
        -v "$V/exchange:/exchange"
        -v "$V/logconf:/opt/1cv8/logconf:ro"
        -v "$V/techjournal:/home/ubuntu/techjournal"
        -v "$V/client-profile:/home/ubuntu/.1cv8/1C/1cv8"
        -v "$V/licenses:/home/ubuntu/.1cv8/1C/1cv8/conf"
        -v "$X11_SOCKET:/tmp/.X11-unix"
        -e "DISPLAY=$DISPLAY_VALUE"
        -e "PLATFORM_VERSION=$PLATFORM_VERSION"
    )

    [ -r "$XAUTH_VALUE" ] && mounts+=(-v "$XAUTH_VALUE:/tmp/.xauth:ro" -e "XAUTHORITY=/tmp/.xauth")

    # Host session bus: desktop notifications (and a chance of portal
    # dialogs; the 1C file dialogs do not use the portal, adr/0008).
    [ -S "$BUS_SOCKET" ] && mounts+=(-v "$BUS_SOCKET:/run/user/1000/bus" -e "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus")

    if container_running; then
        # exec path: quiet on stdout - podman prints the container id
        # which means nothing here and only pollutes the shell.
        podman exec -d "$CONTAINER" /usr/local/bin/entrypoint.sh "$@" >/dev/null 2>&1 \
            || warn "container $CONTAINER is running but exec failed"
        exit 0
    fi

    # Fresh container. It stays up while clients are alive. Quiet the
    # same way: the printed id is noise.
    if ! podman run --rm -d --name "$CONTAINER" \
            --userns=keep-id \
            "${mounts[@]}" \
            "$IMAGE" "$@" >/dev/null 2>&1; then
        warn "container $CONTAINER failed to start"
        exit 1
    fi

    sleep 1
    container_running || warn "container $CONTAINER did not stay up, check image and mounts"
}

# ---- dispatch -------------------------------------------------------------

CMD="${1:-start}"
case "$CMD" in
    build)        shift; cmd_build run ;;
    build+test)   shift; cmd_build test ;;
    build+breeze) shift; cmd_build run 1 ;;
    build+start)  shift; cmd_build run; cmd_start "$@" ;;
    stop)         shift; cmd_stop ;;
    status)       shift; cmd_status ;;
    start)        shift; cmd_start "$@" ;;
    help|-h|--help) shift; cmd_help ;;
    *)            cmd_start "$@" ;;
esac