#!/usr/bin/env bash
# Resolve a Juju unit's public address for Terraform's external data source.
#
# Reads a JSON query object on stdin ({"model":...,"app":...,"unit":...}) and
# writes a JSON object with a single "address" key on stdout.
set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for cmd in juju jq; do
  command -v "${cmd}" >/dev/null 2>&1 || fail "missing required command: ${cmd}"
done

query="$(cat)"
model="$(jq -r '.model' <<<"${query}")"
app="$(jq -r '.app' <<<"${query}")"
unit="$(jq -r '.unit' <<<"${query}")"

address="$(
  juju status --model "${model}" --format=json |
    jq -r --arg app "${app}" --arg unit "${unit}" \
      '.applications[$app].units[$unit]["public-address"] // empty'
)"

[[ -n "${address}" ]] || fail "could not resolve public address for ${unit} in model ${model}"

jq -n --arg address "${address}" '{address: $address}'
