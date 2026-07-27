#!/bin/bash
# Contract tests for shared/unrealini.awk and shared/unrealini.sh.
#
# The corrupted fixtures are copies of what two live servers actually had on
# disk after the third-party config parser had been running for weeks.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
AWK_PROG="${HERE}/unrealini.awk"

PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    fi
}

# run <ini-content> <map-lines> -> rewritten file on stdout
run() {
    printf '%s\n' "$1" > "${WORK}/in.ini"
    printf '%s' "$2" > "${WORK}/map.tsv"
    awk -v mapfile="${WORK}/map.tsv" -f "${AWK_PROG}" "${WORK}/in.ini"
}

quotes() { printf '%s' "$1" | tr -cd '"' | wc -c | tr -d ' '; }

HEADER='[/Script/Pal.PalGameWorldSettings]'
CLEAN='OptionSettings=(Difficulty=None,ServerName="A server",ServerDescription="",AdminPassword="secret",RCONEnabled=False,RCONPort=25575,CrossplayPlatforms=(Steam,Xbox,PS5,Mac),ServerPlayerMaxNum=32)'

# --- overrides -----------------------------------------------------------
out="$(run "${HEADER}
${CLEAN}" 'RCONEnabled	True
RCONPort	16058
')"
check "existing keys rewritten in place" \
    'OptionSettings=(Difficulty=None,ServerName="A server",ServerDescription="",AdminPassword="secret",RCONEnabled=True,RCONPort=16058,CrossplayPlatforms=(Steam,Xbox,PS5,Mac),ServerPlayerMaxNum=32)' \
    "$(printf '%s' "${out}" | grep '^OptionSettings=')"

out="$(run "${HEADER}
${CLEAN}" 'RESTAPIPort	8212
')"
check "unknown key appended at the end" \
    "RESTAPIPort=8212)" \
    "$(printf '%s' "${out}" | grep -o 'RESTAPIPort=8212)')"

check "header line passed through" "${HEADER}" "$(printf '%s' "${out}" | head -1)"

