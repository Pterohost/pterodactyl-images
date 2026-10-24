#!/bin/bash
# Contract tests for images/palworld/start-palworld: the stop path.
#
# Stopping Palworld is the one place in this bootstrap where getting it wrong is
# invisible on the server that was stopped and only shows up on the NEXT start.
# The nodes run containers on the host network stack, so the game's listening
# sockets are held fleet-wide until its process is actually reaped. If the trap
# returns while the game is still alive, the script exits, PID 1 goes with it,
# Wings sees the container stop and starts it again - and the new PalServer
# cannot bind the RCON port, because the old process still owns it. The server
# then runs with RCON silently absent: no player list, no console, socket error
# 111 in the panel. That is what "the Restart button breaks the console, but
# Stop then Start is fine" was, on a live customer server, for four days.
#
# So the property asserted here is not "a signal was sent" but "by the time the
# stop path returns, the process is gone and its port is free" - including the
# case the original code missed, a game that ignores SIGTERM.
#
# Run: bash images/palworld/start-palworld.test.sh
# Wired into the `test` job in .github/workflows/build.yml.

set -u

SCRIPT="$(dirname -- "$0")/start-palworld"
FAILED=0
SANDBOX=""
PROBE_PORT="${PROBE_PORT:-45997}"

cleanup() {
    [ -n "${SANDBOX}" ] && rm -rf "${SANDBOX}"
    [ -n "${CHILD:-}" ] && kill -KILL "${CHILD}" 2>/dev/null
    return 0
}
trap cleanup EXIT

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }

port_held() { # 0 when something still listens on the probe port
    if command -v ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -q ":${PROBE_PORT}\b"
    else
        python3 - "$PROBE_PORT" <<'PY'
import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
try: s.bind(('127.0.0.1',int(sys.argv[1]))); s.close(); sys.exit(1)
except OSError: sys.exit(0)
PY
    fi
}

# Lift the shipped stop path out by marker and run it, so the test covers the
# code that ships rather than a restatement of it.
load_graceful_stop() { # <sandbox>
    sed -n '/^graceful_stop() {/,/^}$/p' "${SCRIPT}" > "$1/stop.sh"
    # shellcheck source=/dev/null
    . "$1/stop.sh"
}

# A stand-in for the game: ignores SIGTERM, as PalServer does while it unwinds a
# loaded world, and holds a listening socket the way RCON does.
spawn_stubborn_child() {
    python3 -c "
import socket,signal,time,sys
signal.signal(signal.SIGTERM, signal.SIG_IGN)
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('127.0.0.1',${PROBE_PORT})); s.listen(1)
while True: time.sleep(0.2)
" &
    CHILD=$!
    local waited=0
    while [ "${waited}" -lt 50 ]; do
        port_held && return 0
        sleep 0.1
        waited=$((waited + 1))
    done
    return 1
}

SANDBOX="$(mktemp -d)"

log() { :; }
rcon_send() { return 1; }   # no RCON: the fallback path, which is the risky one
PAL_RUNTIME=native
PAL_STOP_TIMEOUT=1
CHILD=""

load_graceful_stop "${SANDBOX}"

if ! spawn_stubborn_child; then
    fail "test stub never came up on port ${PROBE_PORT}"
    exit 1
fi

graceful_stop

# The two assertions the customer actually cares about.
if kill -0 "${CHILD}" 2>/dev/null; then
    fail "stop path returned while the game process was still alive"
else
    ok "game process is gone before the stop path returns"
fi

if port_held; then
    fail "stop path returned while the port was still held - the next start loses RCON"
else
    ok "port released before the stop path returns"
fi

# Stopping an already-dead server must be a no-op rather than an error, because
# Wings calls the stop path again on a server that crashed on its own.
CHILD_DEAD_RC=0
graceful_stop || CHILD_DEAD_RC=$?
if [ "${CHILD_DEAD_RC}" -eq 0 ]; then
    ok "stopping an already-stopped server is a no-op"
else
    fail "stopping an already-stopped server returned ${CHILD_DEAD_RC}"
fi

# --- the pre-launch wait on the RCON port ------------------------------------
#
# Second half of the same defect: even once the old process is gone, Palworld
# binds RCON without SO_REUSEADDR, so a leftover socket on that port makes the
# bind fail silently. What matters is that the wrapper does not launch into a
# port it can already see is occupied, and that it still launches eventually.

load_wait_fn() { # <sandbox>
    sed -n '/^wait_for_rcon_port() {/,/^}$/p' "${SCRIPT}" > "$1/wait.sh"
    # shellcheck source=/dev/null
    . "$1/wait.sh"
}
load_wait_fn "${SANDBOX}"

