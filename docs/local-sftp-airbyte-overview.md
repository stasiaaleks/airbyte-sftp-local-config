# Local SFTP + Airbyte + Postgres — system overview

This document describes the **local end-to-end path**:

**files on a Juju/LXD SFTP server → Airbyte (`source-sftp-bulk`) → Postgres in kind**

This monorepo (`airbyte-sftp-local-lab`) holds three **independent Terraform roots**
(separate state and apply/destroy). Nothing shares Terraform state.

| Root | Role |
| --- | --- |
| [`sftp/`](../sftp/) | SFTP-only endpoint on a Juju machine (LXD by default) |
| [`airbyte/`](../airbyte/) | Airbyte OSS on kind + dedicated sync-destination Postgres |
| [`connectors/`](../connectors/) (`environments/dev`) | Airbyte source, destination, and connection via the Airbyte Terraform provider |

---

## 1. Logical topology and interactions

```text
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ Host laptop                                                              │
 │                                                                          │
 │  ┌─────────────────────────────┐     ┌─────────────────────────────────┐ │
 │  │ LXD                          │     │ Docker                          │ │
 │  │  ┌───────────────────────┐  │     │  ┌───────────────────────────┐  │ │
 │  │  │ Juju model "sftp"     │  │     │  │ kind cluster              │  │ │
 │  │  │  machine / ubuntu/0   │  │     │  │  "airbyte-local"          │  │ │
 │  │  │  ┌─────────────────┐  │  │     │  │  namespace: airbyte       │  │ │
 │  │  │  │ sshd            │  │  │     │  │                           │  │ │
 │  │  │  │ ForceCommand    │◄─┼──┼─────┼──┼── Airbyte connector pods  │  │ │
 │  │  │  │ internal-sftp   │  │  │ SFTP│  │   (check / discover /     │  │ │
 │  │  │  │ user: sftpuser  │  │  │ :22 │  │    sync workloads)        │  │ │
 │  │  │  │ land: ~/upload  │  │  │     │  │         │                 │  │ │
 │  │  │  └─────────────────┘  │  │     │  │         ▼                 │  │ │
 │  │  └───────────────────────┘  │     │  │  airbyte-dest-postgres    │  │ │
 │  │           ▲                 │     │  │  (sync destination DB)    │  │ │
 │  │           │ juju ssh/scp    │     │  │         ▲                 │  │ │
 │  └───────────┼─────────────────┘     │  │         │ SQL             │  │ │
 │              │                       │  │  airbyte-server :8001     │  │ │
 │              │                       │  │  (UI + public API)        │  │ │
 │              │                       │  │         ▲                 │  │ │
 │              │                       │  └─────────┼─────────────────┘  │ │
 │              │                       │            │ NodePort→host :8000│ │
 │              │                       └────────────┼────────────────────┘ │
 │              │                                    │                      │
 │  Terraform / scripts / curl / browser ────────────┘                      │
 │  (apply plans, seed CSV, trigger sync, open UI)                          │
 └──────────────────────────────────────────────────────────────────────────┘
```

### Runtime interactions

1. **Human / scripts → SFTP**  
   Upload files (e.g. `seed-sample-csv.sh`) with the generated RSA private key to  
   `sftpuser@<LXD-IP>`, landing directory `/home/sftpuser/upload`.

2. **Human / Terraform → Airbyte API** (`http://localhost:8000/api/public/v1`)  
   `environments/dev` creates:
   - `airbyte_source_sftp_bulk` (host = LXD IP, key, folder path, CSV stream)
   - `airbyte_destination_postgres` (host = in-cluster DNS of dest Postgres)
   - `airbyte_connection` linking them (manual schedule)

3. **Airbyte control plane → connector workloads**  
   On check / discover / sync, the workload-launcher starts short-lived **Kubernetes pods** in the `airbyte` namespace that run the SFTP bulk and Postgres connector images.

4. **Connector pods → SFTP server**  
   Outbound TCP to `<LXD-bridge-IP>:22`. Auth is public key (RSA PEM).  
   Files are listed under the absolute `folder_path` (no chroot on the server).

5. **Connector pods → dest Postgres**  
   In-cluster DNS, e.g. `airbyte-dest-postgres.airbyte.svc.cluster.local:5432`.  
   Synced tables land in the configured schema (default `public`).

