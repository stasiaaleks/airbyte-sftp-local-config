# Connectors root (local demo)

Terraform that configures Airbyte **objects** against the local instance from
[`../airbyte`](../airbyte) (API `http://localhost:8000/api/public/v1`).

## Layout

```
modules/
  connectors/source/sftp_bulk/       airbyte_source_sftp_bulk
  connectors/destination/postgres/   airbyte_destination_postgres
  connections/sftp_bulk/             source + dest + connection
environments/dev/                    local composition only
```

This root does **not** deploy kind, Airbyte, or the SFTP server.

## Usage

```bash
# After sftp/ and airbyte/ are applied:
eval "$(../../sftp/scripts/export-airbyte-env.sh)"
eval "$(cd ../../airbyte/terraform && terraform output -raw export_dest_postgres_env_command)"

cd environments/dev
terraform init
terraform apply
$(terraform output -raw trigger_sync_command)
```

See the monorepo [README](../README.md) and
[docs/local-sftp-airbyte-overview.md](../docs/local-sftp-airbyte-overview.md).
