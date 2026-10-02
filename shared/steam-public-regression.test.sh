#!/bin/bash
set -u

. "${1:?helper path required}"

pterohost_steam_seed() { :; }
pterohost_steam_sdk() { :; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export STEAMCMD_RUN="${tmp}/steamcmd"
export STEAMCMD_ATTEMPTS=1
export STEAMCMD_RETRY_SLEEP=0
export FAKE_STATE="${tmp}/appmanifest.fixture"
export FAKE_CALLS="${tmp}/calls"
export FAKE_SENTINEL="${tmp}/7DaysToDieServer.x86_64"
mkdir -p "${STEAMCMD_RUN}"

cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf 'CALL\n' >> "${FAKE_CALLS}"
printf '%s\n' "$@" >> "${FAKE_CALLS}"
branch=""
appid=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        +app_update) appid="${2:-}"; shift 2 ;;
        -beta) branch="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "${appid}" ] || exit 0
if [ "${FAKE_ERROR_STATE:-0}" = "1" ]; then
    printf "Error! App '%s' state is 0x602 after update job.\n" "${appid}"
    exit 8
fi
if [ "${branch}" = "missing" ] || { [ "${branch}" = "public" ] && [ "${FAKE_FAIL_PUBLIC:-0}" = "1" ]; }; then
    printf "ERROR! Failed to install app '%s' (Missing configuration)\n" "${appid}"
    exit 1
fi
if [ -n "${branch}" ]; then
    if [ "${branch}" = "public" ]; then
        printf 'UserConfig.BetaKey=public\nMountedConfig.BetaKey=public\nbuildid=24994542\n' > "${FAKE_STATE}"
    else
        printf 'UserConfig.BetaKey=%s\nMountedConfig.BetaKey=%s\nbuildid=beta\n' "${branch}" "${branch}" > "${FAKE_STATE}"
    fi
fi
printf "Success! App '%s' already up to date.\n" "${appid}"
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"

pass=0
fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf 'ok %s\n' "$1"
        pass=$((pass + 1))
    else
        printf 'FAIL %s: expected <%s>, got <%s>\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}
reset_case() {
    printf 'UserConfig.BetaKey=v2.6\nMountedConfig.BetaKey=v2.6\nbuildid=22422094\n' > "${FAKE_STATE}"
    : > "${FAKE_CALLS}"
    : > "${FAKE_SENTINEL}"
    unset SRCDS_BETAPASS FAKE_FAIL_PUBLIC FAKE_ERROR_STATE
}
state() { sed -n "s/^$1=//p" "${FAKE_STATE}"; }
calls() { grep -Fxc -- "$1" "${FAKE_CALLS}" || true; }

reset_case
out="$(pterohost_steam_update 294420 '' 0 "${FAKE_SENTINEL}" 2>&1)"
check 'legacy omitted branch leaves sticky beta' v2.6 "$(state MountedConfig.BetaKey)"
check 'legacy call sends no beta flag' 0 "$(calls -beta)"

reset_case
out="$(pterohost_steam_update 294420 '' 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'empty branch exits successfully' 0 "$?"
check 'empty branch selects public' public "$(state MountedConfig.BetaKey)"
check 'empty branch selects public build' 24994542 "$(state buildid)"
check 'empty branch sends beta flag' 1 "$(calls -beta)"
check 'empty branch sends public argument' 1 "$(calls public)"

reset_case
out="$(pterohost_steam_update 294420 public 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'public branch exits successfully' 0 "$?"
check 'public branch replaces sticky beta' public "$(state UserConfig.BetaKey)"
check 'public branch sends beta flag' 1 "$(calls -beta)"

reset_case
out="$(SRCDS_BETAPASS='unused dummy password' pterohost_steam_update 294420 public 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'public branch does not send a beta password' 0 "$(calls -betapassword)"
check 'public branch with stale password still selects public' public "$(state MountedConfig.BetaKey)"

reset_case
out="$(pterohost_steam_update 294420 v2.6 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'explicit beta stays selected' v2.6 "$(state MountedConfig.BetaKey)"
check 'explicit beta argument preserved' 1 "$(calls v2.6)"

reset_case
password='dummy secret with spaces'
out="$(SRCDS_BETAPASS="${password}" pterohost_steam_update 294420 protected 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'private beta sends password as one argument' 1 "$(calls "${password}")"
check 'private beta sends password flag' 1 "$(calls -betapassword)"
case "${out}" in
    *"${password}"*) check 'password absent from helper output' hidden visible ;;
    *) check 'password absent from helper output' hidden hidden ;;
esac

reset_case
out="$(pterohost_steam_update 294420 missing 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'missing beta falls back to explicit public' public "$(state MountedConfig.BetaKey)"
check 'fallback makes two update calls' 2 "$(calls +app_update)"
check 'fallback keeps beta flag on both calls' 2 "$(calls -beta)"

reset_case
export FAKE_FAIL_PUBLIC=1
out="$(pterohost_steam_update 294420 public 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'failed public selection returns error' 1 "$?"
check 'failed public selection keeps existing files' v2.6 "$(state MountedConfig.BetaKey)"
check 'failed public selection never retries without branch' 1 "$(calls +app_update)"
case "${out}" in
    *'SteamCMD update OK.'*) check 'failed public selection cannot claim success' absent present ;;
    *) check 'failed public selection cannot claim success' absent absent ;;
esac

reset_case
export FAKE_ERROR_STATE=1
out="$(pterohost_steam_update 294420 '' 0 "${FAKE_SENTINEL}" 1 2>&1)"
check 'post-update state error returns failure with old binary present' 1 "$?"
case "${out}" in
    *'SteamCMD update OK.'*) check 'post-update state error cannot claim success' absent present ;;
    *) check 'post-update state error cannot claim success' absent absent ;;
esac

printf '%s passed, %s failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
