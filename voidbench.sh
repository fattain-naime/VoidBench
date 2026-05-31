#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  VoidBench  ·  v2.2.0  ·  Lab_0x4E Edition
#  Author  : Fattain Naime  ·  https://iamnaime.info.bd
#  Lab     : Lab_0x4E — Deciphering the Void
#  GitHub  : https://github.com/fattain-naime/voidbench
#  License : MIT
#
#  Supported Distros:
#    Debian · Ubuntu · CentOS · AlmaLinux · Rocky · Arch · RHEL · Fedora
#
#  Tests Covered:
#    System Info · CPU (sysbench/openssl/prime) · Memory · Disk I/O (dd+fio)
#    Network (latency + throughput) · Crypto (openssl) · Compression
#    Scoring · JSON + Text Report
#
#  Usage:
#    chmod +x voidbench.sh
#    sudo ./voidbench.sh [OPTIONS]
#
#  Options:
#    --quick          Reduce iterations for faster results (~5 min)
#    --no-network     Skip all network tests
#    --no-disk        Skip disk write tests
#    --no-compress    Skip compression tests
#    --no-color       Disable ANSI color output
#    --json           Also emit a machine-readable JSON report
#    --no-install     Never attempt to install missing packages
#    --help           Show this help
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ─── STRICT MODE ──────────────────────────────────────────────────────────
set -uo pipefail

# ─── GLOBAL CONFIGURATION ─────────────────────────────────────────────────
readonly BENCH_VERSION="2.2.0"
readonly BENCH_START_TS=$(date +%s)
BENCH_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")
REPORT_STEM="bench_$(hostname -s 2>/dev/null || echo vps)_$(date +%Y%m%d_%H%M%S)"
REPORT_TXT="${REPORT_STEM}.txt"
REPORT_JSON="${REPORT_STEM}.json"
TMPDIR_B=$(mktemp -d /tmp/.vps_bench_XXXXXX)
DISK_TESTFILE="${TMPDIR_B}/diskio"
COMPRESS_TESTFILE="${TMPDIR_B}/compress_src"

# Iteration counts
ITER_DISK=3
ITER_CPU_PRIME=1   # python prime test (longer)

# OPTIONS (overridable by CLI flags)
OPT_QUICK=0
OPT_NO_NETWORK=0
OPT_NO_DISK=0
OPT_NO_COMPRESS=0
OPT_NO_COLOR=0
OPT_JSON=0
OPT_NO_INSTALL=0

# Scores (0–100)
declare -A S=([cpu]=0 [mem]=0 [disk]=0 [net]=0 [crypto]=0)
declare -A R  # raw string results for JSON

# ─── COLORS ───────────────────────────────────────────────────────────────
setup_colors() {
    if [[ $OPT_NO_COLOR -eq 1 ]] || [[ ! -t 1 ]]; then
        R_='' G_='' Y_='' B_='' M_='' C_='' W_=''
        BR_='' BG_='' BY_='' BB_='' BM_='' BC_='' BW_=''
        DIM_='' RST_=''
    else
        R_='\033[0;31m'   G_='\033[0;32m'   Y_='\033[0;33m'
        B_='\033[0;34m'   M_='\033[0;35m'   C_='\033[0;36m'   W_='\033[0;37m'
        BR_='\033[1;31m'  BG_='\033[1;32m'  BY_='\033[1;33m'
        BB_='\033[1;34m'  BM_='\033[1;35m'  BC_='\033[1;36m'  BW_='\033[1;37m'
        DIM_='\033[2m'    RST_='\033[0m'
    fi
}

# ─── CLI PARSING ──────────────────────────────────────────────────────────
parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --quick)        OPT_QUICK=1 ;;
            --no-network)   OPT_NO_NETWORK=1 ;;
            --no-disk)      OPT_NO_DISK=1 ;;
            --no-compress)  OPT_NO_COMPRESS=1 ;;
            --no-color)     OPT_NO_COLOR=1 ;;
            --json)         OPT_JSON=1 ;;
            --no-install)   OPT_NO_INSTALL=1 ;;
            --help|-h)
                sed -n '/#  Usage:/,/#  ━/p' "$0" | grep -v "^# ━"
                exit 0 ;;
            *) echo "Unknown option: $arg  (use --help)"; exit 1 ;;
        esac
    done
    [[ $OPT_QUICK -eq 1 ]] && ITER_DISK=1 && ITER_CPU_PRIME=1
}

# ─── CLEANUP ──────────────────────────────────────────────────────────────
cleanup() { rm -rf "${TMPDIR_B}" 2>/dev/null; }
trap cleanup EXIT INT TERM

# ─── UTILITY FUNCTIONS ────────────────────────────────────────────────────
cmd_exists() { command -v "$1" &>/dev/null; }

die() { echo -e "${BR_}[FATAL]${RST_} $1" >&2; exit 1; }

hr() {
    local char="${1:-─}" width="${2:-72}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

box() {
    local title="$1" color="${2:-${BC_}}" w=72
    local inner=$(( w - 4 ))
    local tlen=${#title}
    local lpad=$(( (inner - tlen) / 2 ))
    local rpad=$(( inner - tlen - lpad ))
    echo
    echo -e "${color}╔$(hr '═' $((w-2)))╗${RST_}"
    printf "${color}║  ${BW_}%-${lpad}s%s%-${rpad}s${color}  ║${RST_}\n" "" "$title" ""
    echo -e "${color}╚$(hr '═' $((w-2)))╝${RST_}"
}

section() {
    local title="$1" icon="${2:-◈}"
    echo
    echo -e "${BB_}${icon}${RST_} ${BW_}${title}${RST_}"
    echo -e "${DIM_}$(hr '─' 68)${RST_}"
}

kv() {
    printf "  ${C_}%-34s${RST_}${W_}%s${RST_}\n" "$1" "$2"
}

kv2() {
    # kv with color for value
    printf "  ${C_}%-34s${RST_}${2}%s${RST_}\n" "$1" "$3"
}

progress_bar() {
    local label="$1" pct="${2:-0}" w=28
    # clamp
    (( pct > 100 )) && pct=100
    (( pct < 0 ))   && pct=0
    local filled=$(( pct * w / 100 ))
    local empty=$(( w - filled ))
    local bar="" color="${BG_}"
    (( pct < 50 )) && color="${BY_}"
    (( pct < 30 )) && color="${BR_}"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty;  i++)); do bar+="░"; done
    printf "  ${C_}%-22s${RST_} ${color}%s${RST_} ${BW_}%3d%%${RST_}\n" \
           "$label" "$bar" "$pct"
}

# Arithmetic helpers (awk-based for portability)
awk_calc()  { awk "BEGIN { printf \"%.2f\", $1 }" 2>/dev/null; }
awk_int()   { awk "BEGIN { printf \"%d\", $1 }"   2>/dev/null; }
awk_avg()   {
    # average of space-separated numbers
    echo "$@" | awk '{ s=0; for(i=1;i<=NF;i++) s+=$i; printf "%.2f", s/NF }'
}
awk_clamp() {
    # awk_clamp value min max
    awk "BEGIN { v=$1; if(v<$2) v=$2; if(v>$3) v=$3; printf \"%.0f\", v }"
}

