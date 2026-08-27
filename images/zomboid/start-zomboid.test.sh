#!/bin/bash
# Contract tests for images/zomboid/start-zomboid: the animation-path case mirror,
# and the libjsig preload path.
#
# The mirror exists because Build 42 opens the files an AnimSet references
# through a path it has lowercased end to end, while the AnimSet itself was
# found under the name the author wrote. On a case-sensitive filesystem the
# second lookup misses, the AnimSet never parses, and the states it defines are
# absent from the server's action state machine - which reaches the owner as
# players stuck in animations rather than as anything that names a mod.
#
# What is asserted here is the property that actually matters: after a pass, the
# fully lowercased path the engine builds resolves to the real file. Plus the
# three things that made the first attempt at this fix unreliable - it must not
# touch media/lua, it must be idempotent, and it must clear the links a Workshop
# update leaves dangling.
#
# Run: bash images/zomboid/start-zomboid.test.sh
# Wired into the `test` job in .github/workflows/build.yml.

set -u

SCRIPT="$(dirname -- "$0")/start-zomboid"
FAILED=0
SANDBOX=""

cleanup() { [ -n "${SANDBOX}" ] && rm -rf "${SANDBOX}"; }
trap cleanup EXIT

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }

check() { # <description> <path-that-must-exist>
    if [ -e "$2" ]; then ok "$1"; else fail "$1 ($2)"; fi
}
check_absent() { # <description> <path-that-must-not-exist>
    if [ -e "$2" ] || [ -L "$2" ]; then fail "$1 ($2)"; else ok "$1"; fi
}

# The mirror is a block inside the bootstrap rather than a sourceable helper, so
# lift it out and point it at a sandbox. Extracting by marker keeps the test
# honest: it runs the shipped code, not a copy of it.
load_mirror() { # <sandbox root>
    local root="$1"
    sed -n '/^ZOMBOID_WORKSHOP_APPID=/,/^fi$/p' "${SCRIPT}" \
        | sed "s|^ZOMBOID_WORKSHOP_DIR=.*|ZOMBOID_WORKSHOP_DIR=\"${root}/steamapps/workshop/content/\${ZOMBOID_WORKSHOP_APPID}\"|" \
        > "${root}/mirror.sh"
    # shellcheck source=/dev/null
    . "${root}/mirror.sh" >/dev/null
}

log() { :; }

SANDBOX="$(mktemp -d)"
B="${SANDBOX}/steamapps/workshop/content/108600"

# A Build 42 versioned mod, the layout Sapph's Cooking actually ships.
mkdir -p "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/AnimSets/player/actions"
mkdir -p "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/anims_X"
mkdir -p "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/lua/client"
: > "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/AnimSets/player/actions/looped.xml"
: > "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/AnimSets/player/actions/Sapph_CookingWok.xml"
: > "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/anims_X/Bob_Wok.fbx"
: > "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/lua/client/SapphUI.lua"

# common/ layout, and a mod name with spaces and capitals in it.
mkdir -p "${B}/2503622437/mods/Skill Recovery Journal/common/media/AnimSets/Player"
: > "${B}/2503622437/mods/Skill Recovery Journal/common/media/AnimSets/Player/SRJ_Read.xml"

# Legacy layout: media straight in the mod directory.
mkdir -p "${B}/3403870858/mods/Lifestyle/media/anims_X"
: > "${B}/3403870858/mods/Lifestyle/media/anims_X/bob_Yoga.fbx"

# A mod the engine reads case-sensitively in the other direction: it walks
# media/AnimSets with that spelling, so an all-lowercase folder is never seen.
mkdir -p "${B}/9999999999/mods/LowerMod/common/media/animsets/player"
: > "${B}/9999999999/mods/LowerMod/common/media/animsets/player/Thing.xml"

# A mod with no animations at all must be left completely alone.
mkdir -p "${B}/2840889213/mods/Chestown/media/maps/Chestown, KY"
: > "${B}/2840889213/mods/Chestown/media/maps/Chestown, KY/World_17_25.lotpack"

load_mirror "${SANDBOX}"
zomboid_mirror_case >/dev/null

echo "the lowercased path the engine builds resolves"
check "versioned mod, referenced file" \
    "${B}/3409143790/mods/sapphcookingb42/42.20.0/media/animsets/player/actions/looped.xml"
check "versioned mod, the AnimSet itself" \
    "${B}/3409143790/mods/sapphcookingb42/42.20.0/media/animsets/player/actions/sapph_cookingwok.xml"
check "versioned mod, anims_X payload" \
    "${B}/3409143790/mods/sapphcookingb42/42.20.0/media/anims_x/bob_wok.fbx"
check "common/ layout, mod name with spaces" \
    "${B}/2503622437/mods/skill recovery journal/common/media/animsets/player/srj_read.xml"
check "legacy layout" \
    "${B}/3403870858/mods/lifestyle/media/anims_x/bob_yoga.fbx"

