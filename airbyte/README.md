# Local Airbyte instance, managed with Terraform

> See [../README.md](../README.md).


Terraform plans that stand up a local [Airbyte](https://airbyte.com/) instance
on a dedicated [kind](https://kind.sigs.k8s.io/) cluster, published on
`http://localhost:8000`.

That address is not arbitrary: the sibling repo
[`connectors (this monorepo)`](../connectors)
configures its `dev` environment as

```hcl
provider "airbyte" {
  server_url = "http://localhost:8000/api/public/v1"
}
```

with no `client_id`/`client_secret`. This module therefore publishes Airbyte on
port 8000 **with authentication disabled**, so those plans work against it
unchanged.

Terraform owns the whole lifecycle:

- creates a dedicated kind cluster (`airbyte-local`) with host port 8000 mapped
  into the cluster
- installs the `airbyte/airbyte` Helm chart with the bundled PostgreSQL and
  MinIO, so there are no external dependencies
- publishes `airbyte-server` on a `NodePort` that lands on host port 8000
- outputs ready-to-run health-check and `kubectl` commands

This repo is deliberately decoupled from the Juju SFTP plans: separate
directory, separate state, separate lifecycle. Nothing here touches Juju or LXD.

## Layout

```
terraform/                     Terraform root module
  versions.tf                  provider + Terraform version pins
  providers.tf                 kind / kubernetes / helm provider configuration
  variables.tf                 all tunables
  main.tf                      cluster, namespace, Helm release, NodePort
  values.yaml.tftpl            Helm values for the Airbyte chart
  outputs.tf                   URLs and helper commands
  terraform.tfvars.example     copy to terraform.tfvars to customise
Makefile                       fmt / lint / up / down / status / health
```

## Prerequisites

- `terraform` >= 1.5
- `docker`, running and usable by your user
- `kubectl`
- ~8 GB of free RAM and 4 cores

`kind` and `helm` binaries are **not** required: Terraform's `tehcyx/kind` and
`hashicorp/helm` providers do the work in-process. Having `kind` installed is
still handy for teardown escape hatches.

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # optional, all values have defaults
terraform init
terraform apply
```

The first apply takes several minutes: it creates the cluster and pulls a few GB
of Airbyte images. Subsequent applies are fast.

On success:

```
airbyte_api_url      = "http://localhost:8000/api/public/v1"
airbyte_url          = "http://localhost:8000"
health_check_command = "curl -sf http://localhost:8000/api/public/v1/health"
kind_cluster_name    = "airbyte-local"
kube_context         = "kind-airbyte-local"
kubeconfig_path      = "/…/terraform/kubeconfig"
kubectl_command      = "kubectl --kubeconfig /…/terraform/kubeconfig -n airbyte get pods"
```

## Verifying

```bash
cd terraform
$(terraform output -raw health_check_command)   # public API
$(terraform output -raw kubectl_command)        # all pods Running
xdg-open "$(terraform output -raw airbyte_url)" # UI
```

All nine Airbyte pods should be `Running` (plus a `Completed` bootloader job).

## Using it with the connector plans

```bash
cd ../connectors/environments/dev
terraform init
terraform plan
```

No provider changes are needed. The instance ships with a `Default Workspace`;
its ID, which those plans need as `workspace_id`, is:

```bash
curl -s http://localhost:8000/api/public/v1/workspaces | jq -r '.data[0].workspaceId'
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `cluster_name` | `airbyte-local` | kind cluster name |
| `kubernetes_version` | `v1.31.2` | kind node image tag |
| `namespace` | `airbyte` | Namespace Airbyte is installed into |
| `release_name` | `airbyte` | Helm release name |
| `chart_version` | `1.8.5` | `airbyte/airbyte` chart version |
| `host_port` | `8000` | Host port Airbyte is published on |
| `node_port` | `30080` | NodePort that `host_port` maps to |
| `listen_address` | `127.0.0.1` | Host address the port is bound to |
| `helm_timeout` | `1800` | Seconds to wait for the Helm release |
| `minio_memory_request` | `256Mi` | MinIO memory request (chart default is 1Gi) |
| `minio_cpu_request` | `100m` | MinIO CPU request |

Keep `host_port` at 8000 unless something else already listens there — the
connector plans hardcode it.

## Design notes

### Why the providers are configured from resource attributes

`providers.tf` configures the `kubernetes` and `helm` providers from
`kind_cluster.airbyte`'s exported attributes, not from `config_path`. Provider
configuration is evaluated before the cluster resource is created, so on a cold
apply a `config_path` pointing at the not-yet-written kubeconfig fails with

```
'config_path' refers to an invalid path: … no such file or directory
```

and the whole apply has to be run twice. Reading the endpoint and certificates
straight off the resource makes a single-pass `terraform apply` work from
scratch.

The kubeconfig file is still written to `terraform/kubeconfig` (git-ignored) for
`kubectl`.

### Why there is a hand-written NodePort service

The chart only exposes `type` and `port` for the server service, not
`nodePort`. `kubernetes_service.airbyte_nodeport` selects the server pods by
their chart labels and pins the NodePort, which keeps the host-port contract in
one readable place.

`airbyte-server` serves both the UI and the public API on port 8001; the
separate `webapp` component is disabled by default in this chart line.

### Authentication

`global.auth.enabled` is `false`. This is a deliberate local-development choice
that matches the connector plans' dev provider block, and it is why the port is
bound to `127.0.0.1` only. Do not expose this instance on a routable address.

## Troubleshooting

### `port is already allocated` on apply

Something already listens on host port 8000. Check with `ss -ltnp | grep :8000`,
then either free it or run with another port — remembering that the connector
plans expect 8000:

```bash
terraform apply -var host_port=8001
```

### Pods stuck `Pending`

Not enough memory or CPU on the host. Check with:

```bash
kubectl --kubeconfig terraform/kubeconfig -n airbyte describe pod <name> | tail -20
```

Free some memory and the scheduler will place them; nothing needs reapplying.

### The Helm release times out

The first pull is large and slow on a cold Docker cache. Raise the timeout and
reapply — the release is resumed, not recreated:

```bash
terraform apply -var helm_timeout=3600
```

### `curl` returns nothing but the pods are Running

`airbyte-workload-launcher` restarts once during startup; give it a minute. If
the port itself is dead, confirm the mapping survived:

```bash
docker port airbyte-local-control-plane
```

### The cluster exists but Terraform does not know about it

If state was lost, delete the cluster by hand and start over:

```bash
kind delete cluster --name airbyte-local
```

## Sync destination Postgres

This module also deploys a small dedicated Postgres used as an Airbyte **sync**
destination (separate from the chart's metadata DB). Workers reach it at the
in-cluster DNS name from `dest_postgres_host` (never `localhost`).

```bash
terraform output dest_postgres_host
eval "$(terraform output -raw export_dest_postgres_env_command)"
$(terraform output -raw dest_postgres_psql_command)
```

## Ingesting from the Juju SFTP server

The companion repo `sftp/` runs an SFTP-only endpoint on a
Juju/LXD machine. The kind node routes to the LXD bridge and reaches the unit's
SSH port — use the unit's LXD address, not `localhost`.

End-to-end connector wiring lives in
`connectors (this monorepo)/environments/dev` (`source-sftp-bulk` → this
destination Postgres). Typical flow:

```bash
# 1) SFTP up + sample file
cd ../sftp
./scripts/seed-sample-csv.sh
eval "$(./scripts/export-airbyte-env.sh)"

# 2) This stack (Airbyte + dest Postgres) already applied
cd ../airbyte//terraform
eval "$(terraform output -raw export_dest_postgres_env_command)"

# 3) Connector plan
cd ../../connectors/environments/dev
terraform init && terraform apply
$(terraform output -raw trigger_sync_command)
```

## Teardown

```bash
cd terraform
terraform destroy
```

This deletes the kind cluster and everything on it, including all Airbyte data.
