#!/bin/bash
# Contract tests for shared/kvconf.sh
set -u

. "$(dirname "$0")/kvconf.sh"

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

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

FILE="${WORK}/servertest.ini"

fixture() {
    cat > "${FILE}" <<'INI'
# The port players connect to
DefaultPort=16261

PublicName=
PublicDescription=
RCONPassword=
Mods=
INI
}

# --- kv_set rewrites in place and leaves everything else alone -------------
fixture
before_lines="$(wc -l < "${FILE}")"
kv_set "${FILE}" DefaultPort 16083
check "existing key is rewritten" "16083" "$(kv_get "${FILE}" DefaultPort)"
check "rewrite adds no lines" "${before_lines}" "$(wc -l < "${FILE}")"
check "the comment above it survives" "1" \
    "$(grep -c '^# The port players connect to$' "${FILE}")"

fixture
kv_set "${FILE}" MaxPlayers 32
check "absent key is appended" "32" "$(kv_get "${FILE}" MaxPlayers)"

printf 'DefaultPort=16261' > "${FILE}"
kv_set "${FILE}" MaxPlayers 32
check "append to a file with no trailing newline keeps both keys" "16261|32" \
    "$(kv_get "${FILE}" DefaultPort)|$(kv_get "${FILE}" MaxPlayers)"

# --- the characters customers actually type -------------------------------
# Every one of these was rejected outright by the egg's alpha_num rule before
# PublicName became a variable of its own; none of them may corrupt the file.
roundtrip() { # <label> <value>
    fixture
    kv_set "${FILE}" PublicName "$2"
    check "roundtrip: $1" "$2" "$(kv_get "${FILE}" PublicName)"
    check "roundtrip: $1 leaves neighbours intact" "1" \
        "$(grep -c '^DefaultPort=16261$' "${FILE}")"
}

roundtrip "brackets, spaces and a plus" '[RU] MEATBALLS [PVE] [VANILLA+] 24/7'
roundtrip "Cyrillic"                    'Сервер Ру [ПВЕ] 24/7'
roundtrip "ampersand"                   'A&B servers'
roundtrip "backslashes"                 'path\to\glory'
roundtrip "pipe"                        'pipe|name'
roundtrip "double quote"                'quote"name'
roundtrip "equals sign in the value"    'name=with=equals'
roundtrip "shell metacharacters"        'Server (1) *stars* $money `tick`'
roundtrip "emoji"                       'ночной 🧟 сервер'

# --- kv_set_owned ---------------------------------------------------------
fixture
kv_set_owned "${FILE}" PublicName '[RU] MEATBALLS [PVE] [VANILLA+] 24/7' 'MEATBALLS'
check "panel value wins over the seed" "[RU] MEATBALLS [PVE] [VANILLA+] 24/7" \
    "$(kv_get "${FILE}" PublicName)"

fixture
kv_set_owned "${FILE}" PublicName '' 'MEATBALLS'
check "empty panel value seeds an empty key" "MEATBALLS" "$(kv_get "${FILE}" PublicName)"

fixture
kv_set "${FILE}" PublicName 'set in game'
kv_set_owned "${FILE}" PublicName '' 'MEATBALLS'
check "empty panel value never overwrites what is already there" "set in game" \
    "$(kv_get "${FILE}" PublicName)"

fixture
kv_set_owned "${FILE}" PublicDescription ''
check "empty panel value with no seed leaves the key empty" "" \
    "$(kv_get "${FILE}" PublicDescription)"

fixture
kv_set_owned "${FILE}" PublicName "$(printf 'two\nlines')" 'seed'
check "a pasted newline cannot split the value across lines" "twolines" \
    "$(kv_get "${FILE}" PublicName)"
check "a pasted newline adds no stray key" "0" "$(grep -c '^lines' "${FILE}")"

fixture
kv_set_owned "${FILE}" PublicName "$(printf 'crlf\r')" 'seed'
check "a stray CR is stripped" "crlf" "$(kv_get "${FILE}" PublicName)"

kv_set_owned "${WORK}/missing.ini" PublicName 'x' 'y'
check "missing file reports failure" "1" "$?"

# --- kv_backup_once -------------------------------------------------------
fixture
kv_backup_once "${FILE}" ports
kv_set "${FILE}" PublicName 'changed'
kv_backup_once "${FILE}" ports
check "the backup is taken from before the first change" "" \
    "$(kv_get "${FILE}.pterohost-orig" PublicName)"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
