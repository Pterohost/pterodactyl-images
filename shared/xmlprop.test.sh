#!/bin/bash
# Contract tests for shared/xmlprop.sh
set -u

. "$(dirname "$0")/xmlprop.sh"

PASS=0
FAIL=0
check() {
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"
    else FAIL=$((FAIL + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
FILE="${WORK}/serverconfig.xml"

# Copied from a live server, tabs and all.
fixture() {
    printf '%s\n' \
'<?xml version="1.0"?>' \
'<ServerSettings>' \
'	<property name="ServerName"						value="My Game Host"/>		<!-- Whatever you want the name of the server to be. -->' \
'	<property name="ServerDescription"				value="A 7 Days to Die server"/>	<!-- Whatever you want the server description to be, will be shown in the server browser. -->' \
'	<property name="ServerPort"						value="26900"/>				<!-- Port you want the server to listen on. -->' \
'	<property name="GameName"						value="My Game"/>			<!-- Whatever you want the game name to be. -->' \
'</ServerSettings>' > "${FILE}"
}

# --- the rewrite touches the value and nothing else ------------------------
fixture
before="$(wc -l < "${FILE}")"
xmlprop_set "${FILE}" ServerName 'REBIRTH TSK'
check "the value is replaced" "REBIRTH TSK" "$(xmlprop_get "${FILE}" ServerName)"
check "no lines are added or lost" "${before}" "$(wc -l < "${FILE}")"
check "the tab alignment survives" "1" \
    "$(grep -c '^	<property name="ServerName"						value="REBIRTH TSK"/>' "${FILE}")"
check "the explanatory comment survives" "1" \
    "$(grep -c 'Whatever you want the name of the server to be' "${FILE}")"
check "the neighbouring properties are untouched" "26900|My Game" \
    "$(xmlprop_get "${FILE}" ServerPort)|$(xmlprop_get "${FILE}" GameName)"
check "a prefix property is not confused for another" "A 7 Days to Die server" \
    "$(xmlprop_get "${FILE}" ServerDescription)"

# --- XML escaping, which a malformed file punishes with a full reset -------
roundtrip() { # <label> <value> <expected in file>
    fixture
    xmlprop_set "${FILE}" ServerName "$2"
    check "$1" "$3" "$(xmlprop_get "${FILE}" ServerName)"
    check "$1 - the file is still one property per line" "4" \
        "$(grep -c '<property name=' "${FILE}")"
}
# An apostrophe needs no escaping inside a double-quoted attribute, and escaping
# it anyway would show up literally in the server browser.
roundtrip "ampersand is escaped"        "Bill & Ted's"          "Bill &amp; Ted's"
roundtrip "angle brackets are escaped"  "<RU> server"           "&lt;RU&gt; server"
roundtrip "a double quote is escaped"   'say "hello"'           'say &quot;hello&quot;'
roundtrip "cyrillic passes through"     "RUST:Эволюция"         "RUST:Эволюция"
roundtrip "brackets and spaces"         "[RU] MEATBALLS [PVE]"  "[RU] MEATBALLS [PVE]"

# --- an absent property is added where the game will read it --------------
fixture
xmlprop_set "${FILE}" ServerWebsiteURL 'https://pterohost.com'
check "an absent property is added" "https://pterohost.com" \
    "$(xmlprop_get "${FILE}" ServerWebsiteURL)"
check "and lands inside ServerSettings" "1" \
    "$(awk '/<property name="ServerWebsiteURL"/{p=NR} /<\/ServerSettings>/{c=NR} END{print (p>0 && p<c) ? 1 : 0}' "${FILE}")"

# --- three-way ownership --------------------------------------------------
fixture
xmlprop_set "${FILE}" ServerName 'set by hand over sftp'
xmlprop_set_owned "${FILE}" ServerName ''
check "an empty panel value leaves the owner's name alone" "set by hand over sftp" \
    "$(xmlprop_get "${FILE}" ServerName)"

xmlprop_set_owned "${FILE}" ServerName 'set in the panel'
check "a panel value wins" "set in the panel" "$(xmlprop_get "${FILE}" ServerName)"

fixture
xmlprop_set "${FILE}" ServerName ''
xmlprop_set_owned "${FILE}" ServerName '' 'seeded default'
check "an empty property is seeded" "seeded default" "$(xmlprop_get "${FILE}" ServerName)"

fixture
xmlprop_set_owned "${FILE}" ServerName '' 'seeded default'
check "a property that already has a value is never seeded over" "My Game Host" \
    "$(xmlprop_get "${FILE}" ServerName)"

# --- a newline pasted into the panel must not split the element -----------
fixture
xmlprop_set_owned "${FILE}" ServerDescription "$(printf 'line one\nline two')"
check "newlines are stripped, not written" "line oneline two" \
    "$(xmlprop_get "${FILE}" ServerDescription)"
check "the file is still well formed" "4" "$(grep -c '<property name=' "${FILE}")"

# --- a missing file is an error, not a crash -----------------------------
xmlprop_set "${WORK}/nope.xml" ServerName x
check "a missing file returns non-zero" "1" "$?"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
