#!/bin/bash
# Pterohost world-identity helper.
#
# THE PROBLEM THIS EXISTS FOR
#
# Several games name their saved data after a "server name" that the panel also
# exposes as an editable field. Project Zomboid is the worst case: -servername
# selects, all at once,
#
#     .cache/Server/<name>.ini              the config, including the mod list
#     .cache/Server/<name>_SandboxVars.lua  every sandbox setting the owner tuned
#     .cache/Server/<name>_spawn*.lua       spawn points and regions
#     .cache/db/<name>.db                   player accounts, whitelist, bans, admins
#     .cache/Saves/Multiplayer/<name>/      the world
#
# so changing that one field in the panel does not rename anything. It points
# the server at a name nothing exists under, and the game does the only thing it
# can: it creates all of it from scratch. The owner restarts and finds an empty
# map, no mods, no settings and no players - while every byte of the old server
# is still on disk under the old name, invisible from the panel.
#
# This is not hypothetical and it is not rare. On the fleet at the time this was
# written, 14 of 62 Project Zomboid servers were carrying worlds abandoned by
# exactly this: one owner had three (6 MB, 18 MB, 177 MB) and had lost a fully
# played world mid-game; another had a world called
# "undergroundWargmClaim360820", created because a mod-shop service asked them to
# rename their server for a few minutes to prove ownership. They did, lost their
# world, renamed back, and got it again - which is only luck, because renaming
# back works exactly as often as the old directory happens to still be there.
#
# THE CONTRACT
#
# pterohost_ident_sync moves the data to follow the name. Rules, in order:
#
#   1. Name unchanged since the last boot -> do nothing.
#   2. The NEW name already has saved data -> use it, move nothing, and say so
#      if the old name still has data too. Two worlds are never merged, and
#      renaming back and forth between worlds an owner keeps on purpose keeps
#      working.
#   3. Otherwise move every path from the old name to the new one.
#
# It never deletes and never overwrites: if any destination already exists the
# whole migration is abandoned rather than half-applied, because half of a
# migration is worse than none - a world that arrives without its player
# database has lost every character on it. A rename is therefore reversible by
# renaming back.
#
# On the first boot after this helper ships there is no record of the previous
# name, so it is inferred from what is on disk, and only when the answer is
# unambiguous: exactly one candidate. With several, it refuses and logs them,
# which leaves the server behaving exactly as it did before this file existed.
#
# TEMPLATES
#
# Callers describe the paths with the identity written as @:
#
#     pterohost_ident_sync "${STATE}" "${SERVER_NAME}" \
#         'Saves/Multiplayer/@' \
#         'Server/@.ini' 'db/@.db'
#
# The first template after the state file and the new name is the WITNESS: the
# one whose existence means "this name has real data". Everything after it comes
# along for the ride. The witness is moved too - it does not need repeating.

_pterohost_ident_log() {
    if declare -F pterohost_log >/dev/null 2>&1; then
        pterohost_log "$@"
    else
        printf '[pterohost] %s\n' "$*"
    fi
}

# _pterohost_ident_path <template> <identity>
_pterohost_ident_path() {
    printf '%s' "${1//@/$2}"
}

# _pterohost_ident_candidates <witness template>
#   Every identity that currently has data on disk, one per line.
_pterohost_ident_candidates() {
    local tmpl="$1" glob pre post match id
    glob="${tmpl//@/*}"
    pre="${tmpl%%@*}"
    post="${tmpl#*@}"

    for match in ${glob}; do
        [ -e "${match}" ] || continue
        id="${match#"${pre}"}"
        id="${id%"${post}"}"
        case "${id}" in
            ''|*'/'*) continue ;;
        esac
        printf '%s\n' "${id}"
    done
}

# pterohost_ident_load <state file>
pterohost_ident_load() {
    [ -f "$1" ] || return 0
    head -n1 "$1" 2>/dev/null | tr -d '\r\n'
}

