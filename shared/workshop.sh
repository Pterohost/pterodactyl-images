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

        remote_mtime="$(pterohost_workshop_remote_mtime "${id}")"

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