# High-resolution timestamp (ms)
now_ms() {
    if date +%s%N &>/dev/null 2>&1 && [[ "$(date +%s%N)" != "%s%N" ]]; then
        echo $(( $(date +%s%N) / 1000000 ))
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

# Parse dd output → MB/s float
dd_to_mbps() {
    # Accepts full dd stderr string
    echo "$1" | awk '/copied/{
        for(i=1;i<=NF;i++){
            if($i~/^[MGk]B\/s$/||$i~/^GB\/s$/){
                v=$(i-1)
                u=$i
                if(u~/^G/)      printf "%.1f", v*1024
                else if(u~/^M/) printf "%.1f", v
                else if(u~/^k/) printf "%.3f", v/1024
                exit
            }
        }
    }'
}

# ─── DEPENDENCY CHECK ─────────────────────────────────────────────────────
check_deps() {
    box "DEPENDENCY CHECK" "${C_}"

    local required=(bc curl openssl tar gzip bzip2 dd awk python3 ping)
    local optional=(sysbench fio iperf3 xz zstd lz4 dmidecode lscpu)
    local missing_req=()

    section "Required Tools" "⚙"
    for dep in "${required[@]}"; do
        if cmd_exists "$dep"; then
            printf "  ${BG_}✔${RST_} %-16s ${DIM_}%s${RST_}\n" "$dep" "$(command -v "$dep")"
        else
            printf "  ${BR_}✘${RST_} %-16s ${R_}MISSING (required)${RST_}\n" "$dep"
            missing_req+=("$dep")
        fi
    done

    section "Optional Tools" "⚙"
    for dep in "${optional[@]}"; do
        if cmd_exists "$dep"; then
            printf "  ${BG_}✔${RST_} %-16s ${DIM_}%s${RST_}\n" "$dep" "$(command -v "$dep")"
        else
            printf "  ${Y_}○${RST_} %-16s ${DIM_}not found${RST_}\n" "$dep"
        fi
    done

    # Install missing optional tools (root only, unless --no-install)
    if [[ ${EUID} -eq 0 && $OPT_NO_INSTALL -eq 0 ]]; then
        local pkg_mgr=""
        cmd_exists apt-get && pkg_mgr="apt-get"
        cmd_exists dnf     && pkg_mgr="dnf"
        cmd_exists yum     && pkg_mgr="yum"
        cmd_exists pacman  && pkg_mgr="pacman"

        if [[ -n "$pkg_mgr" ]]; then
            echo
            echo -e "  ${Y_}↳ Attempting to install optional tools (sysbench, fio, iperf3)...${RST_}"
            for tool in sysbench fio iperf3; do
                if ! cmd_exists "$tool"; then
                    case "$pkg_mgr" in
                        apt-get) apt-get install -y -q "$tool" &>/dev/null && \
                                 printf "    ${BG_}✔${RST_} installed %s\n" "$tool" || \
                                 printf "    ${Y_}○${RST_} could not install %s\n" "$tool" ;;
                        dnf|yum) $pkg_mgr install -y -q "$tool" &>/dev/null && \
                                 printf "    ${BG_}✔${RST_} installed %s\n" "$tool" || \
                                 printf "    ${Y_}○${RST_} could not install %s\n" "$tool" ;;
                        pacman)  pacman -S --noconfirm --quiet "$tool" &>/dev/null && \
                                 printf "    ${BG_}✔${RST_} installed %s\n" "$tool" || \
                                 printf "    ${Y_}○${RST_} could not install %s\n" "$tool" ;;
                    esac
                fi
            done
        fi
    fi

    if [[ ${#missing_req[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing_req[*]}. Install them and retry."
    fi
}

# ─── SYSTEM INFORMATION ───────────────────────────────────────────────────
collect_sysinfo() {
    box "SYSTEM INFORMATION" "${BB_}"

    # ── Basic ──
    section "Host & OS" "🖥"
    local hostname os_name kernel arch uptime_str
    hostname=$(hostname -f 2>/dev/null || hostname)
    kernel=$(uname -r)
    arch=$(uname -m)
    uptime_str=$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | sed 's/,.*load.*//')

    if [[ -f /etc/os-release ]]; then
        os_name=$(. /etc/os-release && echo "${PRETTY_NAME:-$NAME}")
    elif cmd_exists lsb_release; then
        os_name=$(lsb_release -ds)
    else
        os_name="Unknown Linux"
    fi

    kv "Hostname"     "$hostname"
    kv "OS"           "$os_name"
    kv "Kernel"       "$kernel"
    kv "Architecture" "$arch"
    kv "Uptime"       "$uptime_str"
    kv "Date"         "$BENCH_DATE"

    # ── CPU ──
    section "Processor" "⚡"
    local cpu_model cpu_logical cpu_physical cpu_freq cpu_maxfreq
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    cpu_logical=$(nproc)
    cpu_physical=$(grep "cpu cores" /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $4}')
    [[ -z "$cpu_physical" ]] && cpu_physical="$cpu_logical"
    cpu_freq=$(grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 | \
               awk '{printf "%.2f GHz", $4/1000}')
    cpu_maxfreq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null | \
                  awk '{printf "%.2f GHz", $1/1000000}')

    # Cache sizes
    local l1d l1i l2 l3
    l1d=$(cat /sys/devices/system/cpu/cpu0/cache/index0/size 2>/dev/null || echo "N/A")
    l1i=$(cat /sys/devices/system/cpu/cpu0/cache/index1/size 2>/dev/null || echo "N/A")
    l2=$(cat  /sys/devices/system/cpu/cpu0/cache/index2/size 2>/dev/null || echo "N/A")
    l3=$(cat  /sys/devices/system/cpu/cpu0/cache/index3/size 2>/dev/null || echo "N/A")

    # Virtualization
    local virt="Bare Metal"
    if cmd_exists systemd-detect-virt; then
        virt=$(systemd-detect-virt 2>/dev/null || echo "none")
        [[ "$virt" == "none" ]] && virt="Bare Metal"
    elif grep -qi "hypervisor" /proc/cpuinfo 2>/dev/null; then
        virt="Virtual Machine (hypervisor flag set)"
    fi

    kv "CPU Model"         "$cpu_model"
    kv "Physical Cores"    "$cpu_physical"
    kv "Logical CPUs"      "$cpu_logical"
    kv "Current Frequency" "${cpu_freq:-N/A}"
    kv "Max Frequency"     "${cpu_maxfreq:-N/A}"
    kv "L1d / L1i Cache"   "${l1d} / ${l1i}"
    kv "L2 / L3 Cache"     "${l2} / ${l3}"
    kv "Virtualization"    "$virt"

    # CPU feature flags
    local flags=""
    grep -qi "aes"       /proc/cpuinfo 2>/dev/null && flags+="AES-NI "
    grep -qi "avx2"      /proc/cpuinfo 2>/dev/null && flags+="AVX2 "
    grep -qi "avx512"    /proc/cpuinfo 2>/dev/null && flags+="AVX-512 "
    grep -qi "vmx\|svm"  /proc/cpuinfo 2>/dev/null && flags+="VT-x/AMD-V "
    grep -qi "rdrand"    /proc/cpuinfo 2>/dev/null && flags+="RDRAND "
    [[ -n "$flags" ]] && kv "CPU Features" "$flags"

    # Load average
    local loadavg
    loadavg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')
    kv "Load Average (1/5/15)" "$loadavg"
    local load1
    load1=$(echo "$loadavg" | awk '{print $1}')
    if awk "BEGIN{exit !($load1 > $cpu_logical)}" 2>/dev/null; then
        echo -e "  ${BR_}  ⚠ WARNING: Load avg exceeds CPU count. Results may be unreliable.${RST_}"
    fi

    # I/O Scheduler (for disk)
    local iosched="N/A"
    for dev in sda nvme0; do
        if [[ -f "/sys/block/${dev}/queue/scheduler" ]]; then
            iosched=$(cat "/sys/block/${dev}/queue/scheduler" | grep -oP '\[\K[^\]]+')
            break
        fi
    done
    kv "I/O Scheduler"  "$iosched"

    # TCP Congestion Control
    local tcp_cc
    tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "N/A")
    kv "TCP Congestion Ctl" "$tcp_cc"

    # ── Memory ──
    section "Memory" "💾"
    local mt ma mu ms msc
    mt=$(awk '/MemTotal/    {printf "%.2f GiB", $2/1048576}' /proc/meminfo)
    ma=$(awk '/MemAvailable/{printf "%.2f GiB", $2/1048576}' /proc/meminfo)
    mu=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%.2f GiB",(t-a)/1048576}' \
             /proc/meminfo)
    ms=$(awk '/SwapTotal/{printf "%.2f GiB", $2/1048576}' /proc/meminfo)
    msc=$(awk '/SwapFree/{printf "%.2f GiB",  $2/1048576}' /proc/meminfo)

    kv "Total RAM"     "$mt"
    kv "Used RAM"      "$mu"
    kv "Available RAM" "$ma"
    kv "Swap Total"    "$ms"
    kv "Swap Free"     "$msc"

    # dmidecode memory type (root only)
    if cmd_exists dmidecode && [[ ${EUID} -eq 0 ]]; then
        local mem_type mem_speed
        mem_type=$(dmidecode -t memory 2>/dev/null | grep -m1 "Type:" | awk '{print $NF}')
        mem_speed=$(dmidecode -t memory 2>/dev/null | grep -m1 "Speed:" | awk '{print $2, $3}')
        [[ -n "$mem_type"  ]] && kv "RAM Type"  "$mem_type"
        [[ -n "$mem_speed" ]] && kv "RAM Speed" "$mem_speed"
    fi

    # ── Storage ──
    section "Storage" "💿"
    df -Ph 2>/dev/null | grep -v "^Filesystem\|tmpfs\|devtmpfs\|udev\|cgroupfs" | \
    while IFS= read -r line; do
        printf "  ${W_}%s${RST_}\n" "$line"
    done

    # Disk type detection
    local disk_type="Unknown"
    if ls /dev/nvme0* &>/dev/null 2>&1; then
        disk_type="NVMe SSD"
    elif [[ -f /sys/block/sda/queue/rotational ]]; then
        local rot
        rot=$(cat /sys/block/sda/queue/rotational 2>/dev/null)
        [[ "$rot" == "0" ]] && disk_type="SSD" || disk_type="HDD"
    fi
    kv "Detected Disk Type" "$disk_type"

    # ── Network ──
    section "Network Interfaces" "🌐"
    if cmd_exists ip; then
        ip -o addr show 2>/dev/null | \
        awk '{printf "  %-12s %-20s\n", $2, $4}' | \
        grep -v "^  lo "
    fi

    R[os]="$os_name"
    R[cpu_model]="$cpu_model"
    R[cpu_logical]="$cpu_logical"
    R[ram]="$mt"
    R[disk_type]="$disk_type"
    R[virt]="$virt"
}

