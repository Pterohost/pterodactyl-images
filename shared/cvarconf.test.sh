#!/bin/bash
# Contract tests for shared/cvarconf.sh
set -u

. "$(dirname "$0")/cvarconf.sh"

PASS=0
FAIL=0
check() {
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$1"
    else FAIL=$((FAIL+1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
FILE="${WORK}/server.cfg"

fixture() {
    cat > "${FILE}" <<'CFG'
// Owner's own settings - none of this may move
sv_gravity 800
hostname "old name"
mp_friendlyfire 1
CFG
}

fixture
cvar_set "${FILE}" hostname 'Мой сервер [PVE] 24/7'
check "existing cvar is rewritten" 'Мой сервер [PVE] 24/7' "$(cvar_get "${FILE}" hostname)"
check "neighbouring cvars survive" "1" "$(grep -c '^sv_gravity 800$' "${FILE}")"
check "the comment survives" "1" "$(grep -c "^// Owner's own settings" "${FILE}")"
check "no line count drift" "4" "$(wc -l < "${FILE}")"

fixture
cvar_set "${FILE}" sv_maxplayers 8
check "absent cvar is appended" "8" "$(cvar_get "${FILE}" sv_maxplayers)"

fixture
cvar_set "${FILE}" hostname 'spaces need quotes'
check "value is written quoted" "1" "$(grep -c '^hostname "spaces need quotes"$' "${FILE}")"

# A commented-out cvar is the shipped default in most server.cfg templates;
# appending a second one would leave the engine reading whichever came last.
printf '// hostname "commented default"\nsv_gravity 800\n' > "${FILE}"
cvar_set "${FILE}" hostname 'live name'
check "a commented cvar is replaced, not duplicated" "1" "$(grep -c '^hostname ' "${FILE}")"
check "the replacement is the live value" "live name" "$(cvar_get "${FILE}" hostname)"

fixture
cvar_set "${FILE}" hostname 'A&B | C\D'
check "sed metacharacters survive" 'A&B | C\D' "$(cvar_get "${FILE}" hostname)"

fixture
cvar_set "${FILE}" hostname "$(printf 'two\nlines')"
check "a pasted newline cannot split the cvar" "twolines" "$(cvar_get "${FILE}" hostname)"

fixture
cvar_set "${FILE}" hostname 'quote"inside'
check "a double quote is dropped, not left unbalanced" "quoteinside" "$(cvar_get "${FILE}" hostname)"

# --- ownership ------------------------------------------------------------
fixture
cvar_set_owned "${FILE}" hostname 'from the panel' 'seed'
check "panel value wins" "from the panel" "$(cvar_get "${FILE}" hostname)"

fixture
cvar_set_owned "${FILE}" hostname '' 'seed'
check "empty panel value never overwrites what is there" "old name" "$(cvar_get "${FILE}" hostname)"

printf 'sv_gravity 800\n' > "${FILE}"
cvar_set_owned "${FILE}" hostname '' 'Pterohost Left 4 Dead 2'
check "absent cvar is seeded" "Pterohost Left 4 Dead 2" "$(cvar_get "${FILE}" hostname)"

printf 'sv_gravity 800\n' > "${FILE}"
cvar_set_owned "${FILE}" hostname '' ''
check "no panel value and no seed leaves the file alone" "1" "$(wc -l < "${FILE}")"

cvar_set_owned "${WORK}/missing.cfg" hostname 'x' 'y'
check "missing file reports failure" "1" "$?"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
