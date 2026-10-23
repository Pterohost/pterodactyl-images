#!/bin/bash
# Pterohost Steam Workshop helper for the Bohemia images (DayZ, Arma 3).
#
# The images these two replaced carried a mod manager, and dropping it took two
# things away at once:
#
#   1. The mod list itself. Both eggs publish it as MODIFICATIONS (a semicolon
#      list of @names) plus MOD_FILE - the modlist.html a player exports from the
#      DayZ/Arma launcher, which is where most owners actually keep it. The old
#      image folded both into CLIENT_MODS and the egg's startup line read
#      -mod={{CLIENT_MODS}}. Nothing in the new images computed CLIENT_MODS, so
#      -mod= disappeared and every modded server booted vanilla against modded
#      storage.
#
#   2. Downloading and updating those mods. A workshop id in the list is worth
#      nothing until @<id> exists on disk, and mods update on Bohemia's schedule,
#      not ours: a server whose mods lag behind the clients cannot be joined.
#
# Both live here rather than in the two bootstraps because DayZ and Arma 3 differ
# only in which app id owns the workshop items.
#
# Sourced after steam-update.sh - pterohost_log, pterohost_steam_login_args and
# pterohost_steam_seed come from there.

STEAMCMD_RUN="${STEAMCMD_RUN:-/home/container/.steamcmd}"

# pterohost_mods_dedupe <list>
#   Normalises a semicolon list into a de-duplicated, semicolon-terminated one,
#   KEEPING THE ORDER IT WAS GIVEN.
#
#   This used to `sort -u`, justified in a comment as "what the previous image
#   did, so servers keep the load order they have been running with". Both
#   halves were wrong. The order is not incidental in these games: -mod= is
#   evaluated left to right and a mod that overrides another has to come after
#   it, which is why every DayZ Expansion install guide is an ordered list
#   (@CF, then @DayZ-Expansion-Licensed, then @DayZ-Expansion-Core, then the
#   modules). Sorting replaced the owner's list with an alphabetical one - on
#   server 3946 it moved @VPPAdminTools from last position to third and put the
#   main Expansion bundle ahead of Expansion-Core - and the owner had no way to
#   express what they wanted, because whatever they typed got re-sorted.
#
#   `awk '!seen[$0]++'` is first-seen-wins and is portable across mawk, gawk and
#   busybox awk, all three of which turn up in these images.
pterohost_mods_dedupe() {
    local list="$1"

    [ -n "${list}" ] || return 0

    printf '%s' "${list}" \
        | tr ';' '\n' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | grep -v '^$' \
        | awk '!seen[$0]++' \
        | tr '\n' ';'
}

# pterohost_mods_from_launcher <file>
#   Pulls the workshop ids out of a launcher-exported modlist.html. Both the DayZ
#   and the Arma 3 launcher write the id into a steamcommunity filedetails link,
#   which is the one part of that HTML that has never changed shape.
#
#   Order is preserved, and that is the whole point of reading this file: the
#   launcher writes the rows in the exact order the player arranged them, so the
#   export IS the load order. `sort -u` here threw away the one piece of
#   information the file exists to carry.
pterohost_mods_from_launcher() {
    local file="$1"

    [ -f "${file}" ] || return 1

    local ids
    ids="$(grep -oE 'filedetails/\?id=[0-9]+' "${file}" 2>/dev/null | grep -oE '[0-9]+' | awk '!seen[$0]++')"

    [ -n "${ids}" ] || return 1

    # printf '%s\n' keeps the final line terminated: piped into a read loop, an
    # unterminated last line is simply dropped.
    printf '%s\n' "${ids}" | sed -e 's/^/@/' -e 's/$/;/' | tr -d '\n'
}