6. **Airbyte platform internals** (not the sync destination)  
   Metadata (sources, connections, job history) → bundled `airbyte-db` Postgres.  
   Logs / artifacts → bundled MinIO.

### What must not be confused

| Address | Meaning |
| --- | --- |
| `localhost:8000` | Host → Airbyte UI/API (kind port-map). **Only** for humans and the TF provider. |
| LXD unit IP (e.g. `10.60.7.x`) | SFTP host **from inside Airbyte pods**. Never `localhost` for SFTP. |
| `airbyte-dest-postgres.airbyte.svc.cluster.local` | Dest DB **from inside the cluster**. Never host `localhost` for the destination connector. |
| `airbyte-db-0` | Airbyte **metadata** DB, not where business rows land. |

---

## 2. Where configuration lives

### A. SFTP server — `sftp/`

| What | Where |
| --- | --- |
| Terraform root | `terraform/` (`main.tf`, `variables.tf`, `outputs.tf`, …) |
| Tunables | `terraform/variables.tf` / optional `terraform.tfvars` (model name, user, landing dir, key path, cloud) |
| In-unit sshd/user setup | `scripts/remote-sftp-setup.sh` applied via `scripts/apply-sftp.sh` + `juju ssh` |
| Generated private key (RSA PEM) | Default `~/.ssh/sftpuser` (+ `.pub`); also in **local TF state** (secret) |
| TF state | `terraform/terraform.tfstate` (gitignored) |
| Sample data + helpers | `samples/sample.csv`, `scripts/seed-sample-csv.sh`, `scripts/export-airbyte-env.sh` |

**On the machine itself (after apply):**

- Unix user `sftpuser` (default), shell `nologin`
- `~/.ssh/authorized_keys`
- `sshd_config` `Match User` block: `ForceCommand internal-sftp -d /home/sftpuser/upload`, publickey only

### B. Airbyte platform + dest Postgres — `airbyte/`

| What | Where |
| --- | --- |
| Terraform root | `terraform/` |
| kind cluster + Helm Airbyte + NodePort | `terraform/main.tf` |
| Helm values (auth off, MinIO sizing) | `terraform/values.yaml.tftpl` |
| Dest Postgres Deployment/Service/PVC/Secret | `terraform/postgres.tf` |
| Tunables | `terraform/variables.tf` (ports, chart version, PG password, …) |
| Kubeconfig for kubectl | `terraform/kubeconfig` (gitignored) |
| TF state | `terraform/terraform.tfstate` (gitignored) |
| Operator helpers | `Makefile`, `scripts/diagnose.sh` |

**Airbyte chart defaults used here:** auth **disabled**, listen on `127.0.0.1:8000`, bundled Postgres + MinIO enabled.

### C. Connectors (source / dest / connection) — `connectors/`

| What | Where |
| --- | --- |
| **Local only** wiring | `environments/dev/` |
| Provider → local API | `environments/dev/versions.tf` → `http://localhost:8000/api/public/v1` |
| Dev composition | `environments/dev/main.tf` |
| Secrets / hosts as TF vars | `environments/dev/variables.tf` (`TF_VAR_SFTP_*`, `TF_VAR_DEST_PG_*`, …) |
| Local TF state | `environments/dev/terraform.tfstate` (gitignored) |
| Reusable source module | `modules/connectors/source/sftp_bulk/` |
| Reusable connection module | `modules/connections/sftp_bulk/` |
| Shared Postgres dest module | `modules/connectors/destination/postgres/` |

**stg / prod** under `environments/{stg,prod}/` are separate roots with remote S3 state and many real connectors. They are **not** part of this local SFTP path. Do not `terraform apply` them for local testing.

### D. Runtime config inside Airbyte

Once applied, source/destination/connection definitions live in Airbyte’s **metadata database** (`airbyte-db`), managed via the public API. Terraform is the desired-state tool; the API/DB is the live control-plane store.

---

## 3. Under the hood (process model)

```text
Layer                    What it is
───────────────────────  ────────────────────────────────────────────────
LXD container            Juju machine for the ubuntu charm (SFTP host)
Juju model `sftp`        Model + app `ubuntu` + unit `ubuntu/0`
systemd sshd             On that unit; Match block forces internal-sftp
Docker                   kind node + all Airbyte/Postgres containers
kind node VM/container   Single-node Kubernetes (`airbyte-local-control-plane`)
Kubernetes pods          Airbyte server, worker, temporal, minio, db, …
                         + airbyte-dest-postgres
                         + ephemeral connector pods per check/sync
Host processes           terraform, juju CLI, kubectl, curl, browser
```

