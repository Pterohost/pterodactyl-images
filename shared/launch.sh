#!/bin/bash
# Pterohost launch contract.
#
# Every start-* bootstrap used to own the whole command line, so the panel's
# startup field read "start-gmod" and nothing else. An owner asking "what is my
# server actually running with?" had no answer, and the variables they *could*
# edit had no visible connection to the flags they produced.
#
# The contract below moves the command line back into the egg, where the panel
# renders it with the values filled in, while the image keeps the parts a static
# string cannot express. Five rules, identical for every image:
#
#   1. PASS-THROUGH. Whatever reaches the bootstrap as "$@" is the command. It
#      is not reordered and not rewritten. Writing "start-gmod ./srcds_run ..."
#      in the panel behaves exactly like running ./srcds_run by hand.
#
#   2. PRUNE. A flag whose value came out empty is dropped together with that
#      value. This is what lets optional settings live in the visible line:
#      +host_workshop_collection "{{WORKSHOP_ID}}" simply disappears when the
#      variable is unset, instead of handing srcds a stray flag.
#
#      The quotes in the egg line are load-bearing. shared/entrypoint.sh eval's
#      the startup string, so an unquoted empty ${WORKSHOP_ID} vanishes during
#      word splitting and the flag swallows whatever argument follows it. Quoted,
#      it arrives as an explicit empty argument that this helper can see.
#
#   3. APPEND-IF-ABSENT. The image adds only what it computes (thread counts,
#      binary selection) or what a flag/value pair cannot carry (boolean
#      switches, secrets) - and only when that flag is not already in the line.
#      An explicit "-threads 4" from the panel always wins.
#
#   4. LEGACY FALLBACK. No arguments means an un-migrated server: the bootstrap
#      builds the command the old way. Image rollout and panel migration are
#      therefore independent, and a hand-edited startup never gets stranded.
#
#   5. LOG. pterohost_log_cmd prints the final command, so what the image added
#      on top of the panel line is visible on every boot.
#
# The command being assembled lives in the PTEROHOST_ARGS array, element 0 being
# the binary.

# steam-update.sh defines this too; images that do not source it still get logs.
if ! declare -F pterohost_log >/dev/null 2>&1; then
    pterohost_log() { printf '\033[0;36m[pterohost]\033[0m %s\n' "$*"; }
fi

# The assembled command. Element 0 is the binary.
PTEROHOST_ARGS=()

# Set to 1 when the command came from the panel, 0 on the legacy path.
PTEROHOST_FROM_PANEL=0

# pterohost_has_flag <key> [args...]
#   Is <key> already present? Matches both "-x" / "+x" and the "-x=value" form
#   Unreal servers use, so callers pass the bare flag name either way.
pterohost_has_flag() {
    local key="$1"
    shift

    local arg
    for arg in "$@"; do
        [ "${arg}" = "${key}" ] && return 0
        case "${arg}" in
            "${key}="*) return 0 ;;
        esac
    done

    return 1
}

# pterohost_prune_empty_args <args...>
#   Rule 2. Writes the surviving arguments to PTEROHOST_ARGS.
pterohost_prune_empty_args() {
    local args=("$@")
    local count=$#
    local index=0

    PTEROHOST_ARGS=()

    while [ "${index}" -lt "${count}" ]; do
        local current="${args[${index}]}"

        # "-queryport=" - Unreal style, value expanded to nothing.
        case "${current}" in
            -*= | +*=)
                pterohost_log "Dropping ${current} - no value set."
                index=$((index + 1))
                continue
                ;;
        esac

        # "+map" followed by an explicitly empty argument.
        if [ $((index + 1)) -lt "${count}" ] && [ -z "${args[$((index + 1))]}" ]; then
            case "${current}" in
                -* | +*)
                    pterohost_log "Dropping ${current} - no value set."
                    index=$((index + 2))
                    continue
                    ;;
            esac
        fi

        # A leftover empty argument means the flag it belonged to was already
        # dropped, or the egg quoted something that resolved to nothing. Either
        # way passing "" on to the server is never what was meant.
        if [ -z "${current}" ]; then
            index=$((index + 1))
            continue
        fi

        PTEROHOST_ARGS+=("${current}")
        index=$((index + 1))
    done
}