# pterohost_ident_save <state file> <identity>
pterohost_ident_save() {
    local state="$1" identity="$2"
    mkdir -p "$(dirname "${state}")" 2>/dev/null
    printf '%s\n' "${identity}" > "${state}" 2>/dev/null || true
}

# pterohost_ident_sync <state file> <new identity> <witness template> [template...]
pterohost_ident_sync() {
    local state="$1" new="$2" witness="$3"
    shift 3

    [ -n "${new}" ] || return 0

    local previous
    previous="$(pterohost_ident_load "${state}")"
    [ "${previous}" = "${new}" ] && return 0

    if [ -e "$(_pterohost_ident_path "${witness}" "${new}")" ]; then
        if [ -n "${previous}" ] && [ -e "$(_pterohost_ident_path "${witness}" "${previous}")" ]; then
            _pterohost_ident_log "Server name changed ${previous} -> ${new}, and both names already have saved data. Nothing was moved; the ${previous} data is still on disk."
        fi
        pterohost_ident_save "${state}" "${new}"
        return 0
    fi

    local from="${previous}"
    if [ -z "${from}" ] || [ ! -e "$(_pterohost_ident_path "${witness}" "${from}")" ]; then
        local candidates=() candidate
        while IFS= read -r candidate; do
            [ -n "${candidate}" ] && candidates+=("${candidate}")
        done < <(_pterohost_ident_candidates "${witness}")

        case "${#candidates[@]}" in
            0)  pterohost_ident_save "${state}" "${new}"
                return 0 ;;
            1)  from="${candidates[0]}" ;;
            *)  _pterohost_ident_log "WARN: the server name is now '${new}', which has no saved data, and there are ${#candidates[@]} sets on disk (${candidates[*]}). Refusing to guess which one to move - the server will start a new world. Support can move the right one by hand."
                pterohost_ident_save "${state}" "${new}"
                return 0 ;;
        esac
    fi

    [ "${from}" = "${new}" ] && { pterohost_ident_save "${state}" "${new}"; return 0; }

    # Pre-flight. A destination that already exists means a partial migration,
    # so the whole thing is abandoned instead.
    local templates=("${witness}" "$@")
    local template source destination
    local -a sources=() destinations=()

    for template in "${templates[@]}"; do
        source="$(_pterohost_ident_path "${template}" "${from}")"
        destination="$(_pterohost_ident_path "${template}" "${new}")"
        [ -e "${source}" ] || continue
        if [ -e "${destination}" ]; then
            _pterohost_ident_log "WARN: cannot rename '${from}' to '${new}' - '${destination}' already exists. Nothing was moved, so the server keeps every file it had."
            pterohost_ident_save "${state}" "${new}"
            return 0
        fi
        sources+=("${source}")
        destinations+=("${destination}")
    done

    if [ "${#sources[@]}" -eq 0 ]; then
        pterohost_ident_save "${state}" "${new}"
        return 0
    fi

    local index moved=0 failed=0
    for index in "${!sources[@]}"; do
        mkdir -p "$(dirname "${destinations[index]}")" 2>/dev/null
        if mv -- "${sources[index]}" "${destinations[index]}" 2>/dev/null; then
            moved=$((moved + 1))
        else
            failed=$((failed + 1))
            _pterohost_ident_log "WARN: could not move '${sources[index]}' to '${destinations[index]}'."
        fi
    done

    if [ "${failed}" -gt 0 ]; then
        _pterohost_ident_log "WARN: renaming '${from}' to '${new}' moved ${moved} of $((moved + failed)) items. The rest are still under the old name - rename the server back in the panel to reach them."
    else
        _pterohost_ident_log "Server name changed '${from}' -> '${new}': moved ${moved} items, so the world, the settings, the mod list and the players came with it."
    fi

    pterohost_ident_save "${state}" "${new}"
}