### SFTP side

- **Not** a Kubernetes workload.
- Juju deploys the **machine charm** `ubuntu` on the **localhost (LXD)** cloud by default.
- Terraform cannot exec into units; a `terraform_data` provisioner runs host scripts that `juju scp` / `juju ssh` the setup script.
- Network: typically LXD bridge (e.g. `10.60.7.0/24`). kind’s CNI/routing can reach that bridge on a normal laptop setup (verified operationally).

### Airbyte side

- **kind** cluster named `airbyte-local` (default).
- **Helm** release `airbyte` from `airbytehq` charts.
- **airbyte-server** serves UI + public API (container port 8001); a hand-rolled **NodePort** maps to host **8000**.
- Jobs run as **one-shot pods** (workload launcher), not long-lived SFTP daemons.
- **Dest Postgres** is a normal `Deployment` + `ClusterIP` `Service` + `PVC` + `Secret` in namespace `airbyte`.

### Connector side

- Terraform provider `airbytehq/airbyte` talks HTTP to the public API (no auth in local mode).
- `source-sftp-bulk` expects **RSA PEM** private keys (OpenSSH ed25519 keys fail file listing in the connector).
- `folder_path` must be the **absolute landing path** (e.g. `/home/sftpuser/upload`). There is no chroot; `/` is the host root.

---

## 4. Where data is stored

| Data | Location | Lifespan / teardown |
| --- | --- | --- |
| Files dropped for ingest | LXD unit disk: `/home/sftpuser/upload/` | Survives until unit/model destroy or manual delete |
| SFTP private key file | Host `~/.ssh/sftpuser` (default) | TF-managed file; destroy removes it |
| SFTP key material in state | `sftp//terraform/terraform.tfstate` | Treat as secret |
| Airbyte sources/connections/jobs metadata | Pod `airbyte-db-0` (PVC) | Wiped by `terraform destroy` on airbyte-local |
| Airbyte logs / staging artifacts | MinIO (`airbyte-minio-0` PVC) | Same |
| **Synced business rows** | `airbyte-dest-postgres` PVC → DB `airbyte_dest`, schema `public` (default) | Same; query via `dest_postgres_psql_command` |
| kind node filesystem / PVCs | Inside Docker kind node volume | Deleted with cluster |
| Connector TF state (dev) | `environments/dev/terraform.tfstate` | Local only; destroy removes API objects if you `terraform destroy` |

**Example synced table:** after a successful sample sync, `public.sample` contains CSV rows plus Airbyte metadata columns (`_airbyte_*`, `_ab_source_file_*`).

---

## 5. How to bring it up (order)

```bash
# 1) SFTP
cd sftp/terraform
terraform init && terraform apply

# 2) Airbyte + dest Postgres
cd ../../airbyte/terraform
terraform init && terraform apply

# 3) Seed + export credentials
cd ../../sftp/
./scripts/seed-sample-csv.sh
eval "$(./scripts/export-airbyte-env.sh)"
eval "$(cd ../airbyte/terraform && terraform output -raw export_dest_postgres_env_command)"

# 4) Connector objects on local Airbyte
cd ../connectors/environments/dev
terraform init && terraform apply
```

---

## 6. How to test

### Happy path

```bash
# Seed (or re-seed) CSV on SFTP
cd sftp && ./scripts/seed-sample-csv.sh

# Ensure connector TF is current
cd ../connectors/environments/dev
eval "$(../../sftp/scripts/export-airbyte-env.sh)"
eval "$(cd ../../airbyte/terraform && terraform output -raw export_dest_postgres_env_command)"
terraform plan   # ideally: No changes

# Trigger sync via API
$(terraform output -raw trigger_sync_command)

# Job status
curl -s 'http://localhost:8000/api/public/v1/jobs?limit=5' \
  | jq '.data[] | {jobId,status,jobType,startTime}'

# Read destination rows
cd ../../airbyte/terraform
$(terraform output -raw dest_postgres_psql_command)
# SQL:  \dt
#       SELECT id, name, amount FROM sample;
#       \q
```