# ─── CPU BENCHMARK ────────────────────────────────────────────────────────
bench_cpu() {
    box "CPU BENCHMARK" "${BM_}"

    # ── Pre-flight: CPU frequency check ──
    local cur_freq max_freq throttled=0
    cur_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
    if [[ -n "$cur_freq" && -n "$max_freq" ]]; then
        local pct
        pct=$(awk_int "$cur_freq * 100 / $max_freq")
        kv "CPU Frequency Utilization" "${pct}% of max"
        [[ $pct -lt 80 ]] && throttled=1 && \
            echo -e "  ${Y_}  ⚠ CPU may be throttled. Frequency at ${pct}% of max.${RST_}"
    fi

    # ── OpenSSL Crypto Throughput ──
    section "OpenSSL Throughput (5s each)" "🔐"

    local aes128 aes256 aesgcm sha256 sha512

    # Helper: run openssl speed and extract last 16384-byte result
    openssl_speed_mbps() {
        local algo="$1"
        openssl speed -elapsed -seconds 3 -evp "$algo" 2>/dev/null | \
        grep -i "$algo" | tail -1 | \
        awk '{
            # Last column is speed, may have k suffix
            v = $NF
            gsub(/k/, "", v)
            printf "%.1f", v / 1024
        }'
    }

    aes128=$(openssl_speed_mbps "aes-128-cbc")
    aes256=$(openssl_speed_mbps "aes-256-cbc")
    aesgcm=$(openssl_speed_mbps "aes-256-gcm")
    sha256=$(openssl_speed_mbps "sha256")
    sha512=$(openssl_speed_mbps "sha512")

    kv "AES-128-CBC"  "${aes128:-N/A} MB/s"
    kv "AES-256-CBC"  "${aes256:-N/A} MB/s"
    kv "AES-256-GCM"  "${aesgcm:-N/A} MB/s"
    kv "SHA-256"      "${sha256:-N/A} MB/s"
    kv "SHA-512"      "${sha512:-N/A} MB/s"

    # OpenSSL RSA
    section "RSA / ECDSA Performance" "🔑"
    local rsa_out
    rsa_out=$(openssl speed -elapsed -seconds 2 rsa2048 rsa4096 2>/dev/null | \
              grep -E "^rsa")
    if [[ -n "$rsa_out" ]]; then
        echo "$rsa_out" | while IFS= read -r line; do
            printf "  ${W_}%s${RST_}\n" "$line"
        done
    fi
    # ECDSA
    local ecdsa_out
    ecdsa_out=$(openssl speed -elapsed -seconds 2 ecdsap256 ecdsap384 2>/dev/null | \
                grep "ecdsa")
    [[ -n "$ecdsa_out" ]] && echo "$ecdsa_out" | while IFS= read -r line; do
        printf "  ${W_}%s${RST_}\n" "$line"
    done

    # ── sysbench CPU ──
    local cpu_score=50
    if cmd_exists sysbench; then
        section "sysbench CPU" "⚡"

        # Detect sysbench API version
        local sb_ver sb_new=0
        sb_ver=$(sysbench --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        awk "BEGIN{exit !(\"$sb_ver\"+0 >= 1.0)}" 2>/dev/null && sb_new=1

        run_sysbench_cpu() {
            local threads="$1"
            if [[ $sb_new -eq 1 ]]; then
                sysbench cpu \
                    --cpu-max-prime=20000 \
                    --threads="$threads" \
                    --time=10 run 2>/dev/null | \
                grep "events per second" | awk '{printf "%.2f", $NF}'
            else
                sysbench --test=cpu \
                    --cpu-max-prime=20000 \
                    --num-threads="$threads" run 2>/dev/null | \
                grep "events per second" | awk '{printf "%.2f", $NF}'
            fi
        }

        echo -e "  ${DIM_}Single-thread test (prime ≤ 20000, 10s)...${RST_}"
        local sb_single
        sb_single=$(run_sysbench_cpu 1)

        echo -e "  ${DIM_}Multi-thread test ($(nproc) threads, 10s)...${RST_}"
        local sb_multi
        sb_multi=$(run_sysbench_cpu "$(nproc)")

        # Latency from sysbench (ms)
        local sb_lat
        if [[ $sb_new -eq 1 ]]; then
            sb_lat=$(sysbench cpu --cpu-max-prime=20000 --threads=1 --time=5 run 2>/dev/null | \
                     grep "avg:" | awk '{print $2}')
        fi

        kv "Single-Thread Events/s" "${sb_single:-N/A}"
        kv "Multi-Thread Events/s"  "${sb_multi:-N/A}"
        [[ -n "${sb_lat:-}" ]] && kv "Avg Latency (1T)" "${sb_lat} ms"

        R[cpu_sb_single]="${sb_single:-0}"
        R[cpu_sb_multi]="${sb_multi:-0}"

        # Score: normalize to 100 at 2000 events/sec multi-thread
        if [[ -n "$sb_multi" ]] && awk "BEGIN{exit !($sb_multi > 0)}" 2>/dev/null; then
            cpu_score=$(awk_clamp "$sb_multi / 20" 5 100)
        fi
    else
        # ── Python prime sieve fallback ──
        section "Prime Sieve Benchmark (Python)" "⚡"
        echo -e "  ${DIM_}Sieve of Eratosthenes to n=5,000,000 (${ITER_CPU_PRIME} run)...${RST_}"

        local prime_time prime_count
        prime_time=$(python3 -c "
import time, sys
n = 5_000_000
start = time.perf_counter()
sieve = bytearray([1]) * (n + 1)
sieve[0] = sieve[1] = 0
for i in range(2, int(n**0.5) + 1):
    if sieve[i]:
        sieve[i*i::i] = bytearray(len(sieve[i*i::i]))
elapsed = time.perf_counter() - start
count = sum(sieve)
print(f'{elapsed:.4f} {count}')
" 2>/dev/null)

        local psec pcnt
        psec=$(echo "$prime_time" | awk '{print $1}')
        pcnt=$(echo "$prime_time" | awk '{print $2}')

        kv "Primes Found (≤ 5M)"   "${pcnt:-348513}"
        kv "Sieve Time"            "${psec:-N/A}s"

        R[cpu_prime_sec]="${psec:-0}"

        # Score: <0.3s → 90, <1s → 70, <3s → 50
        if [[ -n "$psec" ]]; then
            cpu_score=$(awk "BEGIN{
                t=$psec
                if(t<=0.2)     print 95
                else if(t<=0.5) print 80
                else if(t<=1)   print 65
                else if(t<=2)   print 50
                else if(t<=5)   print 35
                else            print 20
            }")
        fi
    fi

    # ── CPU Integer Multi-thread (additional) ──
    section "Multi-thread Integer Compute" "🧮"
    echo -e "  ${DIM_}Parallel SHA-256 hashing ($(nproc) threads, 5s)...${RST_}"
    local hash_result
    hash_result=$(python3 - <<'PYEOF' 2>/dev/null
import hashlib, threading, time

DURATION = 5
BLOCK    = 65536          # 64 KiB per hash
data     = b'x' * BLOCK
n        = __import__('os').cpu_count() or 1
results  = [0] * n

def worker(idx):
    end = time.perf_counter() + DURATION
    count = 0
    while time.perf_counter() < end:
        hashlib.sha256(data).digest()
        count += 1
    results[idx] = count * BLOCK

threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
[t.start() for t in threads]
[t.join()  for t in threads]
total_mb = sum(results) / 1024 / 1024
print(f"{total_mb / DURATION:.1f}")
PYEOF
)
    kv "Parallel SHA-256 ($(nproc)T)" "${hash_result:-N/A} MB/s"

    [[ $throttled -eq 1 ]] && cpu_score=$(awk_clamp "$cpu_score * 0.85" 0 100)
    S[cpu]=$cpu_score
    echo
    echo -e "  ${BG_}CPU Score: ${S[cpu]}/100${RST_}"
    R[cpu_score]="${S[cpu]}"
}

# ─── MEMORY BENCHMARK ─────────────────────────────────────────────────────
bench_memory() {
    box "MEMORY BENCHMARK" "${BM_}"

    local mem_score=50

    if cmd_exists sysbench; then
        section "sysbench Memory Bandwidth" "💾"

        # Detect sysbench API
        local sb_new=0
        local sb_ver
        sb_ver=$(sysbench --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        awk "BEGIN{exit !(\"$sb_ver\"+0 >= 1.0)}" 2>/dev/null && sb_new=1

        # Parse sysbench memory output:
        # v1.x line → "102400.00 MiB transferred (27745.69 MiB/sec)"
        # v0.4x line → "3264.00 MB transferred (108864.31 MB/sec)"
        # Strip parens, then find the field ending in /sec and print the one before it.
        _sb_mem_bw() {
            awk '/transferred/{
                gsub(/[()]/,"")
                for(i=1;i<=NF;i++)
                    if($i ~ /\/sec$/) { printf "%.2f", $(i-1); exit }
            }'
        }

        run_sb_mem() {
            local oper="$1"
            if [[ $sb_new -eq 1 ]]; then
                sysbench memory \
                    --memory-total-size=8G \
                    --memory-oper="$oper" \
                    --threads="$(nproc)" run 2>/dev/null | _sb_mem_bw
            else
                sysbench --test=memory \
                    --memory-total-size=8G \
                    --memory-oper="$oper" \
                    --num-threads="$(nproc)" run 2>/dev/null | _sb_mem_bw
            fi
        }

        echo -e "  ${DIM_}Sequential write ($(nproc) threads, 8 GiB total)...${RST_}"
        local mem_wr
        mem_wr=$(run_sb_mem write)

        echo -e "  ${DIM_}Sequential read  ($(nproc) threads, 8 GiB total)...${RST_}"
        local mem_rd
        mem_rd=$(run_sb_mem read)

        # Convert MiB/s to GiB/s for display
        local wr_gibs rd_gibs
        wr_gibs=$(awk_calc "${mem_wr:-0} / 1024")
        rd_gibs=$(awk_calc "${mem_rd:-0} / 1024")

        kv "Write Bandwidth" "${mem_wr:-N/A} MiB/s  (${wr_gibs} GiB/s)"
        kv "Read  Bandwidth" "${mem_rd:-N/A} MiB/s  (${rd_gibs} GiB/s)"

        R[mem_write_bw]="${mem_wr:-0}"
        R[mem_read_bw]="${mem_rd:-0}"

        # Score baseline: 40 GiB/s = 100 pts  (DDR5-4800 dual-channel reference)
        #   DDR3 ~ 8-12  GiB/s  →  20-30 pts
        #   DDR4 ~15-25  GiB/s  →  37-62 pts
        #   DDR5 ~25-55  GiB/s  →  62-100 pts
        if [[ -n "$mem_rd" ]] && awk "BEGIN{exit !($mem_rd > 0)}" 2>/dev/null; then
            mem_score=$(awk_clamp "$mem_rd / 409.6" 5 100)
        fi
    else
        section "dd-based Memory Bandwidth (/dev/shm)" "💾"
        local shm_dir="/dev/shm"
        [[ ! -w "$shm_dir" ]] && shm_dir="$TMPDIR_B"

        local wr_speeds=()
        local rd_speeds=()

        for i in 1 2 3; do
            local tf="${shm_dir}/membench_${i}"
            echo -e "  ${DIM_}Write pass ${i}/3 (512 MiB)...${RST_}"
            local dd_out
            dd_out=$(dd if=/dev/zero of="$tf" bs=1M count=512 conv=fdatasync 2>&1)
            local spd
            spd=$(dd_to_mbps "$dd_out")
            [[ -n "$spd" ]] && wr_speeds+=("$spd")

            echo -e "  ${DIM_}Read  pass ${i}/3...${RST_}"
            dd_out=$(dd if="$tf" of=/dev/null bs=1M 2>&1)
            spd=$(dd_to_mbps "$dd_out")
            [[ -n "$spd" ]] && rd_speeds+=("$spd")
            rm -f "$tf"
        done

        local avg_wr avg_rd
        [[ ${#wr_speeds[@]} -gt 0 ]] && avg_wr=$(awk_avg "${wr_speeds[@]}") || avg_wr="N/A"
        [[ ${#rd_speeds[@]} -gt 0 ]] && avg_rd=$(awk_avg "${rd_speeds[@]}") || avg_rd="N/A"

        kv "Avg Write" "${avg_wr} MB/s"
        kv "Avg Read"  "${avg_rd} MB/s"

        R[mem_write_bw]="${avg_wr:-0}"
        R[mem_read_bw]="${avg_rd:-0}"

        if [[ "$avg_rd" != "N/A" ]]; then
            mem_score=$(awk_clamp "$avg_rd / 40" 5 100)
        fi
    fi

    # Memory latency (Python)
    section "Memory Latency (pointer-chase)" "⏱"
    echo -e "  ${DIM_}Random pointer-chase pattern, 64 MiB array...${RST_}"
    local lat_ns
    lat_ns=$(python3 -c "
import ctypes, time, random
n = 1 << 23  # 8M pointers × 8B = 64 MiB
arr = list(range(n))
random.shuffle(arr)
arr2 = (ctypes.c_long * n)(*arr)
steps = 1_000_000
i = 0
start = time.perf_counter()
for _ in range(steps):
    i = arr2[i]
elapsed = time.perf_counter() - start
print(f'{elapsed * 1e9 / steps:.1f}')
" 2>/dev/null)
    kv "Avg Latency" "${lat_ns:-N/A} ns"
    R[mem_latency_ns]="${lat_ns:-0}"

    S[mem]=$mem_score
    echo
    echo -e "  ${BG_}Memory Score: ${S[mem]}/100${RST_}"
    R[mem_score]="${S[mem]}"
}

# ─── DISK I/O BENCHMARK ───────────────────────────────────────────────────
bench_disk() {
    [[ $OPT_NO_DISK -eq 1 ]] && { echo -e "  ${Y_}Disk tests skipped (--no-disk)${RST_}"; return; }
    box "DISK I/O BENCHMARK" "${BM_}"

    # Free space check
    local free_mb
    free_mb=$(df "${TMPDIR_B}" 2>/dev/null | tail -1 | awk '{print int($4/1024)}')
    kv "Free Space (test dir)" "${free_mb:-?} MiB"
    if [[ "${free_mb:-0}" -lt 2200 ]]; then
        echo -e "  ${BR_}⚠ Less than 2.2 GiB free. Reducing test size.${RST_}"
    fi

    local disk_score=40
    local seq_wr_speeds=() seq_rd_speeds=()

    # ── Sequential Write ──
    section "Sequential Write  (dd, bs=1M, fdatasync)" "📝"
    for i in $(seq 1 $ITER_DISK); do
        echo -e "  ${DIM_}Pass ${i}/${ITER_DISK} — writing 1 GiB...${RST_}"
        local dd_out
        dd_out=$(dd if=/dev/zero of="${DISK_TESTFILE}" \
                    bs=1M count=1024 conv=fdatasync 2>&1)
        local spd
        spd=$(dd_to_mbps "$dd_out")
        [[ -n "$spd" ]] && seq_wr_speeds+=("$spd")
        kv "  Write #${i}" "${spd:-?} MB/s"
        sync
    done

    # ── Sequential Read ──
    section "Sequential Read   (dd, bs=1M)" "📖"
    for i in $(seq 1 $ITER_DISK); do
        # Drop page cache (root only)
        [[ ${EUID} -eq 0 ]] && \
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        echo -e "  ${DIM_}Pass ${i}/${ITER_DISK} — reading 1 GiB...${RST_}"
        local dd_out
        dd_out=$(dd if="${DISK_TESTFILE}" of=/dev/null bs=1M 2>&1)
        local spd
        spd=$(dd_to_mbps "$dd_out")
        [[ -n "$spd" ]] && seq_rd_speeds+=("$spd")
        kv "  Read  #${i}" "${spd:-?} MB/s"
    done

    local avg_wr avg_rd
    [[ ${#seq_wr_speeds[@]} -gt 0 ]] && avg_wr=$(awk_avg "${seq_wr_speeds[@]}") || avg_wr=0
    [[ ${#seq_rd_speeds[@]} -gt 0 ]] && avg_rd=$(awk_avg "${seq_rd_speeds[@]}") || avg_rd=0

    echo
    kv "Avg Sequential Write" "${avg_wr} MB/s"
    kv "Avg Sequential Read"  "${avg_rd} MB/s"
    R[disk_seq_wr]="${avg_wr}"
    R[disk_seq_rd]="${avg_rd}"

    # ── Sync / fsync latency ──
    section "Sync Write Latency  (4K blocks, oflag=sync, 64 MiB)" "⏱"
    local sync_out sync_mbps
    sync_out=$(dd if=/dev/zero of="${DISK_TESTFILE}_sync" \
                  bs=4k count=16384 oflag=sync 2>&1)
    sync_mbps=$(dd_to_mbps "$sync_out")
    if [[ -n "$sync_mbps" ]]; then
        if awk "BEGIN{exit !($sync_mbps >= 1000)}" 2>/dev/null; then
            kv "4K Sync Write" "$(awk_calc "$sync_mbps / 1024") GB/s"
        else
            kv "4K Sync Write" "${sync_mbps} MB/s"
        fi
    else
        kv "4K Sync Write" "N/A"
    fi
    rm -f "${DISK_TESTFILE}_sync"

    # ── fio random I/O ──
    if cmd_exists fio; then
        section "Random I/O  (fio, 4K, libaio, QD=64)" "🎲"

        fio_run() {
            local label="$1" rw="$2" extra="${3:-}"
            echo -e "  ${DIM_}${label}...${RST_}" >&2
            local out
            out=$(fio \
                --name="vbench_${rw}" \
                --filename="${DISK_TESTFILE}" \
                --rw="$rw" $extra \
                --bs=4k \
                --size=512M \
                --numjobs=4 \
                --runtime=10 \
                --time_based \
                --group_reporting \
                --ioengine=libaio \
                --iodepth=64 \
                --output-format=json 2>/dev/null)

            # Parse JSON output
            python3 - <<PYEOF 2>/dev/null
import json, sys
data = json.loads('''$out''') if '''$out''' else {}
jobs = data.get('jobs', [{}])
r = jobs[0].get('read', {})
w = jobs[0].get('write', {})
r_iops  = r.get('iops', 0)
w_iops  = w.get('iops', 0)
r_bw    = r.get('bw', 0) / 1024
w_bw    = w.get('bw', 0) / 1024
r_lat   = r.get('lat_ns', {}).get('mean', 0) / 1000
w_lat   = w.get('lat_ns', {}).get('mean', 0) / 1000
print(f"R:{r_iops:.0f} IOPS / {r_bw:.1f} MiB/s / lat {r_lat:.0f}µs  "
      f"W:{w_iops:.0f} IOPS / {w_bw:.1f} MiB/s / lat {w_lat:.0f}µs")
PYEOF
        }

        local rand_rd rand_wr rand_mix
        rand_rd=$(fio_run  "4K random read (QD64, 4 jobs)" "randread")
        rand_wr=$(fio_run  "4K random write (QD64, 4 jobs)" "randwrite")
        rand_mix=$(fio_run "4K mixed RW 70/30 (QD64)"       "randrw" "--rwmixread=70")

        kv "  Rand Read"    "${rand_rd:-N/A}"
        kv "  Rand Write"   "${rand_wr:-N/A}"
        kv "  Mixed 70/30"  "${rand_mix:-N/A}"

        R[disk_rand_rd]="${rand_rd:-N/A}"
        R[disk_rand_wr]="${rand_wr:-N/A}"

        # fio-based score: extract first IOPS number
        local riops
        riops=$(echo "${rand_rd:-0}" | grep -oP 'R:[\d.]+' | grep -oP '[\d.]+' | head -1)
        if [[ -n "$riops" ]]; then
            disk_score=$(awk_clamp "$riops / 1000" 5 100)
        fi
    else
        # dd-based score
        disk_score=$(awk "BEGIN{
            w=$avg_wr; r=$avg_rd; avg=(w+r)/2
            if(avg>=800)       print 100
            else if(avg>=500)  print 80
            else if(avg>=250)  print 65
            else if(avg>=100)  print 50
            else if(avg>=50)   print 35
            else               print 20
        }")
    fi

    rm -f "${DISK_TESTFILE}"
    S[disk]=$disk_score
    echo
    echo -e "  ${BG_}Disk Score: ${S[disk]}/100${RST_}"
    R[disk_score]="${S[disk]}"
}

# ─── NETWORK BENCHMARK ────────────────────────────────────────────────────
bench_network() {
    [[ $OPT_NO_NETWORK -eq 1 ]] && { echo -e "  ${Y_}Network tests skipped (--no-network)${RST_}"; return; }
    box "NETWORK BENCHMARK" "${BM_}"

    local net_score=50

    # ── Public IP & Geo ──
    section "Public IP & Geolocation" "🌍"
    local pub_ipv4 pub_ipv6
    pub_ipv4=$(curl -4 -s --connect-timeout 6 https://api.ipify.org 2>/dev/null || \
               curl -4 -s --connect-timeout 6 https://ipecho.net/plain 2>/dev/null || \
               echo "N/A")
    pub_ipv6=$(curl -6 -s --connect-timeout 6 https://api64.ipify.org 2>/dev/null || echo "N/A")

    kv "Public IPv4" "$pub_ipv4"
    kv "Public IPv6" "${pub_ipv6:0:45}${pub_ipv6:45:+...}"

    if [[ "$pub_ipv4" != "N/A" ]]; then
        local geo
        geo=$(curl -s --connect-timeout 6 \
              "http://ip-api.com/json/${pub_ipv4}?fields=country,regionName,city,isp,org,as" \
              2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"{d.get('city','?')}, {d.get('regionName','?')}, {d.get('country','?')} | {d.get('org','?')}\")" \
              2>/dev/null)
        [[ -n "$geo" ]] && kv "Location / Org" "$geo"
    fi
    R[public_ipv4]="${pub_ipv4:-N/A}"

    # ── IPv6 Connectivity ──
    local ipv6_ok=0
    if [[ "$pub_ipv6" != "N/A" ]] && [[ ! "$pub_ipv6" =~ ^N ]]; then
        kv2 "IPv6 Connectivity" "${BG_}" "✔ Available"
        ipv6_ok=1
    else
        kv2 "IPv6 Connectivity" "${R_}" "✘ Not available"
    fi

    # ── Latency Tests ──
    section "ICMP Latency" "📡"

    declare -A PING_NODES=(
        ["Cloudflare (Global)"]="1.1.1.1"
        ["Google DNS (US)"]="8.8.8.8"
        ["Quad9 (EU/US)"]="9.9.9.9"
        ["Level3 (US)"]="4.2.2.1"
    )

    local min_rtt=9999
    for node_name in "${!PING_NODES[@]}"; do
        local host="${PING_NODES[$node_name]}"
        local rtt
        rtt=$(ping -c 5 -q -W 3 "$host" 2>/dev/null | \
              awk -F'[=/]' '/rtt|round-trip/{printf "%.2f ms (jitter ±", $5; printf "%.2f ms)", $7}')
        if [[ -n "$rtt" ]]; then
            kv "  $node_name" "$rtt"
            local raw
            raw=$(echo "$rtt" | grep -oP '[\d.]+' | head -1)
            awk "BEGIN{exit !($raw < $min_rtt)}" 2>/dev/null && min_rtt="$raw"
        else
            kv "  $node_name" "${Y_}Unreachable${RST_}"
        fi
    done

    # Regional latency — using geographically anchored IPs (IXP / national NOCs)
    # NOT anycast (Cloudflare/Google/Quad9 respond from nearest PoP, not the labelled city)
    section "Regional Latency" "🗺"
    declare -A REGIONAL=(
        ["Tokyo (JP)"]="210.171.224.1"      # JPIX Tokyo
        ["Singapore (SG)"]="202.12.28.1"    # APNIC Singapore
        ["London (UK)"]="195.66.226.11"     # LINX London
        ["Frankfurt (DE)"]="80.81.194.2"    # DE-CIX Frankfurt
        ["São Paulo (BR)"]="200.219.141.10" # PTT São Paulo
        ["Sydney (AU)"]="203.12.160.35"     # AARNet Sydney
        ["New York (US)"]="198.32.160.26"   # NYIIX New York
        ["Los Angeles (US)"]="206.197.187.10" # LAIIX Los Angeles
    )
    for region in "${!REGIONAL[@]}"; do
        local host="${REGIONAL[$region]}"
        local rtt
        rtt=$(ping -c 3 -q -W 4 "$host" 2>/dev/null | \
              awk -F'[=/]' '/rtt|round-trip/{printf "%.1f ms", $5}')
        kv "  $region" "${rtt:-Timeout}"
    done

    # ── Download Speed ──
    section "Download Speed Tests" "⬇"

    declare -A DL_SERVERS=(
        ["Hetzner DE (100MB)"]="https://speed.hetzner.de/100MB.bin"
        ["OVH BHS (100MB)"]="https://proof.ovh.net/files/100Mb.dat"
        ["Linode Tokyo (100MB)"]="https://speed.tokyo2.linode.com/100MB-tokyo2.bin"
        ["Linode Singapore (100MB)"]="https://speed.singapore.linode.com/100MB-singapore.bin"
        ["Vultr Paris (100MB)"]="https://par-fr-ping.vultr.com/vultr.com.100MB.bin"
    )

    local dl_speeds=()
    for srv_name in "${!DL_SERVERS[@]}"; do
        echo -e "  ${DIM_}↓ ${srv_name}...${RST_}"
        local url="${DL_SERVERS[$srv_name]}"
        local bytes_sec
        bytes_sec=$(curl -s -o /dev/null -w "%{speed_download}" \
                    --connect-timeout 8 --max-time 25 \
                    --retry 1 --retry-max-time 30 \
                    "$url" 2>/dev/null)
        local mbps
        mbps=$(awk_calc "${bytes_sec:-0} * 8 / 1000000")
        # Require at least 0.5 Mbps to count as a valid result
        if awk "BEGIN{exit !($mbps > 0.5)}" 2>/dev/null; then
            kv "  ${srv_name}" "${mbps} Mbps"
            dl_speeds+=("$mbps")
        else
            kv "  ${srv_name}" "${Y_}Unreachable / timeout${RST_}"
        fi
    done

    if [[ ${#dl_speeds[@]} -gt 0 ]]; then
        local avg_dl max_dl
        avg_dl=$(awk_avg "${dl_speeds[@]}")
        max_dl=$(printf '%s\n' "${dl_speeds[@]}" | sort -n | tail -1)
        echo
        kv "Average Download" "${avg_dl} Mbps"
        kv "Peak Download"    "${max_dl} Mbps"
        R[net_avg_dl_mbps]="${avg_dl}"
        R[net_peak_dl_mbps]="${max_dl}"
        net_score=$(awk_clamp "($max_dl > $avg_dl ? $max_dl : $avg_dl) / 10" 5 100)
    fi

    # ── iperf3 ──
    if cmd_exists iperf3; then
        section "iperf3 TCP Throughput" "📊"
        echo -e "  ${Y_}Requires reachable iperf3 server. Trying public endpoints...${RST_}"
        local iperf_servers=("iperf.he.net" "bouygues.iperf.fr" "ping.online.net")
        for srv in "${iperf_servers[@]}"; do
            echo -e "  ${DIM_}Connecting to ${srv}:5201...${RST_}"
            local res
            res=$(timeout 35 iperf3 -c "$srv" -t 10 -P 4 2>/dev/null | \
                  grep "SUM" | grep "receiver" | \
                  awk '{printf "%s %s\n", $6, $7}')
            if [[ -n "$res" ]]; then
                kv "  $srv" "$res"
                break
            fi
        done
    fi

    # Latency-based net score boost
    if awk "BEGIN{exit !($min_rtt < 10)}" 2>/dev/null; then
        net_score=$(awk_clamp "$net_score + 5" 0 100)
    fi

    S[net]=$net_score
    echo
    echo -e "  ${BG_}Network Score: ${S[net]}/100${RST_}"
    R[net_score]="${S[net]}"
}

# ─── COMPRESSION BENCHMARK ────────────────────────────────────────────────
bench_compression() {
    [[ $OPT_NO_COMPRESS -eq 1 ]] && { echo -e "  ${Y_}Compression tests skipped.${RST_}"; return; }
    box "COMPRESSION BENCHMARK" "${BM_}"

    section "Preparing 256 MiB Random Data" "📦"
    echo -e "  ${DIM_}dd from /dev/urandom → tmpfs (this may take a moment)...${RST_}"
    dd if=/dev/urandom of="${COMPRESS_TESTFILE}" bs=1M count=256 &>/dev/null
    echo -e "  ${BG_}✔ Source file ready${RST_}"

    local src_size=268435456   # 256 MiB in bytes

    compress_bench() {
        local name="$1"; shift
        local compress_cmd=("$@")
        local ext="${compress_cmd[-1]}"       # last arg = extension, removed next
        unset "compress_cmd[-1]"

        local out_file="${TMPDIR_B}/bench.${ext}"

        # Compress
        local t0 t1 t_comp size ratio comp_mbps
        t0=$(now_ms)
        "${compress_cmd[@]}" < "${COMPRESS_TESTFILE}" > "$out_file" 2>/dev/null
        t1=$(now_ms)
        t_comp=$(awk_calc "($t1 - $t0) / 1000")
        size=$(wc -c < "$out_file" 2>/dev/null || echo 0)
        ratio=$(awk "BEGIN{printf \"%.1f\", $size * 100 / $src_size}")
        comp_mbps=$(awk_calc "256 / ($t_comp < 0.001 ? 0.001 : $t_comp)")

        # Decompress
        local decomp_cmd t_decomp decomp_mbps
        case "$ext" in
            gz)  decomp_cmd=(gzip  -dc) ;;
            bz2) decomp_cmd=(bzip2 -dc) ;;
            xz)  decomp_cmd=(xz    -dc) ;;
            zst) decomp_cmd=(zstd  -dc) ;;
            lz4) decomp_cmd=(lz4   -dc) ;;
        esac
        t0=$(now_ms)
        "${decomp_cmd[@]}" "$out_file" > /dev/null 2>/dev/null
        t1=$(now_ms)
        t_decomp=$(awk_calc "($t1 - $t0) / 1000")
        decomp_mbps=$(awk_calc "256 / ($t_decomp < 0.001 ? 0.001 : $t_decomp)")

        printf "  ${C_}%-10s${RST_}  ${W_}Cmp: %6.1f MB/s  Ratio: %5.1f%%  Dcmp: %6.1f MB/s${RST_}\n" \
               "$name" "$comp_mbps" "$ratio" "$decomp_mbps"

        rm -f "$out_file"
    }

    section "Tool Comparison (level 1 — speed-optimized)" "⚙"
    compress_bench "gzip -1"  gzip  -1  -c gz
    compress_bench "bzip2 -1" bzip2 -1  -c bz2
    cmd_exists xz   && compress_bench "xz -1"   xz   -1  -c xz
    cmd_exists zstd && compress_bench "zstd -1"  zstd -1  -c --  zst
    cmd_exists lz4  && compress_bench "lz4 -1"   lz4  -1  -c lz4

    section "gzip Default (level 6)" "⚙"
    compress_bench "gzip -6"  gzip  -6  -c gz
    cmd_exists zstd && {
        section "zstd Level 3 (balanced)" "⚙"
        compress_bench "zstd -3"  zstd  -3  -c --  zst
    }

    rm -f "${COMPRESS_TESTFILE}"
}

# ─── FINAL SCORING & REPORT ───────────────────────────────────────────────
calc_score_and_report() {
    box "PERFORMANCE SCORE" "${BY_}"

    # Weighted composite
    # CPU 35 / Mem 15 / Disk 30 / Net 20
    local w_cpu=35 w_mem=15 w_disk=30 w_net=20
    local composite
    composite=$(awk_calc "${S[cpu]} * $w_cpu/100 + \
                          ${S[mem]} * $w_mem/100 + \
                          ${S[disk]} * $w_disk/100 + \
                          ${S[net]} * $w_net/100")
    local ci
    ci=$(awk_int "$composite")

    section "Component Scores" "📊"
    progress_bar "CPU        (35%)" "${S[cpu]}"
    progress_bar "Memory     (15%)" "${S[mem]}"
    progress_bar "Disk I/O   (30%)" "${S[disk]}"
    progress_bar "Network    (20%)" "${S[net]}"

    # Grade
    local grade color_g
    if   [[ $ci -ge 95 ]]; then grade="S+" && color_g="${BM_}"
    elif [[ $ci -ge 85 ]]; then grade="S"  && color_g="${BM_}"
    elif [[ $ci -ge 75 ]]; then grade="A"  && color_g="${BG_}"
    elif [[ $ci -ge 65 ]]; then grade="B"  && color_g="${G_}"
    elif [[ $ci -ge 55 ]]; then grade="C"  && color_g="${BC_}"
    elif [[ $ci -ge 45 ]]; then grade="D"  && color_g="${Y_}"
    elif [[ $ci -ge 35 ]]; then grade="E"  && color_g="${Y_}"
    else                        grade="F"  && color_g="${BR_}"
    fi

    echo
    echo -e "  ${color_g}$(hr '━' 68)${RST_}"
    printf "  ${color_g}  %-30s${BW_}%s / 100${color_g}   Grade: ${BW_}%-3s${RST_}\n" \
           "COMPOSITE SCORE:" "$composite" "$grade"
    echo -e "  ${color_g}$(hr '━' 68)${RST_}"

    # Elapsed time
    local elapsed
    elapsed=$(( $(date +%s) - BENCH_START_TS ))
    echo
    kv "Total benchmark time" "${elapsed}s ($(( elapsed / 60 ))m $(( elapsed % 60 ))s)"

    # ── Text Report ──
    {
        printf '%s\n' "$(hr '═' 72)"
        printf ' VPS BENCHMARK REPORT  ·  v%s  ·  Lab_0x4E Edition\n' "$BENCH_VERSION"
        printf ' Author: Fattain Naime | https://iamnaime.info.bd\n'
        printf '%s\n' "$(hr '═' 72)"
        printf ' Date         : %s\n' "$BENCH_DATE"
        printf ' Hostname     : %s\n' "$(hostname -f 2>/dev/null || hostname)"
        printf ' OS           : %s\n' "${R[os]:-N/A}"
        printf ' Kernel       : %s\n' "$(uname -r)"
        printf ' CPU          : %s\n' "${R[cpu_model]:-N/A}"
        printf ' Logical CPUs : %s\n' "${R[cpu_logical]:-N/A}"
        printf ' RAM          : %s\n' "${R[ram]:-N/A}"
        printf ' Disk Type    : %s\n' "${R[disk_type]:-N/A}"
        printf ' Virtualization: %s\n' "${R[virt]:-N/A}"
        printf ' Public IPv4  : %s\n' "${R[public_ipv4]:-N/A}"
        printf '%s\n' "$(hr '─' 72)"
        printf ' SCORES\n'
        printf '   CPU      : %s/100\n' "${S[cpu]}"
        printf '   Memory   : %s/100\n' "${S[mem]}"
        printf '   Disk I/O : %s/100\n' "${S[disk]}"
        printf '   Network  : %s/100\n' "${S[net]}"
        printf '   COMPOSITE: %s/100  [Grade: %s]\n' "$composite" "$grade"
        printf '%s\n' "$(hr '─' 72)"
        printf ' RAW RESULTS\n'
        printf '   CPU sysbench single  : %s events/s\n' "${R[cpu_sb_single]:-N/A}"
        printf '   CPU sysbench multi   : %s events/s\n' "${R[cpu_sb_multi]:-N/A}"
        printf '   Memory Write         : %s MiB/s\n'    "${R[mem_write_bw]:-N/A}"
        printf '   Memory Read          : %s MiB/s\n'    "${R[mem_read_bw]:-N/A}"
        printf '   Memory Latency       : %s ns\n'        "${R[mem_latency_ns]:-N/A}"
        printf '   Disk Seq Write       : %s MB/s\n'     "${R[disk_seq_wr]:-N/A}"
        printf '   Disk Seq Read        : %s MB/s\n'     "${R[disk_seq_rd]:-N/A}"
        printf '   Disk Rand Read       : %s\n'           "${R[disk_rand_rd]:-N/A}"
        printf '   Disk Rand Write      : %s\n'           "${R[disk_rand_wr]:-N/A}"
        printf '   Net Avg Download     : %s Mbps\n'     "${R[net_avg_dl_mbps]:-N/A}"
        printf '   Net Peak Download    : %s Mbps\n'     "${R[net_peak_dl_mbps]:-N/A}"
        printf '%s\n' "$(hr '═' 72)"
        printf ' Generated by: VoidBench v%s\n' "$BENCH_VERSION"
        printf ' https://github.com/fattain-naime/VoidBench  |  Lab_0x4E\n'
        printf '%s\n' "$(hr '═' 72)"
    } > "$REPORT_TXT"

    echo -e "\n  ${BG_}✔${RST_} Report saved  → ${W_}${REPORT_TXT}${RST_}"

    # ── JSON Report ──
    if [[ $OPT_JSON -eq 1 ]]; then
        python3 - <<PYEOF > "$REPORT_JSON" 2>/dev/null
import json, datetime
data = {
  "meta": {
    "version": "${BENCH_VERSION}",
    "date": "${BENCH_DATE}",
    "hostname": "$(hostname -f 2>/dev/null || hostname)",
    "os": "${R[os]:-unknown}",
    "kernel": "$(uname -r)",
    "arch": "$(uname -m)"
  },
  "hardware": {
    "cpu_model":   "${R[cpu_model]:-unknown}",
    "cpu_logical": ${R[cpu_logical]:-0},
    "ram":         "${R[ram]:-unknown}",
    "disk_type":   "${R[disk_type]:-unknown}",
    "virt":        "${R[virt]:-unknown}",
    "public_ipv4": "${R[public_ipv4]:-unknown}"
  },
  "scores": {
    "cpu":       ${S[cpu]},
    "memory":    ${S[mem]},
    "disk":      ${S[disk]},
    "network":   ${S[net]},
    "composite": ${composite},
    "grade":     "${grade}"
  },
  "raw": {
    "cpu_sb_single_eps":   "${R[cpu_sb_single]:-N/A}",
    "cpu_sb_multi_eps":    "${R[cpu_sb_multi]:-N/A}",
    "mem_write_mbps":      "${R[mem_write_bw]:-N/A}",
    "mem_read_mbps":       "${R[mem_read_bw]:-N/A}",
    "mem_latency_ns":      "${R[mem_latency_ns]:-N/A}",
    "disk_seq_write_mbps": "${R[disk_seq_wr]:-N/A}",
    "disk_seq_read_mbps":  "${R[disk_seq_rd]:-N/A}",
    "disk_rand_rd":        "${R[disk_rand_rd]:-N/A}",
    "disk_rand_wr":        "${R[disk_rand_wr]:-N/A}",
    "net_avg_dl_mbps":     "${R[net_avg_dl_mbps]:-N/A}",
    "net_peak_dl_mbps":    "${R[net_peak_dl_mbps]:-N/A}"
  }
}
print(json.dumps(data, indent=2))
PYEOF
        echo -e "  ${BG_}✔${RST_} JSON report saved → ${W_}${REPORT_JSON}${RST_}"
    fi
}

# ─── BANNER ───────────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${BB_}"
    cat << 'BANNER'
 ╔════════════════════════════════════════════════════════════════════════════╗
 ║                                                                            ║
 ║   ██╗   ██╗ ██████╗ ██╗██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗  ██╗  ║
 ║   ██║   ██║██╔═══██╗██║██╔══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║  ║
 ║   ██║   ██║██║   ██║██║██║  ██║██████╔╝█████╗  ██╔██╗ ██║██║     ███████║  ║
 ║   ╚██╗ ██╔╝██║   ██║██║██║  ██║██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══██║  ║
 ║    ╚████╔╝ ╚██████╔╝██║██████╔╝██████╔╝███████╗██║ ╚████║╚██████╗██║  ██║  ║
 ║     ╚═══╝   ╚═════╝ ╚═╝╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝  ║                                                                      ║                                                                       ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║   Benchmark Suite v2.2.0  ·  Lab_0x4E Edition                              ║
 ║   Author: Fattain Naime  |  https://iamnaime.info.bd                       ║
 ║   Tests: CPU · Memory · Disk I/O · Network · Crypto · Compression          ║
 ╚════════════════════════════════════════════════════════════════════v═══════╝
BANNER
    echo -e "${RST_}"

    [[ ${EUID} -ne 0 ]] && \
        echo -e "  ${Y_}⚠  Not running as root. Some tests may be limited.${RST_}\n  ${DIM_}   Tip: sudo $0${RST_}\n"

    [[ $OPT_QUICK -eq 1 ]] && \
        echo -e "  ${Y_}⚡ QUICK MODE: Iterations reduced.${RST_}\n"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    setup_colors
    print_banner

    check_deps
    collect_sysinfo
    bench_cpu
    bench_memory
    bench_disk
    bench_network
    bench_compression
    calc_score_and_report

    echo
    echo -e "${BC_}$(hr '━' 72)${RST_}"
    echo -e "  ${BW_}All benchmarks complete.${RST_}  Check ${G_}${REPORT_TXT}${RST_} for the full report."
    echo -e "${BC_}$(hr '━' 72)${RST_}"
    echo
}

main "$@"
