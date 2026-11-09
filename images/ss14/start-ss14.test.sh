#!/bin/bash
# Contract tests for images/ss14/start-ss14.
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

mkdir -p "${tmp}/lib" "${tmp}/home"
cp "${HERE}/../../shared/launch.sh" "${tmp}/lib/launch.sh"
sed -e "s#/usr/local/lib/pterohost/launch.sh#${tmp}/lib/launch.sh#" \
    -e "s#cd /home/container || exit 1#:#" \
    -e "s#/home/container#${tmp}/home#g" \
    "${HERE}/start-ss14" > "${tmp}/start"

# shellcheck source=/dev/null
SS14_SOURCE_ONLY=1 . "${tmp}/start"

# --- numbers, flags, URLs ----------------------------------------------------
ss14_is_int 1212 1 65535 && r=yes || r=no; check "port in range" yes "${r}"
ss14_is_int 0 1 65535 && r=yes || r=no; check "port zero rejected" no "${r}"
ss14_is_int 65536 1 65535 && r=yes || r=no; check "port too big rejected" no "${r}"
ss14_is_int 12a 1 65535 && r=yes || r=no; check "port with letters rejected" no "${r}"
ss14_is_int "" 1 65535 && r=yes || r=no; check "empty rejected" no "${r}"
ss14_is_int 99999999999999999999 1 65535 && r=yes || r=no; check "huge number rejected" no "${r}"
check "flag 1" 1 "$(ss14_flag 1)"
check "flag true" 1 "$(ss14_flag TRUE)"
check "flag yes" 1 "$(ss14_flag yes)"
check "flag 0" 0 "$(ss14_flag 0)"
check "flag empty" 0 "$(ss14_flag '')"
check "flag junk" 0 "$(ss14_flag banana)"
ss14_http_url "https://cdn.example.org/fork/manifest" && r=yes || r=no; check "https url" yes "${r}"
ss14_http_url "ftp://example.org/x" && r=yes || r=no; check "ftp url rejected" no "${r}"
ss14_http_url "https://a b" && r=yes || r=no; check "url with space rejected" no "${r}"
ss14_http_url 'https://a/$(id)' && r=yes || r=no; check "url with substitution rejected" no "${r}"
ss14_http_url 'https://a/"x' && r=yes || r=no; check "url with quote rejected" no "${r}"

# --- validation --------------------------------------------------------------
valid() { # [VAR=value...]
    (
        export SERVER_PORT=1212 MAX_PLAYERS=30 DB_ENGINE=sqlite
        local kv
        for kv in "$@"; do export "${kv?}"; done
        ss14_validate >/dev/null 2>&1
    ) && echo ok || echo bad
}
check "defaults valid" ok "$(valid)"
check "no port invalid" bad "$( ( unset SERVER_PORT; MAX_PLAYERS=30 ss14_validate >/dev/null 2>&1 ) && echo ok || echo bad )"
check "zero slots invalid" bad "$(valid MAX_PLAYERS=0)"
check "1000 slots valid" ok "$(valid MAX_PLAYERS=1000)"
check "1001 slots invalid" bad "$(valid MAX_PLAYERS=1001)"
check "unknown database invalid" bad "$(valid DB_ENGINE=mysql)"
check "postgres needs a host" bad "$(valid DB_ENGINE=postgres PG_DATABASE=ss14)"
check "postgres needs a database" bad "$(valid DB_ENGINE=postgres PG_HOST=db)"
check "postgres complete" ok "$(valid DB_ENGINE=postgres PG_HOST=db PG_DATABASE=ss14 PG_PORT=5432)"
check "postgres bad port" bad "$(valid DB_ENGINE=postgres PG_HOST=db PG_DATABASE=ss14 PG_PORT=0)"
check "bad manifest url" bad "$(valid MANIFEST_URL='javascript:1')"
check "bad zip url" bad "$(valid SERVER_ZIP_URL='file:///etc/passwd')"
check "bad timeout" bad "$(valid SS14_TIMEOUT_SECONDS=5)"

# --- slots -------------------------------------------------------------------
check "hard cap small plan" 22 "$(ss14_hard_cap 20)"
check "hard cap tiny plan keeps 2 spare" 3 "$(ss14_hard_cap 1)"
check "hard cap 100 slots" 110 "$(ss14_hard_cap 100)"

