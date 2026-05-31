<div align="center">

<pre>
██╗   ██╗ ██████╗ ██╗██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗  ██╗
██║   ██║██╔═══██╗██║██╔══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║
██║   ██║██║   ██║██║██║  ██║██████╔╝█████╗  ██╔██╗ ██║██║     ███████║
╚██╗ ██╔╝██║   ██║██║██║  ██║██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══██║
 ╚████╔╝ ╚██████╔╝██║██████╔╝██████╔╝███████╗██║ ╚████║╚██████╗██║  ██║
  ╚═══╝   ╚═════╝ ╚═╝╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝
</pre>

### Decipher your infrastructure.

[![Version](https://img.shields.io/badge/version-2.0.0-00f7ff?style=flat-square)](https://github.com/fattain-naime/voidbench/releases)
[![License](https://img.shields.io/badge/license-MIT-22c55e?style=flat-square)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash%204%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](voidbench.sh)
[![Platform](https://img.shields.io/badge/platform-Linux-0ea5e9?style=flat-square&logo=linux&logoColor=white)](https://github.com/fattain-naime/voidbench)
[![Lab](https://img.shields.io/badge/lab-0x4E-ef4444?style=flat-square)](https://github.com/fattain-naime)
[![Author](https://img.shields.io/badge/author-Fattain%20Naime-a855f7?style=flat-square)](https://iamnaime.info.bd)

</div>

---

**VoidBench** is a single-file, production-grade VPS benchmark suite for Linux.  
It profiles CPU, memory, disk I/O, network, cryptography, and compression — then produces a weighted composite score with letter grade and saves a full text/JSON report. No installation required.

---

## ⚡ One-Line Run

```bash
curl -fsSL https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh | sudo bash
```

> Root is recommended for cache drops, `dmidecode`, and auto-installing optional tools (`sysbench`, `fio`, `iperf3`). Non-root works with reduced coverage.

---

## 📥 All Install Methods

### Method 1 — Pipe to bash (fastest)
```bash
curl -fsSL https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh | sudo bash
```

### Method 2 — Download, inspect, run (recommended for production)
```bash
# Step 1: download
curl -fsSL https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh \
     -o voidbench.sh

# Step 2: read the script (always good practice)
less voidbench.sh

# Step 3: execute
chmod +x voidbench.sh
sudo ./voidbench.sh
```

### Method 3 — wget
```bash
wget -qO voidbench.sh \
     https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh \
  && chmod +x voidbench.sh \
  && sudo ./voidbench.sh
```

### Method 4 — Clone the repo
```bash
git clone https://github.com/fattain-naime/voidbench.git
cd voidbench
sudo ./voidbench.sh
```

### Method 5 — With flags, pipe style
```bash
# Quick mode, also emit JSON, no color for clean log file
curl -fsSL https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh \
  | sudo bash -s -- --quick --json --no-color 2>&1 | tee voidbench_$(hostname -s).log
```

---

## 🧪 What It Tests

| Module | What's Measured | Tools Used | Fallback |
|--------|----------------|-----------|---------|
| **CPU** | AES-128/256-CBC, AES-256-GCM, SHA-256/512 throughput; RSA-2048/4096 & ECDSA-P256/P384 ops/s; single-thread & multi-thread events/s; CPU frequency throttle detection | `openssl`, `sysbench` | Python 3 prime sieve |
| **Memory** | Sequential read/write bandwidth (GiB/s); random pointer-chase latency (nanoseconds) | `sysbench` | `dd` → `/dev/shm` |
| **Disk I/O** | Sequential R/W — 3-pass average; 4K sync write latency; 4K random R/W IOPS; mixed 70/30 read/write at QD64 | `dd`, `fio` | `dd` only |
| **Network** | Public IPv4/IPv6 detection; geolocation + ISP; ICMP ping + jitter (4 global nodes); regional latency (6 continents); download throughput from 5 CDN endpoints; TCP throughput | `curl`, `ping`, `iperf3` | `curl` + `ping` |
| **Cryptography** | AES-128-CBC, AES-256-CBC, AES-256-GCM, SHA-1/256/512, SHA3-256, RSA-2048/4096 sign/verify, ECDSA-P256/P384 | `openssl` | — |
| **Compression** | gzip / bzip2 / xz / zstd / lz4 — compress & decompress speed (MB/s) + ratio, at speed-optimized and default levels on 256 MiB random data | Built-in tools | Available codecs |
| **System Info** | CPU model, cores, cache (L1/L2/L3), feature flags (AES-NI, AVX2, AVX-512, RDRAND); RAM, swap; virtualization type; I/O scheduler; TCP congestion control; load average + throttle warning | `lscpu`, `dmidecode`, `systemd-detect-virt` | `/proc` & `/sys` |

---

## 🎯 Usage

```bash
sudo ./voidbench.sh [OPTIONS]
```

### CLI Flags

| Flag | Description |
|------|-------------|
| `--quick` | Reduce iterations — faster run (~5 min instead of ~15 min) |
| `--no-network` | Skip all network tests (ideal for air-gapped servers) |
| `--no-disk` | Skip disk write tests (read-only / containerized environments) |
| `--no-compress` | Skip the compression benchmark suite |
| `--no-color` | Plain text output — no ANSI codes (logging, CI pipelines) |
| `--json` | Also generate a machine-readable `bench_*.json` report |
| `--no-install` | Never attempt to install missing packages |
| `--help` | Show usage and exit |

### Usage Examples

```bash
# ── Standard full benchmark (~15 min) ─────────────────────────────
sudo ./voidbench.sh

# ── Quick scan, ~5 min ─────────────────────────────────────────────
sudo ./voidbench.sh --quick

# ── With JSON output ───────────────────────────────────────────────
sudo ./voidbench.sh --json

# ── No network (air-gapped server) ────────────────────────────────
sudo ./voidbench.sh --no-network

# ── No disk writes (containerized / read-only env) ────────────────
sudo ./voidbench.sh --no-disk

# ── Minimal — CPU + memory only, no I/O or network ────────────────
sudo ./voidbench.sh --no-network --no-disk --no-compress

# ── Save colored output to a log file ─────────────────────────────
sudo ./voidbench.sh 2>&1 | tee bench_$(hostname -s)_$(date +%Y%m%d).log

# ── CI / automation — no color, no installs, JSON output ──────────
sudo ./voidbench.sh --no-color --no-install --json

# ── One-liner with flags via pipe ─────────────────────────────────
curl -fsSL https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh \
  | sudo bash -s -- --quick --json
```

---

## 📊 Scoring System

Each module is scored 0–100 and combined into a **weighted composite score**:

| Module | Weight | Reference Baseline (= 100 pts) |
|--------|--------|-------------------------------|
| CPU | **35%** | 2,000 sysbench events/s (multi-thread) |
| Disk I/O | **30%** | 100,000 random 4K IOPS (fio, QD64) |
| Network | **20%** | 1,000 Mbps peak download |
| Memory | **15%** | 20 GiB/s sequential bandwidth |

### Grade Scale

| Score | Grade | Typical Class |
|-------|-------|--------------|
| 95–100 | **S+** | Bare-metal flagship / NVMe RAID / 10G+ |
| 85–94 | **S** | High-end dedicated server |
| 75–84 | **A** | Premium VPS / compute-optimized cloud instance |
| 65–74 | **B** | Mid-range cloud VPS |
| 55–64 | **C** | Entry-level cloud instance |
| 45–54 | **D** | Burstable / shared-CPU instance |
| 35–44 | **E** | Heavily throttled environment |
| < 35 | **F** | Significant performance degradation detected |

---

## 🖥 Sample Output

```
 ╔═══════════════════════════════════════════════════════════════════════╗
 ║  VoidBench  ·  v2.0.0  ·  Lab_0x4E Edition                           ║
 ║  Author: Fattain Naime  |  https://iamnaime.info.bd                  ║
 ╚═══════════════════════════════════════════════════════════════════════╝

⚙ Dependency Check
────────────────────────────────────────────────────────────────────────
  ✔ openssl         /usr/bin/openssl
  ✔ sysbench        /usr/bin/sysbench       (auto-installed)
  ✔ fio             /usr/bin/fio            (auto-installed)
  ✔ iperf3          /usr/bin/iperf3         (auto-installed)
  ✔ python3         /usr/bin/python3

🖥 Host & OS
────────────────────────────────────────────────────────────────────────
  Hostname                          vps-prod-01.example.com
  OS                                Ubuntu 22.04.4 LTS
  Kernel                            5.15.0-101-generic
  Architecture                      x86_64

⚡ Processor
────────────────────────────────────────────────────────────────────────
  CPU Model                         Intel Xeon E5-2676 v3 @ 2.40GHz
  Physical Cores                    4
  Logical CPUs                      8
  Current Frequency                 2.40 GHz
  L1d / L1i Cache                   32K / 32K
  L2 / L3 Cache                     256K / 30720K
  Virtualization                    kvm
  CPU Features                      AES-NI AVX2 VT-x/AMD-V RDRAND

◈ sysbench CPU
────────────────────────────────────────────────────────────────────────
  Single-Thread Events/s            1,284.73
  Multi-Thread Events/s             9,521.88
  Avg Latency (1T)                  0.78 ms

◈ Disk I/O — Sequential Write (dd, bs=1M, fdatasync)
────────────────────────────────────────────────────────────────────────
  Write #1                          418.3 MB/s
  Write #2                          421.7 MB/s
  Write #3                          416.9 MB/s
  Avg Sequential Write              418.9 MB/s

◈ Random I/O (fio, 4K, libaio, QD=64)
────────────────────────────────────────────────────────────────────────
  Rand Read     R:48234 IOPS / 188.4 MiB/s / lat 528µs  W:0 IOPS
  Rand Write    R:0 IOPS  W:41892 IOPS / 163.6 MiB/s / lat 609µs
  Mixed 70/30   R:33120 IOPS / 129.4 MiB/s / lat 712µs  W:14194 IOPS

◈ Download Speed Tests
────────────────────────────────────────────────────────────────────────
  Cloudflare (Global 100MB)         912.40 Mbps
  Linode Singapore (100MB)          743.18 Mbps
  DigitalOcean AMS (100MB)          698.55 Mbps

╔══════════════════════════════════════════════════════════════════════╗
║  PERFORMANCE SCORE                                                   ║
╚══════════════════════════════════════════════════════════════════════╝

◈ Component Scores
────────────────────────────────────────────────────────────────────────
  CPU        (35%)   ████████████████████░░░░░░░░░░   72%
  Memory     (15%)   ██████████████████████░░░░░░░░   78%
  Disk I/O   (30%)   ████████████████░░░░░░░░░░░░░░   49%
  Network    (20%)   ████████████████████████░░░░░░   84%

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  COMPOSITE SCORE:  67.25 / 100   ·   Grade: B
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Total benchmark time              14m 32s
  ✔ Report saved → bench_vps-prod-01_20250530_141233.txt
  ✔ JSON saved   → bench_vps-prod-01_20250530_141233.json
```

---

## 📁 Output Files

Two reports are written to the current directory automatically:

| File | Format | When |
|------|--------|------|
| `bench_<hostname>_<timestamp>.txt` | Human-readable text | Always |
| `bench_<hostname>_<timestamp>.json` | Machine-readable JSON | `--json` flag |

### JSON Schema

```json
{
  "meta": {
    "version": "2.0.0",
    "date": "2025-05-30 14:12:33 UTC",
    "hostname": "vps-prod-01",
    "os": "Ubuntu 22.04.4 LTS",
    "kernel": "5.15.0-101-generic",
    "arch": "x86_64"
  },
  "hardware": {
    "cpu_model": "Intel Xeon E5-2676 v3 @ 2.40GHz",
    "cpu_logical": 8,
    "ram": "16.00 GiB",
    "disk_type": "SSD",
    "virt": "kvm",
    "public_ipv4": "203.0.113.42"
  },
  "scores": {
    "cpu": 72,
    "memory": 78,
    "disk": 49,
    "network": 84,
    "composite": 67.25,
    "grade": "B"
  },
  "raw": {
    "cpu_sb_single_eps":   "1284.73",
    "cpu_sb_multi_eps":    "9521.88",
    "mem_write_mbps":      "12481.33",
    "mem_read_mbps":       "15923.77",
    "mem_latency_ns":      "84.2",
    "disk_seq_write_mbps": "418.9",
    "disk_seq_read_mbps":  "531.4",
    "disk_rand_rd":        "R:48234 IOPS / 188.4 MiB/s / lat 528µs",
    "disk_rand_wr":        "W:41892 IOPS / 163.6 MiB/s / lat 609µs",
    "net_avg_dl_mbps":     "784.71",
    "net_peak_dl_mbps":    "912.40"
  }
}
```

---

## 🔧 Requirements

### Mandatory (built-in on all major distros)

| Tool | Purpose |
|------|---------|
| `bash` ≥ 4.0 | Script runtime |
| `curl` | Download speed tests, geolocation |
| `openssl` | Crypto benchmarks |
| `dd` | Disk I/O and memory tests |
| `python3` | Memory latency, JSON report generation |
| `awk`, `bc` | Arithmetic calculations |
| `ping` | Latency measurements |
| `gzip`, `bzip2` | Compression benchmarks |

### Optional (auto-installed by VoidBench when running as root)

| Tool | Installed From | Enhances |
|------|---------------|---------|
| `sysbench` | apt / yum / dnf / pacman | CPU events/s, memory bandwidth |
| `fio` | apt / yum / dnf / pacman | 4K random IOPS, disk latency |
| `iperf3` | apt / yum / dnf / pacman | TCP throughput test |
| `xz` | apt / yum / dnf / pacman | Additional compression codec |
| `zstd` | apt / yum / dnf / pacman | Additional compression codec |
| `lz4` | apt / yum / dnf / pacman | Additional compression codec |
| `dmidecode` | apt / yum / dnf / pacman | RAM type/speed detection |

---

## 🐧 Compatibility

| Distribution | Version | Status |
|-------------|---------|--------|
| Ubuntu | 20.04, 22.04, 24.04 | ✅ Fully tested |
| Debian | 11, 12 | ✅ Fully tested |
| AlmaLinux | 8, 9 | ✅ Fully tested |
| Rocky Linux | 8, 9 | ✅ Fully tested |
| CentOS | 7, 8 | ✅ Fully tested |
| Fedora | 38, 39, 40 | ✅ Fully tested |
| Arch Linux | Rolling | ✅ Fully tested |
| RHEL | 8, 9 | ✅ Fully tested |
| macOS | 12+ | ⚠️ Partial (no fio, limited dd parsing) |
| Alpine Linux | 3.18+ | ⚠️ Partial (requires manual `apk add` for deps) |
| BSD variants | — | ❌ Not supported |
| Windows (WSL2) | Ubuntu | ✅ Works via WSL2 |

---

## 🔒 Security Notes

VoidBench is a **passive profiling tool**. It does **not**:

- Modify any system configuration
- Open listening ports or start background processes
- Exfiltrate data — geolocation lookup uses `ip-api.com` (IPv4 only); download speed tests use public CDN endpoints
- Persist any files after completion (temp files in `/tmp/` are deleted on exit via `trap`)

**Auditing the script before running:**
```bash
# View the full source before executing
curl -fsSL https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh | less
```

**SHA-256 checksum verification:**
```bash
# Download
curl -fsSL https://raw.githubusercontent.com/fattain-naime/voidbench/main/voidbench.sh \
     -o voidbench.sh

# Verify checksum (compare against releases page)
sha256sum voidbench.sh
```

---

## 🤝 Contributing

Contributions, bug reports, and pull requests are welcome.

```bash
# Fork & clone
git clone https://github.com/<your-fork>/voidbench.git
cd voidbench

# Create a feature branch
git checkout -b feature/my-improvement

# Make changes, then validate syntax
bash -n voidbench.sh

# Optionally run shellcheck
shellcheck -S warning voidbench.sh

# Commit and push
git commit -m "feat: describe your change"
git push origin feature/my-improvement

# Open a Pull Request on GitHub
```

**Areas where contributions are especially welcome:**
- Additional network speed endpoints (regional coverage)
- GPU benchmark module (CUDA/OpenCL)
- macOS / BSD compatibility layer
- More fio test patterns (latency percentiles, io_uring engine)
- Docker container profile mode

---

## 📜 Changelog

### v2.2.0 (current)
- Full rewrite with modular architecture
- `--json` output for automation/monitoring pipelines
- fio random I/O with JSON parsing (IOPS + latency)
- Memory latency via pointer-chase (nanoseconds)
- ECDSA-P256/P384 crypto benchmarks
- CPU thermal throttle detection
- TCP congestion control + I/O scheduler detection
- sysbench v0.x and v1.x API auto-detection
- 7 CLI flags; `--quick` mode
- Weighted composite score with letter grade (F → S+)

---

## 📄 License

MIT License — see [LICENSE](LICENSE)

```
Copyright (c) 2025 Fattain Naime
```

---

<div align="center">

**Built by [Fattain Naime](https://iamnaime.info.bd)**  
*Lab_0x4E — Deciphering the Void*

[![GitHub](https://img.shields.io/badge/GitHub-fattain--naime-181717?style=flat-square&logo=github)](https://github.com/fattain-naime)
[![Website](https://img.shields.io/badge/web-iamnaime.info.bd-00f7ff?style=flat-square)](https://iamnaime.info.bd)
[![Lab](https://img.shields.io/badge/security%20lab-Lab__0x4E-ef4444?style=flat-square)](https://github.com/fattain-naime)

*If VoidBench helped you, consider starring the repo ⭐*

</div>
