#!/usr/bin/env bash
# Upload samples/sample.csv to the SFTP landing directory managed by this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/environments/dev/local-test"
SAMPLE="${ROOT}/samples/sample.csv"

if [[ ! -f "${SAMPLE}" ]]; then
  echo "ERROR: sample file missing: ${SAMPLE}" >&2
  exit 1
fi

if [[ ! -f "${TF_DIR}/terraform.tfstate" ]]; then
  echo "ERROR: no Terraform state in ${TF_DIR}; apply the SFTP plan first" >&2
  exit 1
fi

HOST="$(terraform -chdir="${TF_DIR}" output -raw sftp_host)"
USER="$(terraform -chdir="${TF_DIR}" output -raw sftp_user)"
LANDING="$(terraform -chdir="${TF_DIR}" output -raw sftp_landing_path)"
KEY="$(terraform -chdir="${TF_DIR}" output -raw private_key_path)"

echo "Uploading ${SAMPLE} to ${USER}@${HOST}:${LANDING}/sample.csv"
printf 'cd %s\nput %s sample.csv\n' "${LANDING}" "${SAMPLE}" |
  sftp -i "${KEY}" -oStrictHostKeyChecking=accept-new "${USER}@${HOST}"
echo "Done. Landing contents:"
printf 'cd %s\nls -l\n' "${LANDING}" |
  sftp -i "${KEY}" -oStrictHostKeyChecking=accept-new "${USER}@${HOST}"