### UI

Open `http://localhost:8000` → workspace **Default Workspace** → Connections →  
**Local SFTP bulk → Postgres** → Sync now.

### Expected sample result

| id | name | amount |
| --- | --- | --- |
| 1 | alpha | 10.5 |
| 2 | beta | 20.0 |
| 3 | gamma | 3.25 |

---

## 7. How to diagnose

### One-shot Airbyte stack report

```bash
cd airbyte
make diagnose
# or: ./scripts/diagnose.sh
```

Reports: TF state, kind node, pod readiness, PVCs, dest Postgres deploy, UI/API health, workspace id.

### SFTP

```bash
cd sftp/terraform
terraform output
eval "$(terraform output -raw sftp_command)"   # interactive sftp
# or
../scripts/seed-sample-csv.sh                  # upload + ls
juju status -m sftp
```

### Network path (from inside the cluster)

```bash
kubectl --kubeconfig airbyte/terraform/kubeconfig \
  -n airbyte run -it --rm --restart=Never netcheck --image=alpine:3.20 -- \
  sh -c 'apk add --no-cache busybox-extras >/dev/null && nc -zv <SFTP_HOST> 22'
```

### Connector / job failures

```bash
# Recent jobs
curl -s 'http://localhost:8000/api/public/v1/jobs?limit=5' | jq .

# Ephemeral connector pods (names include sftp-bulk-check|discover|read)
kubectl --kubeconfig airbyte/terraform/kubeconfig \
  -n airbyte get pods --sort-by=.metadata.creationTimestamp | tail

kubectl ... -n airbyte logs <pod> --all-containers
```

### Common failure modes

| Symptom | Likely cause |
| --- | --- |
| Empty stream / no files | `folder_path` is `/` instead of `/home/sftpuser/upload` |
| `unpack requires a buffer of 4 bytes` | Non-RSA (e.g. ed25519 OpenSSH) key given to sftp-bulk |
| Connection to SFTP times out | Wrong host (`localhost` from pod) or LXD/kind routing |
| Dest connection fails | Dest host set to localhost; use cluster DNS |
| API unreachable on apply | airbyte-local not up; `curl localhost:8000/api/public/v1/health` |
| Accidental stg/prod apply | Wrong directory — only use `environments/dev` for this stack |

---

## 8. Teardown

Destroy in reverse order if you want a clean slate:

```bash
# Connector objects on Airbyte
cd connectors/environments/dev && terraform destroy

# kind cluster (Airbyte + dest Postgres + all PVCs)
cd ../../airbyte/terraform && terraform destroy

# Juju model + SFTP unit + generated keys
cd ../../sftp//terraform && terraform destroy
```

Each destroy is independent; skipping connector destroy leaves orphaned sources/connections only until the Airbyte cluster itself is destroyed.

---

## 9. Security notes (local dev)

- Airbyte auth is **off**; API bind is **loopback only** — do not expose `:8000` on a routable interface.
- SFTP and Postgres passwords/keys appear in **local Terraform state** — gitignored; do not commit.
- SFTP user is SFTP-only (no shell) but **not chrooted**; world-readable host paths may be readable.
- This design is for **laptop integration testing**, not a production posture.

---

## 10. Quick reference — default names

| Item | Default |
| --- | --- |
| Juju model | `sftp` |
| SFTP user / landing | `sftpuser` / `/home/sftpuser/upload` |
| SFTP key path | `~/.ssh/sftpuser` (RSA PEM) |
| kind cluster | `airbyte-local` |
| Airbyte URL | `http://localhost:8000` |
| Dest PG service DNS | `airbyte-dest-postgres.airbyte.svc.cluster.local` |
| Dest PG database / user | `airbyte_dest` / `airbyte` |
| Dest PG password | `airbyte-local-dest` |
| Dev connection name | `Local SFTP bulk → Postgres` |
| Sample stream / table | `sample` |

---

## 11. Official external documentation

Upstream docs that correspond to how this stack is built. Prefer these over blog posts when extending or debugging.

### Juju + LXD (SFTP host)

