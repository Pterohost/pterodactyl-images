#!/bin/bash
# Contract tests for shared/launch.sh
set -u

. "$(dirname "$0")/launch.sh"

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

joined() {
    [ "${#PTEROHOST_ARGS[@]}" -eq 0 ] && return
    printf '%s|' "${PTEROHOST_ARGS[@]}"
}

# --- rule 2: prune -------------------------------------------------------
pterohost_prune_empty_args ./srcds_run +map gm_flatgrass +host_workshop_collection "" +gamemode sandbox
check "empty flag+value pair dropped" \
    "./srcds_run|+map|gm_flatgrass|+gamemode|sandbox|" "$(joined)"

pterohost_prune_empty_args PalServer Pal -port=27015 -queryport= -players=10
check "UE style -flag= dropped" \
    "PalServer|Pal|-port=27015|-players=10|" "$(joined)"

pterohost_prune_empty_args ./srcds_run +map gm_flatgrass +fps_max ""
check "trailing empty pair dropped" \
    "./srcds_run|+map|gm_flatgrass|" "$(joined)"

pterohost_prune_empty_args ./sbox-server +game facepunch.sandbox "" +hostname test
check "standalone empty dropped" \
    "./sbox-server|+game|facepunch.sandbox|+hostname|test|" "$(joined)"

pterohost_prune_empty_args ./srcds_run +map gm_construct
check "nothing to prune leaves args untouched" \
    "./srcds_run|+map|gm_construct|" "$(joined)"

# --- rule 1 + 4: pass-through and legacy fallback -------------------------
pterohost_panel_argv ./srcds_run -game garrysmod
check "panel args set the flag" "1" "${PTEROHOST_FROM_PANEL}"
check "panel args pass through" "./srcds_run|-game|garrysmod|" "$(joined)"

pterohost_panel_argv
check "no args means legacy" "0" "${PTEROHOST_FROM_PANEL}"
check "legacy leaves the array empty" "" "$(joined)"

# --- rule 3: append-if-absent --------------------------------------------
pterohost_panel_argv ./srcds_run -threads 4
pterohost_append_if_absent -threads -threads 7
check "explicit -threads wins" "./srcds_run|-threads|4|" "$(joined)"

pterohost_panel_argv ./srcds_run
pterohost_append_if_absent -threads -threads 7
check "missing -threads appended" "./srcds_run|-threads|7|" "$(joined)"

pterohost_panel_argv PalServer Pal -players=10
pterohost_append_if_absent -players "-players=32"
check "-flag=value form detected as present" "PalServer|Pal|-players=10|" "$(joined)"

pterohost_panel_argv ./srcds_run +rcon_password hunter2
pterohost_append_if_absent +rcon_password +rcon_password secret -usercon
check "multi-token append skipped when key present" \
    "./srcds_run|+rcon_password|hunter2|" "$(joined)"

# --- binary swap ----------------------------------------------------------
pterohost_panel_argv ./srcds_run -game garrysmod
pterohost_swap_binary ./srcds_run ./srcds_run_x64 >/dev/null
check "binary swapped" "./srcds_run_x64|-game|garrysmod|" "$(joined)"

pterohost_panel_argv ./srcds_run -game garrysmod
pterohost_swap_binary ./srcds_run ./srcds_run >/dev/null
check "identical swap is a no-op" "./srcds_run|-game|garrysmod|" "$(joined)"

pterohost_panel_argv ./FactoryServer.sh FactoryGame
pterohost_swap_binary ./srcds_run ./srcds_run_x64 >/dev/null
check "swap skipped when binary does not match" \
    "./FactoryServer.sh|FactoryGame|" "$(joined)"

# --- prune_valueless (quote-destroying entrypoints) -----------------------
pterohost_panel_argv ./srcds_run +host_workshop_collection +fps_max 300 +sv_pure
pterohost_prune_valueless_flags +host_workshop_collection +fps_max +sv_pure >/dev/null
check "dangling flag before another flag dropped" \
    "./srcds_run|+fps_max|300|" "$(joined)"

pterohost_panel_argv ./srcds_run +fps_max -1 +sv_pure 2
pterohost_prune_valueless_flags +fps_max +sv_pure >/dev/null
check "negative number is a value, not a flag" \
    "./srcds_run|+fps_max|-1|+sv_pure|2|" "$(joined)"

