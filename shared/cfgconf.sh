#!/bin/bash
# Pterohost shared helper for Bohemia-style config files.
#
# DayZ's serverDZ.cfg and Arma 3's server.cfg are neither flat key=value (that
# is kvconf.sh) nor ini: they use
#
#     hostname = "My Server";
#     maxPlayers = 60;
#
# The panel owns a couple of these keys - notably steamQueryPort, which decides
# whether the server is reachable for a status query at all - while everything
# else belongs to the owner. cfg_set therefore rewrites one key in place and
# leaves the rest of the file byte-for-byte alone.

# cfg_set <file> <key> <value>
#   Pass the value already quoted when the game expects a string:
#     cfg_set serverDZ.cfg hostname '"My Server"'
#     cfg_set serverDZ.cfg steamQueryPort 27016
cfg_set() {
    local file="$1" key="$2" value="$3"

    [ -f "${file}" ] || return 1

    local escaped
    escaped="$(printf '%s' "${value}" | sed -e 's/[&|\\]/\\&/g')"

    # Commented-out keys are the norm in the shipped templates, so match those
    # too rather than appending a duplicate the game would ignore.
    if grep -qE "^[[:space:]]*(//)?[[:space:]]*${key}[[:space:]]*=" "${file}"; then
        sed -i -E "s|^[[:space:]]*(//)?[[:space:]]*${key}[[:space:]]*=.*|${key} = ${escaped};|" "${file}"
    else
        [ -n "$(tail -c1 "${file}")" ] && printf '\n' >> "${file}"
        printf '%s = %s;\n' "${key}" "${escaped}" >> "${file}"
    fi
}

# cfg_get <file> <key>
cfg_get() {
    local file="$1" key="$2"
    [ -f "${file}" ] || return 1
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" | head -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/;[[:space:]]*$//'
}
