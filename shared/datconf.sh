#!/bin/bash
# Pterohost shared helper for Unturned's Commands.dat.
#
# The format is one console command per line, the value bare and unquoted for
# the rest of the line:
#
#     Name Sky Way Unturned | Full Vanilla
#     Port 16684
#     Map Russia Tespy
#
# No existing helper fits: kvconf is key=value, cfgconf is `key = value;`, and
# cvarconf quotes the value, which Unturned would take literally.
#
# WHY THIS FILE MATTERS MORE THAN IT LOOKS. Unturned executes Commands.dat
# AFTER the command line, and last write wins - so every -name, -port and -map
# the panel puts on the launch line is silently overridden by whatever is in
# here. On the fleet that made the panel's Name field cosmetic on three of seven
# servers (their owners had edited the file over SFTP and the panel went on
# showing something else), and on one server a `Port 27015` line moved the game
# off the allocation the node forwards, so it had been unreachable since
# 2026-08-02. The panel has to write this file or it does not really own any of
# these settings.
#
# Two things kvconf.sh does not have to deal with:
#
#   - The command token is matched case-insensitively, because Unturned honours
#     `name`, `Name` and `NAME` alike and owners use all three. Matching
#     case-sensitively would append a second line and leave the file with two
#     contradictory names in it - which is worse than not writing at all,
#     because this is a file owners read in the panel's own config editor.
#   - CR is stripped on read as well as write. These files are edited over SFTP
#     from Windows, and a trailing \r would otherwise turn "is this key already
#     set" into a false answer.
#
# What the panel must NOT write here is the map. Unturned files a world under
# Servers/<instance>/Level/<map>/, so making the panel authoritative for Map
# would orphan the owner's world and generate a fresh empty one - the same trap
# shared/identity.sh exists to close for Zomboid, Rust and Valheim.

# dat_set <file> <command> <value>
dat_set() {
    local file="$1" key="$2" value="$3"

    [ -f "${file}" ] || return 1

    value="$(printf '%s' "${value}" | tr -d '\r\n')"

    local escaped
    escaped="$(printf '%s' "${value}" | sed -e 's/[&|\\]/\\&/g')"

    if grep -qiE "^[[:space:]]*${key}([[:space:]]|$)" "${file}"; then
        sed -i -E "s|^[[:space:]]*${key}([[:space:]].*)?$|${key} ${escaped}|I" "${file}"
    else
        [ -n "$(tail -c1 "${file}")" ] && printf '\n' >> "${file}"
        printf '%s %s\n' "${key}" "${value}" >> "${file}"
    fi
}

# dat_get <file> <command>
dat_get() {
    local file="$1" key="$2"
    [ -f "${file}" ] || return 1
    grep -iE "^[[:space:]]*${key}[[:space:]]" "${file}" \
        | head -1 \
        | sed -E "s|^[[:space:]]*${key}[[:space:]]+||I" \
        | tr -d '\r\n'
}

# dat_set_owned <file> <command> <panel value> [seed]
#   Three-way ownership, the same contract as kv_set_owned in shared/kvconf.sh.
#   The second half is what protects the owners who had already typed a name in
#   here because the panel field did not work.
dat_set_owned() {
    local file="$1" key="$2" panel_value="$3" seed="${4:-}"

    [ -f "${file}" ] || return 1

    panel_value="$(printf '%s' "${panel_value}" | tr -d '\r\n')"

    if [ -n "${panel_value}" ]; then
        dat_set "${file}" "${key}" "${panel_value}"
        return
    fi

    if [ -z "$(dat_get "${file}" "${key}")" ] && [ -n "${seed}" ]; then
        dat_set "${file}" "${key}" "${seed}"
    fi

    return 0
}

# dat_backup_once <file>
dat_backup_once() {
    local file="$1"
    [ -f "${file}" ] || return 0
    [ -f "${file}.pterohost-orig" ] && return 0
    cp -a "${file}" "${file}.pterohost-orig" 2>/dev/null || true
}
