#!/bin/bash
# Pterohost shared SteamCMD helper.
#
# Sourced by the per-game start-* bootstraps. Extracted from images/rust/start-rust,
# where the awkward parts were learned the hard way:
#
#   - Wings mounts the container root read-only and runs the container as its own
#     uid, but SteamCMD self-updates into its own directory. So we run it from a
#     writable copy inside the (persistent) server volume, seeded on first boot.
#   - The very first SteamCMD run updates and restarts itself. Doing that in a
#     throwaway pass means the real update starts from a settled binary.
#   - Every network step is non-fatal. A transient Steam/CDN hiccup logs a warning
#     and boots with the files already on disk instead of leaving the server down.

STEAMCMD_SRC="${STEAMCMD_DIR:-/opt/steamcmd}"
# Overridable so the contract tests can point it at a stub instead of the real
# client; in a container it is always the copy inside the server volume.
STEAMCMD_RUN="${STEAMCMD_RUN:-/home/container/.steamcmd}"

pterohost_log() {
    printf '\033[0;36m[pterohost]\033[0m %s\n' "$*"
}

# pterohost_steam_seed
#   Make a writable SteamCMD available inside the volume. Idempotent.
pterohost_steam_seed() {
    if [ ! -x "${STEAMCMD_RUN}/steamcmd.sh" ]; then
        mkdir -p "${STEAMCMD_RUN}"
        cp -a "${STEAMCMD_SRC}/." "${STEAMCMD_RUN}/" 2>/dev/null || true
    fi
    # Without this SteamCMD reports a spurious disk-write error.
    mkdir -p /home/container/steamapps
}

# pterohost_steam_sdk
#   Link the Steam client SDK where Steamworks expects it. Must happen before the
#   game starts or the server never appears in the in-game browser.
pterohost_steam_sdk() {
    mkdir -p "${HOME}/.steam/sdk32" "${HOME}/.steam/sdk64"
    [ -f "${STEAMCMD_RUN}/linux32/steamclient.so" ] \
        && ln -sf "${STEAMCMD_RUN}/linux32/steamclient.so" "${HOME}/.steam/sdk32/steamclient.so"
    [ -f "${STEAMCMD_RUN}/linux64/steamclient.so" ] \
        && ln -sf "${STEAMCMD_RUN}/linux64/steamclient.so" "${HOME}/.steam/sdk64/steamclient.so"
    return 0
}

# pterohost_steam_login_args
#   Most dedicated servers download anonymously. DayZ (223350) and Arma 3
#   (233780) do not - Bohemia gates their server depots behind an account that
#   owns the game, so those eggs carry STEAM_USER/STEAM_PASS. Anything else
#   stays anonymous, which is both simpler and safer.
pterohost_steam_login_args() {
    if [ -n "${STEAM_USER:-}" ] && [ "${STEAM_USER}" != "anonymous" ] && [ -n "${STEAM_PASS:-}" ]; then
        printf '%s\n%s\n%s\n' "+login" "${STEAM_USER}" "${STEAM_PASS}"
    else
        printf '%s\n%s\n' "+login" "anonymous"
    fi
}

