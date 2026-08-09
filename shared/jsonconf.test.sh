#!/bin/bash
# Contract tests for shared/jsonconf.sh
set -u

. "$(dirname "$0")/jsonconf.sh"

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

FILE="${WORK}/Network.eco"

fixture() {
    cat > "${FILE}" <<'JSON'
{
  "PublicServer": true,
  "Password": "",
  "Name": "Steam:76561198875726167's World",
  "GameServerPort": 3000,
  "WebServerPort": 3001,
  "DefaultSlots": -1,
  "ReservedSlots": 5,
  "SpawnLocation": {
    "x": 382,
    "Name": "nested"
  },
  "UPnPEnabled": true
}
JSON
}

line() { # <key>
    grep -m1 -E "^[[:space:]]*\"$1\"[[:space:]]*:" "${FILE}"
}

# --- scalars keep the shape of the line they replace ----------------------
fixture
json_set "${FILE}" GameServerPort 22729
check "integer written bare, indentation and comma kept" \
    '  "GameServerPort": 22729,' "$(line GameServerPort)"

json_set "${FILE}" PublicServer false
check "boolean written bare" '  "PublicServer": false,' "$(line PublicServer)"

json_set "${FILE}" DefaultSlots -1
check "negative integer stays bare" '  "DefaultSlots": -1,' "$(line DefaultSlots)"

json_set "${FILE}" Name "$(json_string 'Мир Кости')"
check "string quoted" '  "Name": "Мир Кости",' "$(line Name)"

json_set "${FILE}" UPnPEnabled false
check "last key keeps its missing comma" '  "UPnPEnabled": false' "$(line UPnPEnabled)"

# --- values that break a naive sed ----------------------------------------
fixture
json_set "${FILE}" Name "$(json_string 'A & B | C \ D')"
check "sed metacharacters survive verbatim" \
    '  "Name": "A & B | C \\ D",' "$(line Name)"

fixture
json_set "${FILE}" Password "$(json_string 'say "hi"')"
check "double quotes escaped" '  "Password": "say \"hi\"",' "$(line Password)"

fixture
json_set "${FILE}" Name "$(json_string '3000')"
check "digits-only name stays a string" '  "Name": "3000",' "$(line Name)"

fixture
json_set "${FILE}" Password "$(json_string '')"
check "empty string clears the key" '  "Password": "",' "$(line Password)"

# --- what must not be touched ---------------------------------------------
fixture
json_set "${FILE}" SpawnLocation 5
check "object value left alone" '  "SpawnLocation": {' "$(line SpawnLocation)"

fixture
json_set "${FILE}" MaxConnections 4
check "absent key not appended" "" "$(line MaxConnections)"

fixture
json_set "${FILE}" Name "$(json_string 'outer')"
check "nested key of the same name untouched" \
    '    "Name": "nested"' "$(grep -m1 -E '^    "Name"' "${FILE}")"

# --- line endings ---------------------------------------------------------
fixture
sed -i 's/$/\r/' "${FILE}"
json_set "${FILE}" GameServerPort 22729
check "CRLF file keeps CRLF on the rewritten line" "1" \
    "$(grep -c $'": 22729,\r$' "${FILE}")"
check "CRLF file gets no LF-only lines" "0" \
    "$(grep -cv $'\r$' "${FILE}")"

fixture
before="$(cat "${FILE}")"
json_set "${FILE}" GameServerPort 22729
json_set "${FILE}" GameServerPort 3000
check "second pass changes nothing" "${before}" "$(cat "${FILE}")"

json_set "${WORK}/missing.eco" Name '"x"'
check "missing file reports failure" "1" "$?"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
