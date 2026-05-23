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

# Pterodactyl passes STARTUP with {{VAR}} placeholders that map to ${VAR}.
# shellcheck disable=SC2086
MODIFIED_STARTUP=$(echo -e "${STARTUP:-}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

CYAN=$'\033[0;36m'
RESET=$'\033[0m'
printf '%bSTARTUP%b /home/container: %s\n' "${CYAN}" "${RESET}" "${MODIFIED_STARTUP}"

# Hand PID 1 over to the server process so signals propagate cleanly.
# shellcheck disable=SC2086
exec ${MODIFIED_STARTUP}
