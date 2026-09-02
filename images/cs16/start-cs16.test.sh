#!/bin/bash
# Contract tests for images/cs16/start-cs16: the mod-install path and the one
# file it writes, cstrike/liblist.gam.
#
# liblist.gam names the shared object the GoldSrc engine loads as the game
# library. Naming a file that is not there is not a degraded server - hlds
# prints
#     Host_Error: Couldn't get DLL API from !
# and exits 255, and because the bad line is written to the customer's volume it
# survives every restart after that. The server can never come back on its own.
#
# That is not hypothetical. Server 4429, 2026-09-02, the first CS 1.6 customer
# on the fleet: the bootstrap unpacked the Metamod release into
# cstrike/addons/metamod/, but the release zip already carries an addons/metamod/
# prefix and names its module metamod_i386.so - so the module landed at
# cstrike/addons/metamod/addons/metamod/metamod_i386.so while liblist.gam was
# pointed, unconditionally, at addons/metamod/metamod.so. Five crash captures in
# nine minutes, and a server that could not be recovered by restarting it.
#
# So the property asserted here is not "the download ran" but the invariant that
# would have caught it: **whatever path gamedll_linux names, that file exists on
# disk** - checked after every scenario, including the ones where the download
# fails.
#
# The functions are lifted out of the shipped script by marker so the tests
# cover the code that ships rather than a restatement of it. The single edit
# made to the lifted text is /home/container -> the sandbox: these functions
# hardcode the container's home, and the path prefix is not what is under test.
#
# Run: bash images/cs16/start-cs16.test.sh
# Wired into the `test` job in .github/workflows/build.yml.

set -u

SCRIPT="$(dirname -- "$0")/start-cs16"
FAILED=0
SANDBOX=""

cleanup() { [ -n "${SANDBOX}" ] && rm -rf "${SANDBOX}"; return 0; }
trap cleanup EXIT

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }

gamedll_linux() { # -> the path liblist.gam currently names
    grep '^gamedll_linux' "${GAME}/liblist.gam" | cut -d'"' -f2
}

# The invariant the outage violated. Every scenario ends with this.
assert_gamedll_resolves() { # <scenario>
    local target
    target="$(gamedll_linux)"
    if [ -z "${target}" ]; then
        fail "$1: liblist.gam has no gamedll_linux line at all"
    elif [ -f "${GAME}/${target}" ]; then
        ok "$1: gamedll_linux -> ${target}, and that file exists"
    else
        fail "$1: gamedll_linux -> ${target}, which is NOT on disk (this is the 2026-09-02 outage)"
    fi
}

assert_eq() { # <what> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

# ---------------------------------------------------------------- fixtures ---

# A byte-for-byte stand-in for the published metamod-r release layout: the zip
# root is addons/metamod/, and the module is metamod_i386.so.
make_metamod_zip() { # <path>
    local build="${SANDBOX}/mmbuild"
    rm -rf "${build}"
    mkdir -p "${build}/addons/metamod"
    printf 'ELF-stub metamod\n' > "${build}/addons/metamod/metamod_i386.so"
    printf 'stub config\n'      > "${build}/addons/metamod/config.ini"
    mkdir -p "${build}/example_plugin"
    printf 'int main(){}\n'     > "${build}/example_plugin/meta_api.cpp"
    ( cd "${build}" && zip -qr "$1" . )
    rm -rf "${build}"
}

# AMX Mod X ships addons/amxmodx/... at the tar root, which is why the existing
# `tar -C <gamedir>` target was always right; only the URL was not.
make_amxx_tarball() { # <path>
    local build="${SANDBOX}/axbuild"
    rm -rf "${build}"
    mkdir -p "${build}/addons/amxmodx/dlls" "${build}/addons/amxmodx/plugins"
    printf 'ELF-stub amxx\n' > "${build}/addons/amxmodx/dlls/amxmodx_mm_i386.so"
    printf 'stub plugin\n'   > "${build}/addons/amxmodx/plugins/admin.amxx"
    tar -czf "$1" -C "${build}" .
    rm -rf "${build}"
}

# A fresh, correctly installed CS 1.6 volume as SteamCMD leaves it.
new_game_dir() {
    rm -rf "${GAME}"
    mkdir -p "${GAME}/dlls"
    printf 'ELF-stub cs.so\n' > "${GAME}/dlls/cs.so"
    cat > "${GAME}/liblist.gam" <<'LIBLIST'
game "Counter-Strike"
gamedll "dlls\mp.dll"
gamedll_linux "dlls/cs.so"
gamedll_osx "dlls/cs.dylib"
LIBLIST
}

# ------------------------------------------------------------------ harness ---

SANDBOX="$(mktemp -d)"
GAME="${SANDBOX}/cstrike"
MM_ZIP="${SANDBOX}/metamod.zip"
AMXX_TGZ="${SANDBOX}/amxx.tar.gz"

# Lift the shipped functions, retargeting only the container home.
LIFTED="${SANDBOX}/lifted.sh"
: > "${LIFTED}"
for fn in cs16_set_gamedll cs16_metamod_so cs16_install_metamod cs16_amxx_register cs16_install_amxx; do
    if ! sed -n "/^${fn}() {/,/^}$/p" "${SCRIPT}" | grep -q .; then
        printf 'FATAL: could not lift %s out of %s\n' "${fn}" "${SCRIPT}"
        exit 1
    fi
    sed -n "/^${fn}() {/,/^}$/p" "${SCRIPT}" >> "${LIFTED}"
done
sed -i "s#/home/container#${SANDBOX}#g" "${LIFTED}"
# shellcheck source=/dev/null
. "${LIFTED}"

HLDS_GAME="cstrike"
pterohost_log() { printf '    [log] %s\n' "$*"; }

CURL_CALLS=0
CURL_FAILS=0
MM_URL="https://example.invalid/metamod-bin-1.3.0.149.zip"

# Stand-in for the network. Serves the fixture matching the requested output
# file; CURL_FAILS=1 turns every fetch into curl's exit 22 (HTTP 4xx/5xx).
curl() {
    local out=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -o) out="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    CURL_CALLS=$((CURL_CALLS + 1))
    [ "${CURL_FAILS}" = "1" ] && return 22
    case "${out}" in
        *metamod.zip) cp "${MM_ZIP}" "${out}" ;;
        *amxx-*.tar.gz) cp "${AMXX_TGZ}" "${out}" ;;
        *) return 22 ;;
    esac
}

