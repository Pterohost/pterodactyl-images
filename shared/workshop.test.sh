#!/bin/bash
# Contract tests for shared/workshop.sh
#
# Nothing here touches the network or SteamCMD: what is worth pinning down is the
# mod-list resolution, because that is the part the eggs feed and the part whose
# absence booted every modded DayZ server vanilla.
set -u

# workshop.sh expects steam-update.sh to have been sourced first.
pterohost_log() { printf '[pterohost] %s\n' "$*"; }

. "$(dirname "$0")/workshop.sh"

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

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# --- dedupe --------------------------------------------------------------
# Order is the contract, not an accident. -mod= is evaluated left to right, so
# re-ordering the list changes which mod wins - these three cases exist because
# `sort -u` here silently rewrote every owner's load order.
check "dedupe keeps first-seen order and drops duplicates" \
    "@b;@a;" "$(pterohost_mods_dedupe '@b;@a;@b;')"

check "dedupe on an empty list gives an empty list" \
    "" "$(pterohost_mods_dedupe '')"

check "dedupe drops empty entries and whitespace without reordering" \
    "@b;@a;" "$(pterohost_mods_dedupe ';@b; @a ;;')"

# The real shape this has to survive: a dependency-ordered Expansion stack whose
# alphabetical order is wrong in three separate places.
check "a dependency-ordered mod stack survives unchanged" \
    "@CF;@DayZ-Expansion-Licensed;@DayZ-Expansion-Core;@DayZ-Expansion-AI;@VPPAdminTools;" \
    "$(pterohost_mods_dedupe '@CF;@DayZ-Expansion-Licensed;@DayZ-Expansion-Core;@DayZ-Expansion-AI;@VPPAdminTools')"

check "mixed case does not reorder either" \
    "@zMod;@aMod;" "$(pterohost_mods_dedupe '@zMod;@aMod')"

# --- launcher file -------------------------------------------------------
cat > "${TMP}/modlist.html" <<'HTML'
<!DOCTYPE html>
<html><!-- Created by DayZ Launcher -->
<body><table>
<tr><td data-type="Link"><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036">CF</a></td></tr>
<tr><td data-type="Link"><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=2545327648">VPPAdminTools</a></td></tr>
<tr><td data-type="Link"><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036">CF again</a></td></tr>
</table></body></html>
HTML

check "launcher export yields deduped ids" \
    "@1559212036;@2545327648;" "$(pterohost_mods_from_launcher "${TMP}/modlist.html")"

# The launcher writes the rows in the order the player arranged them, so the
# export IS the load order - reading it and then sorting discards the only thing
# the file is good for. Descending ids so a sort would be visible.
cat > "${TMP}/ordered.html" <<'HTML'
<html><body><table>
<tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3000000000">last alphabetically, first in load order</a></td></tr>
<tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=2000000000">middle</a></td></tr>
<tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=1000000000">first alphabetically, last in load order</a></td></tr>
</table></body></html>
HTML

check "launcher export preserves the player's order" \
    "@3000000000;@2000000000;@1000000000;" "$(pterohost_mods_from_launcher "${TMP}/ordered.html")"

pterohost_mods_from_launcher "${TMP}/nope.html" >/dev/null 2>&1
check "missing launcher file reports failure" "1" "$?"

printf 'not a modlist\n' > "${TMP}/empty.html"
pterohost_mods_from_launcher "${TMP}/empty.html" >/dev/null 2>&1
check "launcher file with no ids reports failure" "1" "$?"

# --- client mod list -----------------------------------------------------
CLIENT_MODS="@pinned;" MODIFICATIONS="@ignored" MOD_FILE="${TMP}/modlist.html"
check "an explicit CLIENT_MODS wins" \
    "@pinned;" "$(pterohost_mods_client)"

unset CLIENT_MODS
MODIFICATIONS="@CF;@VPPAdminTools" MOD_FILE=""
check "MODIFICATIONS alone" \
    "@CF;@VPPAdminTools;" "$(pterohost_mods_client)"

MODIFICATIONS="" MOD_FILE="${TMP}/modlist.html"
check "launcher file alone" \
    "@1559212036;@2545327648;" "$(pterohost_mods_client)"

MODIFICATIONS="@1559212036;@Handmade" MOD_FILE="${TMP}/modlist.html"
check "both sources merge and dedupe, MODIFICATIONS first" \
    "@1559212036;@Handmade;@2545327648;" "$(pterohost_mods_client)"