echo "the walk finds an all-lowercase folder too"
check "canonical spelling added" "${B}/9999999999/mods/LowerMod/common/media/AnimSets"

echo "scope stays off everything the engine already lowercases itself"
check_absent "no link in media/lua" \
    "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/lua/client/sapphui.lua"
check_absent "no link in media/maps" \
    "${B}/2840889213/mods/Chestown/media/maps/chestown, ky"
check_absent "a mod without animations gets no mod-level alias" \
    "${B}/2840889213/mods/chestown"

echo "second pass changes nothing"
COUNTS="$(zomboid_mirror_case)"
if [ "${COUNTS}" = "0 0" ]; then ok "idempotent"; else fail "idempotent (got '${COUNTS}')"; fi

echo "a Workshop update does not leave the tree half-linked"
rm -rf "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/AnimSets/player/actions"
mkdir -p "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/AnimSets/player/actions"
: > "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/AnimSets/player/actions/looped.xml"
: > "${B}/3409143790/mods/SapphCookingB42/42.20.0/media/AnimSets/player/actions/Sapph_NewDish.xml"
ln -s NoSuchFile.xml "${B}/3403870858/mods/Lifestyle/media/anims_X/ghost.fbx"
zomboid_mirror_case >/dev/null
check "the new file is mirrored" \
    "${B}/3409143790/mods/sapphcookingb42/42.20.0/media/animsets/player/actions/sapph_newdish.xml"
if [ -z "$(find "${B}" -xtype l -print -quit)" ]; then
    ok "no dangling links left"
else
    fail "no dangling links left"
fi

echo "the switch is honoured"
ZOMBOID_CASE_MIRROR=0
rm -rf "${B}/7777777777"
mkdir -p "${B}/7777777777/mods/OffMod/common/media/AnimSets"
: > "${B}/7777777777/mods/OffMod/common/media/AnimSets/Off.xml"
zomboid_mirror_case >/dev/null
check_absent "ZOMBOID_CASE_MIRROR=0 does nothing" \
    "${B}/7777777777/mods/OffMod/common/media/animsets"

# ---------------------------------------------------------------------------
# libjsig preload path
# ---------------------------------------------------------------------------
# The bug this covers: the guard accepted two JRE layouts while LD_LIBRARY_PATH
# named only one, so on every current build the bootstrap exported the bare name
# "libjsig.so" and ld.so answered "cannot be preloaded ... : ignored" on each
# exec that had no RUNPATH into the JRE - twice per boot, on 65 live consoles.
#
# So the property asserted is not "LD_PRELOAD is set" - a bare name passes that,
# which is exactly how this shipped. It is "whatever is exported is an absolute
# path that exists", which is the only form ld.so can be relied on to resolve.

load_jsig() { # <fake jre64 root> -> prints the LD_PRELOAD the block would export
    local root="$1"
    sed -n '/^ZOMBOID_JRE_DIR=/,/^fi$/p' "${SCRIPT}" \
        | sed "s|^ZOMBOID_JRE_DIR=.*|ZOMBOID_JRE_DIR=\"${root}\"|" \
        > "${root}.jsig.sh"
    # A subshell so each case starts from a clean environment and an export in
    # one cannot leak into the next.
    ( unset LD_PRELOAD
      # shellcheck source=/dev/null
      . "${root}.jsig.sh" >/dev/null
      printf '%s' "${LD_PRELOAD-}" )
}

