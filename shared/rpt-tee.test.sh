#!/bin/bash
# Contract tests for shared/rpt-tee.sh, the persistent server log behind
# start-arma3 (ticket 4626).
#
# What has to hold, because the server is a customer's running game:
#   - the console sees every line, unchanged, live;
#   - the server's exit status is the bootstrap's exit status;
#   - ^C from Wings (SIGINT to the whole process group via tini -g) still stops
#     the server the way it always did, and its shutdown lines reach the file;
#   - the file side can fail (full volume) without touching the console or the
#     server;
#   - the files stay inside the cap.
#
# Run: bash shared/rpt-tee.test.sh
# Wired into the `test` job in .github/workflows/build.yml.

set -u

LIB="$(cd "$(dirname -- "$0")" && pwd)/rpt-tee.sh"
SANDBOX="$(mktemp -d)"
FAILED=0
trap 'rm -rf "${SANDBOX}"' EXIT

# The images run Debian's default awk, which is mawk. Test with it when the
# machine has it, so a gawk-only construct cannot slip through.
if command -v mawk >/dev/null 2>&1; then
    mkdir -p "${SANDBOX}/bin"
    ln -s "$(command -v mawk)" "${SANDBOX}/bin/awk"
    export PATH="${SANDBOX}/bin:${PATH}"
fi

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }

# A runner that ends exactly like start-arma3: source the library, call
# pterohost_rpt_exec with a stand-in server. It is started in its own session
# so a signal can be sent to its process group, the way tini -g does.
cat > "${SANDBOX}/run.sh" <<RUN
#!/bin/bash
set -u
. "${LIB}"
pterohost_rpt_exec "\$1" arma3 "binary=test mods=2" "\${@:2}"
RUN

cat > "${SANDBOX}/server.sh" <<'SRV'
#!/bin/bash
# <mode> [lines] - prints numbered lines, then behaves per mode.
mode="$1"; n="${2:-5}"
trap 'echo "server: SIGINT, saving world"; sleep 0.2; echo "server: saved"; exit 0' INT
for i in $(seq 1 "${n}"); do printf 'line %06d %s\n' "${i}" "$(printf '%0100d' 0)"; done
echo "stderr line" >&2
case "${mode}" in
    exit3) exit 3 ;;
    wait)  echo ready; while :; do sleep 0.05; done ;;
    *)     exit 0 ;;
esac
SRV
chmod +x "${SANDBOX}/run.sh" "${SANDBOX}/server.sh"

printf 'rpt-tee\n'

# 1. Console and file both get everything; the exit status is the server's.
D="${SANDBOX}/rpt1"
bash "${SANDBOX}/run.sh" "${D}" "${SANDBOX}/server.sh" exit3 5 > "${SANDBOX}/console1" 2>&1
rc=$?
assert_eq "the server's exit status comes through" "3" "${rc}"
assert_eq "the console gets every stdout and stderr line" "6" "$(grep -cE '^line|^stderr line' "${SANDBOX}/console1")"
assert_eq "the file gets every line plus the marker" "7" "$(wc -l < "${D}/arma3-current.log" | tr -d ' ')"
assert_eq "the marker carries a full date" "yes" \
    "$(head -n 1 "${D}/arma3-current.log" | grep -qE '^### pterohost rpt start [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}.* binary=test mods=2$' && echo yes || echo no)"
assert_eq "the console holds no marker of ours" "0" "$(grep -c 'pterohost rpt' "${SANDBOX}/console1")"

# 2. The next start archives the previous run, compressed, under its own time.
touch -d '2026-10-22 19:00:13' "${D}/arma3-current.log"
bash "${SANDBOX}/run.sh" "${D}" "${SANDBOX}/server.sh" ok 2 > /dev/null 2>&1
assert_eq "the previous run is archived as a .gz named after its last write" "yes" \
    "$([ -f "${D}/arma3-20261022-190013.log.gz" ] && echo yes || echo no)"
assert_eq "the archive holds the previous run" "7" "$(gzip -dc "${D}/arma3-20261022-190013.log.gz" | wc -l | tr -d ' ')"
assert_eq "the new current file holds only the new run" "4" "$(wc -l < "${D}/arma3-current.log" | tr -d ' ')"

# 3. Size cap and retention: 1 MB files, keep 2 archives.
D="${SANDBOX}/rpt3"
RPT_LOG_MAX_MB=1 RPT_LOG_KEEP=2 bash "${SANDBOX}/run.sh" "${D}" "${SANDBOX}/server.sh" ok 40000 > "${SANDBOX}/console3" 2>&1
sleep 1
size="$(stat -c %s "${D}/arma3-current.log")"
assert_eq "the current file stays under the cap" "yes" "$([ "${size}" -le $((1048576 + 200)) ] && echo yes || echo no)"
assert_eq "no more than RPT_LOG_KEEP archives are kept" "2" "$(ls "${D}"/arma3-2*.log.gz 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no uncompressed archive is left behind" "0" "$(ls "${D}"/arma3-2*.log 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "a continued segment says so" "yes" "$(head -n 1 "${D}/arma3-current.log" | grep -q '^### pterohost rpt continued ' && echo yes || echo no)"
assert_eq "the console still got all 40000 lines" "40000" "$(grep -c '^line' "${SANDBOX}/console3")"
last="$(grep '^line' "${D}/arma3-current.log" | tail -n 1 | cut -d' ' -f2)"
assert_eq "the newest segment ends with the last line" "040000" "${last}"

