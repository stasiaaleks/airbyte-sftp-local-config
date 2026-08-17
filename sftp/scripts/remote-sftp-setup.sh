#!/usr/bin/env bash
# Run on the target unit (as root): SFTP-only user, publickey auth, no chroot.
set -euo pipefail

SFTP_USER="${SFTP_USER:-sftpuser}"
SFTP_DIR="${SFTP_DIR:-upload}"
SFTP_PUBKEY="${SFTP_PUBKEY:-}"
SFTP_PUBKEY_B64="${SFTP_PUBKEY_B64:-}"

if [[ -n "${SFTP_PUBKEY_B64}" ]]; then
  SFTP_PUBKEY="$(printf '%s' "${SFTP_PUBKEY_B64}" | base64 -d)"
fi

if [[ -z "${SFTP_PUBKEY}" ]]; then
  echo "ERROR: SFTP_PUBKEY or SFTP_PUBKEY_B64 is required" >&2
  exit 1
fi

HOME_DIR="/home/${SFTP_USER}"
UPLOAD_DIR="${HOME_DIR}/${SFTP_DIR}"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
SSHD_CONFIG="/etc/ssh/sshd_config"

if ! id "${SFTP_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' "${SFTP_USER}"
fi

# No interactive shell; SFTP only via ForceCommand.
usermod -s /usr/sbin/nologin "${SFTP_USER}"

mkdir -p "${UPLOAD_DIR}" "${SSH_DIR}"
chmod 755 "${HOME_DIR}"
chmod 700 "${SSH_DIR}"
chown -R "${SFTP_USER}:${SFTP_USER}" "${HOME_DIR}"

printf '%s\n' "${SFTP_PUBKEY}" > "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"
chown "${SFTP_USER}:${SFTP_USER}" "${AUTH_KEYS}"

# Drop any previous Match block for this user (chroot or otherwise).
if grep -q "^Match User ${SFTP_USER}$" "${SSHD_CONFIG}"; then
  awk -v user="${SFTP_USER}" '
    $0 == "Match User " user { skip=1; next }
    skip && /^Match / { skip=0 }
    skip && /^[^[:space:]#]/ && !/^Match / { skip=0 }
    !skip { print }
  ' "${SSHD_CONFIG}" > "${SSHD_CONFIG}.tmp"
  mv "${SSHD_CONFIG}.tmp" "${SSHD_CONFIG}"
fi

cat >> "${SSHD_CONFIG}" <<CFG

Match User ${SFTP_USER}
  ForceCommand internal-sftp -d ${UPLOAD_DIR}
  PasswordAuthentication no
  AuthenticationMethods publickey
  AllowTcpForwarding no
  X11Forwarding no
  PermitTunnel no
  AllowAgentForwarding no
CFG

sshd -t
systemctl restart ssh
echo "SFTP ready: user=${SFTP_USER} land=${UPLOAD_DIR} auth=publickey (no chroot)"
