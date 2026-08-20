#!/usr/bin/env bash
set -euo pipefail

decode() {
    printf '%s' "$1" | base64 -d
}

SFTP_USER=$(decode "$1")

[[ "$SFTP_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ||
    { echo "Invalid SFTP user" >&2; exit 2; }

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROP_IN="/etc/ssh/sshd_config.d/90-sftp-${SFTP_USER}.conf"

config_changed=false

if [ -f "$SSHD_DROP_IN" ]; then
    rm -f "$SSHD_DROP_IN"
    config_changed=true
fi

if grep -q "^Match User ${SFTP_USER}$" "$SSHD_CONFIG"; then
    sshd_config_tmp=$(mktemp)
    trap 'rm -f "${sshd_config_tmp:-}"' EXIT
    awk -v user="$SFTP_USER" '
        $0 == "Match User " user { skipping = 1; next }
        skipping && /^Match[[:space:]]/ { skipping = 0 }
        !skipping { print }
    ' "$SSHD_CONFIG" > "$sshd_config_tmp"
    install -o root -g root -m 644 "$sshd_config_tmp" "$SSHD_CONFIG"
    config_changed=true
fi

# Remove the authorized_keys to revoke key-based access, keep SFTP data intact.
if id -u "$SFTP_USER" >/dev/null 2>&1; then
    USER_HOME=$(getent passwd "$SFTP_USER" | cut -d: -f6)
    if [ -n "$USER_HOME" ] && [ -f "${USER_HOME}/.ssh/authorized_keys" ]; then
        rm -f "${USER_HOME}/.ssh/authorized_keys"
    fi
    userdel "$SFTP_USER"
fi

if [ "$config_changed" = true ]; then
    if /usr/sbin/sshd -t; then
        systemctl restart ssh
    else
        echo "SSHD configuration invalid after cleanup; not restarting ssh" >&2
        exit 1
    fi
fi

echo "SFTP cleanup complete for $SFTP_USER."