#!/usr/bin/env bash
set -euo pipefail

: "${MACHINE_ID:?Missing MACHINE_ID env var}"
: "${MODEL_NAME:?Missing MODEL_NAME env var}"
: "${MACHINE_NAME:?Missing MACHINE_NAME env var}"
: "${SFTP_USER:?Missing SFTP_USER env var}"
: "${SFTP_GROUP:?Missing SFTP_GROUP env var}"
: "${SFTP_ROOT:?Missing SFTP_ROOT env var}"
: "${SFTP_DIRECTORIES:?Missing SFTP_DIRECTORIES env var}"
: "${SSH_PUBLIC_KEYS_B64:?Missing SSH_PUBLIC_KEYS_B64 env var}"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

encode() {
    printf '%s' "$1" | base64 -w0
}

SFTP_USER_B64=$(encode "$SFTP_USER")
SFTP_GROUP_B64=$(encode "$SFTP_GROUP")
SFTP_ROOT_B64=$(encode "$SFTP_ROOT")
SFTP_DIRECTORIES_B64=$(encode "$SFTP_DIRECTORIES")

echo "Deploying to machine: $MACHINE_ID ($MACHINE_NAME)"

juju ssh -m "$MODEL_NAME" "$MACHINE_ID" \
    "sudo bash -s -- '$SFTP_USER_B64' '$SFTP_GROUP_B64' '$SFTP_ROOT_B64' '$SFTP_DIRECTORIES_B64' '$SSH_PUBLIC_KEYS_B64'" \
    < "$SCRIPT_DIR/configure-sftp-server-remote.sh"

echo "SUCCESS: SFTP setup complete on machine $MACHINE_ID"
