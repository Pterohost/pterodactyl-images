#!/bin/bash
# Contract tests for shared/cfgconf.sh
set -u

. "$(dirname "$0")/cfgconf.sh"

PASS=0
FAIL=0
check() {
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"
    else FAIL=$((FAIL + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
FILE="${WORK}/server.cfg"

# The shape Arma 3 and DayZ ship, including the commented-out hostname that
# five of the six live Arma servers still have.
fixture() {
    cat > "${FILE}" <<'CFG'
// Hostname for server.
// hostname = "My Arma 3 Server";
password = "";
passwordAdmin = "secret";
maxPlayers = 60;
motd[] = {"line one","line two"};
CFG
}

# --- cfg_set is surgical ---------------------------------------------------
fixture
before="$(wc -l < "${FILE}")"
cfg_set "${FILE}" maxPlayers 32
check "a number is rewritten in place" "32" "$(cfg_get "${FILE}" maxPlayers)"
check "no lines appear or vanish" "${before}" "$(wc -l < "${FILE}")"
check "the motd array is untouched" "1" \
    "$(grep -c '^motd\[\] = {"line one","line two"};$' "${FILE}")"

fixture
cfg_set "${FILE}" steamQueryPort 27016
check "an absent key is appended" "27016" "$(cfg_get "${FILE}" steamQueryPort)"

# --- cfg_set_owned, the three-way contract --------------------------------
fixture
cfg_set_owned "${FILE}" hostname "[RU] MEATBALLS [PVE] [VANILLA+] 24/7"
check "a panel value wins and is written quoted" '"[RU] MEATBALLS [PVE] [VANILLA+] 24/7"' \
    "$(cfg_get "${FILE}" hostname)"
check "and it replaces the commented-out line rather than duplicating it" "1" \
    "$(grep -c '^hostname = ' "${FILE}")"
check "the // Hostname for server. comment is left alone" "1" \
    "$(grep -c '^// Hostname for server\.$' "${FILE}")"

# an owner who typed a name into the file keeps it when the panel field is blank
fixture
cfg_set "${FILE}" hostname '"BD Halo server"'
cfg_set_owned "${FILE}" hostname ""
check "an empty panel value leaves the owner's hostname alone" '"BD Halo server"' \
    "$(cfg_get "${FILE}" hostname)"

# a server with no hostname at all is seeded, once
fixture
cfg_set_owned "${FILE}" hostname "" "Pterohost Arma 3"
check "an absent key is seeded" '"Pterohost Arma 3"' "$(cfg_get "${FILE}" hostname)"
cfg_set_owned "${FILE}" hostname "" "something else"
check "and never seeded twice" '"Pterohost Arma 3"' "$(cfg_get "${FILE}" hostname)"

# an empty string in the file counts as absent - Arma ships password = "";
fixture
cfg_set_owned "${FILE}" password "" "letmein"
check "a key holding an empty string is seeded" '"letmein"' "$(cfg_get "${FILE}" password)"

# --- the characters that would break the file -----------------------------
fixture
cfg_set_owned "${FILE}" hostname 'say "hello" now'
check "a double quote cannot close the string early" '"say hello now"' \
    "$(cfg_get "${FILE}" hostname)"
check "the file still parses as one statement per line" "1" \
    "$(grep -c '^hostname = ' "${FILE}")"

fixture
cfg_set_owned "${FILE}" hostname "$(printf 'first\nsecond')"
check "a pasted newline cannot split the statement" '"firstsecond"' \
    "$(cfg_get "${FILE}" hostname)"

fixture
cfg_set_owned "${FILE}" hostname 'Rock & Roll | Server'
check "sed metacharacters survive intact" '"Rock & Roll | Server"' \
    "$(cfg_get "${FILE}" hostname)"

fixture
cfg_set_owned "${FILE}" hostname 'Сервер «Тест»'
check "cyrillic survives intact" '"Сервер «Тест»"' "$(cfg_get "${FILE}" hostname)"

# --- a missing file is an error, not a crash ------------------------------
cfg_set_owned "${WORK}/nope.cfg" hostname x
check "a missing file returns non-zero" "1" "$?"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
