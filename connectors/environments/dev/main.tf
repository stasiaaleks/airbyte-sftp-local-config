locals {
  # Default Workspace on the local airbyte-local instance. Override with
  # TF_VAR_workspace_id after a reinstall if needed:
  #   curl -s http://localhost:8000/api/public/v1/workspaces | jq -r '.data[0].workspaceId'
  discovered_workspace_id = try(jsondecode(data.http.workspace.response_body).data[0].workspaceId, null)
  workspace_id            = var.workspace_id != "" ? var.workspace_id : local.discovered_workspace_id

  sftp_private_key = var.SFTP_PRIVATE_KEY != "" ? var.SFTP_PRIVATE_KEY : file(pathexpand(var.sftp_private_key_path))
}

data "http" "workspace" {
  url = "http://localhost:8000/api/public/v1/workspaces"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Local Airbyte API is not reachable at http://localhost:8000. Apply the airbyte/ root first."
    }
  }
}

module "sftp_bulk_connection" {
  providers = {
    airbyte = airbyte
  }

  source       = "../../modules/connections/sftp_bulk"
  workspace_id = local.workspace_id
  tag_id       = var.tag_id

  connection_config = {
    name                                 = "Local SFTP bulk → Postgres"
    status                               = "active"
    non_breaking_schema_updates_behavior = "ignore"
    schedule_type                        = "manual"
    streams = [
      {
        name      = "sample"
        sync_mode = "full_refresh_overwrite"
      }
    ]
  }

  sftp_config = {
    name        = "Local Juju SFTP"
    host        = var.SFTP_HOST
    port        = var.SFTP_PORT
    username    = var.SFTP_USER
    private_key = local.sftp_private_key
    # Absolute landing path: sftp/ root has no chroot, only ForceCommand -d.
    # '/' is the host root and will not see uploaded files.
    folder_path = var.SFTP_FOLDER_PATH
    start_date  = var.SFTP_START_DATE
    streams = [
      {
        name   = "sample"
        globs  = ["*.csv", "**/*.csv"]
        format = "csv"
      }
    ]
  }

  pg_config = {
    name     = "Local kind Postgres"
    host     = var.DEST_PG_HOST
    port     = var.DEST_PG_PORT
    database = var.DEST_PG_DATABASE
    username = var.DEST_PG_USERNAME
    password = var.DEST_PG_PASSWORD
    schema   = var.DEST_PG_SCHEMA
    ssl      = false
    ssl_mode = {
      disable = {}
    }
  }
}
