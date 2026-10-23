#!/bin/bash
# Pterohost persistent server log ("RPT") with rotation.
#
# On Linux the Bohemia engine writes its RPT - script errors, mod warnings, the
# "Server load" lines - to stdout and nowhere else. stdout reaches the panel
# console and Docker's log, and Wings keeps that log at 5 MB in a single file
# and throws it away with the container on every start. So the history of a
# server that stutters in the evening and restarts at 05:00 was gone by morning:
# ticket 4626 (Arma 3, FPS collapses) could not be diagnosed because not one
# line of the sessions in question survived anywhere.
#
# This copies the stream into the server volume, where the owner and support
# can read it with the file manager:
#
#   <dir>/<prefix>-current.log              the run in progress, written line by line
#   <dir>/<prefix>-YYYYmmdd-HHMMSS.log.gz   finished runs and full segments
#
# The current file is archived at every start and whenever it reaches
# RPT_LOG_MAX_MB; RPT_LOG_KEEP archives are kept, the oldest go first. The cap
# is per file, so the volume never holds more than MAX_MB plus KEEP compressed
# segments of this log. Every file starts with a marker line carrying the full
# date, which the RPT itself (hh:mm:ss only) does not.
#
# The copy must never cost the server anything: a full volume or a deleted
# directory stops the copy, not the console and not the game. tee keeps
# feeding the console after its file side fails (--output-error=warn), and the
# file side ignores INT/TERM/HUP so the shutdown lines reach the file too - it
# ends on end-of-file, when the server's output closes.
#
# Variables: RPT_LOG (1 = on, the default; 0 = off), RPT_LOG_MAX_MB (8),
# RPT_LOG_KEEP (12).

PTEROHOST_RPT_LIB="${PTEROHOST_RPT_LIB:-$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")}"

# pterohost_rpt_enabled - true unless RPT_LOG says off.
pterohost_rpt_enabled() {
    case "${RPT_LOG:-1}" in
        0|false|no|off) return 1 ;;
    esac
    return 0
}

# pterohost_rpt_max_bytes / pterohost_rpt_keep - the two limits, defaulted
# when unset or not a positive number.
pterohost_rpt_max_bytes() {
    local mb="${RPT_LOG_MAX_MB:-8}"
    case "${mb}" in ''|*[!0-9]*|0) mb=8 ;; esac
    printf '%s\n' "$((mb * 1048576))"
}

pterohost_rpt_keep() {
    local keep="${RPT_LOG_KEEP:-12}"
    case "${keep}" in ''|*[!0-9]*) keep=12 ;; esac
    printf '%s\n' "${keep}"
}

# pterohost_rpt_prune <dir> <prefix> <keep>
#   Compresses archives left uncompressed (a container stopped mid-gzip) and
#   deletes all but the newest <keep>.
pterohost_rpt_prune() {
    local dir="$1" prefix="$2" keep="$3" old
    for old in "${dir}/${prefix}"-2*.log; do
        [ -f "${old}" ] && gzip -f "${old}" 2>/dev/null
    done
    # shellcheck disable=SC2012
    ls -1t "${dir}/${prefix}"-2*.log.gz 2>/dev/null | tail -n +"$((keep + 1))" | while IFS= read -r old; do
        rm -f "${old}"
    done
    return 0
}

# pterohost_rpt_archive <dir> <prefix>
#   Moves <prefix>-current.log aside under the time of its last write.
pterohost_rpt_archive() {
    local dir="$1" prefix="$2" cur stamp dest n=1
    cur="${dir}/${prefix}-current.log"
    [ -s "${cur}" ] || return 0
    stamp="$(date -r "${cur}" +%Y%m%d-%H%M%S 2>/dev/null || date +%Y%m%d-%H%M%S)"
    dest="${dir}/${prefix}-${stamp}.log"
    while [ -e "${dest}" ] || [ -e "${dest}.gz" ]; do
        dest="${dir}/${prefix}-${stamp}-${n}.log"
        n=$((n + 1))
    done
    mv -f "${cur}" "${dest}"
}

