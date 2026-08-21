#!/bin/bash
# Contract tests for shared/datconf.sh
set -u

. "$(dirname "$0")/datconf.sh"

PASS=0
FAIL=0
check() {
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"
    else FAIL=$((FAIL + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
FILE="${WORK}/Commands.dat"

# Server 3543's real file, node07.
fixture() {
    cat > "${FILE}" <<'DAT'
Name Sky Way Unturned | Full Vanilla
Port 16684
MaxPlayers 100
Map Russia Tespy
Mode Normal
Perspective vehicle
Cheats Off
Hide_Admins
DAT
}

# Server 3073's real file, node09 - lowercase commands, Cyrillic, pipes.
fixture_lower() {
    cat > "${FILE}" <<'DAT'
name Unturned KAMA ВЫЖИВАНИЕ №1 [KITS|TPA|HOME|AIRDROP]
maxplayers 24
perspective both
mode easy
Cheats Enabled
DAT
}

# --- reading ---------------------------------------------------------------
fixture
check "a value is read whole, spaces and pipes included" "Sky Way Unturned | Full Vanilla" \
    "$(dat_get "${FILE}" Name)"
check "a numeric value reads back" "16684" "$(dat_get "${FILE}" Port)"
check "an absent command reads empty" "" "$(dat_get "${FILE}" Welcome)"
check "a valueless command reads empty" "" "$(dat_get "${FILE}" Hide_Admins)"

fixture_lower
check "a lowercase command is found" "Unturned KAMA ВЫЖИВАНИЕ №1 [KITS|TPA|HOME|AIRDROP]" \
    "$(dat_get "${FILE}" Name)"

# --- writing is surgical ---------------------------------------------------
fixture
before="$(wc -l < "${FILE}")"
dat_set "${FILE}" Port 27015
check "an existing command is rewritten" "27015" "$(dat_get "${FILE}" Port)"
check "no lines appear or vanish" "${before}" "$(wc -l < "${FILE}")"
check "the map is untouched" "Russia Tespy" "$(dat_get "${FILE}" Map)"
check "the valueless command survives" "1" "$(grep -c '^Hide_Admins$' "${FILE}")"

fixture
dat_set "${FILE}" Welcome "Добро пожаловать"
check "an absent command is appended" "Добро пожаловать" "$(dat_get "${FILE}" Welcome)"

# --- case-insensitivity is the whole point ---------------------------------
# Without it the file ends up with two contradictory names and the game picks
# the last one, which is not the one the panel just wrote.
fixture_lower
dat_set "${FILE}" Name "Panel Chosen Name"
check "a lowercase line is rewritten, not duplicated" "1" \
    "$(grep -ciE '^[[:space:]]*name[[:space:]]' "${FILE}")"
check "and holds the new value" "Panel Chosen Name" "$(dat_get "${FILE}" Name)"
check "the other lowercase commands are left alone" "24|both" \
    "$(dat_get "${FILE}" maxplayers)|$(dat_get "${FILE}" perspective)"

# --- the characters Unturned server names are actually full of -------------
roundtrip() { # <label> <value>
    fixture
    dat_set "${FILE}" Name "$2"
    check "$1" "$2" "$(dat_get "${FILE}" Name)"
    check "$1 - still one Name line" "1" "$(grep -ciE '^[[:space:]]*name[[:space:]]' "${FILE}")"
}
roundtrip "pipes survive"       '[RU] Titan | 4x loot | PVP | /home | /tpa | /kits'
roundtrip "ampersand survives"  'Rock & Roll'
roundtrip "backslash survives"  'C:\Server\Name'
roundtrip "cyrillic survives"   'Unturned KAMA ВЫЖИВАНИЕ №1 [KITS|TPA|HOME|AIRDROP]'
roundtrip "hash and colon"      'Jaguar #1 | RU | X3'

# a pasted newline must not become a second command
fixture
dat_set "${FILE}" Name "$(printf 'first\nsecond')"
check "a pasted newline cannot become a command" "firstsecond" "$(dat_get "${FILE}" Name)"
check "and the line count is unchanged" "8" "$(wc -l < "${FILE}")"

# a windows CR must not leak into the value
printf 'Name Windows Edited\r\nPort 16684\r\n' > "${FILE}"
check "a CR is stripped on read" "Windows Edited" "$(dat_get "${FILE}" Name)"

# --- three-way ownership ---------------------------------------------------
fixture
dat_set_owned "${FILE}" Name ""
check "an empty panel value leaves the owner's name alone" "Sky Way Unturned | Full Vanilla" \
    "$(dat_get "${FILE}" Name)"

dat_set_owned "${FILE}" Name "Panel Wins"
check "a panel value wins" "Panel Wins" "$(dat_get "${FILE}" Name)"

fixture
dat_set_owned "${FILE}" Welcome "" "seeded"
check "an absent command is seeded" "seeded" "$(dat_get "${FILE}" Welcome)"
dat_set_owned "${FILE}" Welcome "" "different"
check "and never seeded twice" "seeded" "$(dat_get "${FILE}" Welcome)"

# --- an empty file is a normal state, not an error ------------------------
: > "${FILE}"
dat_set "${FILE}" Port 18009
check "a 0-byte file gains its first command" "18009" "$(dat_get "${FILE}" Port)"
dat_set "${FILE}" Name "Jaguar #1"
check "and a second one on its own line" "Jaguar #1|18009" \
    "$(dat_get "${FILE}" Name)|$(dat_get "${FILE}" Port)"
check "with no blank line between them" "2" "$(grep -c . "${FILE}")"

# a file with no trailing newline must not have its last line joined
printf 'Cheats Off' > "${FILE}"
dat_set "${FILE}" Port 18009
check "a missing trailing newline is repaired" "Off|18009" \
    "$(dat_get "${FILE}" Cheats)|$(dat_get "${FILE}" Port)"

# --- backup ---------------------------------------------------------------
fixture
dat_backup_once "${FILE}"
dat_set "${FILE}" Name "changed"
dat_backup_once "${FILE}"
check "the pristine copy is taken once and kept" "Sky Way Unturned | Full Vanilla" \
    "$(dat_get "${FILE}.pterohost-orig" Name)"

# --- a missing file is an error, not a crash ------------------------------
dat_set "${WORK}/nope.dat" Name x
check "a missing file returns non-zero" "1" "$?"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
