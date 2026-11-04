#!/bin/bash
# Resolves TERRARIA_VERSION for the vanilla core.
#
# terraria.org serves the dedicated server as terraria-server-<NNNN>.zip and has
# no "latest" link, so a default that is a literal number goes stale at the next
# game patch and every new server then refuses clients on the current version.
# "latest" (or an empty value) is resolved by probing upward from the version
# known to exist; any other value is an explicit pin and is returned untouched.
#
# Network trouble is not allowed to block a start: when terraria.org does not
# answer, the version already installed in the server directory is kept, and
# without one the floor below is used.
#
# Sourced by start-terraria. Tests stub `curl` with a shell function.

TERRARIA_VERSION_FLOOR="${TERRARIA_VERSION_FLOOR:-1456}"
TERRARIA_PROBE_AHEAD="${TERRARIA_PROBE_AHEAD:-6}"
TERRARIA_PROBE_TIMEOUT="${TERRARIA_PROBE_TIMEOUT:-6}"
TERRARIA_DOWNLOAD_BASE="${TERRARIA_DOWNLOAD_BASE:-https://terraria.org/api/download/pc-dedicated-server}"

# HTTP status of the archive for a version; 000 when the host is unreachable.
terraria_probe_version() { # <version>
    local code
    code="$(curl -s -o /dev/null -I -m "${TERRARIA_PROBE_TIMEOUT}" -w '%{http_code}' \
        "${TERRARIA_DOWNLOAD_BASE}/terraria-server-${1}.zip" 2>/dev/null)" || true
    printf '%s' "${code:-000}"
}

# The version recorded by the installer's .terraria-<NNNN> marker, if the
# server binary is really there.
terraria_installed_version() { # <server root>
    local root="$1" marker
    [ -f "${root}/TerrariaServer.bin.x86_64" ] || return 0
    marker="$(find "${root}" -maxdepth 1 -name '.terraria-[0-9]*' 2>/dev/null | sort | tail -n 1)"
    [ -n "${marker}" ] && printf '%s' "${marker##*/.terraria-}"
}

# Next candidates above a known version. Patch numbers are consecutive, but a
# minor or major release skips the tail of the old series (1458 -> 1460,
# 1499 -> 1500), so the start of the next minor and major series are tried too.
terraria_version_candidates() { # <version>
    local v="$1" i
    for ((i = 1; i <= TERRARIA_PROBE_AHEAD; i++)); do
        echo $((v + i))
    done
    echo $(((v / 10 + 1) * 10))
    echo $(((v / 100 + 1) * 100))
}

terraria_latest_version() { # <start version>; prints the newest published one
    local best="$1" found=1 cand code
    while [ "${found}" = "1" ]; do
        found=0
        while read -r cand; do
            [ "${cand}" -gt "${best}" ] || continue
            code="$(terraria_probe_version "${cand}")"
            case "${code}" in
                200) best="${cand}"; found=1 ;;
                404) ;;
                *) printf '%s' "${best}"; return 1 ;;
            esac
        done < <(terraria_version_candidates "${best}")
    done
    printf '%s' "${best}"
}

terraria_resolve_version() { # <requested> <server root>
    local want="${1:-}" root="$2" installed start latest
    case "${want}" in
        ''|latest|LATEST|Latest) ;;
        *) printf '%s' "${want}"; return 0 ;;
    esac

    installed="$(terraria_installed_version "${root}")"
    start="${installed:-${TERRARIA_VERSION_FLOOR}}"
    [ "${start}" -lt "${TERRARIA_VERSION_FLOOR}" ] && start="${TERRARIA_VERSION_FLOOR}"

    if latest="$(terraria_latest_version "${start}")"; then
        printf '%s' "${latest}"
    else
        printf '%s' "${installed:-${TERRARIA_VERSION_FLOOR}}"
    fi
}
