#!/bin/bash
# Pterohost container entrypoint for Pterodactyl Wings.
# Renders diagnostics, expands ${VAR} tokens in STARTUP, then exec's the server.

set -u
cd /home/container || exit 1

# Diagnostics block (non-fatal).
if [ -x /sysinfo.sh ]; then
    /sysinfo.sh || true
fi

# Expose container IP the same way the official yolks do.
INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
export INTERNAL_IP

# Wings runs the container under the node's own uid (988 on one node, 999 on the
# next), and that uid has no line in the image's /etc/passwd. Every getpwuid()
# call inside the container then returns NULL, which most servers never notice -
# but the Bohemia engine reads pw_dir straight off the result, so DayZ and Arma 3
# die with SIGSEGV at pw_dir's offset (0x20) before writing a single log line.
#
# nss_wrapper answers those lookups out of a file we are allowed to write. It is
# how the upstream yolks have always handled this. Nothing to do when the uid
# does resolve (root, or a node whose uid happens to exist), so the block is a
# no-op everywhere else.
pterohost_setup_nss() {
    local uid gid lib=/usr/lib/x86_64-linux-gnu/libnss_wrapper.so

    uid="$(id -u)"
    gid="$(id -g)"

    getent passwd "${uid}" >/dev/null 2>&1 && return 0

    if [ ! -e "${lib}" ]; then
        printf '\033[0;36m[pterohost]\033[0m WARN: uid %s has no passwd entry and nss_wrapper is not installed.\n' "${uid}"
        return 0
    fi

    {
        cat /etc/passwd 2>/dev/null
        printf 'container:x:%s:%s::/home/container:/bin/bash\n' "${uid}" "${gid}"
    } > /tmp/pterohost-passwd
    {
        cat /etc/group 2>/dev/null
        printf 'container:x:%s:\n' "${gid}"
    } > /tmp/pterohost-group

    export NSS_WRAPPER_PASSWD=/tmp/pterohost-passwd
    export NSS_WRAPPER_GROUP=/tmp/pterohost-group
    # The bare soname rather than the absolute path: SteamCMD is a 32-bit binary
    # and the game servers are 64-bit, and only the loader knows which build of
    # the library a given process needs.
    export LD_PRELOAD="libnss_wrapper.so${LD_PRELOAD:+:${LD_PRELOAD}}"

    printf '\033[0;36m[pterohost]\033[0m uid %s has no passwd entry - resolving user lookups through nss_wrapper.\n' "${uid}"
}

pterohost_setup_nss

# Pterodactyl passes STARTUP with {{VAR}} placeholders that map to ${VAR}.
# shellcheck disable=SC2086
MODIFIED_STARTUP=$(echo -e "${STARTUP:-}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

CYAN=$'\033[0;36m'
RESET=$'\033[0m'
printf '%bSTARTUP%b /home/container: %s\n' "${CYAN}" "${RESET}" "${MODIFIED_STARTUP}"

# eval expands ${VAR} references inside MODIFIED_STARTUP (e.g. ${SERVER_MEMORY}),
# then exec replaces PID 1 so signals propagate cleanly.
#
# set +u first, and only here. A startup line is owner-editable and outlives the
# egg it came from: a container created before a migration, or a line someone
# hand-edited, can still name a variable that no longer exists. The upstream
# entrypoint expands those to nothing; under set -u the container would instead
# die with "CLIENT_MODS: unbound variable" and no server at all. An empty flag is
# recoverable, a container that never starts is not.
set +u
eval "exec ${MODIFIED_STARTUP}"