# --- watchdog port -----------------------------------------------------------
check "watchdog port default" 5000 "$(SERVER_PORT=1212 ss14_watchdog_port)"
check "watchdog port avoids the game port" 5001 "$(SERVER_PORT=5000 ss14_watchdog_port)"
check "watchdog port override" 6000 "$(SERVER_PORT=1212 SS14_WATCHDOG_PORT=6000 ss14_watchdog_port)"

# --- GC ----------------------------------------------------------------------
check "default heap 85% -> hex" "DOTNET_GCHeapHardLimitPercent=0x55" "$(ss14_gc_env 2>/dev/null)"
check "explicit 90" "DOTNET_GCHeapHardLimitPercent=0x5a" "$(SS14_GC_HEAP_PERCENT=90 ss14_gc_env 2>/dev/null)"
check "off keeps .NET default" "" "$(SS14_GC_HEAP_PERCENT=off ss14_gc_env 2>/dev/null)"
check "out of range falls back to 85" "DOTNET_GCHeapHardLimitPercent=0x55" "$(SS14_GC_HEAP_PERCENT=99 ss14_gc_env 2>/dev/null)"
check "garbage falls back to 85" "DOTNET_GCHeapHardLimitPercent=0x55" "$(SS14_GC_HEAP_PERCENT=abc ss14_gc_env 2>/dev/null)"
check "owner limit wins" "" "$(DOTNET_GCHeapHardLimit=0x100000000 ss14_gc_env 2>/dev/null)"

gcmode() { # <cpu milli> <SS14_GC_MODE>
    local milli="$1" mode="$2"
    ( ss14_cpu_milli() { echo "${milli}"; }; SS14_GC_MODE="${mode}" ss14_gc_mode_env 2>/dev/null | tr '\n' ' ' )
}
check "2 cores -> workstation" "DOTNET_gcServer=0 DOTNET_gcConcurrent=1 " "$(gcmode 2000 auto)"
check "1.5 cores -> workstation" "DOTNET_gcServer=0 DOTNET_gcConcurrent=1 " "$(gcmode 1500 auto)"
check "4 cores -> engine default (server)" "" "$(gcmode 4000 auto)"
check "forced server on 1 core" "" "$(gcmode 1000 server)"
check "forced workstation on 8 cores" "DOTNET_gcServer=0 DOTNET_gcConcurrent=1 " "$(gcmode 8000 workstation)"
check "garbage mode acts as auto" "DOTNET_gcServer=0 DOTNET_gcConcurrent=1 " "$(gcmode 2000 banana)"

check "full PGO by default" "DOTNET_TieredPGO=1 DOTNET_TC_QuickJitForLoops=1 DOTNET_ReadyToRun=0 " "$(ss14_perf_env | tr '\n' ' ')"
check "full PGO can be turned off" "" "$(SS14_FULL_PGO=0 ss14_perf_env)"

# --- update mode -------------------------------------------------------------
check "fresh server, updates on -> manifest" manifest "$(AUTO_UPDATE=1 ss14_update_mode)"
check "fresh server, updates off -> manifest (needs a first install)" manifest "$(AUTO_UPDATE=0 ss14_update_mode)"
mkdir -p "${SS14_INSTANCE_DIR}/bin"
printf '#!/bin/sh\n' > "${SS14_INSTANCE_DIR}/bin/Robust.Server"; chmod +x "${SS14_INSTANCE_DIR}/bin/Robust.Server"
check "installed, updates on -> manifest" manifest "$(AUTO_UPDATE=1 ss14_update_mode)"
check "installed, updates off -> pinned" pinned "$(AUTO_UPDATE=0 ss14_update_mode)"
check "zip url wins" zip "$(SERVER_ZIP_URL=https://x/y.zip AUTO_UPDATE=0 ss14_update_mode)"

