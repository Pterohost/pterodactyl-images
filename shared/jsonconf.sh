#!/bin/bash
# Pterohost shared helper for pretty-printed JSON config files.
#
# Eco keeps its settings in Configs/*.eco: JSON that the game rewrites on every
# shutdown, one scalar per line. The panel owns a handful of those keys - the
# ports above all, because a server listening on the wrong port simply does not
# exist for its players - while every other key, including the nested objects
# the game writes back, belongs to the owner.
#
# json_set therefore rewrites one scalar key in place, keeping the indentation
# and the trailing comma, and never touches a line it did not match.
#
# Deliberately not sed. The value is arbitrary owner input - a server name with
# quotes, an ampersand, a backslash - and the key pattern itself needs an
# alternation, so every candidate delimiter is a character somebody eventually
# types. awk reads both out of the environment, where nothing needs escaping.

# json_string <value>
#   Renders a shell value as a quoted JSON string. Callers pass numbers and
#   booleans to json_set as they are; anything the game types as a string goes
#   through here, so a server named "3000" stays a name and does not turn into
#   a number the game then refuses to deserialize.
json_string() {
    printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# json_set <file> <key> <json-scalar>
#   Rewrites the first scalar occurrence of <key>. The value is written as
#   given, so strings arrive already quoted - see json_string.
#
#   A key that is absent, or whose value is an object or an array, is left
#   alone: the game's own template decides which keys exist, and a nested
#   structure is never ours to rewrite.
json_set() {
    local file="$1" key="$2" json="$3"

    [ -f "${file}" ] || return 1
    [ -n "${key}" ] || return 1

    local tmp="${file}.pterohost.tmp"

    JSONCONF_KEY="${key}" JSONCONF_JSON="${json}" awk '
        BEGIN {
            key = ENVIRON["JSONCONF_KEY"]
            json = ENVIRON["JSONCONF_JSON"]
            pattern = "^[[:space:]]*\"" key "\"[[:space:]]*:[[:space:]]*[^[:space:]{[]"
            replaced = 0
        }
        !replaced && $0 ~ pattern {
            indent = ""
            if (match($0, /^[[:space:]]+/)) indent = substr($0, 1, RLENGTH)
            comma = ($0 ~ /,[[:space:]]*$/) ? "," : ""
            print indent "\"" key "\": " json comma
            replaced = 1
            next
        }
        { print }
    ' "${file}" > "${tmp}" || { rm -f "${tmp}"; return 1; }

    # Copy rather than move: the file belongs to the container user and keeping
    # its inode keeps its ownership and mode.
    cat "${tmp}" > "${file}" && rm -f "${tmp}"
}
