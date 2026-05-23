#!/bin/bash
# Pterohost container diagnostics.
# Prints JDK, CPU, memory, disk and network info at startup.
# Defensive: every probe has a fallback, never aborts the container.

set -u

C_RESET=$'\033[0m'
C_DIM=$'\033[2m'
C_BOLD=$'\033[1m'
C_CYAN=$'\033[0;36m'
C_MAG=$'\033[0;35m'
C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[0;33m'

hr() { printf '%b\n' "${C_DIM}--------------------------------------------------------------------${C_RESET}"; }
row() { printf '  %b%-16s%b %s\n' "${C_CYAN}" "$1" "${C_RESET}" "$2"; }

# ---------- CPU ----------
cpu_model="unknown"
if [ -r /proc/cpuinfo ]; then
    cpu_model=$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)
    [ -z "$cpu_model" ] && cpu_model=$(awk -F': ' '/^Model/ {print $2; exit}' /proc/cpuinfo)
fi

cpu_cores=""
if command -v nproc >/dev/null 2>&1; then
    cpu_cores=$(nproc 2>/dev/null)
fi
[ -z "$cpu_cores" ] && cpu_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "?")

cpu_quota=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r q p < /sys/fs/cgroup/cpu.max 2>/dev/null
    if [ "$q" != "max" ] && [ -n "$q" ] && [ -n "$p" ] && [ "$p" -gt 0 ] 2>/dev/null; then
        cpu_quota=$(awk -v q="$q" -v p="$p" 'BEGIN{printf "%.2f", q/p}')
    fi
elif [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -r /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
    q=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null)
    p=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null)
    if [ -n "$q" ] && [ "$q" -gt 0 ] 2>/dev/null && [ -n "$p" ] && [ "$p" -gt 0 ] 2>/dev/null; then
        cpu_quota=$(awk -v q="$q" -v p="$p" 'BEGIN{printf "%.2f", q/p}')
    fi
fi

# ---------- Memory ----------
mem_limit_bytes=""
if [ -r /sys/fs/cgroup/memory.max ]; then
    v=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
    [ "$v" != "max" ] && mem_limit_bytes="$v"
elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    v=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
    # 9223372036854771712 is the "unlimited" sentinel
    if [ -n "$v" ] && [ "$v" != "9223372036854771712" ]; then
        mem_limit_bytes="$v"
    fi
fi

mem_total_kb=$(awk '/^MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null)
mem_total_bytes=""
[ -n "$mem_total_kb" ] && mem_total_bytes=$((mem_total_kb * 1024))

human_bytes() {
    awk -v b="$1" 'BEGIN{
        if (b == "" || b+0 == 0) { print "n/a"; exit }
        split("B KiB MiB GiB TiB", u, " "); i=1;
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf "%.2f %s", b, u[i]
    }'
}

# ---------- Disk ----------
disk_info=$(df -h /home/container 2>/dev/null | awk 'NR==2 {printf "%s used / %s total (%s free)", $3, $2, $4}')
[ -z "$disk_info" ] && disk_info="n/a"

# ---------- Network ----------
internal_ip=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
[ -z "$internal_ip" ] && internal_ip=$(hostname -i 2>/dev/null | awk '{print $1}')
[ -z "$internal_ip" ] && internal_ip="n/a"

host_name=$(hostname 2>/dev/null || echo "?")

# ---------- JDK ----------
jdk_line="not detected"
jdk_vendor=""
if command -v java >/dev/null 2>&1; then
    jdk_raw=$(java -version 2>&1 | head -3)
    jdk_line=$(printf '%s\n' "$jdk_raw" | head -1)
    jdk_vendor=$(printf '%s\n' "$jdk_raw" | sed -n '2p')
fi

# ---------- Render ----------
printf '%b' "${C_MAG}"
[ -r /motd.txt ] && cat /motd.txt
printf '%b\n' "${C_RESET}"

hr
printf '  %b%s%b\n' "${C_BOLD}" "Container diagnostics" "${C_RESET}"
hr

row "Image tag"      "${PTEROHOST_JDK_TAG:-unknown}"
row "JDK"            "${jdk_line}"
[ -n "$jdk_vendor" ] && row ""            "${jdk_vendor}"
row "Recommended GC" "${PTEROHOST_GC:-G1}"

hr
row "CPU model"      "${cpu_model:-unknown}"
row "CPU cores"      "${cpu_cores}${cpu_quota:+ (quota: ${cpu_quota})}"
row "Memory limit"   "$(human_bytes "${mem_limit_bytes:-}")"
row "Host memory"    "$(human_bytes "${mem_total_bytes:-}")"
row "Disk /home"     "${disk_info}"
row "Internal IP"    "${internal_ip}"
row "Hostname"       "${host_name}"

hr
printf '  %bPowered by Pterohost%b - %bhttps://pterohost.com%b\n' \
    "${C_GREEN}" "${C_RESET}" "${C_YELLOW}" "${C_RESET}"
printf '  %bImages%b: https://github.com/Pterohost/pterodactyl-images\n' "${C_DIM}" "${C_RESET}"
hr