pterohost_panel_argv ./srcds_run -tickrate 22 -norestart
pterohost_prune_valueless_flags -tickrate >/dev/null
check "flag with a value survives" \
    "./srcds_run|-tickrate|22|-norestart|" "$(joined)"

# --- has_flag edge cases --------------------------------------------------
pterohost_has_flag -threads ./srcds_run -threads 4 && r=yes || r=no
check "has_flag finds a bare flag" "yes" "${r}"
pterohost_has_flag -threads ./srcds_run -tickrate 22 && r=yes || r=no
check "has_flag does not match a prefix of another flag" "no" "${r}"

# --- rule 5: the printed command must not leak credentials ----------------
printed="$(pterohost_log_cmd ./srcds_run -game garrysmod +rcon_password hunter2 \
    +sv_setsteamaccount GSLTTOKEN -adminpassword=plaintext +map gm_flatgrass 2>&1)"
check "rcon password not printed" "" "$(printf '%s' "${printed}" | grep -o hunter2)"
check "gslt not printed" "" "$(printf '%s' "${printed}" | grep -o GSLTTOKEN)"
check "flag=value secret not printed" "" "$(printf '%s' "${printed}" | grep -o plaintext)"
check "non secret arguments still printed" "gm_flatgrass" \
    "$(printf '%s' "${printed}" | grep -o gm_flatgrass)"
check "secret flag itself still visible" "+rcon_password" \
    "$(printf '%s' "${printed}" | grep -o '+rcon_password')"


# --- retry: early transient failure --------------------------------------
# The helper is opt-in and narrow on purpose; each case below is one of the
# three ways it must refuse to retry.
RETRY_LOG="$(mktemp)"
fake_server() { # <attempts_before_success> <message>
    local n; n=$(cat "${RETRY_LOG}" 2>/dev/null || echo 0)
    n=$((n + 1)); printf '%s' "${n}" > "${RETRY_LOG}"
    printf '%s\n' "$2"
    [ "${n}" -gt "$1" ] && return 0
    return 1
}
attempts() { cat "${RETRY_LOG}"; }

export START_RETRY_PATTERN='Unable to initialize the game'
export START_RETRY_GRACE=180
export START_RETRY_DELAY=0

printf '0' > "${RETRY_LOG}"; START_RETRIES=0 \
    pterohost_run_with_retry fake_server 1 'Unable to initialize the game' >/dev/null 2>&1
check "disabled by default: single attempt" "1" "$(attempts)"

printf '0' > "${RETRY_LOG}"; START_RETRIES=3 \
    pterohost_run_with_retry fake_server 2 'Unable to initialize the game' >/dev/null 2>&1
check "transient error retried until success" "3" "$(attempts)"

printf '0' > "${RETRY_LOG}"; START_RETRIES=3 \
    pterohost_run_with_retry fake_server 9 'Unable to initialize the game' >/dev/null 2>&1
check "retries are capped" "4" "$(attempts)"

printf '0' > "${RETRY_LOG}"; START_RETRIES=3 \
    pterohost_run_with_retry fake_server 9 'config.json is malformed' >/dev/null 2>&1
check "unmatched error is not retried" "1" "$(attempts)"

printf '0' > "${RETRY_LOG}"; START_RETRIES=3 START_RETRY_GRACE=0 \
    pterohost_run_with_retry fake_server 9 'Unable to initialize the game' >/dev/null 2>&1
check "late exit is a real crash, not retried" "1" "$(attempts)"

printf '0' > "${RETRY_LOG}"; START_RETRIES=3 \
    pterohost_run_with_retry fake_server 0 'Unable to initialize the game' >/dev/null 2>&1
check "clean exit is never retried" "1" "$(attempts)"

RETRY_OUT="$(printf '0' > "${RETRY_LOG}"; START_RETRIES=1 \
    pterohost_run_with_retry fake_server 1 'Unable to initialize the game' 2>&1 | grep -c 'Unable to initialize')"
check "console keeps streaming both attempts" "2" "${RETRY_OUT}"

rm -f "${RETRY_LOG}"
unset START_RETRY_PATTERN START_RETRY_GRACE START_RETRY_DELAY

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
