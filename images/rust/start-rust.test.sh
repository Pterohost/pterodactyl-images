#!/bin/bash
# Contract tests for images/rust/start-rust: the SteamCMD verdict and the
# panel-console bridge.
#
# Both defects these pin down were invisible from the console:
#
#   - "SteamCMD update OK." was printed whenever RustDedicated existed, which is
#     every boot after the first, so a failed update ("Failed updating depot
#     258552 ... (Read Failed) (Corrupt game files)") booted the old build and
#     said it was current (tickets 4038, 4683, 4785).
#   - The console bridge ended at the first end-of-file on stdin, after which
#     panel commands and the egg's stop command `quit` went nowhere and every
#     Stop/Restart hung in "stopping" (tickets 4683, 4785).
#
# The functions are lifted out of the shipped script by marker, so the tests
# cover the code that ships. The one edit made to the lifted text is
# /home/container -> the sandbox.
#
# Run: bash images/rust/start-rust.test.sh
# Wired into the `test` job in .github/workflows/build.yml.

set -u

SCRIPT="$(cd "$(dirname -- "$0")" && pwd)/start-rust"
FAILED=0
SANDBOX="$(mktemp -d)"
PIDS=()

cleanup() {
    local p
    for p in "${PIDS[@]}"; do kill "${p}" 2>/dev/null; done
    rm -rf "${SANDBOX}"
    return 0
}
trap cleanup EXIT

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
assert_has() { if grep -qE -- "$2" "$3" 2>/dev/null; then ok "$1"; else fail "$1 (no /$2/ in $3)"; sed 's/^/      | /' "$3" 2>/dev/null; fi; }
assert_not() { if grep -qE -- "$2" "$3" 2>/dev/null; then fail "$1 (/$2/ found in $3)"; sed 's/^/      | /' "$3"; else ok "$1"; fi; }

wait_for() { # <seconds> <command...>
    local end=$((SECONDS + $1)); shift
    while [ "${SECONDS}" -le "${end}" ]; do "$@" && return 0; sleep 0.1; done
    return 1
}

LIFTED="${SANDBOX}/lifted.sh"
: > "${LIFTED}"
for fn in rust_manifest_field rust_steam_failure rust_steam_update console_bridge_line console_bridge start_bridge rust_supervise; do
    if ! sed -n "/^${fn}() {/,/^}$/p" "${SCRIPT}" | grep -q .; then
        printf 'FATAL: could not lift %s out of %s\n' "${fn}" "${SCRIPT}"
        exit 1
    fi
    sed -n "/^${fn}() {/,/^}$/p" "${SCRIPT}" >> "${LIFTED}"
done
HOME_DIR="${SANDBOX}/home"
sed -i "s#/home/container#${HOME_DIR}#g" "${LIFTED}"

# ------------------------------------------------------------- SteamCMD ---
#
# A stand-in steamcmd.sh. Each call consumes the next scenario word from
# ${SANDBOX}/plan and acts it out: console lines, content_log lines and the app
# manifest, the three places the real client reports to.
cat > "${SANDBOX}/steamcmd.sh" <<'STUB'
#!/bin/bash
home="${STUB_HOME}"
printf '%s\n' "$*" >> "${STUB_HOME}/../calls"
step="$(head -n 1 "${STUB_HOME}/../plan")"; sed -i '1d' "${STUB_HOME}/../plan"
mkdir -p "${home}/steamapps" "${home}/Steam/logs"
manifest() { printf '"AppState"\n{\n\t"appid"\t\t"258550"\n\t"StateFlags"\t\t"%s"\n\t"buildid"\t\t"%s"\n}\n' "$1" "$2" > "${home}/steamapps/appmanifest_258550.acf"; }
case "${step}" in
    ok)
        manifest 4 26139947
        echo "Success! App '258550' fully installed."; exit 0 ;;
    uptodate)
        echo "Success! App '258550' already up to date."; exit 0 ;;
    corrupt)
        manifest 1158 25823813
        echo '[2026-10-23 09:22:57] AppID 258550 update canceled : Failed updating depot 258552 while reading chunk "4096" (Read Failed) (Corrupt game files) "/home/container/RustDedicated_Data/Managed/System.Data.dll"' >> "${home}/Steam/logs/content_log.txt"
        echo "Error! App '258550' state is 0x48E after update job."; exit 8 ;;
    missing)
        manifest 1062 25902425
        echo '[2026-10-22 11:00:00] AppID 258550 update canceled : Failed updating depot 258552 (Missing game files)' >> "${home}/Steam/logs/content_log.txt"
        echo "Error! App '258550' state is 0x426 after update job."; exit 8 ;;
    neterr)
        echo "ERROR! Failed to install app '258550' (No Connection)"; exit 8 ;;
    silent)
        exit 0 ;;
esac
STUB
chmod +x "${SANDBOX}/steamcmd.sh"