| Topic | Link |
| --- | --- |
| Juju docs home | https://canonical.com/juju/docs |
| Get started with Juju | https://canonical.com/juju/docs/get-started-with-juju |
| Bootstrap a controller | https://canonical.com/juju/docs/juju-bootstrap |
| LXD cloud with Juju | https://canonical.com/juju/docs/lxd-cloud |
| `juju ssh` | https://canonical.com/juju/docs/juju-ssh |
| LXD documentation | https://documentation.ubuntu.com/lxd/en/latest/ |
| LXD getting started | https://documentation.ubuntu.com/lxd/en/latest/getting_started/ |
| `ubuntu` charm (Charmhub) | https://charmhub.io/ubuntu |

### Terraform — Juju / generic providers (SFTP TF)

| Topic | Link |
| --- | --- |
| Terraform CLI docs | https://developer.hashicorp.com/terraform/docs |
| Juju Terraform provider | https://registry.terraform.io/providers/juju/juju/latest/docs |
| `tls_private_key` (RSA PEM keys) | https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key |
| `local` provider (key files on disk) | https://registry.terraform.io/providers/hashicorp/local/latest/docs |
| `terraform_data` resource | https://developer.hashicorp.com/terraform/language/resources/terraform-data |

### kind + Kubernetes + Helm (Airbyte platform TF)

| Topic | Link |
| --- | --- |
| kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| kind extra port mappings | https://kind.sigs.k8s.io/docs/user/configuration/#extra-port-mappings |
| Terraform kind provider (`tehcyx/kind`) | https://registry.terraform.io/providers/tehcyx/kind/latest/docs |
| Kubernetes provider | https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs |
| Helm provider | https://registry.terraform.io/providers/hashicorp/helm/latest/docs |
| Kubernetes Service / DNS (`*.svc.cluster.local`) | https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/ |
| Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Persistent volumes / PVCs | https://kubernetes.io/docs/concepts/storage/persistent-volumes/ |

### Airbyte platform (Helm / local OSS)

| Topic | Link |
| --- | --- |
| Airbyte docs home | https://docs.airbyte.com/ |
| Deploy Airbyte | https://docs.airbyte.com/platform/deploying-airbyte |
| Deploy with Helm | https://docs.airbyte.com/platform/deploying-airbyte/integrations/deploy-ab-helm-chart |
| Airbyte Helm charts | https://airbytehq.github.io/helm-charts/ |
| Public API reference | https://reference.airbyte.com/ |
| OSS quickstart / abctl (alternative to kind) | https://docs.airbyte.com/platform/using-airbyte/getting-started/oss-quickstart |

### Airbyte Terraform (source / destination / connection)

| Topic | Link |
| --- | --- |
| Airbyte Terraform provider (latest) | https://registry.terraform.io/providers/airbytehq/airbyte/latest/docs |
| `airbyte_source_sftp_bulk` (v0.12.0, pinned) | https://registry.terraform.io/providers/airbytehq/airbyte/0.12.0/docs/resources/source_sftp_bulk |
| `airbyte_destination_postgres` (v0.12.0) | https://registry.terraform.io/providers/airbytehq/airbyte/0.12.0/docs/resources/destination_postgres |
| `airbyte_connection` (v0.12.0) | https://registry.terraform.io/providers/airbytehq/airbyte/0.12.0/docs/resources/connection |
| SFTP Bulk source (product docs) | https://docs.airbyte.com/integrations/sources/sftp-bulk |
| Postgres destination (product docs) | https://docs.airbyte.com/integrations/destinations/postgres |

### Postgres (destination image / ops)

| Topic | Link |
| --- | --- |
| Official Postgres Docker image | https://hub.docker.com/_/postgres |
| PostgreSQL documentation | https://www.postgresql.org/docs/current/ |
| `pg_isready` | https://www.postgresql.org/docs/current/app-pg-isready.html |

### SSH / SFTP (server lockdown + keys)

| Topic | Link |
| --- | --- |
| `sshd_config` (`Match`, `ForceCommand internal-sftp`) | https://man.openbsd.org/sshd_config |
| `ssh-keygen` (RSA PEM for Airbyte bulk: `-t rsa -m PEM`) | https://man.openbsd.org/ssh-keygen |

### Related in-repo READMEs

| Repo | Path |
| --- | --- |
| SFTP stack | [`sftp/README.md`](../sftp/README.md) |
| Airbyte + dest Postgres | [`airbyte/README.md`](../airbyte/README.md) |
| Connector modules / dev env | [`connectors/` + root README](../README.md) |
