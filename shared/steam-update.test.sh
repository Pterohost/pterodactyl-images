#!/bin/bash
# Contract tests for shared/steam-update.sh
#
# Nothing here touches the network: SteamCMD is a stub script whose output is
# whatever the case under test needs it to be. What is worth pinning down is the
# verdict - did the update actually happen - because that is the part every
# start-* bootstrap trusts and the part that was quietly wrong.
#
# The bug these tests exist for: success was judged by the presence of the game
# binary. On a first install that is sound. On every boot after it, the file is
# already there from last time, so a run that downloaded nothing still printed
# "SteamCMD update OK." Six Project Zomboid servers pinned to a Steam branch
# Valve had deleted sat on an old build for as long as it took someone to
# notice, and the console said the update had succeeded every single boot.
set -u

. "$(dirname "$0")/steam-update.sh"

# The seed copies SteamCMD into the server volume and the SDK step symlinks into
# ${HOME}; neither is under test and both would write outside the temp dir.
pterohost_steam_seed() { :; }
pterohost_steam_sdk() { :; }

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

check_contains() { # <name> <needle> <haystack>
    case "$3" in
        *"$2"*) PASS=$((PASS + 1)); printf 'ok   %s\n' "$1" ;;
        *) FAIL=$((FAIL + 1)); printf 'FAIL %s\n  expected to contain: %s\n  actual:\n%s\n' "$1" "$2" "$3" ;;
    esac
}

check_lacks() { # <name> <needle> <haystack>
    case "$3" in
        *"$2"*) FAIL=$((FAIL + 1)); printf 'FAIL %s\n  expected NOT to contain: %s\n  actual:\n%s\n' "$1" "$2" "$3" ;;
        *) PASS=$((PASS + 1)); printf 'ok   %s\n' "$1" ;;
    esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

export STEAMCMD_RUN="${TMP}/steamcmd"
export STEAMCMD_ATTEMPTS=1
export STEAMCMD_RETRY_SLEEP=0
SENTINEL="${TMP}/ProjectZomboid64"
mkdir -p "${STEAMCMD_RUN}"

# A stub SteamCMD. FAKE_SCRIPT decides what it prints and whether it "downloads"
# anything; FAKE_CALLS records the argument lists it was invoked with, so a test
# can assert that the retry dropped -beta.
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case " $* " in
    *" +quit "*) ;;
esac
# The settle pass (+quit only) stays silent, like the real thing.
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
if [ -n "${FAKE_OUTPUT:-}" ]; then
    printf '%s\n' "${FAKE_OUTPUT}"
fi
if [ "${FAKE_DOWNLOADS:-0}" = "1" ]; then
    : > "${FAKE_SENTINEL}"
fi
exit "${FAKE_EXIT:-0}"
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"

export FAKE_SENTINEL="${SENTINEL}"
export FAKE_CALLS="${TMP}/calls"

reset_case() {
    rm -f "${SENTINEL}" "${FAKE_CALLS}"
    : > "${FAKE_CALLS}"
    unset FAKE_OUTPUT FAKE_DOWNLOADS FAKE_EXIT
}

# --- a first install that works ------------------------------------------
reset_case
export FAKE_DOWNLOADS=1 FAKE_OUTPUT="Success! App '380870' fully installed."
out="$(pterohost_steam_update 380870 "" 0 "${SENTINEL}" 2>&1)"
check "успешное обновление возвращает 0" "0" "$?"
check_contains "успешное обновление сообщает OK" "SteamCMD update OK" "${out}"

# --- the regression this file exists for ---------------------------------
# Steam deleted the branch. Nothing downloads, but the binary from the previous
# install is still sitting in the volume.
reset_case
: > "${SENTINEL}"                        # last install left the game on disk
export FAKE_DOWNLOADS=0 FAKE_EXIT=1 STEAM_BRANCH_FALLBACK=0
export FAKE_OUTPUT="ERROR! Failed to install app '380870' (Missing configuration)"
out="$(pterohost_steam_update 380870 unstable 0 "${SENTINEL}" 2>&1)"
rc=$?
check "несуществующая ветка при уже установленных файлах: не 0" "1" "${rc}"
check_lacks "несуществующая ветка не рапортует об успехе" "SteamCMD update OK" "${out}"
check_contains "несуществующая ветка названа в консоли" "no branch named 'unstable'" "${out}"

# Older SteamCMD builds word it differently; both must be recognised.
reset_case
: > "${SENTINEL}"
export FAKE_DOWNLOADS=0 FAKE_EXIT=1 STEAM_BRANCH_FALLBACK=0
export FAKE_OUTPUT="Failed to set beta 'unstable' for app 380870"
out="$(pterohost_steam_update 380870 unstable 0 "${SENTINEL}" 2>&1)"
check "старая формулировка Steam тоже опознаётся" "1" "$?"
check_contains "старая формулировка называет ветку" "no branch named 'unstable'" "${out}"

# --- fallback to the default branch --------------------------------------
# The point of the fallback is that the server still comes up, on the current
# release, instead of sitting on a dead pin.
reset_case
: > "${SENTINEL}"
export STEAM_BRANCH_FALLBACK=1
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
case "$*" in
    *-beta*)
        printf "ERROR! Failed to install app '380870' (Missing configuration)\n"
        exit 1
        ;;
