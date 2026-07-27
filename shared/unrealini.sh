#!/bin/bash
# Pterohost helper for Unreal "one giant tuple" ini files (Palworld).
#
# The parsing and rewriting lives in unrealini.awk - see the header there for
# why a comma-split cannot work and how an already-corrupted line is repaired.
# This file is the shell surface the bootstraps use:
#
#   unreal_begin                      # start a new set of overrides
#   unreal_set   RCONPort 25575       # bare token (numbers, booleans, tuples)
#   unreal_str   ServerName "My, srv" # string - quoted and sanitised
#   unreal_apply /path/PalWorldSettings.ini
#
# unreal_apply rewrites the file only when the result differs, so a boot that
# changes nothing leaves the mtime alone and an operator can see when the panel
# last actually changed something.

UNREAL_MAP=""

unreal_begin() {
    UNREAL_MAP="$(mktemp 2>/dev/null || echo /tmp/pterohost-unreal.$$)"
    : > "${UNREAL_MAP}"
}

# unreal_set <key> <value>
#   The value is written verbatim. Use it for numbers, True/False and nested
#   tuples like (Steam,Xbox).
unreal_set() {
    [ -n "${UNREAL_MAP}" ] || unreal_begin
    [ -n "$1" ] || return 0
    printf '%s\t%s\n' "$1" "$2" >> "${UNREAL_MAP}"
}

# unreal_str <key> <value>
#   Quotes the value. A double quote has no escape in this format and a newline
#   would split the tuple across lines, so both are removed rather than passed
#   through - that is exactly the corruption we are here to prevent. Commas are
#   safe inside the quotes and are kept, because customers do write them in
#   server names and descriptions.
unreal_str() {
    local clean
    clean="$(printf '%s' "$2" | tr -d '"\r\n')"
    unreal_set "$1" "\"${clean}\""
}

# unreal_apply <file>
#   Returns 0 when the file was rewritten, 1 when it was already correct, and 2
#   when the file could not be processed (missing, or no OptionSettings line).
unreal_apply() {
    local file="$1" tmp status

    [ -f "${file}" ] || return 2
    [ -n "${UNREAL_MAP}" ] || return 2

    tmp="$(mktemp 2>/dev/null || echo "${file}.pterohost-tmp")"

    awk -v mapfile="${UNREAL_MAP}" -f /usr/local/lib/pterohost/unrealini.awk "${file}" > "${tmp}" 2>/dev/null
    status=$?

    if [ "${status}" -ne 0 ] || [ ! -s "${tmp}" ]; then
        rm -f "${tmp}"
        return 2
    fi

    if cmp -s "${tmp}" "${file}"; then
        rm -f "${tmp}"
        return 1
    fi

    # Preserve ownership and mode: the file lives in the customer's volume and
    # is read by the game, not by us.
    cat "${tmp}" > "${file}"
    rm -f "${tmp}"

    return 0
}

# unreal_get <file> <key>
#   Reads one key back out, for diagnostics and tests.
unreal_get() {
    local file="$1" key="$2"

    [ -f "${file}" ] || return 1

    awk -v key="${key}" '
        /^[ \t]*OptionSettings[ \t]*=[ \t]*\(/ {
            line = $0
            if (match(line, "[(,]" key "=")) {
                rest = substr(line, RSTART + RLENGTH)
                if (substr(rest, 1, 1) == "\"") {
                    q = index(substr(rest, 2), "\"")
                    print substr(rest, 2, q - 1)
                } else if (substr(rest, 1, 1) == "(") {
                    depth = 0
                    for (i = 1; i <= length(rest); i++) {
                        c = substr(rest, i, 1)
                        if (c == "(") depth++
                        else if (c == ")") { depth--; if (depth == 0) break }
                    }
                    print substr(rest, 1, i)
                } else {
                    e = index(rest, ",")
                    if (e == 0) e = index(rest, ")")
                    print substr(rest, 1, e - 1)
                }
            }
        }
    ' "${file}"
}
