#!/bin/bash
# Contract tests for images/vintagestory/start-vintagestory.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

mkdir -p "${tmp}/lib"
cp "${HERE}/../../shared/launch.sh" "${tmp}/lib/launch.sh"
sed "s#/usr/local/lib/pterohost/launch.sh#${tmp}/lib/launch.sh#; s#cd /home/container || exit 1#:#" \
    "${HERE}/start-vintagestory" > "${tmp}/start"

# shellcheck source=/dev/null
VS_SOURCE_ONLY=1 . "${tmp}/start"

# --- runtime major -----------------------------------------------------------
cat > "${tmp}/rc10.json" <<'EOF'
{ "runtimeOptions": { "tfm": "net10.0", "framework": { "name": "Microsoft.NETCore.App", "version": "10.0.0" } } }
EOF
cat > "${tmp}/rc8.json" <<'EOF'
{
  "runtimeOptions": {
    "tfm": "net8.0",
    "framework": {
      "name": "Microsoft.NETCore.App",
      "version": "8.0.0"
    }
  }
}
EOF
check "runtime 10 from one-line json" "10" "$(vs_runtime_major "${tmp}/rc10.json")"
check "runtime 8 from pretty json" "8" "$(vs_runtime_major "${tmp}/rc8.json")"
vs_runtime_major "${tmp}/missing.json" >/dev/null && r=found || r=missing
check "missing runtimeconfig" "missing" "${r}"

mkdir -p "${tmp}/dn/shared/Microsoft.NETCore.App/10.0.14" "${tmp}/dn/shared/Microsoft.NETCore.App/8.0.30"
DOTNET_ROOT="${tmp}/dn/"
vs_has_runtime 10 && r=yes || r=no; check "runtime 10 present" "yes" "${r}"
vs_has_runtime 8 && r=yes || r=no; check "runtime 8 present" "yes" "${r}"
vs_has_runtime 11 && r=yes || r=no; check "runtime 11 absent" "no" "${r}"

# --- GC heap ceiling ------------------------------------------------------------
gc() { ( unset DOTNET_GCHeapHardLimitPercent; "$@" ; vs_gc_env >/dev/null; printf '%s' "${DOTNET_GCHeapHardLimitPercent:-unset}" ); }
check "default 85% -> hex" "0x55" "$(gc true)"
check "explicit 90" "0x5a" "$(VS_GC_HEAP_PERCENT=90 gc true)"
check "off keeps .NET default" "unset" "$(VS_GC_HEAP_PERCENT=off gc true)"
check "out of range falls back to 85" "0x55" "$(VS_GC_HEAP_PERCENT=99 gc true)"
check "garbage falls back to 85" "0x55" "$(VS_GC_HEAP_PERCENT=abc gc true)"
check "owner limit wins" "unset" "$(DOTNET_GCHeapHardLimit=0x100000000 gc true)"

# --- reducedthreads -------------------------------------------------------------
args() { # <cpu milli> <VS_REDUCED_THREADS> <panel args...>
    local milli="$1" mode="$2"; shift 2
    (
        vs_cpu_milli() { echo "${milli}"; }
        VS_REDUCED_THREADS="${mode}"
        pterohost_panel_argv "$@"
        vs_reduced_threads
        printf '%s|' "${PTEROHOST_ARGS[@]}"
    )
}
check "2 cores -> reducedthreads" "./VintagestoryServer|--port=1|--reducedthreads|" "$(args 2000 auto ./VintagestoryServer --port=1)"
check "1.5 cores -> reducedthreads" "./VintagestoryServer|--reducedthreads|" "$(args 1500 auto ./VintagestoryServer)"
check "4 cores -> none" "./VintagestoryServer|" "$(args 4000 auto ./VintagestoryServer)"
check "forced on 8 cores" "./VintagestoryServer|--reducedthreads|" "$(args 8000 1 ./VintagestoryServer)"
check "forced off on 1 core" "./VintagestoryServer|" "$(args 1000 0 ./VintagestoryServer)"
check "already in OPTIONS not doubled" "./VintagestoryServer|--reducedthreads|" "$(args 1000 auto ./VintagestoryServer --reducedthreads)"
check "empty OPTIONS pruned" "./VintagestoryServer|--maxclients=16|" "$(args 4000 auto ./VintagestoryServer --maxclients=16 '')"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
