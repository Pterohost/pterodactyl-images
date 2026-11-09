#!/bin/bash
# Contract tests for images/enshrouded/start-enshrouded: the default config and
# the stop path, run end to end against a stand-in for Proton and the server.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

mkdir -p "${tmp}/lib" "${tmp}/bin" "${tmp}/home/.steam/sdk64" "${tmp}/proton/files/bin"
cp "${HERE}/../../shared/launch.sh" "${tmp}/lib/launch.sh"
cat > "${tmp}/lib/steam-update.sh" <<'EOF'
pterohost_log() { printf '[pterohost] %s\n' "$*"; }
pterohost_steam_seed() { :; }
pterohost_steam_sdk() { :; }
pterohost_steam_update() { :; }
STEAMCMD_RUN=/nonexistent
EOF
sed -e "s#/usr/local/lib/pterohost/launch.sh#${tmp}/lib/launch.sh#" \
    -e "s#/usr/local/lib/pterohost/steam-update.sh#${tmp}/lib/steam-update.sh#" \
    -e "s#cd /home/container || exit 1#cd \"\${ENS_TEST_HOME}\" || exit 1#" \
    -e "s#/home/container/#\${ENS_TEST_HOME}/#g" \
    "${HERE}/start-enshrouded" > "${tmp}/start"

# --- default config ----------------------------------------------------------
# shellcheck source=/dev/null
ENS_TEST_HOME="${tmp}/home" ENS_SOURCE_ONLY=1 . "${tmp}/start"
cfg="$(ens_default_config 15637 'My World' 8)"
check "config carries the allocated port" "15637" "$(jq -r .queryPort <<<"${cfg}")"
check "config carries the name" "My World" "$(jq -r .name <<<"${cfg}")"
check "config carries the slot count" "8" "$(jq -r .slotCount <<<"${cfg}")"
check "config listens on all addresses" "0.0.0.0" "$(jq -r .ip <<<"${cfg}")"
check "config keeps saves in the volume" "./savegame" "$(jq -r .saveDirectory <<<"${cfg}")"

# --- stop path -----------------------------------------------------------------
# The stand-in server is named like the real one (the bootstrap finds it by
# process name), saves on Ctrl+C after a short delay, and otherwise exits with
# the code it is given. Python, not bash: a background bash job cannot trap
# SIGINT, while the real server (like any native program) can.
cat > "${tmp}/bin/enshrouded_server" <<'EOF'
#!/usr/bin/python3
import os, signal, sys, time
def stop(*_):
    time.sleep(1)
    open("saved", "w").write("saved")
    sys.exit(0)
signal.signal(signal.SIGINT, stop)
open("running", "w").write("running")
for _ in range(int(os.environ.get("ENS_FAKE_TICKS", "300"))):
    time.sleep(0.1)
sys.exit(int(os.environ.get("ENS_FAKE_EXIT", "0")))
EOF
cat > "${tmp}/bin/proton" <<EOF
#!/bin/bash
shift
exec "${tmp}/bin/enshrouded_server"
EOF
printf '#!/bin/sh\nexit 0\n' > "${tmp}/proton/files/bin/wineserver"
chmod +x "${tmp}/bin/enshrouded_server" "${tmp}/bin/proton" "${tmp}/proton/files/bin/wineserver"

run_server() { # <home> [env...]
    local home="$1"; shift
    mkdir -p "${home}/.steam/sdk64"
    : > "${home}/.steam/sdk64/steamclient.so"
    : > "${home}/enshrouded_server.exe"
    (cd "${home}" && exec env PATH="${tmp}/bin:${PATH}" HOME="${home}" ENS_TEST_HOME="${home}" \
        PROTON_DIR="${tmp}/proton" AUTO_UPDATE=0 SERVER_PORT=15637 "$@" \
        bash "${tmp}/start" ./enshrouded_server.exe > "${home}/console" 2>&1) &
    SERVER_PID=$!
    for _ in $(seq 1 50); do
        [ -f "${home}/running" ] && return 0
        sleep 0.1
    done
    return 1
}

h="${tmp}/run-stop"
mkdir -p "${h}"
run_server "${h}"
check "server started" "running" "$(cat "${h}/running" 2>/dev/null)"
check "missing config was created" "15637" "$(jq -r .queryPort "${h}/enshrouded_server.json" 2>/dev/null)"
start=$(date +%s)
kill -TERM "${SERVER_PID}"
wait "${SERVER_PID}"
rc=$?
took=$(( $(date +%s) - start ))
check "stop lets the server save first" "saved" "$(cat "${h}/saved" 2>/dev/null)"
check "stop reports the server's own exit code" "0" "${rc}"
check "stop does not wait for the timeout" "yes" "$([ "${took}" -lt 10 ] && echo yes || echo no)"

h="${tmp}/run-exit"
mkdir -p "${h}"
run_server "${h}" ENS_FAKE_EXIT=3 ENS_FAKE_TICKS=10
wait "${SERVER_PID}"
check "a server exit code is passed through" "3" "$?"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