# --- values containing a comma ------------------------------------------
out="$(run "${HEADER}
${CLEAN}" 'ServerDescription	"Русский сервер, для мужчин"
')"
check "quoted value keeps its comma" \
    'ServerDescription="Русский сервер, для мужчин"' \
    "$(printf '%s' "${out}" | grep -o 'ServerDescription="[^"]*"')"
check "comma in a value does not add keys" \
    "$(printf '%s' "${CLEAN}" | grep -o '[(,][A-Za-z_][A-Za-z0-9_]*=' | wc -l | tr -d ' ')" \
    "$(printf '%s' "${out}" | grep '^OptionSettings=' | grep -o '[(,][A-Za-z_][A-Za-z0-9_]*=' | wc -l | tr -d ' ')"

# --- nested tuple --------------------------------------------------------
out="$(run "${HEADER}
${CLEAN}" 'Difficulty	Hard
')"
check "nested tuple survives untouched" \
    'CrossplayPlatforms=(Steam,Xbox,PS5,Mac)' \
    "$(printf '%s' "${out}" | grep -o 'CrossplayPlatforms=([^)]*)')"

out="$(run "${HEADER}
${CLEAN}" 'CrossplayPlatforms	(Steam)
')"
check "nested tuple can be replaced" \
    'CrossplayPlatforms=(Steam)' \
    "$(printf '%s' "${out}" | grep -o 'CrossplayPlatforms=([^)]*)')"

# --- repair: server 3742 (one duplicated tail, odd quote count) ----------
BROKEN_3742='OptionSettings=(Difficulty=None,ServerName="Sunypret Online",ServerDescription="Русский сервер, для мужчин и красав", для мужчин и красав",AdminPassword="18706011",ServerPassword="3243",RCONEnabled=True,RCONPort=16058)'
check "fixture 3742 really is unbalanced" "odd" \
    "$([ $(( $(quotes "${BROKEN_3742}") % 2 )) -eq 1 ] && echo odd || echo even)"

out="$(run "${HEADER}
${BROKEN_3742}" 'AdminPassword	"18706011"
')"
line="$(printf '%s' "${out}" | grep '^OptionSettings=')"
check "3742 repaired to balanced quotes" "even" \
    "$([ $(( $(quotes "${line}") % 2 )) -eq 0 ] && echo even || echo odd)"
check "3742 keeps the real description" \
    'ServerDescription="Русский сервер, для мужчин и красав"' \
    "$(printf '%s' "${line}" | grep -o 'ServerDescription="[^"]*"')"
check "3742 duplicated tail dropped" "1" \
    "$(printf '%s' "${line}" | grep -o 'для мужчин и красав' | wc -l | tr -d ' ')"
check "3742 admin password intact" 'AdminPassword="18706011"' \
    "$(printf '%s' "${line}" | grep -o 'AdminPassword="[^"]*"')"
check "3742 rcon port intact" 'RCONPort=16058' \
    "$(printf '%s' "${line}" | grep -o 'RCONPort=[0-9]*')"

# --- repair: server 3477 (eight duplicated tails) ------------------------
BROKEN_3477='OptionSettings=(Difficulty=None,ServerDescription="Кринжовое, лайтовое", лайтовое", лайтовое", лайтовое", лайтовое", лайтовое", лайтовое", лайтовое",AdminPassword="2192c873",RCONPort=16011)'
out="$(run "${HEADER}
${BROKEN_3477}" '')"
line="$(printf '%s' "${out}" | grep '^OptionSettings=')"
check "3477 all eight tails dropped" \
    'ServerDescription="Кринжовое, лайтовое"' \
    "$(printf '%s' "${line}" | grep -o 'ServerDescription="[^"]*"')"
check "3477 keys after the corruption survive" 'AdminPassword="2192c873"' \
    "$(printf '%s' "${line}" | grep -o 'AdminPassword="[^"]*"')"

# --- repair: a line cut mid-value with no closing parenthesis ------------
# Server 3477 on node05 was in exactly this state: the tuple never closed, so
# Unreal could not read the struct at all and every setting fell back to the
# default while the panel kept showing the customer's values.
TRUNCATED='OptionSettings=(Difficulty=None,ServerDescription="Кринжовое, лайтовое", лайтовое",AdminPassword="2192c873",RCONPort=16011,BanListURL="https:'
out="$(run "${HEADER}
${TRUNCATED}" '')"
line="$(printf '%s' "${out}" | grep '^OptionSettings=')"
check "truncated tuple gets closed" "1" \
    "$(printf '%s' "${line}" | grep -o ')' | wc -l | tr -d ' ')"
check "truncated tuple keeps the good keys" 'RCONPort=16011' \
    "$(printf '%s' "${line}" | grep -o 'RCONPort=[0-9]*')"
check "half written value is dropped, not guessed" "" \
    "$(printf '%s' "${line}" | grep -o 'BanListURL')"
check "truncated tuple ends up balanced" "even" \
    "$([ $(( $(quotes "${line}") % 2 )) -eq 0 ] && echo even || echo odd)"

# --- idempotency ---------------------------------------------------------
printf '%s\n%s\n' "${HEADER}" "${BROKEN_3742}" > "${WORK}/i1.ini"
printf 'RCONPort\t16058\n' > "${WORK}/m.tsv"
awk -v mapfile="${WORK}/m.tsv" -f "${AWK_PROG}" "${WORK}/i1.ini" > "${WORK}/i2.ini"
awk -v mapfile="${WORK}/m.tsv" -f "${AWK_PROG}" "${WORK}/i2.ini" > "${WORK}/i3.ini"
check "second pass changes nothing" "same" \
    "$(cmp -s "${WORK}/i2.ini" "${WORK}/i3.ini" && echo same || echo differs)"

# --- a file with no OptionSettings line ----------------------------------
printf '%s\n' "${HEADER}" > "${WORK}/empty.ini"
awk -v mapfile="${WORK}/m.tsv" -f "${AWK_PROG}" "${WORK}/empty.ini" > /dev/null 2>&1
check "missing OptionSettings line reports failure" "3" "$?"

# --- shell surface: quoting and sanitising -------------------------------
# shellcheck source=/dev/null
. "${HERE}/unrealini.sh"
printf '%s\n%s\n' "${HEADER}" "${CLEAN}" > "${WORK}/sh.ini"
mkdir -p "${WORK}/lib" && cp "${AWK_PROG}" "${WORK}/lib/unrealini.awk"
unreal_apply() {
    local file="$1" tmp
    tmp="$(mktemp)"
    awk -v mapfile="${UNREAL_MAP}" -f "${WORK}/lib/unrealini.awk" "${file}" > "${tmp}" || { rm -f "${tmp}"; return 2; }
    cmp -s "${tmp}" "${file}" && { rm -f "${tmp}"; return 1; }
    cat "${tmp}" > "${file}"; rm -f "${tmp}"; return 0
}

unreal_begin
unreal_str ServerName 'He said "hi", loudly'
unreal_set RCONPort 16000
unreal_apply "${WORK}/sh.ini"
check "unreal_str strips quotes the format cannot escape" \
    'ServerName="He said hi, loudly"' \
    "$(grep -o 'ServerName="[^"]*"' "${WORK}/sh.ini")"
check "unreal_set writes a bare token" "RCONPort=16000" \
    "$(grep -o 'RCONPort=[0-9]*' "${WORK}/sh.ini")"
check "sanitised file stays balanced" "even" \
    "$([ $(( $(quotes "$(grep '^OptionSettings=' "${WORK}/sh.ini")") % 2 )) -eq 0 ] && echo even || echo odd)"

unreal_begin
unreal_set RCONPort 16000
unreal_apply "${WORK}/sh.ini"
check "apply reports 1 when nothing changed" "1" "$?"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