# pterohost_mods_client
#   The client-side mod list, echoed semicolon-terminated.
#
#   CLIENT_MODS wins if something already set it (an admin pinning an exact list
#   through the startup command), then MODIFICATIONS, then the launcher file.
#   MODIFICATIONS and MOD_FILE are additive - owners routinely keep the bulk in
#   the exported file and add one mod by hand.
pterohost_mods_client() {
    local mods="${CLIENT_MODS:-}"

    if [ -n "${mods}" ]; then
        pterohost_mods_dedupe "${mods}"
        return 0
    fi

    mods="${MODIFICATIONS:-}"

    local file="${MOD_FILE:-}"
    if [ -n "${file}" ]; then
        local from_file
        if from_file="$(pterohost_mods_from_launcher "${file}")"; then
            mods="${mods};${from_file}"
        else
            # stderr: this function's stdout is the mod list itself.
            pterohost_log "WARN: mod list file '${file}' is missing or holds no workshop ids." >&2
            [ -n "${mods}" ] && pterohost_log "Falling back to the MODIFICATIONS list." >&2
        fi
    fi

    pterohost_mods_dedupe "${mods}"
}

# pterohost_mods_lowercase <dir>
#   Bohemia's Windows-built mods ship mixed-case paths that the engine then looks
#   up in lowercase. On a case-sensitive filesystem that is a missing file.
#
#   -mindepth 1 is the point: the mod directory itself keeps its name. Renaming
#   @CF to @cf would break the -mod= entry that names it.
pterohost_mods_lowercase() {
    local dir="$1"
    local src dst

    [ -d "${dir}" ] || return 0

    find "${dir}" -depth -mindepth 1 -print | while IFS= read -r src; do
        dst="$(dirname "${src}")/$(basename "${src}" | tr '[:upper:]' '[:lower:]')"
        [ "${src}" = "${dst}" ] && continue
        [ -e "${dst}" ] && continue
        mv -T "${src}" "${dst}" 2>/dev/null || true
    done
}

# pterohost_mods_fix_meta <dir> [<dir>...]
#   Give every workshop mod a meta.cpp that names its own workshop id.
#
#   SteamCMD downloads meta.cpp exactly as the author uploaded it, and a fair
#   number of authors publish theirs with `publishedid = 0` - the value the
#   DayZ Tools publisher writes before the item has an id. A subscriber never
#   sees it, because the game's own launcher rewrites the file locally; a
#   server does, and it advertises that zero to clients.
#
#   What that costs, measured 2026-09-09 on DayZ service 7785: five mods out of
#   48 carried a zero, so the mod list in the A2S rules reply carried five
#   entries with no id. DZSA refuses the whole server with "The mod 'FBB Admin
#   Gear' has a Steam Workshop ID of '0'", and the official launcher shows
#   "the server could not send all data" plus an EMPTY required-mod list - so
#   the server is unjoinable from both, while being perfectly healthy and
#   answering A2S. Two of four modded DayZ servers on that node were affected.
#
#   The folder name IS the workshop id (that is how the sync writes them), so
#   the repair needs no network. Only numeric @<id> directories qualify: a
#   hand-installed @MyServerMod has no id to claim and is left alone.
pterohost_mods_fix_meta() {
    local dir base id meta

    for dir in "$@"; do
        [ -d "${dir}" ] || continue
        base="$(basename "${dir}")"
        id="${base#@}"

        # Numeric-only. `case` avoids a grep per mod on a 50-mod server.
        case "${id}" in
            ''|*[!0-9]*) continue ;;
        esac

        meta="${dir}/meta.cpp"

        if [ ! -f "${meta}" ]; then
            printf 'protocol = 1;\npublishedid = %s;\nname = "%s";\n' "${id}" "${id}" > "${meta}" 2>/dev/null \
                && pterohost_log "meta.cpp was missing for ${base} - created one."
            continue
        fi

        grep -qE '^[[:space:]]*publishedid[[:space:]]*=[[:space:]]*0[[:space:]]*;' "${meta}" 2>/dev/null || continue

        # In place, keeping name/timestamp: the launcher shows `name`, and the
        # sync compares `timestamp` to decide whether the mod needs a redownload.
        sed -i -E "s/^[[:space:]]*publishedid[[:space:]]*=[[:space:]]*0[[:space:]]*;/publishedid = ${id};/" "${meta}" 2>/dev/null \
            && pterohost_log "${base}: meta.cpp said publishedid = 0 - set it to ${id} so launchers can list this mod."
    done
}