# --- token -------------------------------------------------------------------
SS14_TOKEN_FILE="${tmp}/api-token"
ss14_token
t1="$(cat "${SS14_TOKEN_FILE}")"
check "token generated" 1 "$([ "${#t1}" -ge 32 ] && echo 1 || echo 0)"
check "token mode 600" 600 "$(stat -c %a "${SS14_TOKEN_FILE}")"
ss14_token
check "token fresh at every start" 1 "$([ "$(cat "${SS14_TOKEN_FILE}")" != "${t1}" ] && echo 1 || echo 0)"
check "token never lands on the volume" 0 "$(find "${SS14_STATE_DIR}" -name 'api-token*' 2>/dev/null | grep -c .)"
WATCHDOG_TOKEN=fromthepanel ss14_token
check "panel token wins" fromthepanel "$(cat "${SS14_TOKEN_FILE}")"

# --- config.toml is the owner's ----------------------------------------------
ss14_write_config_toml
check "config.toml created" 1 "$([ -s "${SS14_INSTANCE_DIR}/config.toml" ] && echo 1 || echo 0)"
printf '[game]\nlobbyenabled = false\n' > "${SS14_INSTANCE_DIR}/config.toml"
ss14_write_config_toml
check "config.toml never rewritten" "[game]
lobbyenabled = false" "$(cat "${SS14_INSTANCE_DIR}/config.toml")"

# --- appsettings -------------------------------------------------------------
ss14_write_appsettings
as="${SS14_STATE_DIR}/watchdog/appsettings.yml"
check "appsettings written" 1 "$([ -s "${as}" ] && echo 1 || echo 0)"
check "request logging silenced" 1 "$(grep -q 'Serilog.AspNetCore: Warning' "${as}" && echo 1 || echo 0)"
check "no colour codes in the console" 1 "$(grep -q 'ConsoleTheme::None' "${as}" && echo 1 || echo 0)"
check "debug logging off" 0 "$(grep -c 'Debug' "${as}")"

# --- resetting the watchdog's build record -------------------------------------
touch "${SS14_STATE_DIR}/watchdog.db"
ss14_reset_watchdog_state manifest >/dev/null
check "first start records the kind" manifest "$(cat "${SS14_STATE_DIR}/update-kind")"
touch "${SS14_STATE_DIR}/watchdog.db"
ss14_reset_watchdog_state manifest >/dev/null
check "same kind keeps the record" 1 "$([ -e "${SS14_STATE_DIR}/watchdog.db" ] && echo 1 || echo 0)"
ss14_reset_watchdog_state pinned >/dev/null
check "manifest -> pinned drops the record" 0 "$([ -e "${SS14_STATE_DIR}/watchdog.db" ] && echo 1 || echo 0)"
check "pinned recorded as dummy" dummy "$(cat "${SS14_STATE_DIR}/update-kind")"
touch "${SS14_STATE_DIR}/watchdog.db"
ss14_reset_watchdog_state zip >/dev/null
check "pinned <-> zip keeps the record" 1 "$([ -e "${SS14_STATE_DIR}/watchdog.db" ] && echo 1 || echo 0)"

# --- watchdog environment ------------------------------------------------------
envof() { # <var> : run the export in a subshell and print one variable
    local want="$1"; shift
    ( SERVER_PORT=1212 SERVER_NAME="Sol Station" "$@" 2>/dev/null; printenv "${want}" )
}
ex() { ss14_export_watchdog_env manifest /tok 5000 "$@"; }
check "instance name" "Sol Station" "$(envof Servers__Instances__ss14__Name ex)"
check "api port is the game port" 1212 "$(envof Servers__Instances__ss14__ApiPort ex)"
check "token file" /tok "$(envof Servers__Instances__ss14__ApiTokenFile ex)"
check "manifest provider" Manifest "$(envof Servers__Instances__ss14__UpdateType ex)"
check "default manifest" "${SS14_DEFAULT_MANIFEST}" "$(envof Servers__Instances__ss14__Updates__ManifestUrl ex)"
check "fork manifest" "https://forks.example/manifest" "$(MANIFEST_URL=https://forks.example/manifest envof Servers__Instances__ss14__Updates__ManifestUrl ex)"
check "dump on timeout off" false "$(envof Servers__Instances__ss14__DumpOnTimeout ex)"
check "loopback only" "http://127.0.0.1:5000" "$(envof ASPNETCORE_URLS ex)"
check "no extra arguments" "" "$(envof Servers__Instances__ss14__Arguments__0 ex)"
check "first extra argument" "--cvar" "$(envof Servers__Instances__ss14__Arguments__0 ex --cvar game.x=1)"
check "second extra argument" "game.x=1" "$(envof Servers__Instances__ss14__Arguments__1 ex --cvar game.x=1)"
check "argument with a space survives" "game.hostname=My Station" "$(envof Servers__Instances__ss14__Arguments__1 ex --cvar "game.hostname=My Station")"
check "pinned uses Dummy" Dummy "$(envof Servers__Instances__ss14__UpdateType ss14_export_watchdog_env pinned /tok 5000)"
check "zip uses Dummy" Dummy "$(envof Servers__Instances__ss14__UpdateType ss14_export_watchdog_env zip /tok 5000)"
check "GC ceiling goes to the server only" "0x55" "$(envof Servers__Instances__ss14__EnvironmentVariables__DOTNET_GCHeapHardLimitPercent ex)"
check "runtime image port cleared" "" "$(ASPNETCORE_HTTP_PORTS=8080 envof ASPNETCORE_HTTP_PORTS ex)"

# --- server settings -------------------------------------------------------------
cv() { # [VAR=value...]
    (
        export SERVER_PORT=1212 SERVER_NAME="Sol Station" MAX_PLAYERS=40
        local kv
        for kv in "$@"; do export "${kv?}"; done
        ss14_export_cvars
        printenv "${CVAR}"
    )
}
CVAR=ROBUST_CVAR_net__port; check "cvar port" 1212 "$(cv)"
CVAR=ROBUST_CVAR_game__hostname; check "cvar hostname" "Sol Station" "$(cv)"
CVAR=ROBUST_CVAR_game__soft_max_players; check "cvar soft cap" 40 "$(cv)"
CVAR=ROBUST_CVAR_net__max_connections; check "cvar hard cap" 44 "$(cv)"
CVAR=ROBUST_CVAR_hub__advertise; check "hub off by default" false "$(cv)"
CVAR=ROBUST_CVAR_hub__advertise; check "hub on" true "$(cv HUB_ADVERTISE=1)"
CVAR=ROBUST_CVAR_hub__tags; check "hub tags" "lang:ru,rp:low" "$(cv HUB_TAGS=lang:ru,rp:low)"
CVAR=ROBUST_CVAR_hub__tags; check "no hub tags by default" "" "$(cv)"
CVAR=ROBUST_CVAR_console__login_host_user; check "host user" "Alice" "$(cv ADMIN_USER=Alice)"
CVAR=ROBUST_CVAR_console__loginlocal; check "no implicit local host login" false "$(cv)"
CVAR=ROBUST_CVAR_database__engine; check "sqlite by default" sqlite "$(cv)"
CVAR=ROBUST_CVAR_database__engine; check "postgres engine" postgres "$(cv DB_ENGINE=postgres PG_HOST=h PG_DATABASE=d)"
CVAR=ROBUST_CVAR_database__pg_host; check "postgres host" db.internal "$(cv DB_ENGINE=postgres PG_HOST=db.internal PG_DATABASE=d)"
CVAR=ROBUST_CVAR_database__pg_password; check "postgres password" 's3cr"et$x' "$(cv DB_ENGINE=postgres PG_HOST=h PG_DATABASE=d PG_PASSWORD='s3cr"et$x')"
CVAR=ROBUST_CVAR_database__pg_host; check "sqlite sets no postgres host" "" "$(cv)"

# --- the panel's command line ------------------------------------------------------
args() { ( pterohost_panel_argv "$@" >/dev/null; printf '%s|' "${PTEROHOST_ARGS[@]}" ); }
check "bare watchdog" "SS14.Watchdog|" "$(args SS14.Watchdog)"
check "empty extra arguments are dropped" "SS14.Watchdog|" "$(args SS14.Watchdog '')"
check "extra arguments kept in order" "SS14.Watchdog|--cvar|game.x=1|" "$(args SS14.Watchdog --cvar game.x=1)"
check "a trailing valueless flag is pruned" "SS14.Watchdog|" "$(args SS14.Watchdog --cvar '')"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = 0 ]