check_preload() { # <description> <fake jre64 root> <expected path>
    local got
    got="$(load_jsig "$2")"
    if [ "${got}" != "$3" ]; then
        fail "$1 (got '${got}', want '$3')"
        return
    fi
    case "${got}" in
        /*) ;;
        *) fail "$1 - not an absolute path ('${got}')"; return ;;
    esac
    if [ ! -f "${got}" ]; then
        fail "$1 - exported a path that does not exist ('${got}')"
        return
    fi
    ok "$1"
}

echo "libjsig is preloaded by absolute path, whichever layout the JRE ships"

# Today's builds: a Zulu JRE with the modern layout and no amd64 directory.
MODERN="${SANDBOX}/jre-modern"
mkdir -p "${MODERN}/lib/server"
: > "${MODERN}/lib/libjsig.so"
: > "${MODERN}/lib/server/libjsig.so"
check_preload "modern layout resolves lib/libjsig.so" "${MODERN}" "${MODERN}/lib/libjsig.so"

# Build 41 shipped the Java 8 layout.
LEGACY="${SANDBOX}/jre-legacy"
mkdir -p "${LEGACY}/lib/amd64"
: > "${LEGACY}/lib/amd64/libjsig.so"
check_preload "B41 layout still resolves lib/amd64" "${LEGACY}" "${LEGACY}/lib/amd64/libjsig.so"

# Some JDK builds carry it only beside the server VM.
SERVERONLY="${SANDBOX}/jre-serveronly"
mkdir -p "${SERVERONLY}/lib/server"
: > "${SERVERONLY}/lib/server/libjsig.so"
check_preload "server-only layout falls through to lib/server" \
    "${SERVERONLY}" "${SERVERONLY}/lib/server/libjsig.so"

# First boot, before SteamCMD has put the game files down. Exporting anything
# here is what printed the preload error on a brand new server.
echo "nothing is exported when the JRE is not there yet"
EMPTY="${SANDBOX}/jre-absent"
mkdir -p "${EMPTY}/lib"
GOT="$(load_jsig "${EMPTY}")"
if [ -z "${GOT}" ]; then ok "no game files, no LD_PRELOAD"; else fail "no game files, no LD_PRELOAD (got '${GOT}')"; fi

# An LD_PRELOAD already in the environment must be kept, and joined without the
# leading colon the old "${LD_PRELOAD}:${JSIG}" form produced when it was empty.
echo "an existing LD_PRELOAD is appended to, not replaced"
sed -n '/^ZOMBOID_JRE_DIR=/,/^fi$/p' "${SCRIPT}" \
    | sed "s|^ZOMBOID_JRE_DIR=.*|ZOMBOID_JRE_DIR=\"${MODERN}\"|" > "${SANDBOX}/jsig-append.sh"
GOT="$( LD_PRELOAD=/lib/x86_64-linux-gnu/libjemalloc.so.2
        # shellcheck source=/dev/null
        . "${SANDBOX}/jsig-append.sh" >/dev/null
        printf '%s' "${LD_PRELOAD}" )"
WANT="/lib/x86_64-linux-gnu/libjemalloc.so.2:${MODERN}/lib/libjsig.so"
if [ "${GOT}" = "${WANT}" ]; then ok "existing entry preserved"; else fail "existing entry preserved (got '${GOT}')"; fi

GOT="$(load_jsig "${MODERN}")"
case "${GOT}" in
    :*) fail "no leading colon when LD_PRELOAD starts empty (got '${GOT}')" ;;
    *)  ok "no leading colon when LD_PRELOAD starts empty" ;;
esac


# graceful_stop must actually end the process. "quit" then SIGTERM was the whole
# escalation, and the JVM ignores SIGTERM often enough that the function returned
# with the child still running - the panel then showed "stopping" until Wings'
# own timeout expired and Wings SIGKILLed the container. What is asserted here is
# the property that matters to the owner: after graceful_stop returns, the child
# is gone, whichever signal it chose to honour.
echo "graceful_stop ends the process even when SIGTERM is ignored"

sed -n '/^graceful_stop() {/,/^}$/p' "${SCRIPT}" > "${SANDBOX}/stop.sh"

# Alive and not a zombie: a killed background job lingers as Z until reaped, and
# kill -0 succeeds on a zombie, so it cannot answer this on its own.
still_alive() {
    local st
    st="$(ps -p "$1" -o stat= 2>/dev/null | tr -d ' ')"
    [ -n "${st}" ] && case "${st}" in Z*) return 1 ;; *) return 0 ;; esac
    return 1
}

run_stop() {
    # shellcheck source=/dev/null
    ( log() { printf '%s\n' "$*"; }
      exec 3>/dev/null
      . "${SANDBOX}/stop.sh"
      CHILD="$1" ZOMBOID_STOP_TIMEOUT=1 ZOMBOID_KILL_TIMEOUT=1
      CHILD="$1" graceful_stop ) 2>/dev/null
}

# disown keeps bash from printing its own "Killed" job notice when the child is
# SIGKILLed - that line reads like a test failure in CI output, and is not one.
bash -c 'trap "" TERM INT; while :; do sleep 0.2; done' & STUBBORN=$!
disown "${STUBBORN}" 2>/dev/null || true
sleep 0.3
run_stop "${STUBBORN}" >"${SANDBOX}/stubborn.log"
if still_alive "${STUBBORN}"; then
    fail "a child that ignores SIGTERM is killed"
    kill -KILL "${STUBBORN}" 2>/dev/null || true
else
    ok "a child that ignores SIGTERM is killed"
fi

if grep -q 'SIGKILL' "${SANDBOX}/stubborn.log"; then
    ok "the SIGKILL stage is reported in the log"
else
    fail "the SIGKILL stage is reported in the log"
fi

# The new stage must not fire when SIGTERM was enough - reaching SIGKILL every
# time would be the same bug wearing the fix as a disguise.
bash -c 'while :; do sleep 0.2; done' & POLITE=$!
disown "${POLITE}" 2>/dev/null || true
sleep 0.3
run_stop "${POLITE}" >"${SANDBOX}/polite.log"
if grep -q 'SIGKILL' "${SANDBOX}/polite.log"; then
    fail "SIGKILL is not sent when SIGTERM already worked"
else
    ok "SIGKILL is not sent when SIGTERM already worked"
fi


[ "${FAILED}" -eq 0 ] && echo "PASS" || echo "FAILURES"
exit "${FAILED}"