# 4. ^C the way Wings sends it: SIGINT to the process group. The server saves
# and exits 0; the shutdown lines reach the console and the file.
D="${SANDBOX}/rpt4"
# A background job of this shell starts with SIGINT ignored, which bash then
# cannot trap; tini starts the bootstrap with default dispositions, so restore
# them and give the runner its own process group.
python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash "${SANDBOX}/run.sh" "${D}" "${SANDBOX}/server.sh" wait 3 > "${SANDBOX}/console4" 2>&1 &
RP=$!
for _ in $(seq 1 50); do grep -q ready "${SANDBOX}/console4" 2>/dev/null && break; sleep 0.1; done
kill -INT -- "-${RP}"
wait "${RP}"
rc=$?
assert_eq "SIGINT to the group: the server saves and the bootstrap exits 0" "0" "${rc}"
assert_eq "the shutdown lines reach the console" "yes" "$(grep -q 'server: saved' "${SANDBOX}/console4" && echo yes || echo no)"
assert_eq "the shutdown lines reach the file" "yes" "$(grep -q 'server: saved' "${D}/arma3-current.log" && echo yes || echo no)"

# 4b. A server that does not handle SIGINT dies of it, and the container must
# report that exactly as a bare exec under tini did: 128 + 2.
cat > "${SANDBOX}/plain.sh" <<'SRV'
#!/bin/bash
echo ready
exec sleep 30
SRV
chmod +x "${SANDBOX}/plain.sh"
python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash "${SANDBOX}/run.sh" "${SANDBOX}/rpt4b" "${SANDBOX}/plain.sh" > "${SANDBOX}/console4b" 2>&1 &
RP=$!
for _ in $(seq 1 50); do grep -q ready "${SANDBOX}/console4b" 2>/dev/null && break; sleep 0.1; done
kill -INT -- "-${RP}"
wait "${RP}"
assert_eq "a server killed by SIGINT gives the same status as under a bare exec" "130" "$?"

# 5. The file side fails mid-run (a full volume). Console and server must not
# notice beyond a warning.
D="${SANDBOX}/rpt5"
mkdir -p "${D}"
cat > "${SANDBOX}/run-full.sh" <<RUN
#!/bin/bash
. "${LIB}"
pterohost_rpt_open() { mkdir -p "\$1"; ln -sfn /dev/full "\$1/\$2-current.log"; }
pterohost_rpt_exec "\$1" arma3 "x" "\${@:2}"
RUN
bash "${SANDBOX}/run-full.sh" "${D}" "${SANDBOX}/server.sh" exit3 3000 > "${SANDBOX}/console5" 2>&1
rc=$?
assert_eq "a failing file side leaves the exit status alone" "3" "${rc}"
assert_eq "a failing file side leaves the console complete" "3000" "$(grep -c '^line' "${SANDBOX}/console5")"

# 6. An unwritable directory: no copy, plain exec, nothing else changes.
D="${SANDBOX}/rpt6"
: > "${D}"
bash "${SANDBOX}/run.sh" "${D}/sub" "${SANDBOX}/server.sh" exit3 2 > "${SANDBOX}/console6" 2>&1
rc=$?
assert_eq "an unwritable directory falls back to exec with the same status" "3" "${rc}"
assert_eq "an unwritable directory falls back to exec with the same output" "3" "$(grep -cE '^line|^stderr' "${SANDBOX}/console6")"

# 7. RPT_LOG=0 is the old exec.
D="${SANDBOX}/rpt7"
RPT_LOG=0 bash "${SANDBOX}/run.sh" "${D}" "${SANDBOX}/server.sh" exit3 2 > /dev/null 2>&1
rc=$?
assert_eq "RPT_LOG=0 keeps the exit status" "3" "${rc}"
assert_eq "RPT_LOG=0 writes nothing" "no" "$([ -e "${D}" ] && echo yes || echo no)"

# 8. The file-only writer used for headless clients drains after a failure, so
# the client never gets a broken pipe.
D="${SANDBOX}/rpt8"
mkdir -p "${D}"
ln -sfn /dev/full "${D}/hc1-current.log"
out="$( ( . "${LIB}"; seq 1 20000 | pterohost_rpt_file "${D}" hc1; echo "pipe=${PIPESTATUS[0]}" ) 2>/dev/null )"
assert_eq "the headless-client writer never breaks its pipe" "pipe=0" "$(printf '%s\n' "${out}" | tail -n 1)"

if [ "${FAILED}" -ne 0 ]; then
    printf 'FAILED\n'
    exit 1
fi
printf 'PASS\n'
