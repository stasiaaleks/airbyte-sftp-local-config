#!/usr/bin/env bash
# Print shell exports for connectors/environments/dev.
# Usage:
#   eval "$(./scripts/export-airbyte-env.sh)"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/environments/dev/local-test"

if [[ ! -f "${TF_DIR}/terraform.tfstate" ]]; then
  echo "ERROR: no Terraform state in ${TF_DIR}; apply the SFTP plan first" >&2
  exit 1
fi

HOST="$(terraform -chdir="${TF_DIR}" output -raw sftp_host)"
USER="$(terraform -chdir="${TF_DIR}" output -raw sftp_user)"
LANDING="$(terraform -chdir="${TF_DIR}" output -raw sftp_landing_path)"
KEY_PATH="$(terraform -chdir="${TF_DIR}" output -raw private_key_path)"

if [[ ! -r "${KEY_PATH}" ]]; then
  echo "ERROR: private key not readable: ${KEY_PATH}" >&2
  exit 1
fi

# Emit exports only (no other stdout) so eval works cleanly.
# The user is chrooted, so folder_path is relative to the chroot ("/uploads").
#
# Prefer the key *path* only. Putting the PEM body in TF_VAR_SFTP_PRIVATE_KEY is
# fragile: shells / copy-paste often turn PEM newlines into spaces, and Airbyte
# then fails with "not a valid RSA private key file" / schema inference errors.
# Unset any stale key body so terraform uses file(pathexpand(path)) instead.
python3 - "${HOST}" "${USER}" "${LANDING}" "${KEY_PATH}" <<'PY'
import shlex, sys
host, user, landing, key_path = sys.argv[1:5]
print(f"export TF_VAR_SFTP_HOST={shlex.quote(host)}")
print(f"export TF_VAR_SFTP_USER={shlex.quote(user)}")
print(f"export TF_VAR_SFTP_PORT={shlex.quote('22')}")
print(f"export TF_VAR_SFTP_FOLDER_PATH={shlex.quote(landing)}")
print(f"export TF_VAR_sftp_private_key_path={shlex.quote(key_path)}")
print("unset TF_VAR_SFTP_PRIVATE_KEY SFTP_PRIVATE_KEY")
PY