esac
printf "Success! App '380870' fully installed.\n"
: > "${FAKE_SENTINEL}"
exit 0
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"
out="$(pterohost_steam_update 380870 unstable 0 "${SENTINEL}" 2>&1)"
check "откат на дефолтную ветку возвращает 0" "0" "$?"
check_contains "откат объявлен в консоли" "Falling back to the default branch" "${out}"
check "вторая попытка ушла без -beta" "1" \
    "$(grep -c -- '-beta' "${FAKE_CALLS}")"

# --- transient failures stay transient -----------------------------------
# A CDN hiccup is not a dead branch: it must not clear the pin, and it must not
# be reported as a successful update either.
reset_case
: > "${SENTINEL}"
export STEAM_BRANCH_FALLBACK=1
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
printf "ERROR! Failed to install app '380870' (Disk write failure)\n"
exit 1
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"
out="$(pterohost_steam_update 380870 42.19 0 "${SENTINEL}" 2>&1)"
check "транзиентный сбой возвращает не 0" "1" "$?"
check_lacks "транзиентный сбой не рапортует об успехе" "SteamCMD update OK" "${out}"
check_lacks "транзиентный сбой не сбрасывает ветку" "Falling back" "${out}"
check_contains "транзиентный сбой оставляет сервер на старых файлах" \
    "continuing with existing files" "${out}"

# --- AUTO_UPDATE-style skip is not this function's business --------------
# but a branch of "public" must never become "-beta public": that is a real
# branch name to SteamCMD only by accident, and passing it has bitten before.
reset_case
export FAKE_DOWNLOADS=1 FAKE_OUTPUT="Success! App '380870' fully installed."
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
printf '%s\n' "${FAKE_OUTPUT}"
: > "${FAKE_SENTINEL}"
exit 0
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"
pterohost_steam_update 380870 public 0 "${SENTINEL}" >/dev/null 2>&1
check "ветка public не превращается в -beta public" "0" \
    "$(grep -c -- '-beta' "${FAKE_CALLS}")"

# --- пароль закрытой ветки ------------------------------------------------
# Переменная SRCDS_BETAPASS жила в яйцах, но её никто не читал: пароль до
# SteamCMD не доходил, и сервер молча оставался на публичной ветке.
reset_case
export FAKE_DOWNLOADS=1 FAKE_OUTPUT="Success! App '380870' fully installed."
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
printf '%s\n' "${FAKE_OUTPUT}"
: > "${FAKE_SENTINEL}"
exit 0
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"
SRCDS_BETAPASS=hunter2 pterohost_steam_update 380870 experimental 0 "${SENTINEL}" >/dev/null 2>&1
check "пароль закрытой ветки уходит в SteamCMD" "1" \
    "$(grep -c -- '-betapassword hunter2' "${FAKE_CALLS}")"

reset_case
export FAKE_DOWNLOADS=1 FAKE_OUTPUT="Success! App '380870' fully installed."
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
printf '%s\n' "${FAKE_OUTPUT}"
: > "${FAKE_SENTINEL}"
exit 0
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"
unset SRCDS_BETAPASS
pterohost_steam_update 380870 experimental 0 "${SENTINEL}" >/dev/null 2>&1
check "без пароля лишнего флага в команде нет" "0" \
    "$(grep -c -- '-betapassword' "${FAKE_CALLS}")"

# --- validate against a forced platform ----------------------------------
# App 222860 (Left 4 Dead 2) installs only from its Windows depot, and SteamCMD
# refuses to validate a depot for an OS it is not running on. The retry has to
# drop the flag rather than burn all three attempts on it.
reset_case
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
case "$*" in
    *validate*)
        printf "ERROR! Failed to install app '222860' (Missing configuration)\n"
        exit 1
        ;;
esac
printf "Success! App '222860' fully installed.\n"
: > "${FAKE_SENTINEL}"
exit 0
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"
STEAMCMD_PLATFORM=windows pterohost_steam_update 222860 "" 1 "${SENTINEL}" >/dev/null 2>&1
check "принудительная платформа: validate снимается и установка идёт" "0" "$?"
check "первая попытка всё же пробует validate" "1" \
    "$(grep -c -- 'app_update 222860 validate' "${FAKE_CALLS}")"
check "повтор уходит без validate" "1" \
    "$(grep -c -- 'app_update 222860 +quit' "${FAKE_CALLS}")"

reset_case
export FAKE_DOWNLOADS=0 FAKE_EXIT=1
export FAKE_OUTPUT="ERROR! Failed to install app '380870' (Missing configuration)"
cat > "${STEAMCMD_RUN}/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_CALLS}"
case "$*" in
    *app_update*) ;;
    *) exit 0 ;;
esac
printf '%s\n' "${FAKE_OUTPUT}"
exit 1
STUB
chmod +x "${STEAMCMD_RUN}/steamcmd.sh"
unset STEAMCMD_PLATFORM
pterohost_steam_update 380870 "" 1 "${SENTINEL}" >/dev/null 2>&1
check "без принудительной платформы validate не снимается" "0" \
    "$(grep -c -- 'app_update 380870 +quit' "${FAKE_CALLS}")"

printf '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
