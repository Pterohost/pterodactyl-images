#!/bin/bash
# Pterohost shared helper for 7 Days to Die's serverconfig.xml.
#
# That file is not key=value, not ini and not a cfg: every setting is one
# self-closing element on its own line, with the shipped file's own alignment
# and an explanatory comment after it -
#
#     <property name="ServerName"        value="My Game Host"/>  <!-- Whatever you want the name of the server to be. -->
#
# The alignment is tabs, the comment is the only documentation an owner has, and
# both must survive: this is the file people read to work out what a setting
# does. So the rewrite replaces the contents of value="..." and nothing else -
# not the indentation, not the spacing between the attributes, not the comment.
#
# XML, unlike every other config format in this directory, has to escape what it
# stores. A server called "Bill & Ted's" written literally makes the file
# malformed, and 7DTD answers a malformed serverconfig.xml by falling back to
# defaults across the board - a whole server silently reset because of one
# ampersand in its name.

# _xmlprop_escape <value>
_xmlprop_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

# xmlprop_set <file> <property name> <value>
xmlprop_set() {
    local file="$1" name="$2" value="$3"

    [ -f "${file}" ] || return 1

    local escaped
    escaped="$(_xmlprop_escape "$(printf '%s' "${value}" | tr -d '\r\n')")"
    # Now for sed's replacement side. This runs after the XML escaping on
    # purpose: that step introduces & characters of its own, and sed would read
    # every one of them as "the whole match".
    escaped="$(printf '%s' "${escaped}" | sed -e 's/[&|\\]/\\&/g')"

    if grep -qE "^[[:space:]]*<property[[:space:]]+name=\"${name}\"[[:space:]]*value=\"" "${file}"; then
        sed -i -E "s|^([[:space:]]*<property[[:space:]]+name=\"${name}\"[[:space:]]*value=\")[^\"]*(\".*)$|\1${escaped}\2|" "${file}"
    else
        # Absent: add it just before the closing tag rather than at the end of
        # the file, where 7DTD would not read it.
        local literal
        literal="$(_xmlprop_escape "$(printf '%s' "${value}" | tr -d '\r\n')")"
        if grep -q '</ServerSettings>' "${file}"; then
            local tmp="${file}.pterohost.tmp"
            awk -v line="	<property name=\"${name}\"				value=\"${literal}\"/>" \
                '/<\/ServerSettings>/ && !done { print line; done = 1 } { print }' \
                "${file}" > "${tmp}" && mv -f "${tmp}" "${file}"
        else
            [ -n "$(tail -c1 "${file}")" ] && printf '\n' >> "${file}"
            printf '\t<property name="%s"\t\t\t\tvalue="%s"/>\n' "${name}" "${literal}" >> "${file}"
        fi
    fi
}

# xmlprop_get <file> <property name>
#   The stored value, still XML-escaped. Callers only ever ask "is this empty",
#   so unescaping it would buy nothing and could mislead.
xmlprop_get() {
    local file="$1" name="$2"
    [ -f "${file}" ] || return 1
    grep -E "^[[:space:]]*<property[[:space:]]+name=\"${name}\"[[:space:]]*value=\"" "${file}" \
        | head -1 \
        | sed -E "s|^[[:space:]]*<property[[:space:]]+name=\"${name}\"[[:space:]]*value=\"||; s|\".*$||"
}

# xmlprop_set_owned <file> <property name> <panel value> [seed]
#   Three-way ownership, the same contract as kv_set_owned in shared/kvconf.sh:
#   the panel wins when its variable is set; when it is empty the FILE wins, and
#   the property is seeded only while it is still empty. Four of the six live
#   7DTD servers had typed a name straight into this file because the panel gave
#   them nowhere else to type it - writing an empty panel field over that would
#   have taken the name off all four.
xmlprop_set_owned() {
    local file="$1" name="$2" panel_value="$3" seed="${4:-}"

    [ -f "${file}" ] || return 1

    panel_value="$(printf '%s' "${panel_value}" | tr -d '\r\n')"

    if [ -n "${panel_value}" ]; then
        xmlprop_set "${file}" "${name}" "${panel_value}"
        return
    fi

    if [ -z "$(xmlprop_get "${file}" "${name}")" ] && [ -n "${seed}" ]; then
        xmlprop_set "${file}" "${name}" "${seed}"
    fi

    return 0
}
