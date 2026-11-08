#!/bin/bash
# Contract tests for the GMod network-ping addon and its ICMP probe.
# See images/gmod/netping/README.md.
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

# --- shipped Lua carries no comments ---------------------------------------
LUA="${HERE}/netping/lua/autorun/pterohost_netping.lua"
check "addon has no comments" "0" "$(grep -cE -- '--' "${LUA}")"

# --- probe helpers -----------------------------------------------------------
# shellcheck source=/dev/null
NETPING_SOURCE_ONLY=1 . "${HERE}/gmod-netping-probe" 0 /nonexistent

out='PING 1.1.1.1 (1.1.1.1) 56(84) bytes of data.

--- 1.1.1.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 402ms
rtt min/avg/max/mdev = 38.104/39.002/40.117/0.812 ms'
check "min RTT parsed" "38.104" "$(netping_min_rtt "${out}")"

out='--- 192.0.2.1 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2041ms'
check "no reply -> nothing" "" "$(netping_min_rtt "${out}")"

netping_valid_ip 203.0.113.7 && r=yes || r=no
check "valid IPv4 accepted" "yes" "${r}"
netping_valid_ip '203.0.113.7; rm -rf /' && r=yes || r=no
check "injection rejected" "no" "${r}"
netping_valid_ip '2001:db8::1' && r=yes || r=no
check "IPv6 rejected" "no" "${r}"

# --- probe end to end against loopback, with a fake ping ---------------------
tmp="$(mktemp -d)"
cat > "${tmp}/ping" <<'EOF'
#!/bin/bash
printf 'rtt min/avg/max/mdev = 12.500/13.000/14.000/0.100 ms\n'
EOF
chmod +x "${tmp}/ping"
mkdir -p "${tmp}/data"
sleep 30 & watched=$!
PTEROHOST_PING="${tmp}/ping" NETPING_INTERVAL=0.2 bash "${HERE}/gmod-netping-probe" "${watched}" "${tmp}/data" &
probe=$!
sleep 0.3
printf '203.0.113.7\nnot-an-ip\n203.0.113.7\n' > "${tmp}/data/targets.txt"
for _ in $(seq 1 30); do [ -s "${tmp}/data/rtt.txt" ] && break; sleep 0.1; done
check "probe writes one line per unique valid IP" "203.0.113.7 12.500" "$(cut -d' ' -f1,2 "${tmp}/data/rtt.txt" 2>/dev/null)"
kill "${watched}" 2>/dev/null
for _ in $(seq 1 30); do kill -0 "${probe}" 2>/dev/null || break; sleep 0.1; done
kill -0 "${probe}" 2>/dev/null && r=running || r=stopped
check "probe exits with the watched process" "stopped" "${r}"
kill "${probe}" 2>/dev/null

cat > "${tmp}/ping" <<'EOF'
#!/bin/bash
echo "ping: socket: Operation not permitted" >&2
exit 2
EOF
msg="$(PTEROHOST_PING="${tmp}/ping" bash "${HERE}/gmod-netping-probe" $$ "${tmp}/data2")"
case "${msg}" in *"ICMP is not permitted"*) r=logged ;; *) r="${msg}" ;; esac
check "no ICMP -> one line and exit" "logged" "${r}"
rm -rf "${tmp}"

# --- Lua decision logic --------------------------------------------------------
if command -v luajit >/dev/null 2>&1; then
    if luajit "${HERE}/netping/pterohost_netping.test.lua" "${LUA}"; then
        PASS=$((PASS + 1)); echo "ok   lua suite"
    else
        FAIL=$((FAIL + 1)); echo "FAIL lua suite"
    fi
else
    FAIL=$((FAIL + 1)); echo "FAIL luajit is not installed"
fi

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
