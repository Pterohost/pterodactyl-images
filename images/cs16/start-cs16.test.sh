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

# A stand-in for the published Metamod-P release layout: the archive root is
# addons/metamod/dlls/, and the module is metamod.so.
make_metamod_archive() { # <path>
    local build="${SANDBOX}/mmbuild"
    rm -rf "${build}"
    mkdir -p "${build}/addons/metamod/dlls"
    printf 'ELF-stub metamod\n' > "${build}/addons/metamod/dlls/metamod.so"
    printf 'ELF-stub trace\n'   > "${build}/addons/metamod/dlls/trace_mm.so"
    ( cd "${build}" && tar -c . | xz -c > "$1" )
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
MM_ARCHIVE="${SANDBOX}/metamod.tar.xz"
AMXX_TGZ="${SANDBOX}/amxx.tar.gz"

# Lift the shipped functions, retargeting only the container home.
LIFTED="${SANDBOX}/lifted.sh"
: > "${LIFTED}"
for fn in cs16_elf_strings cs16_engine_is_loadable cs16_set_gamedll cs16_metamod_so cs16_install_metamod cs16_amxx_register cs16_install_amxx; do
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
MM_URL="https://example.invalid/metamod-p-v1.21p109-linux_ubuntu1804.tar.xz"

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
        *metamod.tar.xz) cp "${MM_ARCHIVE}" "${out}" ;;
        *amxx-*.tar.gz) cp "${AMXX_TGZ}" "${out}" ;;
        *) return 22 ;;
    esac
}

cs16_github_asset() { [ "${CURL_FAILS}" = "1" ] && return 0; printf '%s' "${MM_URL}"; }

make_metamod_archive "${MM_ARCHIVE}"
make_amxx_tarball "${AMXX_TGZ}"

# ------------------------------------------------------------------- tests ---

printf 'images/cs16/start-cs16\n'

# 1. The regression itself: the real archive layout must not end up nested, and
#    liblist.gam must name the module that was actually written.
new_game_dir
CS16_METAMOD_SO=""
INSTALL_METAMOD=1
cs16_install_metamod

if [ -f "${GAME}/addons/metamod/dlls/metamod.so" ]; then
    ok "metamod module lands at addons/metamod/dlls/metamod.so"
else
    fail "metamod module is not at addons/metamod/dlls/metamod.so"
fi
if [ -e "${GAME}/addons/metamod/addons" ]; then
    fail "archive was unpacked into itself: addons/metamod/addons/ exists"
else
    ok "no nested addons/metamod/addons/ tree"
fi
assert_eq "liblist.gam names the module that was written" \
    "addons/metamod/dlls/metamod.so" "$(gamedll_linux)"
assert_eq "CS16_METAMOD_SO is set for the AMXX gate" \
    "${GAME}/addons/metamod/dlls/metamod.so" "${CS16_METAMOD_SO}"
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
sed -i 's|^gamedll_linux.*|gamedll_linux "addons/metamod/dlls/metamod.so"|' "${GAME}/liblist.gam"
CS16_METAMOD_SO=""
INSTALL_METAMOD=0
cs16_install_metamod
assert_eq "INSTALL_METAMOD=0 restores the stock game library" \
    "dlls/cs.so" "$(gamedll_linux)"
assert_gamedll_resolves "metamod turned off"

# 7. The ReHLDS guard: an engine whose Steam symbol the shipped libsteam_api.so
#    cannot satisfy must be rejected, or hlds dies inside dlopen with
#    "Unable to load engine, image is corrupt" before printing anything.
mk_elf() { # <path> <NUL-separated symbol names...>
    local out="$1"; shift
    : > "${out}"
    for sym in "$@"; do printf '%s\0' "${sym}" >> "${out}"; done
}
# The real depot library: exports the Safe/Internal variants, NOT the plain one.
mk_elf "${SANDBOX}/libsteam_api.so" SteamInternal_GameServer_Init SteamGameServer_InitSafe SteamAPI_Init
mk_elf "${SANDBOX}/rehlds_engine.so" SteamGameServer_Init SteamAPI_Init
mk_elf "${SANDBOX}/stock_engine.so"  SteamGameServer_InitSafe SteamAPI_Init

if cs16_engine_is_loadable "${SANDBOX}/rehlds_engine.so"; then
    fail "ReHLDS engine accepted although libsteam_api.so lacks SteamGameServer_Init"
else
    ok "ReHLDS engine rejected when libsteam_api.so cannot satisfy it"
fi
if cs16_engine_is_loadable "${SANDBOX}/stock_engine.so"; then
    ok "stock engine accepted"
else
    fail "stock engine wrongly rejected"
fi
# The substring trap: SteamGameServer_InitSafe must not be read as a match for
# SteamGameServer_Init. If it were, the broken engine would sail through.
mk_elf "${SANDBOX}/libsteam_api.so" SteamGameServer_InitSafe
if cs16_engine_is_loadable "${SANDBOX}/rehlds_engine.so"; then
    fail "SteamGameServer_InitSafe was accepted as SteamGameServer_Init"
else
    ok "InitSafe is not mistaken for Init"
fi

if [ "${FAILED}" -ne 0 ]; then
    printf '\nFAILED\n'
    exit 1
fi
printf '\nall good\n'
