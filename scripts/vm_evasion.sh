#!/bin/bash
# T1497 — Virtualization/Sandbox Evasion
# Detect VMs, containers, debuggers, and monitoring tools before executing payloads

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_vmevasion"

banner_vm() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1497 — VM / Sandbox Evasion                ║"
    echo "  ║   Detect VMs, containers, debuggers, monitors ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

DETECTED=()

detect_hypervisor() {
    echo -e "${CYAN}[*] Checking for hypervisors...${NC}"
    local found=0

    # DMI/SMBIOS
    if [[ -r /sys/class/dmi/id/product_name ]]; then
        local prod
        prod=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        case "$prod" in
            *VirtualBox*)  echo -e "  ${RED}[!] VirtualBox detected (DMI: ${prod})${NC}"; DETECTED+=("VirtualBox"); found=1 ;;
            *VMware*)      echo -e "  ${RED}[!] VMware detected (DMI: ${prod})${NC}"; DETECTED+=("VMware"); found=1 ;;
            *KVM*|*QEMU*)  echo -e "  ${RED}[!] KVM/QEMU detected (DMI: ${prod})${NC}"; DETECTED+=("KVM"); found=1 ;;
            *HVM*domU*)    echo -e "  ${RED}[!] Xen detected (DMI: ${prod})${NC}"; DETECTED+=("Xen"); found=1 ;;
        esac
    fi

    if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
        local vendor
        vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
        case "$vendor" in
            *Microsoft*)   echo -e "  ${RED}[!] Hyper-V detected (vendor: ${vendor})${NC}"; DETECTED+=("Hyper-V"); found=1 ;;
            *QEMU*)        echo -e "  ${RED}[!] QEMU detected (vendor: ${vendor})${NC}"; DETECTED+=("QEMU"); found=1 ;;
            *innotek*)     echo -e "  ${RED}[!] VirtualBox detected (vendor: ${vendor})${NC}"; DETECTED+=("VirtualBox"); found=1 ;;
            *Parallels*)   echo -e "  ${RED}[!] Parallels detected (vendor: ${vendor})${NC}"; DETECTED+=("Parallels"); found=1 ;;
        esac
    fi

    # CPUID hypervisor bit
    if [[ -r /proc/cpuinfo ]]; then
        if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
            echo -e "  ${RED}[!] Hypervisor flag set in CPUID${NC}"
            [[ $found -eq 0 ]] && DETECTED+=("Unknown-Hypervisor")
            found=1
        fi
    fi

    # Systemd virtualization detection
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null)
        if [[ "$virt" != "none" && -n "$virt" ]]; then
            echo -e "  ${RED}[!] systemd-detect-virt: ${virt}${NC}"
            [[ $found -eq 0 ]] && DETECTED+=("$virt")
            found=1
        fi
    fi

    # MAC address prefix (VMs have known prefixes)
    local MAC
    MAC=$(cat /sys/class/net/*/address 2>/dev/null | head -1)
    if [[ -n "$MAC" ]]; then
        local prefix="${MAC:0:8}"
        case "$prefix" in
            08:00:27*|0a:00:27*) echo -e "  ${RED}[!] VirtualBox MAC: ${MAC}${NC}"; found=1 ;;
            00:0c:29*|00:50:56*) echo -e "  ${RED}[!] VMware MAC: ${MAC}${NC}"; found=1 ;;
            52:54:00*)           echo -e "  ${RED}[!] QEMU/KVM MAC: ${MAC}${NC}"; found=1 ;;
            00:15:5d*)           echo -e "  ${RED}[!] Hyper-V MAC: ${MAC}${NC}"; found=1 ;;
        esac
    fi

    # VM-specific devices/files
    [[ -d /proc/vz ]] && { echo -e "  ${RED}[!] OpenVZ detected (/proc/vz)${NC}"; DETECTED+=("OpenVZ"); found=1; }
    [[ -f /proc/xen/capabilities ]] && { echo -e "  ${RED}[!] Xen detected (/proc/xen)${NC}"; DETECTED+=("Xen"); found=1; }
    [[ -c /dev/vboxguest ]] && { echo -e "  ${RED}[!] VirtualBox Guest Additions detected${NC}"; found=1; }

    [[ $found -eq 0 ]] && echo -e "  ${GREEN}[+] No hypervisor detected${NC}"
}

detect_container() {
    echo -e "${CYAN}[*] Checking for containers...${NC}"
    local found=0

    # Docker
    [[ -f /.dockerenv ]] && { echo -e "  ${RED}[!] Docker detected (/.dockerenv)${NC}"; DETECTED+=("Docker"); found=1; }

    # Cgroup check
    if [[ -f /proc/1/cgroup ]]; then
        if grep -qE 'docker|lxc|containerd|kubepods|garden' /proc/1/cgroup 2>/dev/null; then
            local ctype
            ctype=$(grep -oE 'docker|lxc|containerd|kubepods|garden' /proc/1/cgroup | head -1)
            echo -e "  ${RED}[!] Container detected via cgroup: ${ctype}${NC}"
            DETECTED+=("$ctype")
            found=1
        fi
    fi

    # PID namespace check (PID 1 is not systemd/init in containers)
    local init_name
    init_name=$(cat /proc/1/comm 2>/dev/null)
    if [[ "$init_name" != "systemd" && "$init_name" != "init" && "$init_name" != "launchd" ]]; then
        echo -e "  ${YELLOW}[?] PID 1 is '${init_name}' (may indicate container)${NC}"
    fi

    # Kubernetes
    [[ -n "$KUBERNETES_SERVICE_HOST" ]] && { echo -e "  ${RED}[!] Kubernetes detected (env var)${NC}"; DETECTED+=("Kubernetes"); found=1; }
    [[ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]] && { echo -e "  ${RED}[!] Kubernetes service account detected${NC}"; found=1; }

    # LXC
    if [[ -f /proc/1/environ ]]; then
        if tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -q "^container=lxc"; then
            echo -e "  ${RED}[!] LXC container detected${NC}"
            DETECTED+=("LXC")
            found=1
        fi
    fi

    # systemd-nspawn
    if [[ -f /proc/1/environ ]]; then
        if tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -q "^container=systemd-nspawn"; then
            echo -e "  ${RED}[!] systemd-nspawn detected${NC}"
            DETECTED+=("systemd-nspawn")
            found=1
        fi
    fi

    # Limited /proc filesystem
    if [[ ! -d /proc/scsi ]] || [[ ! -f /proc/uptime ]]; then
        echo -e "  ${YELLOW}[?] Limited /proc — possible container${NC}"
    fi

    [[ $found -eq 0 ]] && echo -e "  ${GREEN}[+] No container detected${NC}"
}

detect_debugger() {
    echo -e "${CYAN}[*] Checking for debuggers...${NC}"
    local found=0

    # ptrace self-check
    if [[ -r /proc/self/status ]]; then
        local tracer
        tracer=$(grep "^TracerPid:" /proc/self/status 2>/dev/null | awk '{print $2}')
        if [[ "$tracer" != "0" && -n "$tracer" ]]; then
            echo -e "  ${RED}[!] Being traced! TracerPid: ${tracer}${NC}"
            local tname
            tname=$(cat "/proc/${tracer}/comm" 2>/dev/null)
            echo -e "  ${RED}[!] Tracer: ${tname} (PID ${tracer})${NC}"
            DETECTED+=("Debugger:${tname}")
            found=1
        fi
    fi

    # Check for common debuggers running
    local DEBUGGERS=("gdb" "strace" "ltrace" "valgrind" "radare2" "r2" "ida" "x64dbg" "edb")
    for dbg in "${DEBUGGERS[@]}"; do
        if pgrep -x "$dbg" &>/dev/null; then
            echo -e "  ${RED}[!] Debugger running: ${dbg} (PID $(pgrep -x "$dbg" | head -1))${NC}"
            DETECTED+=("Debugger:${dbg}")
            found=1
        fi
    done

    # LD_PRELOAD check (dynamic analysis)
    if [[ -n "$LD_PRELOAD" ]]; then
        echo -e "  ${RED}[!] LD_PRELOAD set: ${LD_PRELOAD}${NC}"
        DETECTED+=("LD_PRELOAD")
        found=1
    fi

    [[ $found -eq 0 ]] && echo -e "  ${GREEN}[+] No debugger detected${NC}"
}

detect_monitoring() {
    echo -e "${CYAN}[*] Checking for monitoring/security tools...${NC}"
    local found=0

    local MONITORS=(
        "pspy32:pspy (process spy)"
        "pspy64:pspy (process spy)"
        "sysdig:sysdig (syscall capture)"
        "falco:falco (runtime security)"
        "auditd:auditd (audit daemon)"
        "osqueryd:osquery"
        "ossec:OSSEC HIDS"
        "wazuh:Wazuh agent"
        "falcon-sensor:CrowdStrike Falcon"
        "cbagentd:Carbon Black"
        "mdatp:Microsoft Defender ATP"
        "clamd:ClamAV"
        "chkrootkit:chkrootkit"
        "rkhunter:rkhunter"
        "aide:AIDE"
        "tripwire:Tripwire"
        "snort:Snort IDS"
        "suricata:Suricata IDS"
    )

    for entry in "${MONITORS[@]}"; do
        local proc="${entry%%:*}"
        local desc="${entry##*:}"
        if pgrep -f "$proc" &>/dev/null; then
            echo -e "  ${RED}[!] ${desc} running (${proc})${NC}"
            DETECTED+=("Monitor:${proc}")
            found=1
        fi
    done

    # Check auditd rules
    if command -v auditctl &>/dev/null; then
        local rules
        rules=$(auditctl -l 2>/dev/null | wc -l)
        if [[ "$rules" -gt 0 ]]; then
            echo -e "  ${YELLOW}[!] auditd has ${rules} active rule(s)${NC}"
        fi
    fi

    # Check if syslog is active
    if systemctl is-active rsyslog &>/dev/null || systemctl is-active syslog-ng &>/dev/null; then
        echo -e "  ${YELLOW}[*] Syslog active${NC}"
    fi

    [[ $found -eq 0 ]] && echo -e "  ${GREEN}[+] No monitoring tools detected${NC}"
}

detect_hardware_anomaly() {
    echo -e "${CYAN}[*] Checking hardware anomalies (sandbox indicators)...${NC}"
    local found=0

    # CPU count
    local cpus
    cpus=$(nproc 2>/dev/null)
    if [[ "$cpus" -le 1 ]]; then
        echo -e "  ${YELLOW}[?] Only ${cpus} CPU(s) — possible sandbox${NC}"
        found=1
    fi

    # RAM size
    local ram_mb
    ram_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    if [[ "$ram_mb" -lt 1024 ]]; then
        echo -e "  ${YELLOW}[?] Only ${ram_mb}MB RAM — possible sandbox${NC}"
        found=1
    fi

    # Disk size
    local disk_gb
    disk_gb=$(df / 2>/dev/null | awk 'NR==2{printf "%d", $2/1048576}')
    if [[ "$disk_gb" -lt 20 ]]; then
        echo -e "  ${YELLOW}[?] Only ${disk_gb}GB disk — possible sandbox${NC}"
        found=1
    fi

    # Uptime check (sandboxes often have short uptime)
    local uptime_sec
    uptime_sec=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)
    if [[ "$uptime_sec" -lt 300 ]]; then
        echo -e "  ${YELLOW}[?] Uptime only ${uptime_sec}s — possible sandbox${NC}"
        found=1
    fi

    # User activity check
    local user_count
    user_count=$(who 2>/dev/null | wc -l)
    if [[ "$user_count" -eq 0 ]]; then
        echo -e "  ${YELLOW}[?] No logged-in users — possible sandbox${NC}"
    fi

    # Check for common sandbox artifacts
    local ARTIFACTS=(
        "/tmp/cuckoo-tmp"
        "/tmp/VBoxGuestAdditions"
        "/usr/bin/VBoxClient"
        "/usr/bin/vmtoolsd"
    )
    for art in "${ARTIFACTS[@]}"; do
        [[ -e "$art" ]] && { echo -e "  ${RED}[!] Sandbox artifact: ${art}${NC}"; found=1; }
    done

    [[ $found -eq 0 ]] && echo -e "  ${GREEN}[+] No hardware anomalies detected${NC}"
}

run_all_checks() {
    DETECTED=()
    detect_hypervisor
    echo ""
    detect_container
    echo ""
    detect_debugger
    echo ""
    detect_monitoring
    echo ""
    detect_hardware_anomaly

    echo ""
    echo -e "${YELLOW}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}[*] SUMMARY${NC}"
    echo -e "${YELLOW}══════════════════════════════════════${NC}"

    if [[ ${#DETECTED[@]} -eq 0 ]]; then
        echo -e "${GREEN}[+] CLEAN — No VM/container/debugger/monitor detected${NC}"
        echo -e "${GREEN}[+] Safe to proceed with operations${NC}"
        return 0
    else
        echo -e "${RED}[!] DETECTED (${#DETECTED[@]} items):${NC}"
        for d in "${DETECTED[@]}"; do
            echo -e "  ${RED}• ${d}${NC}"
        done

        echo ""
        echo -e "  ${CYAN}[1]${NC} Continue anyway"
        echo -e "  ${CYAN}[2]${NC} Abort"
        echo -e "  ${CYAN}[3]${NC} Sleep and retry (sandbox timeout evasion)"
        read -p "  Action [2]: " act
        act="${act:-2}"

        case "$act" in
            1) echo -e "${YELLOW}[*] Continuing...${NC}"; return 0 ;;
            2) echo -e "${RED}[!] Aborting.${NC}"; return 1 ;;
            3)
                local WAIT=301
                echo -e "${YELLOW}[*] Sleeping ${WAIT}s to outlast sandbox timeout...${NC}"
                echo -e "${YELLOW}[*] (Most sandboxes timeout at 60-300s)${NC}"
                # Don't actually sleep — just inform
                echo -e "${YELLOW}[*] Use: nohup bash -c 'sleep ${WAIT} && <your_command>' &${NC}"
                return 1
                ;;
        esac
    fi
}

main() {
    banner_vm

    echo -e "  ${CYAN}[1]${NC} Detect hypervisors (VMware/VBox/KVM/Hyper-V)"
    echo -e "  ${CYAN}[2]${NC} Detect containers (Docker/LXC/K8s)"
    echo -e "  ${CYAN}[3]${NC} Detect debuggers (gdb/strace/ptrace)"
    echo -e "  ${CYAN}[4]${NC} Detect monitoring tools (EDR/HIDS/IDS)"
    echo -e "  ${CYAN}[5]${NC} Hardware anomaly check (sandbox)"
    echo -e "  ${CYAN}[6]${NC} ${RED}RUN ALL CHECKS${NC}"
    echo ""
    read -p "Choose [1-6]: " OPT

    case "$OPT" in
        1) detect_hypervisor ;;
        2) detect_container ;;
        3) detect_debugger ;;
        4) detect_monitoring ;;
        5) detect_hardware_anomaly ;;
        6) run_all_checks ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
