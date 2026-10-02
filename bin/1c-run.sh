#!/bin/bash
# Lifecycle for the 1C client container (rootless podman, host = KDE Wayland).
#
# Usage: 1c-run.sh [command] [args...]
#   A command is one word or '+'-joined tokens (build/start/test/breeze):
#     start        (default) launch a 1C client: the first argument is the
#                  1C binary (1cv8c, 1cv8, 1cestart), the rest go to it.
#                  Any other first word (e.g. ENTERPRISE, DESIGNER, a
#                  connection string) is treated as an argument of 1cv8.
#                  Without arguments it launches 1cv8 with no arguments -
#                  the 1C startup dialog.
#     stop         stop the container
#     status       container state + number of 1C processes
#     build        build the image
#     help         this help
#   Variants as '+' tokens: test (debug tooling, MODE=test) and breeze
#   (Breeze GTK theme). Each build overwrites the single image tag - the
#   last built variant is what start runs. Only the last two builds are
#   kept by podman; older ones stay as dangling images.
#   Examples: build+test, build+breeze, build+start, build+start+test.
#   Plain `test` / `breeze` mean start (that variant had better be built).
# Examples:
#   1c-run.sh start 1cv8c /IBConnectionString 'File="/home/user/Documents/InfoBase"'
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
    podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

# ---- commands -------------------------------------------------------------

cmd_help() {
    # Help text lives in the header comment; print it without the "# "
    # prefix, up to (not including) the "Platform version" line.
    sed -n '/^# Usage:/,/^# Platform/p' "$0" | sed '$d' | cut -c3-
}

cmd_build() {
    local mode="run" breeze=0
    local token
    for token in "$@"; do
        case "$token" in
            test)   mode="test" ;;
            breeze) breeze=1 ;;
        esac
    done
    mkdir -p "$V"
    # build+breeze also turns the theme on in the container home profile:
    # without the setting nothing changes visually and the variant is
    # lost ("built but you cannot find it"). Plain build restores the
    # default look by removing the theme line.
    local ini="$V/home/.config/gtk-3.0/settings.ini"
    if [ "$breeze" = 1 ]; then
        mkdir -p "$(dirname "$ini")"
        touch "$ini"
        grep -q "^gtk-theme-name=" "$ini" \
            && sed -i 's/^gtk-theme-name=.*/gtk-theme-name=Breeze/' "$ini" \
            || echo "gtk-theme-name=Breeze" >> "$ini"
        echo "breeze: theme enabled in $ini"
    elif [ -f "$ini" ] && grep -q "^gtk-theme-name=" "$ini"; then
        sed -i '/^gtk-theme-name=/d' "$ini"
        echo "breeze: theme setting removed from $ini"
    fi
    podman build \
        --build-arg DISTR_CLIENT="distr/1c-${PLATFORM_VERSION}" \
        --build-arg PLATFORM_VERSION="${PLATFORM_VERSION}" \
        --build-arg MODE="${mode}" \
        --build-arg BREEZE="${breeze}" \
        -t "$IMAGE" \
        -f client/Containerfile "$PROJECT_DIR" || { warn "build failed"; exit 1; }
}

cmd_stop() {
    podman stop "$CONTAINER" >/dev/null 2>&1 || warn "container $CONTAINER is not running"
    echo stopped
}

cmd_status() {
    if ! container_running "$CONTAINER"; then
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

    mkdir -p "$V/home" "$V/techjournal" "$V/licenses" "$V/logconf"

    local mounts=(
        # Persistent home: client profile (bases, settings) lives here.
        -v "$V/home:/home/user"
        # Tech journal (1C-specific format): out of home by design.
        -v "$V/techjournal:/tmp/1c-techjournal"
        # license (rw): the client keeps licenses in its conf dir.
        -v "$V/licenses:/home/user/.1cv8/1C/1cv8/conf"
        -v "$X11_SOCKET:/tmp/.X11-unix"
        -e "DISPLAY=$DISPLAY_VALUE"
        -e "PLATFORM_VERSION=$PLATFORM_VERSION"
    )

    [ -r "$XAUTH_VALUE" ] && mounts+=(-v "$XAUTH_VALUE:/tmp/.xauth:ro" -e "XAUTHORITY=/tmp/.xauth")

    # Host session bus: desktop notifications (and a chance of portal
    # dialogs; the 1C file dialogs do not use the portal, adr/0008).
    [ -S "$BUS_SOCKET" ] && mounts+=(-v "$BUS_SOCKET:/run/user/1000/bus" -e "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus")

    # Tech journal config: mounted as a single file into the client conf
    # directory when present (its <log location> points to
    # /tmp/1c-techjournal). Without logcfg.xml the TJ is simply off.
    if [ -r "$V/logconf/logcfg.xml" ]; then
        mounts+=(-v "$V/logconf/logcfg.xml:/home/user/.1cv8/1C/1cv8/conf/logcfg.xml:ro")
    fi

    if container_running "$CONTAINER"; then
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
    container_running "$CONTAINER" || warn "container $CONTAINER did not stay up, check image and mounts"
}

# ---- dispatch -------------------------------------------------------------

CMD="${1:-start}"
[ $# -gt 0 ] && shift

# Plain specials first.
case "$CMD" in
    stop)   cmd_stop ;;
    status) cmd_status ;;
    help|-h|--help) cmd_help ;;
    *)
        # Token grammar: '+'-joined build/start/test/breeze; anything
        # else in the first word means it is a 1C argument -> start.
        DO_BUILD=0
        DO_START=0
        VARIANT_TOKENS=()
        KNOWN=1
        IFS='+' read -ra TOKENS <<< "$CMD"
        for token in "${TOKENS[@]}"; do
            case "$token" in
                build)  DO_BUILD=1 ;;
                start)  DO_START=1 ;;
                test|breeze) VARIANT_TOKENS+=("$token") ;;
                *)      KNOWN=0; break ;;
            esac
        done

        if [ "$KNOWN" = 0 ]; then
            cmd_start "$CMD" "$@"
        else
            [ "$DO_BUILD" = 1 ] && cmd_build "${VARIANT_TOKENS[@]}"
            if [ "$DO_START" = 1 ] || { [ "$DO_BUILD" = 0 ] && [ ${#VARIANT_TOKENS[@]} -gt 0 ]; }; then
                cmd_start "$@"
            fi
        fi
        ;;
esac
