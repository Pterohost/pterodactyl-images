#!/bin/bash
# Pterohost shared key=value config helper.
#
# Project Zomboid's <server>.ini and Palworld's PalWorldSettings.ini are both
# flat key=value files that the game rewrites at will. The panel needs a handful
# of keys (ports, RCON, slot count) to match the allocations it handed out, but
# must not touch the dozens of gameplay keys the owner has tuned.
#
# kv_set is therefore surgical: it rewrites one key in place if present, appends
# it if absent, and leaves every other line - including comments and ordering -
# exactly as it found them.

# kv_set <file> <key> <value>
kv_set() {
    local file="$1" key="$2" value="$3"

    [ -f "${file}" ] || return 1

    # Escape the replacement for sed: & and the delimiter would be interpreted.
    local escaped
    escaped="$(printf '%s' "${value}" | sed -e 's/[&|\\]/\\&/g')"

    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${escaped}|" "${file}"
    else
        # Guarantee the appended key lands on its own line even when the file
        # does not end with a newline.
        [ -n "$(tail -c1 "${file}")" ] && printf '\n' >> "${file}"
        printf '%s=%s\n' "${key}" "${value}" >> "${file}"
    fi
}

# kv_get <file> <key>
kv_get() {
    local file="$1" key="$2"
    [ -f "${file}" ] || return 1
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" | head -1 | cut -d= -f2-
}

# kv_set_owned <file> <key> <panel value> [seed]
#   Three-way ownership for a key the server owner can also edit themselves -
#   a server name, a description, a welcome message.
#
#   Panel value set    -> the panel wins, on every boot. That is what an egg
#                         variable is for: type it in the panel, restart, done.
#   Panel value empty  -> the FILE wins. The key is seeded from <seed> only
#                         while it is still empty, and is never touched again -
#                         so an edit made over SFTP, or an in-game console
#                         command, survives the next restart.
#
#   The second half is the half that keeps getting left out, and it is the half
#   customers notice. Writing a display name unconditionally from an egg
#   variable on every boot means the owner cannot change it by any route at all
#   when that variable is also an identifier and therefore validated down to
#   letters and digits: they cannot type brackets or Cyrillic into the panel,
#   and whatever they write into the config lasts exactly until the next
#   restart. Project Zomboid service 7657 spent a day advertising itself as
#   "MEATBALLS" that way while its owner asked, repeatedly, for
#   "[RU] MEATBALLS [PVE] [VANILLA+] 24/7".
#
#   CR and LF are stripped rather than escaped. These files are one key per
#   line, so a pasted multi-line description does not look wrong - it silently
#   turns the rest of the value into keys the game then fails to parse.
kv_set_owned() {
    local file="$1" key="$2" panel_value="$3" seed="${4:-}"

    [ -f "${file}" ] || return 1

    panel_value="$(printf '%s' "${panel_value}" | tr -d '\r\n')"

    if [ -n "${panel_value}" ]; then
        kv_set "${file}" "${key}" "${panel_value}"
        return
    fi

    if [ -z "$(kv_get "${file}" "${key}")" ] && [ -n "${seed}" ]; then
        kv_set "${file}" "${key}" "$(printf '%s' "${seed}" | tr -d '\r\n')"
    fi

    return 0
}

# kv_backup_once <file> <tag>
#   Keep one pristine copy from before we ever touched the file, so an operator
#   can always see what the game itself wrote.
kv_backup_once() {
    local file="$1" tag="$2"
    [ -f "${file}" ] || return 0
    [ -f "${file}.pterohost-orig" ] && return 0
    cp -a "${file}" "${file}.pterohost-orig" 2>/dev/null || true
    printf '' > /dev/null
    unset tag
}
