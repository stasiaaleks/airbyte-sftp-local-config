#!/usr/bin/env bash
# Resolve a Juju machine's public address for Terraform's external data source.
#
# Reads a JSON query object on stdin ({"model":..., "machine_id":...}) and
# writes {"address":"<ip>"} on stdout.
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
machine_id="$(jq -r '.machine_id' <<<"${query}")"

[[ -n "${model}" && "${model}" != "null" ]] || fail "model is required"
[[ -n "${machine_id}" && "${machine_id}" != "null" ]] || fail "machine_id is required"

address="$(
  juju status --model "${model}" --format=json |
    jq -r --arg id "${machine_id}" '.machines[$id]["dns-name"] // .machines[$id]["ip-addresses"][0] // empty'
)"

[[ -n "${address}" ]] || fail "could not resolve address for machine ${machine_id} in model ${model}"

jq -n --arg address "${address}" '{address: $address}'