# pterohost_prune_valueless_flags <keys...>
#   Rule 2, for images running behind an entrypoint that destroys quoting.
#
#   The upstream Pterodactyl entrypoint resolves STARTUP with
#   `eval echo $(...)` before eval'ing the result, which flattens the string and
#   loses the quotes around it. An empty "{{WORKSHOP_ID}}" therefore does not
#   arrive as an empty argument at all - it disappears, and its flag is left
#   dangling in front of whatever comes next, which srcds then reads as the
#   value. Our own shared/entrypoint.sh does not do this, so images on it are
#   already covered by pterohost_prune_empty_args.
#
#   Drops each listed flag when it is last or is followed by another flag. The
#   "looks like a flag" test requires a letter after the -/+, so a negative
#   number stays a value.
pterohost_prune_valueless_flags() {
    local keys=" $* "
    local kept=()
    local count=${#PTEROHOST_ARGS[@]}
    local index=0

    while [ "${index}" -lt "${count}" ]; do
        local current="${PTEROHOST_ARGS[${index}]}"
        local next=""
        [ $((index + 1)) -lt "${count}" ] && next="${PTEROHOST_ARGS[$((index + 1))]}"

        case "${keys}" in
            *" ${current} "*)
                case "${next}" in
                    "" | -[A-Za-z]* | +[A-Za-z]*)
                        pterohost_log "Dropping ${current} - no value set."
                        index=$((index + 1))
                        continue
                        ;;
                esac
                ;;
        esac

        kept+=("${current}")
        index=$((index + 1))
    done

    PTEROHOST_ARGS=("${kept[@]}")
}

# pterohost_panel_argv "$@"
#   Rules 1 and 4. Call it with the bootstrap's own arguments; check
#   PTEROHOST_FROM_PANEL afterwards to decide whether the legacy command needs
#   building.
pterohost_panel_argv() {
    if [ "$#" -gt 0 ]; then
        PTEROHOST_FROM_PANEL=1
        pterohost_prune_empty_args "$@"
    else
        PTEROHOST_FROM_PANEL=0
        PTEROHOST_ARGS=()
    fi
}

# pterohost_append_if_absent <key> <args...>
#   Rule 3. Appends <args...> to the command unless <key> is already there.
pterohost_append_if_absent() {
    local key="$1"
    shift

    pterohost_has_flag "${key}" "${PTEROHOST_ARGS[@]}" && return 0

    PTEROHOST_ARGS+=("$@")
}

# Flags whose value is a credential. The whole point of appending these in the
# image rather than writing them into the egg's startup string is that they stay
# out of sight - printing the resolved command then handed them straight back to
# the console, where the server log and every screenshot a customer sends to
# support carries the RCON password and the GSLT.
PTEROHOST_SECRET_FLAGS="${PTEROHOST_SECRET_FLAGS:-+rcon_password +sv_setsteamaccount +rcon.password -adminpassword -serverpassword -password +sv_password +sv_downloadurl_password -userToken -password -username}"

# pterohost_is_secret_flag <flag>
pterohost_is_secret_flag() {
    case " ${PTEROHOST_SECRET_FLAGS} " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# pterohost_log_cmd <binary> <args...>
#   Rule 5. Print the fully resolved launch command into the panel console, so
#   what the image appended on top of the startup string is never a mystery -
#   with credential values replaced by a placeholder.
pterohost_log_cmd() {
    local binary="$1"; shift
    local arg previous="" head

    printf '\033[0;36m[pterohost]\033[0m Launch command:\n'
    printf '  \033[1m%s\033[0m' "${binary}"

    for arg in "$@"; do
        if [ -n "${previous}" ] && pterohost_is_secret_flag "${previous}"; then
            printf ' %s' '<hidden>'
            previous="${arg}"
            continue
        fi

        # "-adminpassword=secret" - the value rides on the flag itself.
        case "${arg}" in
            -*=*|+*=*)
                head="${arg%%=*}"
                if pterohost_is_secret_flag "${head}"; then
                    printf ' %s=%s' "${head}" '<hidden>'
                    previous="${arg}"
                    continue
                fi
                ;;
        esac

        printf ' %s' "${arg}"
        previous="${arg}"
    done

    printf '\n'
    printf '\033[2m  Add your own flags with the ADDITIONAL_ARGS variable in the server settings.\033[0m\n'
}

# pterohost_swap_binary <expected> <replacement>
#   The one deliberate exception to rule 1. The egg line names a stable binary
#   (./srcds_run), but the image may have installed a different one for the
#   selected branch (./srcds_run_x64). Swapping element 0 keeps the visible line
#   readable without silently running the wrong build; the swap is logged.
pterohost_swap_binary() {
    local expected="$1" replacement="$2"

    [ "${#PTEROHOST_ARGS[@]}" -gt 0 ] || return 0
    [ "${PTEROHOST_ARGS[0]}" = "${expected}" ] || return 0
    [ "${expected}" = "${replacement}" ] && return 0

    PTEROHOST_ARGS[0]="${replacement}"
    pterohost_log "Using ${replacement} instead of ${expected} for the selected branch."
}
