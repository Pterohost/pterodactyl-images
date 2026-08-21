#!/bin/bash
# Contract tests for shared/identity.sh
#
# The invariant every one of these defends: a rename must never cost the owner
# data. Moving is allowed, refusing is allowed, deleting and overwriting are not.
set -u

. "$(dirname "$0")/identity.sh"

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

STATE="${WORK}/.pterohost-world-identity"

# The real Project Zomboid path set, which is what this helper was written for.
TEMPLATES=(
    'Saves/Multiplayer/@'
    'Server/@.ini'
    'Server/@.ini.pterohost-orig'
    'Server/@_SandboxVars.lua'
    'Server/@_spawnpoints.lua'
    'Server/@_spawnregions.lua'
    'db/@.db'
)

world() { # <identity> [marker]
    mkdir -p "${WORK}/Saves/Multiplayer/$1/map"
    printf '%s' "${2:-$1}" > "${WORK}/Saves/Multiplayer/$1/map/chunk.bin"
    mkdir -p "${WORK}/Server" "${WORK}/db"
    printf 'PublicName=%s\nMods=BigModList\n' "${2:-$1}" > "${WORK}/Server/$1.ini"
    : > "${WORK}/Server/$1.ini.pterohost-orig"
    printf 'SandboxVars = { ZombieCount = 4 }' > "${WORK}/Server/$1_SandboxVars.lua"
    printf 'spawnpoints' > "${WORK}/Server/$1_spawnpoints.lua"
    printf 'spawnregions' > "${WORK}/Server/$1_spawnregions.lua"
    printf 'players-and-whitelist' > "${WORK}/db/$1.db"
}

reset() {
    rm -rf "${WORK}/Saves" "${WORK}/Server" "${WORK}/db" "${STATE}"
}

sync_as() { # <identity>
    ( cd "${WORK}" && pterohost_ident_sync "${STATE}" "$1" "${TEMPLATES[@]}" )
}

inventory() { # every identity that still has a world, sorted
    ( cd "${WORK}" && ls Saves/Multiplayer 2>/dev/null | sort | tr '\n' ',' )
}

# --- 1. nothing to do -------------------------------------------------------
reset
world Fox
sync_as Fox
check "first boot records the identity" "Fox" "$(pterohost_ident_load "${STATE}")"
check "first boot moves nothing" "Fox," "$(inventory)"

sync_as Fox
check "an unchanged name is a no-op" "Fox," "$(inventory)"

# --- 2. the rename this whole file exists for -------------------------------
reset
world Pterodactyl "the owner's world"
sync_as Pterodactyl
sync_as MeatBalls

check "rename moves the world" "MeatBalls," "$(inventory)"
check "the world contents came too" "the owner's world" \
    "$(cat "${WORK}/Saves/Multiplayer/MeatBalls/map/chunk.bin")"
check "the config came too, mod list intact" "1" \
    "$(grep -c '^Mods=BigModList$' "${WORK}/Server/MeatBalls.ini")"
check "the sandbox settings came too" "1" \
    "$(ls "${WORK}/Server/MeatBalls_SandboxVars.lua" >/dev/null 2>&1 && echo 1 || echo 0)"
check "the spawn files came too" "11" \
    "$(ls "${WORK}/Server/MeatBalls_spawnpoints.lua" >/dev/null 2>&1 && printf 1)$(ls "${WORK}/Server/MeatBalls_spawnregions.lua" >/dev/null 2>&1 && printf 1)"
check "the player database came too" "players-and-whitelist" \
    "$(cat "${WORK}/db/MeatBalls.db")"
check "the pristine backup came too" "1" \
    "$(ls "${WORK}/Server/MeatBalls.ini.pterohost-orig" >/dev/null 2>&1 && echo 1 || echo 0)"
check "nothing is left under the old name" "0" \
    "$(ls "${WORK}/Server/" | grep -c '^Pterodactyl')"
check "the new identity is recorded" "MeatBalls" "$(pterohost_ident_load "${STATE}")"

# --- 3. renaming back gets the same world back -----------------------------
sync_as Pterodactyl
check "renaming back is symmetric" "Pterodactyl," "$(inventory)"
check "and the world is the same one" "the owner's world" \
    "$(cat "${WORK}/Saves/Multiplayer/Pterodactyl/map/chunk.bin")"

# --- 4. two worlds are never merged ----------------------------------------
reset
world Alpha "alpha world"
world Beta  "beta world"
sync_as Alpha
sync_as Beta
check "switching to a name that already has data moves nothing" "Alpha,Beta," "$(inventory)"
check "the target world is untouched" "beta world" \
    "$(cat "${WORK}/Saves/Multiplayer/Beta/map/chunk.bin")"
check "the source world is untouched" "alpha world" \
    "$(cat "${WORK}/Saves/Multiplayer/Alpha/map/chunk.bin")"
check "switching still records the new name" "Beta" "$(pterohost_ident_load "${STATE}")"

sync_as Alpha
check "switching back also moves nothing" "Alpha,Beta," "$(inventory)"

# --- 5. first boot with no record: one candidate is unambiguous ------------
reset
world OldName "pre-existing world"
sync_as NewName
check "an inferred rename migrates" "NewName," "$(inventory)"
check "and keeps the contents" "pre-existing world" \
    "$(cat "${WORK}/Saves/Multiplayer/NewName/map/chunk.bin")"

