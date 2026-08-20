#!/usr/bin/env bash
set -euo pipefail

: "${MACHINE_ID:?Missing MACHINE_ID env var}"
: "${MODEL_NAME:?Missing MODEL_NAME env var}"
: "${MACHINE_NAME:?Missing MACHINE_NAME env var}"
: "${SFTP_USER:?Missing SFTP_USER env var}"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

encode() {
    printf '%s' "$1" | base64 -w0
}

SFTP_USER_B64=$(encode "$SFTP_USER")

echo "Reconciling previous SFTP user on machine: $MACHINE_ID ($MACHINE_NAME)"

# Revoke the previous SFTP user's credentials without deleting its data.
juju ssh -m "$MODEL_NAME" "$MACHINE_ID" \
    "sudo bash -s -- '$SFTP_USER_B64'" \
    < "$SCRIPT_DIR/cleanup-sftp-user-remote.sh"

echo "SUCCESS: SFTP cleanup complete on machine $MACHINE_ID"