steam_case() { # <name> <plan words...> - runs rust_steam_update in a fresh volume
    local name="$1"; shift
    rm -rf "${HOME_DIR}" "${SANDBOX}/calls"
    mkdir -p "${HOME_DIR}/steamapps" "${HOME_DIR}/.tmp"
    printf '#!/bin/sh\n' > "${HOME_DIR}/RustDedicated"; chmod +x "${HOME_DIR}/RustDedicated"
    printf '"AppState"\n{\n\t"StateFlags"\t\t"4"\n\t"buildid"\t\t"25823813"\n}\n' > "${HOME_DIR}/steamapps/appmanifest_258550.acf"
    printf '%s\n' "$@" > "${SANDBOX}/plan"
    (
        export STUB_HOME="${HOME_DIR}" TMPDIR="${HOME_DIR}/.tmp" STEAMCMD_RETRY_SLEEP=0
        APPID=258550
        log() { printf '[rust] %s\n' "$*"; }
        . "${LIFTED}"
        RUST_VALIDATED=0
        rust_steam_update "${SANDBOX}/steamcmd.sh" "${VALIDATE_IN:-0}"
        printf 'rc=%s validated=%s\n' "$?" "${RUST_VALIDATED}"
    ) > "${SANDBOX}/${name}.out" 2>&1
}

printf 'SteamCMD verdict\n'

steam_case success ok
assert_has "a real update says OK and names both builds" 'SteamCMD update OK - build 25823813 -> 26139947' "${SANDBOX}/success.out"
assert_has "a real update returns success" 'rc=0 validated=0' "${SANDBOX}/success.out"

steam_case uptodate uptodate
assert_has "an up-to-date server says so" 'already on the latest build 25823813' "${SANDBOX}/uptodate.out"

# The 4683 shape: the update fails, RustDedicated is still on disk. The old code
# printed "SteamCMD update OK." here.
steam_case corrupt_then_ok corrupt ok
assert_has "a corrupt-files failure is reported with Steam's own reason" 'attempt 1 FAILED \(exit 8\): AppID 258550 update canceled : Failed updating depot 258552.*Corrupt game files' "${SANDBOX}/corrupt_then_ok.out"
assert_has "it is retried with validate" 'retrying once with validate' "${SANDBOX}/corrupt_then_ok.out"
assert_eq  "the retry passes validate to SteamCMD" "validate" "$(sed -n 2p "${SANDBOX}/calls" | grep -o 'validate' | head -n 1)"
assert_eq  "the first run did not validate" "" "$(sed -n 1p "${SANDBOX}/calls" | grep -o 'validate')"
assert_has "after the validate retry the update succeeds and the framework is re-applied" 'rc=0 validated=1' "${SANDBOX}/corrupt_then_ok.out"

steam_case corrupt_always corrupt corrupt corrupt corrupt corrupt
assert_not "a failed update never claims OK" 'update OK' "${SANDBOX}/corrupt_always.out"
assert_has "a failed update says it is booting the old build" 'SteamCMD update FAILED .* starting the build already on disk \(buildid 25823813\)' "${SANDBOX}/corrupt_always.out"
assert_eq  "the validate retry happens once, on top of the normal attempts" "4" "$(wc -l < "${SANDBOX}/calls" | tr -d ' ')"
assert_has "a failed update returns failure" 'rc=1' "${SANDBOX}/corrupt_always.out"

steam_case missing_then_ok missing ok
assert_has "missing game files get the same validate retry" 'retrying once with validate' "${SANDBOX}/missing_then_ok.out"

steam_case neterr neterr neterr neterr
assert_has "a network failure is reported as such" 'FAILED \(exit 8\): ERROR! Failed to install app' "${SANDBOX}/neterr.out"
assert_not "a network failure is not retried with validate" 'retrying once with validate' "${SANDBOX}/neterr.out"
assert_eq  "a network failure uses the normal three attempts" "3" "$(wc -l < "${SANDBOX}/calls" | tr -d ' ')"

steam_case silent silent silent silent
assert_has "a run that never reports success is a failure" 'did not report success' "${SANDBOX}/silent.out"
assert_not "a run that never reports success never claims OK" 'update OK' "${SANDBOX}/silent.out"

# Staging clean-up proper: the directory must be gone before the second run.
rm -rf "${HOME_DIR}"; mkdir -p "${HOME_DIR}/steamapps/downloading/258550" "${HOME_DIR}/.tmp"
printf 'x' > "${HOME_DIR}/steamapps/downloading/258550/chunk"
printf '#!/bin/sh\n' > "${HOME_DIR}/RustDedicated"; chmod +x "${HOME_DIR}/RustDedicated"
printf '%s\n' corrupt ok > "${SANDBOX}/plan"; rm -f "${SANDBOX}/calls"
(
    export STUB_HOME="${HOME_DIR}" TMPDIR="${HOME_DIR}/.tmp" STEAMCMD_RETRY_SLEEP=0
    APPID=258550; log() { :; }; . "${LIFTED}"; rust_steam_update "${SANDBOX}/steamcmd.sh" 0
) >/dev/null 2>&1
assert_eq "steamapps/downloading/<appid> is removed for the validate retry" "gone" "$([ -d "${HOME_DIR}/steamapps/downloading/258550" ] && echo present || echo gone)"

