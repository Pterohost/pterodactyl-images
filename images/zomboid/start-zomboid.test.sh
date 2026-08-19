#!/bin/bash
# Contract tests for the animation-path case mirror in images/zomboid/start-zomboid.
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
# Not yet wired into .github/workflows/build.yml.

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

[ "${FAILED}" -eq 0 ] && echo "PASS" || echo "FAILURES"
exit "${FAILED}"
