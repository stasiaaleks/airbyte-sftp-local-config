#!/usr/bin/env bash
set -euo pipefail

decode() {
    printf '%s' "$1" | base64 -d
}

SFTP_USER=$(decode "$1")
SFTP_GROUP=$(decode "$2")
SFTP_ROOT=$(decode "$3")
SFTP_DIRECTORIES=$(decode "$4")
SSH_PUBLIC_KEYS=$(decode "$5")

[[ "$SFTP_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Invalid SFTP user" >&2; exit 2; }
[[ "$SFTP_GROUP" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Invalid SFTP group" >&2; exit 2; }
[[ "$SFTP_ROOT" =~ ^/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ &&
    "$SFTP_ROOT" != *"/../"* && "$SFTP_ROOT" != */.. && "$SFTP_ROOT" != /.. ]] ||
    { echo "Invalid SFTP root" >&2; exit 2; }

USER_HOME="${SFTP_ROOT%/}/${SFTP_USER}"
AUTHORIZED_KEYS_PATH="${USER_HOME}/.ssh/authorized_keys"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROP_IN="/etc/ssh/sshd_config.d/90-sftp-${SFTP_USER}.conf"

if ! dpkg -s openssh-server >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
fi

getent group "$SFTP_GROUP" >/dev/null || groupadd --system "$SFTP_GROUP"

mkdir -p "$USER_HOME"
chown root:root "$USER_HOME"
chmod 755 "$USER_HOME"

if ! id -u "$SFTP_USER" >/dev/null 2>&1; then
    useradd -M -d "$USER_HOME" -s /usr/sbin/nologin -g "$SFTP_GROUP" "$SFTP_USER"
else
    usermod -d "$USER_HOME" -g "$SFTP_GROUP" "$SFTP_USER"
fi

mkdir -p "${USER_HOME}/.ssh"
while IFS= read -r directory; do
    [ -n "$directory" ] || continue
    [[ "$directory" != /* && "$directory" != */ && "$directory" != *//* ]] ||
        { echo "Invalid SFTP directory: $directory" >&2; exit 2; }
    IFS='/' read -r -a directory_segments <<< "$directory"
    for segment in "${directory_segments[@]}"; do
        [[ -n "$segment" && "$segment" != ".." ]] ||
            { echo "Invalid SFTP directory: $directory" >&2; exit 2; }
    done
    mkdir -p "${USER_HOME}/${directory}"
    chown -R "$SFTP_USER:$SFTP_GROUP" "${USER_HOME}/${directory}"
done <<< "$SFTP_DIRECTORIES"

authorized_keys_tmp=$(mktemp)
trap 'rm -f "$authorized_keys_tmp" "${sshd_tmp:-}" "${sshd_config_tmp:-}" "${sshd_config_backup:-}" "${sshd_drop_in_backup:-}"' EXIT
printf '%s\n' "$SSH_PUBLIC_KEYS" > "$authorized_keys_tmp"
install -o "$SFTP_USER" -g "$SFTP_GROUP" -m 600 \
    "$authorized_keys_tmp" "$AUTHORIZED_KEYS_PATH"
chown "$SFTP_USER:$SFTP_GROUP" "${USER_HOME}/.ssh"
chmod 700 "${USER_HOME}/.ssh"

mkdir -p /etc/ssh/sshd_config.d
sshd_tmp=$(mktemp)
cat > "$sshd_tmp" <<SSHD_CONFIG
Match User ${SFTP_USER}
    ChrootDirectory ${USER_HOME}
    ForceCommand internal-sftp
    PasswordAuthentication no
    PubkeyAuthentication yes
    X11Forwarding no
    AllowTcpForwarding no
Match all
SSHD_CONFIG

sshd_config_backup=$(mktemp)
sshd_drop_in_backup=$(mktemp)
cp "$SSHD_CONFIG" "$sshd_config_backup"
drop_in_existed=false
if [ -f "$SSHD_DROP_IN" ]; then
    cp "$SSHD_DROP_IN" "$sshd_drop_in_backup"
    drop_in_existed=true
fi

config_changed=false
if [ ! -f "$SSHD_DROP_IN" ] || ! cmp -s "$sshd_tmp" "$SSHD_DROP_IN"; then
    install -o root -g root -m 644 "$sshd_tmp" "$SSHD_DROP_IN"
    config_changed=true
fi

if grep -q "^Match User ${SFTP_USER}$" "$SSHD_CONFIG"; then
    sshd_config_tmp=$(mktemp)
    awk -v user="$SFTP_USER" '
        $0 == "Match User " user { skipping = 1; next }
        skipping && /^Match[[:space:]]/ { skipping = 0 }
        !skipping { print }
    ' "$SSHD_CONFIG" > "$sshd_config_tmp"
    install -o root -g root -m 644 "$sshd_config_tmp" "$SSHD_CONFIG"
    config_changed=true
fi

if [ "$config_changed" = true ]; then
    if ! /usr/sbin/sshd -t; then
        install -o root -g root -m 644 "$sshd_config_backup" "$SSHD_CONFIG"
        if [ "$drop_in_existed" = true ]; then
            install -o root -g root -m 644 "$sshd_drop_in_backup" "$SSHD_DROP_IN"
        else
            rm -f "$SSHD_DROP_IN"
        fi
        echo "Refusing to install invalid SSHD configuration" >&2
        exit 1
    fi
    systemctl restart ssh
fi

echo "SFTP setup complete for $SFTP_USER."