# --- 6. first boot with no record: several candidates, refuse -------------
reset
world One   "world one"
world Two   "world two"
world Three "world three"
out="$(sync_as Fresh 2>&1)"
check "an ambiguous inferred rename moves nothing" "One,Three,Two," "$(inventory)"
check "and says so" "1" "$(printf '%s' "${out}" | grep -c 'Refusing to guess')"
check "and names the candidates" "1" \
    "$(printf '%s' "${out}" | grep -c 'One')"
check "and still records the new name so it only warns once" "Fresh" \
    "$(pterohost_ident_load "${STATE}")"

# --- 7. a brand new server has nothing to migrate -------------------------
reset
out="$(sync_as Brandnew 2>&1)"
check "an empty volume is silent" "" "${out}"
check "an empty volume creates nothing" "" "$(inventory)"
check "an empty volume records the identity" "Brandnew" "$(pterohost_ident_load "${STATE}")"

# --- 8. a partial collision aborts the whole migration --------------------
# The world is free but the player database is not. Moving the world without it
# would hand the owner their map back with every character on it deleted.
reset
world Source "source world"
mkdir -p "${WORK}/db"
printf 'someone-elses-players' > "${WORK}/db/Target.db"
sync_as Source
out="$(sync_as Target 2>&1)"
check "a partial collision moves nothing" "Source," "$(inventory)"
check "the colliding file is untouched" "someone-elses-players" "$(cat "${WORK}/db/Target.db")"
check "the source config stays put" "1" \
    "$(ls "${WORK}/Server/Source.ini" >/dev/null 2>&1 && echo 1 || echo 0)"
check "and it says why" "1" "$(printf '%s' "${out}" | grep -c 'already exists')"

# --- 9. identities with the characters the egg actually allows ------------
reset
world "pz-server_01" "dashed world"
sync_as "pz-server_01"
sync_as "pz-server_02"
check "dashes and underscores survive a rename" "pz-server_02," "$(inventory)"
check "with contents" "dashed world" \
    "$(cat "${WORK}/Saves/Multiplayer/pz-server_02/map/chunk.bin")"

# --- 10. a missing state file is not an error ----------------------------
check "loading an absent state file is empty, not an error" "" \
    "$(pterohost_ident_load "${WORK}/definitely-not-here")"

# --- 11. an empty new identity is refused outright -----------------------
reset
world Kept "kept world"
sync_as ""
check "an empty server name changes nothing" "Kept," "$(inventory)"

# --- 12. glob templates, which is how Valheim keeps its rolled backups ------
VALHEIM=(
    'worlds_local/@.db'
    'worlds_local/@.fwl'
    'worlds_local/@_backup_auto-*.db'
    'worlds_local/@_backup_auto-*.fwl'
)
vsync() { ( cd "${WORK}" && pterohost_ident_sync "${STATE}" "$1" "${VALHEIM[@]}" ); }
vworld() {
    mkdir -p "${WORK}/worlds_local"
    printf 'world %s' "$1" > "${WORK}/worlds_local/$1.db"
    printf 'seed %s'  "$1" > "${WORK}/worlds_local/$1.fwl"
    printf 'backup a' > "${WORK}/worlds_local/$1_backup_auto-20260819185151.db"
    printf 'backup a' > "${WORK}/worlds_local/$1_backup_auto-20260819185151.fwl"
    printf 'backup b' > "${WORK}/worlds_local/$1_backup_auto-20260821013956.db"
}

reset; rm -rf "${WORK}/worlds_local"
vworld ALLAHH333
vsync ALLAHH333
vsync Valhalla
check "a glob template moves the world itself" "world ALLAHH333" \
    "$(cat "${WORK}/worlds_local/Valhalla.db" 2>/dev/null)"
check "and the seed file" "seed ALLAHH333" \
    "$(cat "${WORK}/worlds_local/Valhalla.fwl" 2>/dev/null)"
check "and every rolled backup, keeping its timestamp" \
    "Valhalla.db,Valhalla.fwl,Valhalla_backup_auto-20260819185151.db,Valhalla_backup_auto-20260819185151.fwl,Valhalla_backup_auto-20260821013956.db," \
    "$(ls "${WORK}/worlds_local" | LC_ALL=C sort | tr '\n' ',')"
check "backup contents survive" "backup b" \
    "$(cat "${WORK}/worlds_local/Valhalla_backup_auto-20260821013956.db" 2>/dev/null)"

# a collision on one glob match must abandon the whole migration, not most of it
reset; rm -rf "${WORK}/worlds_local"
vworld Source
printf 'not yours' > "${WORK}/worlds_local/Target_backup_auto-20260819185151.db"
vsync Source
out="$(vsync Target 2>&1)"
check "a colliding backup abandons the whole rename" "world Source" \
    "$(cat "${WORK}/worlds_local/Source.db" 2>/dev/null)"
check "and leaves the colliding file alone" "not yours" \
    "$(cat "${WORK}/worlds_local/Target_backup_auto-20260819185151.db" 2>/dev/null)"
check "and no half-moved world appears" "" \
    "$(cat "${WORK}/worlds_local/Target.db" 2>/dev/null)"
check "and it says why" "1" "$(printf '%s' "${out}" | grep -c 'already exists')"

# a glob that matches nothing is not an error
reset; rm -rf "${WORK}/worlds_local"
mkdir -p "${WORK}/worlds_local"
printf 'lonely world' > "${WORK}/worlds_local/Solo.db"
vsync Solo
vsync Duo
check "a glob matching nothing does not stop the rest" "lonely world" \
    "$(cat "${WORK}/worlds_local/Duo.db" 2>/dev/null)"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