# pterohost_steam_update <appid> <branch> <validate> <sentinel>
#   sentinel: a path that must exist for the update to count as successful.
pterohost_steam_update() {
    local appid="$1" branch="${2:-}" validate="${3:-1}" sentinel="$4"
    local attempt=1 max_attempts="${STEAMCMD_ATTEMPTS:-3}"
    local branch_args=() validate_arg=() login_args=() platform_args=()

    pterohost_steam_seed

    # readarray keeps the password intact even if it contains whitespace.
    while IFS= read -r arg; do login_args+=("${arg}"); done < <(pterohost_steam_login_args)

    case "${branch}" in
        public|"") ;;                          # default branch takes no -beta
        *) branch_args=(-beta "${branch}") ;;
    esac
    [ "${validate}" = "1" ] && validate_arg=(validate)

    # STEAMCMD_PLATFORM lets an image pull a depot for an OS other than the one
    # it runs on - the Windows depot under Proton or Wine. Unset means "whatever
    # SteamCMD would pick", i.e. exactly what every Linux-native image already
    # gets, so this is a no-op for them.
    #
    # The flag has to come before +login: SteamCMD applies it to the session,
    # and after the login it is simply ignored - the depot still downloads as
    # Linux and the Windows binary the caller is waiting for never appears.
    [ -n "${STEAMCMD_PLATFORM:-}" ] && platform_args=(+@sSteamCmdForcePlatformType "${STEAMCMD_PLATFORM}")

    pterohost_log "Updating Steam app ${appid}${branch:+ (branch ${branch})}${STEAMCMD_PLATFORM:+ (platform ${STEAMCMD_PLATFORM})} as ${login_args[1]}..."

    # Settle SteamCMD's own self-update first.
    "${STEAMCMD_RUN}/steamcmd.sh" +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +quit >/dev/null 2>&1 || true

    local log_file
    log_file="$(mktemp 2>/dev/null || echo "/tmp/pterohost-steamcmd.$$")"

    while [ "${attempt}" -le "${max_attempts}" ]; do
        pterohost_log "SteamCMD attempt ${attempt}/${max_attempts}..."
        timeout "${STEAMCMD_TIMEOUT:-1800}" "${STEAMCMD_RUN}/steamcmd.sh" \
            +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 \
            "${platform_args[@]}" \
            +force_install_dir /home/container \
            "${login_args[@]}" \
            +app_update "${appid}" "${branch_args[@]}" "${validate_arg[@]}" \
            +quit 2>&1 | tee "${log_file}" || true

        # Ask SteamCMD whether it failed BEFORE looking at the sentinel. The
        # sentinel is only evidence of a successful update on a first install;
        # on every boot after that the file is already in the volume from last
        # time, so a run that downloaded nothing still satisfies it. Checking it
        # first is how six Project Zomboid servers pinned to a branch Valve had
        # deleted printed "SteamCMD update OK." on every single boot while
        # sitting on an old build - and how the branch handling below, which was
        # written for exactly that case, turned out to be unreachable code.
        local failed=0
        grep -qiE "Failed to (install app|set beta)" "${log_file}" 2>/dev/null && failed=1

        if [ "${failed}" -eq 0 ] && [ -e "${sentinel}" ]; then
            pterohost_log "SteamCMD update OK."
            pterohost_steam_sdk
            rm -f "${log_file}"
            return 0
        fi

        # A branch name that does not exist is not a transient failure, and
        # retrying it changes nothing. SteamCMD downloads NOTHING, so a fresh
        # server starts with no binary and exits 127, and an existing one stays
        # on whatever it already had. That is how one paid Project Zomboid
        # server sat dead for five days and another could not get build 42.20:
        # the console said "Starting server..." and nothing explained why it was
        # not. Wording varies by client version - older builds say "Failed to
        # set beta 'x'", current ones fail the install with "(Missing
        # configuration)" - so both are matched.
        if [ -n "${branch}" ] && [ "${failed}" -eq 1 ] \
            && grep -qiE "Failed to set beta|Missing configuration" "${log_file}" 2>/dev/null; then
            pterohost_log "ERROR: Steam has no branch named '${branch}' for app ${appid} - nothing was downloaded."
            pterohost_log "       Check the branch variable in the panel. An empty value means the current stable release, which is what almost every server wants."
            if [ "${STEAM_BRANCH_FALLBACK:-1}" = "1" ]; then
                pterohost_log "       Falling back to the default branch so the server still comes up."
                branch=""
                branch_args=()
                continue
            fi
            break
        fi

        if [ "${failed}" -eq 1 ]; then
            pterohost_log "attempt ${attempt}: SteamCMD reported a failure (see above)."
        else
            pterohost_log "attempt ${attempt} did not produce ${sentinel} (transient?); retrying..."
        fi
        attempt=$((attempt + 1))
        [ "${attempt}" -le "${max_attempts}" ] && sleep "${STEAMCMD_RETRY_SLEEP:-5}"
    done

    rm -f "${log_file}"
    pterohost_log "WARN: ${sentinel} missing after ${max_attempts} attempts - continuing with existing files."
    pterohost_steam_sdk
    return 1
}

# pterohost_log_cmd moved to shared/launch.sh - it belongs with the rest of the
# launch contract, and the classic-shell images carry launch.sh without this
# SteamCMD helper.
