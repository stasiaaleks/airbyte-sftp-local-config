# Local SFTP → Airbyte → Postgres lab

Demo monorepo for the **local development and testing** stack:

**Juju/LXD SFTP → Airbyte OSS (kind) → destination Postgres**

Three **separate Terraform roots** (separate state, separate apply/destroy):

| Root | Path | What it owns |
| --- | --- | --- |
| SFTP | [`sftp/`](./sftp/) | Juju model + SFTP-only ubuntu unit + RSA key |
| Airbyte platform | [`airbyte/`](./airbyte/) | kind cluster, Airbyte Helm chart, dest Postgres |
| Connectors | [`connectors/`](./connectors/) | Airbyte source/destination/connection via API |

Production connector fleet stays in [`airbyte-connector-terraform-plans`](../airbyte-connector-terraform-plans) (`stg`/`prod` only).

Docs:

- [docs/local-sftp-airbyte-overview.md](./docs/local-sftp-airbyte-overview.md) — topology, storage, diagnose, upstream links
- [docs/STATE.md](./docs/STATE.md) — Terraform state migration notes

## Prerequisites

- `terraform` >= 1.5
- `juju` 3.x, bootstrapped LXD controller (`juju bootstrap localhost lxd-controller`)
- `docker`, `kubectl`, `jq`
- Client SSH key for `juju ssh` (`~/.ssh/id_ed25519` or `id_rsa`)
- ~8 GB free RAM for kind/Airbyte

## Bring-up order

```bash
# 1) SFTP
cd sftp/environments/dev/local-test
terraform init && terraform apply

# 2) Airbyte + dest Postgres
cd ../../../../airbyte/terraform
terraform init && terraform apply

# 3) Seed file + export env for connectors
cd ../../sftp
./scripts/seed-sample-csv.sh
eval "$(./scripts/export-airbyte-env.sh)"
eval "$(cd ../airbyte/terraform && terraform output -raw export_dest_postgres_env_command)"

# 4) Airbyte source / dest / connection
cd ../connectors/environments/dev
terraform init && terraform apply
$(terraform output -raw trigger_sync_command)
```

## Day-2 commands

```bash
# Airbyte pods (use this root's kubeconfig)
export KUBECONFIG=$PWD/airbyte/terraform/kubeconfig
kubectl -n airbyte get pods

# Diagnose platform
cd airbyte && make diagnose

# Re-seed SFTP sample
cd sftp && ./scripts/seed-sample-csv.sh

# Query synced rows
cd airbyte/terraform
$(terraform output -raw dest_postgres_psql_command)
```

## Teardown (reverse order)

```bash
cd connectors/environments/dev && terraform destroy
cd ../../../airbyte/terraform && terraform destroy
cd ../../sftp/environments/dev/local-test && terraform destroy
```

## Design notes

- **No shared Terraform state** between roots. Glue is env vars (`TF_VAR_SFTP_*`, `TF_VAR_DEST_PG_*`).
- Connector workers must use the **LXD unit IP** for SFTP and **cluster DNS** for Postgres — never `localhost` for either from inside pods.
- SFTP private key is **RSA PEM** (Airbyte `source-sftp-bulk` rejects ed25519 OpenSSH keys).
