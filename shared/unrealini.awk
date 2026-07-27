# Pterohost Unreal ini tuple rewriter.
#
# Palworld keeps every server setting inside one line:
#
#   OptionSettings=(Difficulty=None,ServerName="My server",CrossplayPlatforms=(Steam,Xbox),...)
#
# which is neither a flat key=value file (kvconf.sh) nor an ini section. Two
# properties make a naive rewrite dangerous, and both have already cost us live
# servers:
#
#   1. A value may legitimately contain a comma ("Русский сервер, для мужчин"),
#      so splitting the tuple on commas mangles it. The third-party parser the
#      old egg shipped replaces the text up to the first comma AFTER THE KEY,
#      which appends a duplicate of the tail on every boot until the quotes no
#      longer balance and the game stops reading the settings that follow.
#   2. A value may itself be a tuple (CrossplayPlatforms=(Steam,Xbox,PS5,Mac)).
#
# This program therefore walks the tuple with the KEY as the anchor: a key is
# read, then exactly one value (quoted run, nested tuple, or bare token), then
# everything up to the next top-level comma is discarded. That last rule is what
# repairs an already-corrupted file - the duplicated tails carry no "key=", so
# they are dropped rather than re-parsed.
#
# Usage:
#   awk -v mapfile=overrides.tsv -f unrealini.awk PalWorldSettings.ini
#
# mapfile is TSV: Key<TAB>Value, one per line, value written exactly as it must
# appear in the file (quoted for strings, bare for numbers and booleans).
# Blank lines and lines starting with # are ignored. Keys not present in the
# file are appended; keys present are rewritten in place, preserving order.
#
# Every other line of the ini is passed through untouched.

BEGIN {
    FS = "\t"
    if (mapfile != "") {
        while ((getline line < mapfile) > 0) {
            if (line ~ /^[ \t]*(#|$)/) continue
            tab = index(line, "\t")
            if (tab == 0) continue
            k = substr(line, 1, tab - 1)
            v = substr(line, tab + 1)
            sub(/[ \t\r]+$/, "", v)
            if (k == "") continue
            if (!(k in override)) {
                override_order[++override_count] = k
            }
            override[k] = v
        }
        close(mapfile)
    }
}

/^[ \t]*OptionSettings[ \t]*=[ \t]*\(/ {
    print rebuild($0)
    rewritten = 1
    next
}

{ print }

END {
    if (!rewritten) {
        exit 3
    }
}

function rebuild(line,   open, close_pos, inner, prefix, tail, i, out, key) {
    open = index(line, "(")
    if (open == 0) {
        return line
    }

    prefix = substr(line, 1, open)
    close_pos = lastindex(line, ")")

    if (close_pos > open) {
        inner = substr(line, open + 1, close_pos - open - 1)
        tail = substr(line, close_pos + 1)
    } else {
        # No closing parenthesis at all. Seen in production: the third-party
        # parser wrote a short buffer and cut the tuple mid-value, which makes
        # the whole struct unreadable and silently reverts every setting on the
        # server. Everything up to the cut is still good, so keep it, drop the
        # half-written key (parse() refuses an unterminated value) and close the
        # tuple properly.
        inner = substr(line, open + 1)
        tail = ""
    }

    parse(inner)

    for (i = 1; i <= key_count; i++) {
        key = keys[i]
        if (key in override) {
            value[key] = override[key]
            seen_override[key] = 1
        }
    }

    for (i = 1; i <= override_count; i++) {
        key = override_order[i]
        if (!(key in seen_override)) {
            keys[++key_count] = key
            value[key] = override[key]
            seen_override[key] = 1
        }
    }

    out = ""
    for (i = 1; i <= key_count; i++) {
        out = out (i > 1 ? "," : "") keys[i] "=" value[keys[i]]
    }

    return prefix out ")" tail
}

function parse(inner,   len, i, j, ch, key, val, depth, e, quote_at) {
    key_count = 0
    split("", keys)
    split("", value)

    len = length(inner)
    i = 1

    while (i <= len) {
        ch = substr(inner, i, 1)
        if (ch == "," || ch == " " || ch == "\t") {
            i++
            continue
        }

        j = i
        while (j <= len && substr(inner, j, 1) ~ /[A-Za-z0-9_]/) {
            j++
        }

        if (j > i && j <= len && substr(inner, j, 1) == "=") {
            key = substr(inner, i, j - i)
            i = j + 1
            ch = substr(inner, i, 1)

            if (ch == "\"") {
                quote_at = index(substr(inner, i + 1), "\"")
                if (quote_at == 0) {
                    # Unterminated string: the line was cut here, so the value
                    # is whatever survived the cut. Inventing a closing quote
                    # would write a half URL or half name into the config as if
                    # it were the real one - drop the key and let the game use
                    # its default instead.
                    i = len + 1
                    continue
                }
                val = substr(inner, i, quote_at + 1)
                i = i + quote_at + 1
            } else if (ch == "(") {
                depth = 0
                e = i
                while (e <= len) {
                    ch = substr(inner, e, 1)
                    if (ch == "(") {
                        depth++
                    } else if (ch == ")") {
                        depth--
                        if (depth == 0) break
                    }
                    e++
                }
                val = substr(inner, i, e - i + 1)
                i = e + 1
            } else {
                e = i
                while (e <= len && substr(inner, e, 1) != ",") {
                    e++
                }
                val = substr(inner, i, e - i)
                i = e
            }

            if (!(key in value)) {
                keys[++key_count] = key
            }
            value[key] = val
        }

        while (i <= len && substr(inner, i, 1) != ",") {
            i++
        }
    }
}

function lastindex(s, needle,   i, pos) {
    pos = 0
    for (i = length(s); i >= 1; i--) {
        if (substr(s, i, 1) == needle) {
            return i
        }
    }
    return pos
}
