#!/usr/bin/env bash
# Apply the SFTP configuration to a Juju unit.
#
# Invoked by Terraform's local-exec provisioner. All inputs come from the
# environment so the provisioner command stays a single path.
#
#   JUJU_MODEL          model containing the unit          (required)
#   SFTP_UNIT           unit name, e.g. ubuntu/0           (required)
#   SFTP_PUBKEY_FILE    path to the public key to install  (required)
#   REMOTE_SETUP_SCRIPT script executed on the unit        (required)
#   SFTP_USER           unix user to create                (default: sftpuser)
#   SFTP_DIR            landing dir under the user's home  (default: upload)
#   SFTP_WAIT_TIMEOUT   wait-for timeout                   (default: 20m)
set -euo pipefail

JUJU_MODEL="${JUJU_MODEL:?JUJU_MODEL is required}"
SFTP_UNIT="${SFTP_UNIT:?SFTP_UNIT is required}"
SFTP_PUBKEY_FILE="${SFTP_PUBKEY_FILE:?SFTP_PUBKEY_FILE is required}"
REMOTE_SETUP_SCRIPT="${REMOTE_SETUP_SCRIPT:?REMOTE_SETUP_SCRIPT is required}"
SFTP_USER="${SFTP_USER:-sftpuser}"
SFTP_DIR="${SFTP_DIR:-upload}"
SFTP_WAIT_TIMEOUT="${SFTP_WAIT_TIMEOUT:-20m}"

log() {
  printf '%s\n' "$*" >&2
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmds() {
  local cmd
  for cmd in juju base64; do    command -v "${cmd}" >/dev/null 2>&1 || fail "missing required command: ${cmd}"
  done
  [[ -f "${REMOTE_SETUP_SCRIPT}" ]] || fail "remote setup script not found: ${REMOTE_SETUP_SCRIPT}"
  [[ -s "${SFTP_PUBKEY_FILE}" ]] || fail "public key file missing or empty: ${SFTP_PUBKEY_FILE}"
}

wait_for_unit() {
  log "Waiting for ${SFTP_UNIT} in model ${JUJU_MODEL} to be active/idle..."
  if ! juju wait-for unit \
    --model "${JUJU_MODEL}" \
    --timeout "${SFTP_WAIT_TIMEOUT}" \
    --query='life=="alive" && workload-status=="active" && agent-status=="idle"' \
    "${SFTP_UNIT}"; then
    log "Unit not ready. Current status:"
    juju status --model "${JUJU_MODEL}" >&2 || true
    fail "unit ${SFTP_UNIT} did not become ready within ${SFTP_WAIT_TIMEOUT}"
  fi
}

configure_unit() {
  local pubkey_b64 remote_script
  # base64 avoids shell word-splitting on the spaces inside the key line
  pubkey_b64="$(base64 -w0 <"${SFTP_PUBKEY_FILE}" 2>/dev/null || base64 <"${SFTP_PUBKEY_FILE}" | tr -d '\n')"
  remote_script="/tmp/remote-sftp-setup.$$.sh"

  # `juju ssh` only forwards stdin when it is a pipe, not when it is a regular
  # file, so `bash -s < script.sh` silently runs nothing. Copy and execute
  # instead, which does not depend on how stdin happens to be wired up.
  log "Copying setup script to ${SFTP_UNIT}..."
  juju scp --model "${JUJU_MODEL}" "${REMOTE_SETUP_SCRIPT}" "${SFTP_UNIT}:${remote_script}" >&2

  log "Configuring SFTP on ${SFTP_UNIT} (user=${SFTP_USER}, dir=${SFTP_DIR}, auth=publickey)..."
  juju ssh --model "${JUJU_MODEL}" "${SFTP_UNIT}" -- sudo env \
    "SFTP_USER=${SFTP_USER}" \
    "SFTP_DIR=${SFTP_DIR}" \
    "SFTP_PUBKEY_B64=${pubkey_b64}" \
    bash "${remote_script}" >&2

  juju ssh --model "${JUJU_MODEL}" "${SFTP_UNIT}" -- rm -f "${remote_script}" >&2
}

main() {
  require_cmds
  wait_for_unit
  configure_unit
}

main "$@"