cs16_github_asset() { [ "${CURL_FAILS}" = "1" ] && return 0; printf '%s' "${MM_URL}"; }

make_metamod_zip "${MM_ZIP}"
make_amxx_tarball "${AMXX_TGZ}"

# ------------------------------------------------------------------- tests ---

printf 'images/cs16/start-cs16\n'

# 1. The regression itself: the real archive layout must not end up nested, and
#    liblist.gam must name the module that was actually written.
new_game_dir
CS16_METAMOD_SO=""
INSTALL_METAMOD=1
cs16_install_metamod

if [ -f "${GAME}/addons/metamod/metamod_i386.so" ]; then
    ok "metamod module lands at addons/metamod/metamod_i386.so"
else
    fail "metamod module is not at addons/metamod/metamod_i386.so"
fi
if [ -e "${GAME}/addons/metamod/addons" ]; then
    fail "archive was unpacked into itself: addons/metamod/addons/ exists"
else
    ok "no nested addons/metamod/addons/ tree"
fi
assert_eq "liblist.gam names the module that was written" \
    "addons/metamod/metamod_i386.so" "$(gamedll_linux)"
assert_eq "config.ini came across too" "stub config" "$(cat "${GAME}/addons/metamod/config.ini" 2>/dev/null)"
assert_eq "CS16_METAMOD_SO is set for the AMXX gate" \
    "${GAME}/addons/metamod/metamod_i386.so" "${CS16_METAMOD_SO}"
assert_gamedll_resolves "metamod installed"

# 2. Second start must not re-download and must not disturb the layout.
before="${CURL_CALLS}"
CS16_METAMOD_SO=""
cs16_install_metamod
assert_eq "second start does not re-download Metamod" "${before}" "${CURL_CALLS}"
[ -e "${GAME}/addons/metamod/addons" ] && fail "second start nested the tree" || ok "second start leaves the layout alone"
assert_gamedll_resolves "metamod, second start"

# 3. AMX Mod X on top of a working Metamod.
INSTALL_AMXX=1
cs16_install_amxx
if [ -f "${GAME}/addons/amxmodx/dlls/amxmodx_mm_i386.so" ]; then
    ok "amxmodx_mm_i386.so installed"
else
    fail "amxmodx_mm_i386.so missing"
fi
cs16_install_amxx   # idempotency
assert_eq "plugins.ini registers the AMXX module exactly once" \
    "1" "$(grep -c 'amxmodx_mm_i386.so' "${GAME}/addons/metamod/plugins.ini")"
assert_gamedll_resolves "metamod + amxx"

# 4. The download fails. This is the case that must NOT poison liblist.gam.
new_game_dir
CS16_METAMOD_SO=""
INSTALL_METAMOD=1
CURL_FAILS=1
cs16_install_metamod
rc=$?
assert_eq "a failed Metamod install reports failure" "1" "${rc}"
assert_eq "a failed Metamod install leaves the stock game library" \
    "dlls/cs.so" "$(gamedll_linux)"
assert_gamedll_resolves "metamod download failed"

# 5. AMXX must not pretend to be installed when Metamod is not there.
INSTALL_AMXX=1
cs16_install_amxx
if [ -e "${GAME}/addons/metamod/plugins.ini" ]; then
    fail "AMXX registered itself with a Metamod that is not installed"
else
    ok "AMXX skipped when Metamod is absent"
fi
CURL_FAILS=0

# 6. Turning Metamod off must un-poison a volume that had it on.
new_game_dir
sed -i 's|^gamedll_linux.*|gamedll_linux "addons/metamod/metamod_i386.so"|' "${GAME}/liblist.gam"
CS16_METAMOD_SO=""
INSTALL_METAMOD=0
cs16_install_metamod
assert_eq "INSTALL_METAMOD=0 restores the stock game library" \
    "dlls/cs.so" "$(gamedll_linux)"
assert_gamedll_resolves "metamod turned off"

if [ "${FAILED}" -ne 0 ]; then
    printf '\nFAILED\n'
    exit 1
fi
printf '\nall good\n'