if ! command -v ss >/dev/null 2>&1; then
    printf '  skip iproute2 (ss) unavailable - port-wait assertions skipped\n'
else
    RCON_PORT="${PROBE_PORT}"
    PAL_PORT_WAIT_TIMEOUT=3

    # Free port: must return at once.
    START=${SECONDS}
    wait_for_rcon_port
    if [ $((SECONDS - START)) -le 1 ]; then
        ok "free port is not waited on"
    else
        fail "waited on a port that was already free"
    fi

    # Occupied port: must not return before the timeout, and must return after.
    if spawn_stubborn_child; then
        START=${SECONDS}
        wait_for_rcon_port
        ELAPSED=$((SECONDS - START))
        if [ "${ELAPSED}" -ge "${PAL_PORT_WAIT_TIMEOUT}" ]; then
            ok "occupied port is waited on, then start proceeds anyway"
        else
            fail "returned after ${ELAPSED}s on an occupied port, expected >= ${PAL_PORT_WAIT_TIMEOUT}s"
        fi
        kill -KILL "${CHILD}" 2>/dev/null
        CHILD=""
    else
        fail "test stub never came up for the port-wait check"
    fi

    # No RCON port configured at all must be a no-op, not a 45-second stall.
    RCON_PORT=""
    START=${SECONDS}
    wait_for_rcon_port
    if [ $((SECONDS - START)) -le 1 ]; then
        ok "no RCON port configured is a no-op"
    else
        fail "stalled even though no RCON port is configured"
    fi
fi

# --- PAL_UE4SS_SYNC=0: the owner's own UE4SS build ---------------------------
#
# An experimental UE4SS loads through dwmapi.dll. Wine has to be told to prefer
# that native proxy, and the winmm proxy an earlier sync left behind must not
# load a second UE4SS next to it - two loaders hang the server during startup.

load_ue4ss_fns() { # <sandbox>
    sed -n -e '/^pal_dll_override() {/,/^}$/p' -e '/^pal_owner_ue4ss() {/,/^}$/p' "${SCRIPT}" > "$1/ue4ss.sh"
    # shellcheck source=/dev/null
    . "$1/ue4ss.sh"
}
load_ue4ss_fns "${SANDBOX}"

WIN64="${SANDBOX}/Win64"
mkdir -p "${WIN64}/ue4ss"
: > "${WIN64}/winmm.dll"
: > "${WIN64}/UE4SS.dll"
: > "${WIN64}/ue4ss/UE4SS.dll"

WINEDLLOVERRIDES="winmm=n,b;d3d9=n,b"
pal_owner_ue4ss "${WIN64}"
if [ "${WINEDLLOVERRIDES}" = "winmm=n,b;d3d9=n,b" ]; then
    ok "no dwmapi.dll - the overrides are left alone"
else
    fail "overrides changed without a dwmapi proxy: ${WINEDLLOVERRIDES}"
fi

: > "${WIN64}/dwmapi.dll"
pal_owner_ue4ss "${WIN64}"
case ";${WINEDLLOVERRIDES};" in
    *";dwmapi=n,b;"*) ok "owner's dwmapi proxy is preferred over wine's builtin" ;;
    *) fail "dwmapi not overridden: ${WINEDLLOVERRIDES}" ;;
esac
case ";${WINEDLLOVERRIDES};" in
    *";winmm=b;"*) ok "leftover winmm proxy is kept from loading a second UE4SS" ;;
    *) fail "winmm still native-first next to dwmapi: ${WINEDLLOVERRIDES}" ;;
esac
case ";${WINEDLLOVERRIDES};" in
    *";d3d9=n,b;"*) ok "unrelated overrides (d3d9 for PalDefender) survive" ;;
    *) fail "d3d9 override lost: ${WINEDLLOVERRIDES}" ;;
esac

pal_owner_ue4ss "${WIN64}"
if [ "$(printf '%s' "${WINEDLLOVERRIDES}" | tr ';' '\n' | grep -c '^dwmapi=')" = "1" ]; then
    ok "applying the overrides twice does not duplicate entries"
else
    fail "duplicated entries: ${WINEDLLOVERRIDES}"
fi

if [ -f "${WIN64}/winmm.dll" ] && [ -f "${WIN64}/UE4SS.dll" ] && [ -f "${WIN64}/ue4ss/UE4SS.dll" ]; then
    ok "owner mode does not touch the files in Win64"
else
    fail "owner mode removed files from Win64"
fi

exit "${FAILED}"