# --------------------------------------------------------- console bridge ---
#
# RCON is stubbed: rcon_up is always true and rcon_send appends the command to
# a file, so "the server received it" is a line in that file.

printf 'Console bridge\n'

bridge_env() {
    log() { printf '[rust] %s\n' "$*"; }
    rcon_up() { return 0; }
    rcon_send() { printf '%s\n' "$1" >> "${SANDBOX}/rcon"; }
    . "${LIFTED}"
}

# 1. stdin closed outright. The old loop returned at once.
rm -f "${SANDBOX}/rcon"
( bridge_env; BRIDGE_EOF_SLEEP=0.1 console_bridge < /dev/null ) > "${SANDBOX}/closed.out" 2>&1 &
BP=$!; PIDS+=("${BP}")
sleep 1
assert_eq  "the bridge survives a closed stdin" "alive" "$(kill -0 "${BP}" 2>/dev/null && echo alive || echo dead)"
assert_eq  "a closed stdin is reported once, not once per poll" "1" "$(grep -c 'input stream closed' "${SANDBOX}/closed.out")"
kill "${BP}" 2>/dev/null; wait "${BP}" 2>/dev/null

# 2. Detach and re-attach: every writer of the stream goes away (EOF), then a
# new one arrives. A FIFO behaves exactly like that. Commands sent after the
# re-attach - `quit` above all - must still arrive.
rm -f "${SANDBOX}/rcon"; mkfifo "${SANDBOX}/stdin"
( bridge_env; BRIDGE_EOF_SLEEP=0.1 console_bridge < "${SANDBOX}/stdin" ) > "${SANDBOX}/fifo.out" 2>&1 &
BP=$!; PIDS+=("${BP}")
printf 'status\n' > "${SANDBOX}/stdin"
wait_for 5 grep -qx status "${SANDBOX}/rcon"
sleep 0.5
printf 'say hi\r\nquit' > "${SANDBOX}/stdin"
wait_for 5 grep -qx quit "${SANDBOX}/rcon"
assert_eq "commands before and after a detach both reach RCON" "status|say hi|quit" "$(paste -sd'|' "${SANDBOX}/rcon")"
assert_eq "the bridge is still running after the re-attach" "alive" "$(kill -0 "${BP}" 2>/dev/null && echo alive || echo dead)"
kill "${BP}" 2>/dev/null; wait "${BP}" 2>/dev/null

# 3. The supervisor: the server's exit code is passed through, a dead bridge is
# restarted while the server runs, and `quit` sent to the restarted bridge stops
# the server. The stub server exits 0 when RCON delivers `quit`.
cat > "${SANDBOX}/server.sh" <<'SRV'
#!/bin/bash
while ! grep -qx quit "$1" 2>/dev/null; do sleep 0.1; done
exit "${2:-0}"
SRV
chmod +x "${SANDBOX}/server.sh"

rm -f "${SANDBOX}/rcon" "${SANDBOX}/stdin"; mkfifo "${SANDBOX}/stdin"
exec 7<>"${SANDBOX}/stdin"
(
    bridge_env
    "${SANDBOX}/server.sh" "${SANDBOX}/rcon" 7 &
    SERVER_PID=$!
    printf '%s\n' "${SERVER_PID}" > "${SANDBOX}/server.pid"
    exec 3<"${SANDBOX}/stdin"
    start_bridge
    printf '%s\n' "${BRIDGE_PID}" > "${SANDBOX}/bridge.pid"
    rust_supervise
    printf 'EXIT_CODE=%s\n' "${EXIT_CODE}"
) > "${SANDBOX}/super.out" 2>&1 &
SP=$!; PIDS+=("${SP}")
wait_for 5 test -s "${SANDBOX}/bridge.pid"
kill -KILL "$(cat "${SANDBOX}/bridge.pid")" 2>/dev/null
wait_for 5 grep -q 'bridge stopped' "${SANDBOX}/super.out"
sleep 1.5
printf 'quit\n' >&7
wait_for 10 grep -q EXIT_CODE "${SANDBOX}/super.out"
assert_has "a killed bridge is restarted while the server runs" 'bridge stopped \(status 137\) - restarting it' "${SANDBOX}/super.out"
assert_has "quit through the restarted bridge stops the server" '^quit$' "${SANDBOX}/rcon"
assert_has "the server's own exit code comes out of the supervisor" '^EXIT_CODE=7$' "${SANDBOX}/super.out"
exec 7>&-

if [ "${FAILED}" -ne 0 ]; then
    printf 'FAILED\n'
    exit 1
fi
printf 'PASS\n'
