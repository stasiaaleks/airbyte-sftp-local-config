#!/usr/bin/env bash
# Report the state of the local Airbyte instance
# Cluster, pods, volumes, API and UI reachability, etc.
# Read-only

set -uo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"

if [ -t 1 ]; then
    BOLD=$(tput bold) RED=$(tput setaf 1) GREEN=$(tput setaf 2) YELLOW=$(tput setaf 3) RESET=$(tput sgr0)
else
    BOLD="" RED="" GREEN="" YELLOW="" RESET=""
fi

section() { printf '\n%s== %s%s\n' "${BOLD}" "$1" "${RESET}"; }
ok()      { printf '  %s✔%s %s\n' "${GREEN}" "${RESET}" "$1"; }
warn()    { printf '  %s!%s %s\n' "${YELLOW}" "${RESET}" "$1"; }
fail()    { printf '  %s✘%s %s\n' "${RED}" "${RESET}" "$1"; }
info()    { printf '    %s\n' "$1"; }

# tf_output reads a Terraform output, falling back to the module defaults so the
# script still says something useful when state is missing.
tf_output() {
    terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null
}

CLUSTER=$(tf_output kind_cluster_name); CLUSTER=${CLUSTER:-airbyte-local}
KUBECONFIG_PATH=$(tf_output kubeconfig_path); KUBECONFIG_PATH=${KUBECONFIG_PATH:-${TF_DIR}/kubeconfig}
URL=$(tf_output airbyte_url); URL=${URL:-http://localhost:8000}
API_URL=$(tf_output airbyte_api_url); API_URL=${API_URL:-${URL}/api/public/v1}
NAMESPACE=airbyte
NODE_CONTAINER="${CLUSTER}-control-plane"

KUBECTL=(kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NAMESPACE}")

section "Terraform state"
if [ -s "${TF_DIR}/terraform.tfstate" ]; then
    RESOURCES=$(terraform -chdir="${TF_DIR}" state list 2>/dev/null | wc -l)
    ok "${RESOURCES} resource(s) tracked in ${TF_DIR}/terraform.tfstate"
else
    fail "no Terraform state in ${TF_DIR} — nothing has been applied yet"
    info "run: cd terraform && terraform init && terraform apply"
    exit 1
fi

section "Cluster"
if ! docker info >/dev/null 2>&1; then
    fail "docker is not running or not usable by this user"
    exit 1
fi
ok "docker is running"

NODE_STATE=$(docker inspect -f '{{.State.Status}}' "${NODE_CONTAINER}" 2>/dev/null)
if [ -z "${NODE_STATE}" ]; then
    fail "kind node container '${NODE_CONTAINER}' does not exist"
    info "the cluster is gone; run: cd terraform && terraform apply"
    exit 1
elif [ "${NODE_STATE}" != "running" ]; then
    fail "kind node container '${NODE_CONTAINER}' is ${NODE_STATE}"
    info "start it with: docker start ${NODE_CONTAINER}"
else
    STARTED=$(docker inspect -f '{{.State.StartedAt}}' "${NODE_CONTAINER}" 2>/dev/null)
    ok "kind node '${NODE_CONTAINER}' is running (since ${STARTED})"
fi

if [ ! -r "${KUBECONFIG_PATH}" ]; then
    fail "kubeconfig not readable at ${KUBECONFIG_PATH}"
    exit 1
fi
ok "kubeconfig: ${KUBECONFIG_PATH}"

section "Workloads"
if ! "${KUBECTL[@]}" get pods >/dev/null 2>&1; then
    fail "cannot reach the Kubernetes API"
    exit 1
fi

PODS=$("${KUBECTL[@]}" get pods --no-headers 2>/dev/null)
RUNNING=$(echo "${PODS}" | awk '$3=="Running"' | wc -l)
TOTAL=$(echo "${PODS}" | grep -cv 'Completed')
if [ "${RUNNING}" -eq "${TOTAL}" ] && [ "${TOTAL}" -gt 0 ]; then
    ok "${RUNNING}/${TOTAL} pods Running"
else
    warn "${RUNNING}/${TOTAL} pods Running"
fi
echo "${PODS}" | awk '{printf "    %-52s %-10s %s restart(s)\n", $1, $3, $4}'

NOT_READY=$(echo "${PODS}" | awk '$3!="Running" && $3!="Completed" {print $1}')
if [ -n "${NOT_READY}" ]; then
    warn "not ready: $(echo "${NOT_READY}" | tr '\n' ' ')"
    info "kubectl --kubeconfig ${KUBECONFIG_PATH} -n ${NAMESPACE} describe pod <name>"
fi

section "Data"
info "Airbyte's metadata (sources, connections, job history) lives in the bundled"
info "PostgreSQL (airbyte-db-0); sync artifacts and logs live in MinIO (airbyte-minio-0)."
info "Sync destination Postgres (airbyte-dest-postgres) is separate from metadata."
"${KUBECTL[@]}" get pvc --no-headers 2>/dev/null |
    awk '{printf "    %-34s %-8s %-6s volume=%s\n", $1, $2, $4, $3}'

DEST_PG=$("${KUBECTL[@]}" get deploy airbyte-dest-postgres --no-headers 2>/dev/null | awk '{print $2}')
if [ -n "${DEST_PG}" ]; then
    ok "dest Postgres deploy ready replicas: ${DEST_PG}"
    info "host: $(tf_output dest_postgres_host)"
else
    warn "dest Postgres deploy not found"
fi

info ""
info "Those volumes are directories inside the kind node container, so everything"
info "is destroyed by 'terraform destroy' or 'kind delete cluster':"
docker exec "${NODE_CONTAINER}" sh -c 'du -sh /var/local-path-provisioner/* 2>/dev/null' 2>/dev/null |
    awk '{printf "    %-8s %s\n", $1, $2}'

info ""
info "Inspect the metadata database directly:"
info "  kubectl --kubeconfig ${KUBECONFIG_PATH} -n ${NAMESPACE} exec -it airbyte-db-0 -- psql -U airbyte db-airbyte"

section "Access"
HOST_PORT=${URL##*:}
# docker port lists the Kubernetes API server mapping too; pick the one that
# actually publishes Airbyte.
APP_MAP=$(docker port "${NODE_CONTAINER}" 2>/dev/null | grep -E "> *[0-9.]+:${HOST_PORT}\$")
if [ -n "${APP_MAP}" ]; then
    ok "host port mapping: ${APP_MAP}"
else
    warn "no host mapping publishing port ${HOST_PORT} on ${NODE_CONTAINER}"
    docker port "${NODE_CONTAINER}" 2>/dev/null | awk '{printf "    %s\n", $0}'
fi

HTTP_UI=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${URL}/" 2>/dev/null)
if [ "${HTTP_UI}" = "200" ]; then
    ok "UI:  ${URL} (HTTP ${HTTP_UI})"
else
    fail "UI:  ${URL} (HTTP ${HTTP_UI:-no response})"
fi

HTTP_API=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${API_URL}/health" 2>/dev/null)
if [ "${HTTP_API}" = "200" ]; then
    ok "API: ${API_URL} (HTTP ${HTTP_API}, no authentication)"
else
    fail "API: ${API_URL} (HTTP ${HTTP_API:-no response})"
fi

if command -v jq >/dev/null 2>&1; then
    WORKSPACE_ID=$(curl -s -m 10 "${API_URL}/workspaces" 2>/dev/null | jq -r '.data[0].workspaceId // empty' 2>/dev/null)
    if [ -n "${WORKSPACE_ID}" ]; then
        ok "workspace_id: ${WORKSPACE_ID}"
        info "use this as workspace_id in connectors/environments/dev"
    else
        warn "could not read a workspace id from the API"
    fi
else
    warn "jq not installed; skipping workspace lookup"
fi

section "Next steps"
info "open the UI:      xdg-open ${URL}"
info "follow logs:      kubectl --kubeconfig ${KUBECONFIG_PATH} -n ${NAMESPACE} logs -f deploy/airbyte-server"
info "connector plans:  cd ../connectors/environments/dev && terraform plan"
info "dest psql:        $(tf_output dest_postgres_psql_command)"
info "tear it all down: cd terraform && terraform destroy"
echo
