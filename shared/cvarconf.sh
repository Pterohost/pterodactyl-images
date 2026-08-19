#!/bin/bash
# Pterohost shared helper for Source-engine cfg files.
#
# srcds takes its settings as console commands, one per line:
#
#     hostname "My Server"
#     sv_maxplayers 8
#
# Neither kvconf.sh (key=value) nor cfgconf.sh (key = value;) matches that
# shape, and the difference is not cosmetic: the value is separated by
# whitespace and quoted, and everything after a // is a comment.
#
# The file that matters is <game>/cfg/server.cfg, because the engine exec's it
# after every map load - a cvar set on the command line does not survive that,
# which is why "+sv_maxplayers 8" on the launch line leaves Left 4 Dead 2
# reporting 0/4 anyway. The panel owns a couple of cvars in that file; every
# other line in it belongs to the owner and is left byte-for-byte alone.

# cvar_set <file> <cvar> <value>
#   The value is always written quoted - server names contain spaces, and an
#   unquoted one would leave the engine reading only the first word.
cvar_set() {
    local file="$1" cvar="$2" value="$3"

    [ -f "${file}" ] || return 1

    local escaped
    escaped="$(printf '%s' "${value}" | tr -d '"\r\n' | sed -e 's/[&|\\]/\\&/g')"

    if grep -qE "^[[:space:]]*(//)?[[:space:]]*${cvar}[[:space:]]" "${file}"; then
        sed -i -E "s|^[[:space:]]*(//)?[[:space:]]*${cvar}[[:space:]].*|${cvar} \"${escaped}\"|" "${file}"
    else
        [ -n "$(tail -c1 "${file}")" ] && printf '\n' >> "${file}"
        printf '%s "%s"\n' "${cvar}" "${value}" >> "${file}"
    fi
}

# cvar_get <file> <cvar>
cvar_get() {
    local file="$1" cvar="$2"
    [ -f "${file}" ] || return 1
    grep -E "^[[:space:]]*${cvar}[[:space:]]" "${file}" | head -1 \
        | sed -E "s|^[[:space:]]*${cvar}[[:space:]]+||; s|^\"||; s|\"[[:space:]]*$||; s|[[:space:]]*//.*$||"
}

# cvar_set_owned <file> <cvar> <panel value> [seed]
#   The same three-way ownership kvconf.sh uses, and for the same reason: the
#   panel wins when its variable is set, and when it is empty the file is left
#   as it is - seeded only while the cvar is still absent. See the long comment
#   on kv_set_owned in shared/kvconf.sh for what goes wrong without the second
#   half.
cvar_set_owned() {
    local file="$1" cvar="$2" panel_value="$3" seed="${4:-}"

    [ -f "${file}" ] || return 1

    panel_value="$(printf '%s' "${panel_value}" | tr -d '\r\n')"

    if [ -n "${panel_value}" ]; then
        cvar_set "${file}" "${cvar}" "${panel_value}"
        return
    fi

    if [ -z "$(cvar_get "${file}" "${cvar}")" ] && [ -n "${seed}" ]; then
        cvar_set "${file}" "${cvar}" "${seed}"
    fi

    return 0
}
