#!/bin/bash
# Builds GE-Proton's x86_64 ntdll.so from the exact sources of one GE-Proton
# release, with the patches in this directory applied on top.
#
#   build-ntdll.sh <ge-tag> <wine-sha> <staging-sha> <release-proton-dir> <out>
#
# Only ntdll.so is rebuilt; everything else comes from the release tarball, so
# the result must match that release exactly. verify-ntdll.py checks the parts
# that have to agree (syscall numbers shared with the PE ntdll.dll, exported
# symbols) and the build fails if they do not.
set -euo pipefail

TAG=$1 WINE_SHA=$2 STAGING_SHA=$3 RELEASE=$4 OUT=$5
HERE="$(cd "$(dirname "$0")" && pwd)"
W=/build
mkdir -p "$W" && cd "$W"

git clone -q --depth 1 --branch "$TAG" https://github.com/GloriousEggroll/proton-ge-custom.git pge
cd pge
# The submodule pins in the tag must be the ones this image was written for.
[ "$(git ls-tree HEAD wine | awk '{print $3}')" = "$WINE_SHA" ] || { echo "wine submodule of $TAG is not $WINE_SHA"; exit 1; }
[ "$(git ls-tree HEAD wine-staging | awk '{print $3}')" = "$STAGING_SHA" ] || { echo "wine-staging submodule of $TAG is not $STAGING_SHA"; exit 1; }
rmdir wine wine-staging
git init -q wine
git -C wine fetch -q --depth 1 https://github.com/ValveSoftware/wine "$WINE_SHA"
git -C wine checkout -q FETCH_HEAD
# GE's prep reverts e813ca57 ("remove configure") and needs it with its parent.
git -C wine fetch -q --depth 2 https://github.com/ValveSoftware/wine e813ca5771658b00875924ab88d525322e50d39f
git init -q wine-staging
git -C wine-staging fetch -q --depth 1 https://github.com/wine-staging/wine-staging "$STAGING_SHA"
git -C wine-staging checkout -q FETCH_HEAD

# GE's own wine preparation, taken from the tag: its helper functions and the
# "(2) WINE PATCHING" section, minus the generator calls run below.
{ sed -n '1,15p' patches/protonprep-valve-staging.sh
  awk '/^### \(2\) WINE PATCHING/{f=1} f' patches/protonprep-valve-staging.sh \
      | grep -v -E 'autoreconf -f|tools/make_requests'
} > ../wineprep.sh
git -C wine config user.email build@localhost
git -C wine config user.name build
bash ../wineprep.sh > ../wineprep.log 2>&1 || { tail -40 ../wineprep.log; exit 1; }
if find wine -name '*.rej' | grep -q .; then
    echo "GE patches did not apply cleanly"; find wine -name '*.rej'; exit 1
fi

# Generated files, the way Proton's build produces them.
cd wine
autoreconf -f
./tools/make_requests
XDG_CACHE_HOME="$W/cache" dlls/winevulkan/make_vulkan -x vk.xml -X video.xml
tools/make_specfiles

for p in "$HERE"/*.patch; do
    patch -p1 --forward < "$p"
done

mkdir -p "$W/build64" && cd "$W/build64"
CF="-O2 -fwrapv -fno-strict-aliasing -ffunction-sections -fdata-sections -fno-omit-frame-pointer -mcmodel=small -march=nocona -mtune=core-avx2 -mfpmath=sse -Wno-discarded-qualifiers"
../pge/wine/configure --enable-win64 --enable-archs=x86_64 --without-mingw --disable-tests \
    --without-x --without-freetype --without-wayland --without-ffmpeg CFLAGS="$CF" > ../configure.log \
    || { tail -40 ../configure.log; exit 1; }
make -j"$(nproc)" dlls/ntdll/ntdll.so > ../make.log 2>&1 || { tail -40 ../make.log; exit 1; }

python3 "$HERE/verify-ntdll.py" \
    "$RELEASE/files/lib/wine/x86_64-windows/ntdll.dll" "$W/pge/wine/dlls/ntdll/ntsyscalls.h" \
    "$RELEASE/files/lib/wine/x86_64-unix/ntdll.so" dlls/ntdll/ntdll.so

strip --strip-unneeded -o "$OUT" dlls/ntdll/ntdll.so