# pterohost_rpt_open <dir> <prefix> <marker>
#   Archives the previous run and starts a fresh current file with the marker.
#   Fails when the directory cannot be written, and the caller then runs the
#   server exactly as it would without this file.
pterohost_rpt_open() {
    local dir="$1" prefix="$2" marker="$3"
    mkdir -p "${dir}" 2>/dev/null || return 1
    pterohost_rpt_archive "${dir}" "${prefix}" || return 1
    pterohost_rpt_prune "${dir}" "${prefix}" "$(pterohost_rpt_keep)"
    printf '### pterohost rpt start %s %s\n' "$(date -Iseconds)" "${marker}" > "${dir}/${prefix}-current.log" 2>/dev/null
}

# pterohost_rpt_roll <dir> <prefix> <keep>
#   Size rotation, called by the writer between two lines: the full file moves
#   aside at once, compression and pruning happen in the background so the
#   stream is never held up.
pterohost_rpt_roll() {
    local dir="$1" prefix="$2" keep="$3"
    pterohost_rpt_archive "${dir}" "${prefix}"
    printf '### pterohost rpt continued %s\n' "$(date -Iseconds)" > "${dir}/${prefix}-current.log" 2>/dev/null
    pterohost_rpt_prune "${dir}" "${prefix}" "${keep}" </dev/null >/dev/null 2>&1 &
    return 0
}

# pterohost_rpt_writer <dir> <prefix>
#   stdin -> <dir>/<prefix>-current.log, flushed per line, rolled at the cap.
pterohost_rpt_writer() {
    local dir="$1" prefix="$2" cur size
    cur="${dir}/${prefix}-current.log"
    size="$(stat -c %s "${cur}" 2>/dev/null || echo 0)"
    awk -v cur="${cur}" -v max="$(pterohost_rpt_max_bytes)" -v size="${size}" \
        -v roll="bash '${PTEROHOST_RPT_LIB}' pterohost_rpt_roll '${dir}' '${prefix}' '$(pterohost_rpt_keep)'" '
        {
            print >> cur
            fflush(cur)
            size += length($0) + 1
            if (size >= max) {
                close(cur)
                system(roll)
                size = 0
            }
        }'
}

# pterohost_rpt_tee <dir> <prefix>
#   stdin -> stdout (the console) and the rotated file.
pterohost_rpt_tee() {
    trap '' INT TERM HUP
    tee --output-error=warn >(pterohost_rpt_writer "$1" "$2")
    wait "$!" 2>/dev/null
    return 0
}

# pterohost_rpt_file <dir> <prefix>
#   stdin -> the rotated file only. If the writer gives up, the rest of the
#   stream is drained, so the process feeding it never sees a broken pipe.
pterohost_rpt_file() {
    trap '' INT TERM HUP
    pterohost_rpt_writer "$1" "$2"
    cat >/dev/null
    return 0
}

# pterohost_rpt_exec <dir> <prefix> <marker> <command...>
#   Replaces the bootstrap's final `exec <command>`. The command stays a direct
#   child in the foreground: same stdin, same process group for tini -g to
#   signal, and its own exit status is what the bootstrap exits with - only its
#   stdout/stderr go through the copy. With RPT_LOG=0, or a directory that
#   cannot be written, it is the plain exec it always was.
#
#   The copy is opened on a descriptor of this shell rather than as a
#   redirection of the command: a `cmd > >(...)` substitution is created inside
#   the forked command and cannot be waited for, and the last lines would race
#   the container's exit.
pterohost_rpt_exec() {
    local dir="$1" prefix="$2" marker="$3" status copy_fd copy_pid
    shift 3
    if pterohost_rpt_enabled && pterohost_rpt_open "${dir}" "${prefix}" "${marker}" \
        && exec {copy_fd}> >(pterohost_rpt_tee "${dir}" "${prefix}"); then
        copy_pid=$!
        "$@" >&"${copy_fd}" 2>&1 {copy_fd}>&-
        status=$?
        exec {copy_fd}>&-
        wait "${copy_pid}" 2>/dev/null
        exit "${status}"
    fi
    exec "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        pterohost_rpt_roll) "$@" ;;
    esac
fi
