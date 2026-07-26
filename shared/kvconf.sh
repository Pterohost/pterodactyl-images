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
