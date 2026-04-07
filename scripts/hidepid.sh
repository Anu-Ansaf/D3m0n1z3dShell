#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Hidepid /proc Mount Option [*] "
echo ""
echo "This remounts /proc with hidepid= option so non-root users"
echo "cannot see other users' processes (ps, top, /proc/PID)."
echo ""

echo "Select hidepid level:"
echo "  [1] hidepid=1 — Users can access /proc/PID but not cmdline, environ, etc."
echo "  [2] hidepid=2 — Users cannot see other users' /proc/PID entries at all (recommended)"
echo "  [3] Revert to hidepid=0 (default, no hiding)"
read -p "Choice [1-3]: " level

case "$level" in
    1) hidepid_val=1 ;;
    2) hidepid_val=2 ;;
    3) hidepid_val=0 ;;
    *)
        echo "[ERROR] Invalid choice" >&2
        exit 1
        ;;
esac

# Apply immediately
mount -o remount,hidepid=$hidepid_val /proc
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to remount /proc with hidepid=$hidepid_val" >&2
    exit 1
fi

echo "[+] /proc remounted with hidepid=$hidepid_val"

# Make persistent via fstab
read -p "Make persistent across reboots? (y/n): " persist

if [[ "$persist" == "y" || "$persist" == "Y" ]]; then
    FSTAB_LINE="proc /proc proc defaults,hidepid=$hidepid_val 0 0"

    # Remove any existing proc mount line with hidepid
    sed -i '/^proc.*\/proc.*hidepid/d' /etc/fstab 2>/dev/null

    if [ "$hidepid_val" -ne 0 ]; then
        echo "$FSTAB_LINE" >> /etc/fstab
        echo "[+] Added to /etc/fstab: $FSTAB_LINE"
    else
        echo "[+] Removed hidepid entries from /etc/fstab (reverted to default)"
    fi
fi

clear

echo "[*] Success!! /proc is now mounted with hidepid=$hidepid_val [*]"
if [ "$hidepid_val" -eq 2 ]; then
    echo "[*] Non-root users can no longer see other users' processes [*]"
elif [ "$hidepid_val" -eq 1 ]; then
    echo "[*] Non-root users can see PIDs but not sensitive details [*]"
else
    echo "[*] Default behavior restored — all processes visible to all users [*]"
fi

sleep 1

clear