# pterohost_workshop_remote_mtime <id>
#   Last update of a workshop item, in epoch seconds, from its changelog page.
#   Empty when Steam cannot be reached - the caller then leaves an installed mod
#   alone rather than re-downloading the whole collection on every boot.
#
#   The User-Agent is load-bearing, not politeness. Steam answers curl's default
#   `curl/x.y.z` UA with HTTP 429 and a short non-HTML body; the same request
#   with a browser UA, from the same address a second later, returns 200 and the
#   full page. Measured 2026-08-08:
#
#     default UA -> http=429 bytes=5873   -> no mtime parsed
#     browser UA -> http=200 bytes=58384  -> mtime 1771519119
#
#   Because a parse failure is indistinguishable from "not updated", this made
#   the whole refresh path dead: every mod was downloaded once, when @<id> was
#   absent, and then frozen forever. When an author publishes an update Steam
#   updates every player's client automatically and the server, still on the old
#   version, rejects all of them - which is exactly the failure this file's
#   header says the feature exists to prevent.
#
#   `--compressed` because a browser UA invites a gzipped response, and the
#   caller greps the body as text.
PTEROHOST_WORKSHOP_UA="${PTEROHOST_WORKSHOP_UA:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36}"

pterohost_workshop_remote_mtime() {
    local id="$1"

    curl -sL --compressed --max-time 20 \
        -A "${PTEROHOST_WORKSHOP_UA}" \
        "https://steamcommunity.com/sharedfiles/filedetails/changelog/${id}" 2>/dev/null \
        | grep '<p id=' | head -1 | cut -d'"' -f2 | grep -E '^[0-9]+$'
}

# pterohost_workshop_remote_mtimes <id>...
#   "<id> <epoch>" per line for every item the Steam Web API describes, from
#   ISteamRemoteStorage/GetPublishedFileDetails - one POST per 100 items, no API
#   key. This is the primary source; the changelog page above is only the
#   fallback for ids missing here.
#
#   The page stopped being enough: on 2026-10-17 node03 and node10 got HTTP 429
#   from it even with the browser UA once the first few mods of a list had been
#   asked for, so every later mod logged "could not read its Steam changelog" and
#   DayZ/Arma servers kept stale copies while every client had the update
#   (ticket 4714: DayZ 1.30, `Can't compile "World" script module!`). The Web
#   API answers the whole list in one request and reports time_updated directly.
#   An item it cannot describe (result != 1: removed, private, unknown) is left
#   out, so the caller falls back to the page for exactly those.
PTEROHOST_WORKSHOP_API="${PTEROHOST_WORKSHOP_API:-https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/}"