# The regression that would silently poison the command line: warnings must not
# end up inside the captured mod list.
MODIFICATIONS="@CF" MOD_FILE="${TMP}/nope.html"
check "a missing launcher file leaves the list clean" \
    "@CF;" "$(pterohost_mods_client 2>/dev/null)"

MODIFICATIONS="" MOD_FILE=""
check "no mods configured gives an empty list" \
    "" "$(pterohost_mods_client)"

# --- lowercase -----------------------------------------------------------
mkdir -p "${TMP}/@Mod/Addons"
: > "${TMP}/@Mod/Addons/Thing.PBO"
pterohost_mods_lowercase "${TMP}/@Mod"
check "mod contents are lowercased" \
    "yes" "$([ -f "${TMP}/@Mod/addons/thing.pbo" ] && echo yes || echo no)"
check "the mod directory keeps its own name" \
    "yes" "$([ -d "${TMP}/@Mod" ] && echo yes || echo no)"

# --- meta.cpp publishedid ------------------------------------------------
# A publishedid of 0 is what an author's own meta.cpp carries when they never
# filled it in. The subscriber's launcher rewrites the file locally, so only a
# server ever sees the zero - and then advertises it, and BOTH launchers refuse
# to parse the whole mod list. Measured 2026-09-09 on a 48-mod DayZ server:
# DZSA answered "The mod 'FBB Admin Gear' has a Steam Workshop ID of '0'" and
# the official launcher showed an EMPTY required-mod list on a server that was
# up and answering A2S.
mkdir -p "${TMP}/@3792546258" "${TMP}/@1559212036" "${TMP}/@Handmade" "${TMP}/@3730899494"
printf 'protocol = 1;\npublishedid = 0;\nname = "FBB Admin Gear";\ntimestamp = 5250922604720454087;\n' \
    > "${TMP}/@3792546258/meta.cpp"
printf 'protocol = 1;\npublishedid = 1559212036;\nname = "CF";\ntimestamp = 42;\n' \
    > "${TMP}/@1559212036/meta.cpp"
printf 'protocol = 1;\npublishedid = 0;\nname = "Handmade";\n' \
    > "${TMP}/@Handmade/meta.cpp"

pterohost_mods_fix_meta "${TMP}/@3792546258" "${TMP}/@1559212036" "${TMP}/@Handmade" "${TMP}/@3730899494" >/dev/null

check "publishedid = 0 is replaced by the folder id" \
    "publishedid = 3792546258;" "$(grep publishedid "${TMP}/@3792546258/meta.cpp")"

check "the mod name is preserved" \
    'name = "FBB Admin Gear";' "$(grep name "${TMP}/@3792546258/meta.cpp")"

# The sync compares timestamp to decide whether a mod needs redownloading -
# rewriting the file must not cost that.
check "the timestamp is preserved" \
    "timestamp = 5250922604720454087;" "$(grep timestamp "${TMP}/@3792546258/meta.cpp")"

check "a correct publishedid is left alone" \
    "publishedid = 1559212036;" "$(grep publishedid "${TMP}/@1559212036/meta.cpp")"

# A hand-installed mod has no workshop id to claim, and inventing one would
# point every client at somebody else's item.
check "a non-numeric mod directory is not touched" \
    "publishedid = 0;" "$(grep publishedid "${TMP}/@Handmade/meta.cpp")"

check "a missing meta.cpp is created with the folder id" \
    "publishedid = 3730899494;" "$(grep publishedid "${TMP}/@3730899494/meta.cpp")"

check "a mod directory that does not exist is skipped without error" \
    "0" "$(pterohost_mods_fix_meta "${TMP}/@nope" >/dev/null 2>&1; echo $?)"

# --- update detection: Steam Web API first, changelog page as fallback ------
# The changelog page answers 429 after a handful of requests (2026-10-17,
# node03/node10), which froze every installed mod. The sync now asks
# GetPublishedFileDetails once for the whole list and only goes to the page for
# the ids the API did not describe. curl is stubbed: no network here.
API_LOG="${TMP}/api.log"
API_REPLY=""
curl() {
    printf '%s\n' "$*" >> "${API_LOG}"
    [ -n "${API_REPLY}" ] || return 22
    printf '%s' "${API_REPLY}"
}

: > "${API_LOG}"
API_REPLY='{"response":{"result":1,"resultcount":3,"publishedfiledetails":[
 {"publishedfileid":"111","result":1,"time_updated":1791897978},
 {"publishedfileid":"222","result":9},
 {"publishedfileid":"333","result":1,"time_updated":1700000000}]}}'
