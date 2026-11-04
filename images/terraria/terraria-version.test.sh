#!/bin/bash
# Contract tests for images/terraria/terraria-version.sh.
#
# curl is replaced by a shell function that answers from a table of published
# versions, so nothing here touches terraria.org. What is asserted: "latest"
# and an empty value climb to the newest published number (across a skipped
# patch and across a minor series), a number is a pin that is never probed,
# and a dead network leaves the installed version - or the floor - in place.
#
# Run: bash images/terraria/terraria-version.test.sh
# Wired into the `test` job in .github/workflows/build.yml.

set -u

. "$(dirname -- "$0")/terraria-version.sh"

PASS=0
FAIL=0
SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

PUBLISHED=" 1456 1457 1458 "
NETWORK=up
PROBES=0

curl() {
    local url="" arg
    for arg in "$@"; do url="${arg}"; done
    PROBES=$((PROBES + 1))
    if [ "${NETWORK}" = "down" ]; then printf '000'; return 6; fi
    local v="${url##*terraria-server-}"
    v="${v%.zip}"
    case "${PUBLISHED}" in
        *" ${v} "*) printf '200' ;;
        *) printf '404' ;;
    esac
}

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    fi
}

fresh() { rm -rf "${SANDBOX}/root"; mkdir -p "${SANDBOX}/root"; echo "${SANDBOX}/root"; }
install_marker() { # <root> <version>
    touch "$1/TerrariaServer.bin.x86_64" "$1/.terraria-$2"
}

R="$(fresh)"
check "latest climbs to the newest" "1458" "$(terraria_resolve_version latest "$R")"
check "empty value behaves as latest" "1458" "$(terraria_resolve_version "" "$R")"

PROBES=0
check "explicit number is returned as is" "1455" "$(terraria_resolve_version 1455 "$R")"
terraria_resolve_version 1455 "$R" >/dev/null
check "explicit number is not probed" "0" "${PROBES}"

R="$(fresh)"; install_marker "$R" 1457
check "starts from the installed version" "1458" "$(terraria_resolve_version latest "$R")"

R="$(fresh)"; install_marker "$R" 1458
PUBLISHED=" 1456 1457 1458 "
check "already newest stays" "1458" "$(terraria_resolve_version latest "$R")"

PUBLISHED=" 1456 1457 1458 1460 "
R="$(fresh)"
check "skipped patch number is crossed" "1460" "$(terraria_resolve_version latest "$R")"

PUBLISHED=" 1456 1457 1458 1459 1460 1461 "
check "several releases in a row" "1461" "$(terraria_resolve_version latest "$R")"

PUBLISHED=" 1456 1457 1458 1500 "
check "new major series is found" "1500" "$(terraria_resolve_version latest "$R")"

PUBLISHED=" 1456 1457 1458 "
R="$(fresh)"; touch "$R/.terraria-1458"
NETWORK=down
check "marker without binary is ignored, floor used offline" "1456" "$(terraria_resolve_version latest "$R")"

R="$(fresh)"; install_marker "$R" 1458
check "offline keeps the installed version" "1458" "$(terraria_resolve_version latest "$R")"
check "offline does not break a pin" "1457" "$(terraria_resolve_version 1457 "$R")"

R="$(fresh)"; install_marker "$R" 1450
check "offline keeps even an installed version below the floor" "1450" "$(terraria_resolve_version latest "$R")"
NETWORK=up
check "online below the floor still reaches newest" "1458" "$(terraria_resolve_version latest "$R")"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