pterohost_workshop_remote_mtimes() {
    [ "$#" -gt 0 ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local ids=("$@") start=0 i
    local chunk=() form=()
    while [ "${start}" -lt "${#ids[@]}" ]; do
        chunk=("${ids[@]:${start}:100}")
        form=(-d "itemcount=${#chunk[@]}")
        for i in "${!chunk[@]}"; do
            form+=(-d "publishedfileids[${i}]=${chunk[${i}]}")
        done
        curl -sf --max-time 30 "${form[@]}" "${PTEROHOST_WORKSHOP_API}" 2>/dev/null \
            | jq -r '.response.publishedfiledetails[]?
                     | select(.result == 1 and (.time_updated | type) == "number" and .time_updated > 0)
                     | "\(.publishedfileid) \(.time_updated)"' 2>/dev/null \
            | grep -E '^[0-9]+ [0-9]+$'
        start=$((start + 100))
    done
    return 0
}

# pterohost_workshop_download <game_appid> <id>
#   One item, with the same retry budget as the server update.
pterohost_workshop_download() {
    local game="$1" id="$2"
    local attempt=1 max_attempts="${STEAMCMD_ATTEMPTS:-3}"
    local login_args=() src=""

    while IFS= read -r arg; do login_args+=("${arg}"); done < <(pterohost_steam_login_args)

    while [ "${attempt}" -le "${max_attempts}" ]; do
        # SteamCMD caches a manifest per app and will happily serve a stale
        # "already up to date" from it after a failed download.
        rm -f "/home/container/steamapps/workshop/appworkshop_${game}.acf" \
              "/home/container/Steam/steamapps/workshop/appworkshop_${game}.acf" 2>/dev/null

        timeout "${STEAMCMD_TIMEOUT:-1800}" "${STEAMCMD_RUN}/steamcmd.sh" \
            +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 \
            +force_install_dir /home/container \
            "${login_args[@]}" \
            +workshop_download_item "${game}" "${id}" \
            +quit || true

        src=""
        local candidate
        for candidate in \
            "/home/container/steamapps/workshop/content/${game}/${id}" \
            "/home/container/Steam/steamapps/workshop/content/${game}/${id}" \
            "${STEAMCMD_RUN}/steamapps/workshop/content/${game}/${id}"
        do
            if [ -d "${candidate}" ] && [ -n "$(ls -A "${candidate}" 2>/dev/null)" ]; then
                src="${candidate}"
                break
            fi
        done

        if [ -n "${src}" ]; then
            mkdir -p "/home/container/@${id}"
            rm -rf "/home/container/@${id:?}"/*
            mv -f "${src}"/* "/home/container/@${id}/" 2>/dev/null
            rmdir "${src}" 2>/dev/null || true

            # Always, not only when MODS_LOWERCASE is set: a freshly downloaded
            # mod is the one place we know the paths came straight off Windows.
            pterohost_mods_lowercase "/home/container/@${id}"

            mkdir -p /home/container/keys
            find "/home/container/@${id}" -iname '*.bikey' -type f -exec cp -f {} /home/container/keys/ \; 2>/dev/null

            pterohost_log "Mod ${id} installed."
            return 0
        fi

        pterohost_log "Mod ${id}: attempt ${attempt}/${max_attempts} produced nothing; retrying..."
        attempt=$((attempt + 1))
        sleep 3
    done

    pterohost_log "WARN: mod ${id} could not be downloaded - the server will start without an up-to-date copy."
    return 1
}

# pterohost_workshop_sync <game_appid> <mod list>
#   Downloads what is missing and refreshes what Steam says is newer. Never
#   fatal: a Steam outage must not keep a server with a working install down.
pterohost_workshop_sync() {
    local game="$1" list="$2"
    local entry id local_mtime remote_mtime

    [ -n "${list}" ] || return 0

    pterohost_steam_seed

    pterohost_log "Checking Steam Workshop mods for updates..."

    local installed=() api_times=""
    while IFS= read -r entry; do
        id="${entry#@}"
        case "${id}" in
            ''|*[!0-9]*) continue ;;
        esac
        [ -d "/home/container/@${id}" ] && installed+=("${id}")
    done < <(printf '%s\n' "${list}" | tr ';' '\n')
    if [ "${#installed[@]}" -gt 0 ]; then
        api_times="$(pterohost_workshop_remote_mtimes "${installed[@]}")"
        [ -n "${api_times}" ] || pterohost_log "Steam Web API gave no update times - asking each mod's changelog page instead."
    fi

    printf '%s' "${list}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r entry; do
        id="${entry#@}"

        # Named mods (@CF and friends) were uploaded by hand over SFTP. There is
        # nothing to check them against, so they are left exactly as they are.
        case "${id}" in
            ''|*[!0-9]*) continue ;;
        esac

        if [ ! -d "/home/container/@${id}" ]; then
            pterohost_log "Mod ${id} is not installed - downloading."
            pterohost_workshop_download "${game}" "${id}"
            continue
        fi

        remote_mtime="$(printf '%s\n' "${api_times}" | awk -v id="${id}" '$1 == id { print $2; exit }')"
        [ -n "${remote_mtime}" ] || remote_mtime="$(pterohost_workshop_remote_mtime "${id}")"

        # Say so. An unanswerable update check looks exactly like "this mod is
        # current", and that silence is what hid a permanently dead refresh path
        # for as long as it existed. Still never fatal: a Steam outage must not
        # keep a server with a working install down.
        if [ -z "${remote_mtime}" ]; then
            pterohost_log "Mod ${id}: could not read its Steam changelog - keeping the copy on disk, which may be out of date."
            continue
        fi

        local_mtime="$(stat -c %Y "/home/container/@${id}" 2>/dev/null || echo 0)"
        if [ "${remote_mtime}" -gt "${local_mtime}" ]; then
            pterohost_log "Mod ${id} was updated on $(date -d "@${remote_mtime}" 2>/dev/null || echo "${remote_mtime}") - refreshing."
            pterohost_workshop_download "${game}" "${id}"
        fi
    done

    pterohost_log "Steam Workshop check complete."
}
