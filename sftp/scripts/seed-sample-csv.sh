#!/usr/bin/env bash
# Upload samples/sample.csv to the SFTP landing directory managed by this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
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
KEY="$(terraform -chdir="${TF_DIR}" output -raw private_key_path)"

echo "Uploading ${SAMPLE} to ${USER}@${HOST} as sample.csv"
printf 'put %s sample.csv\n' "${SAMPLE}" | sftp -i "${KEY}" -oStrictHostKeyChecking=accept-new "${USER}@${HOST}"
echo "Done. Landing contents:"
printf 'ls -l\n' | sftp -i "${KEY}" -oStrictHostKeyChecking=accept-new "${USER}@${HOST}"
