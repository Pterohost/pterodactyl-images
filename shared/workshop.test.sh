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
check "dedupe sorts and drops duplicates" \
    "@a;@b;" "$(pterohost_mods_dedupe '@b;@a;@b;')"

check "dedupe on an empty list gives an empty list" \
    "" "$(pterohost_mods_dedupe '')"

check "dedupe drops empty entries and whitespace" \
    "@a;@b;" "$(pterohost_mods_dedupe ';@b; @a ;;')"

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
check "both sources merge and dedupe" \
    "@1559212036;@2545327648;@Handmade;" "$(pterohost_mods_client)"

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

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