check "the API reply is turned into id/epoch pairs, unknown items left out" \
    "111 1791897978|333 1700000000" "$(pterohost_workshop_remote_mtimes 111 222 333 | paste -sd'|')"
check "all ids go out in one request" \
    "1" "$(grep -c 'itemcount=3' "${API_LOG}")"
check "each id is posted as publishedfileids[n]" \
    "yes" "$(grep -q 'publishedfileids\[0\]=111 -d publishedfileids\[1\]=222 -d publishedfileids\[2\]=333' "${API_LOG}" && echo yes || echo no)"

: > "${API_LOG}"
API_REPLY='{"response":{"result":1,"publishedfiledetails":[]}}'
check "more than 100 ids are split into requests of 100" \
    "itemcount=100|itemcount=100|itemcount=5" \
    "$(pterohost_workshop_remote_mtimes $(seq 1000 1204) >/dev/null; grep -oE 'itemcount=[0-9]+' "${API_LOG}" | paste -sd'|')"

API_REPLY=""
check "an unreachable API yields nothing and still succeeds" \
    "0:" "$(out="$(pterohost_workshop_remote_mtimes 111)"; echo "$?:${out}")"

API_REPLY='<html>429 Too Many Requests</html>'
check "a non-JSON reply yields nothing" \
    "" "$(pterohost_workshop_remote_mtimes 111)"
unset -f curl

# The sync itself, lifted with /home/container pointed at a sandbox. Downloads
# and the page fallback are recorded instead of performed.
SYNC_HOME="${TMP}/home"
mkdir -p "${SYNC_HOME}/@111" "${SYNC_HOME}/@333" "${SYNC_HOME}/@444" "${SYNC_HOME}/@Handmade"
touch -d '@1750000000' "${SYNC_HOME}/@111" "${SYNC_HOME}/@333" "${SYNC_HOME}/@444"
LIFTED="${TMP}/sync.sh"
sed -n '/^pterohost_workshop_sync() {/,/^}$/p' "$(dirname "$0")/workshop.sh" \
    | sed "s#/home/container#${SYNC_HOME}#g" > "${LIFTED}"
. "${LIFTED}"
SYNC_LOG="${TMP}/sync.log"
pterohost_steam_seed() { :; }
pterohost_workshop_download() { printf 'download %s\n' "$2" >> "${SYNC_LOG}"; }
pterohost_workshop_remote_mtime() { printf 'page %s\n' "$1" >> "${SYNC_LOG}"; [ "$1" = 444 ] && echo 1800000000; return 0; }

API_TIMES=$'111 1791897978\n333 1700000000'
pterohost_workshop_remote_mtimes() { printf 'api %s\n' "$*" >> "${SYNC_LOG}"; printf '%s\n' "${API_TIMES}"; }
: > "${SYNC_LOG}"
pterohost_workshop_sync 221100 "@111;@333;@444;@555;@Handmade;" >/dev/null
check "the API is asked once, for the installed workshop ids only" \
    "api 111 333 444" "$(grep '^api' "${SYNC_LOG}")"
check "a mod the API reports as newer is refreshed" \
    "yes" "$(grep -qx 'download 111' "${SYNC_LOG}" && echo yes || echo no)"
check "a mod the API reports as older is left alone" \
    "no" "$(grep -qx 'download 333' "${SYNC_LOG}" && echo yes || echo no)"
check "only the id the API did not describe goes to the changelog page" \
    "page 444" "$(grep '^page' "${SYNC_LOG}" | paste -sd'|')"
check "the page fallback still refreshes a newer mod" \
    "yes" "$(grep -qx 'download 444' "${SYNC_LOG}" && echo yes || echo no)"
check "a missing mod is downloaded without asking about updates" \
    "yes" "$(grep -qx 'download 555' "${SYNC_LOG}" && echo yes || echo no)"

API_TIMES=""
: > "${SYNC_LOG}"
check "an API outage falls back to the page for every installed mod and says so" \
    "page 111|page 333|page 444|1" \
    "$(pterohost_workshop_sync 221100 "@111;@333;@444;" | grep -c 'Steam Web API gave no update times' > "${TMP}/said"; grep '^page' "${SYNC_LOG}" | paste -sd'|' | tr -d '\n'; printf '|%s' "$(cat "${TMP}/said")")"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
