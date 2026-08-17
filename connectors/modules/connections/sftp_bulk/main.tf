terraform {
  required_providers {
    airbyte = {
      source  = "airbytehq/airbyte"
      version = "0.12.0"
    }
  }
}

module "source_sftp_bulk" {
  source       = "../../connectors/source/sftp_bulk"
  workspace_id = var.workspace_id
  sftp_config  = var.sftp_config
}

module "destination_postgres" {
  source       = "../../connectors/destination/postgres"
  workspace_id = var.workspace_id
  pg_config = {
    name                 = var.pg_config.name
    host                 = var.pg_config.host
    port                 = var.pg_config.port
    database             = var.pg_config.database
    username             = var.pg_config.username
    password             = var.pg_config.password
    schema               = var.pg_config.schema
    ssl                  = var.pg_config.ssl
    ssl_mode             = var.pg_config.ssl_mode
    disable_type_dedupe  = var.pg_config.disable_type_dedupe
    drop_cascade         = var.pg_config.drop_cascade
    jdbc_url_params      = var.pg_config.jdbc_url_params
    raw_data_schema      = var.pg_config.raw_data_schema
    unconstrained_number = var.pg_config.unconstrained_number
  }
}

resource "airbyte_connection" "sftp_bulk_postgres_connection" {
  configurations = {
    streams = var.connection_config.streams
  }
  destination_id                       = module.destination_postgres.destination_id
  name                                 = var.connection_config.name
  non_breaking_schema_updates_behavior = var.connection_config.non_breaking_schema_updates_behavior
  schedule = var.connection_config.schedule_type == "cron" ? {
    schedule_type   = "cron"
    cron_expression = var.connection_config.schedule_cron
    } : {
    schedule_type = "manual"
  }
  source_id = module.source_sftp_bulk.source_id
  status    = var.connection_config.status
  tags = length(compact([var.tag_id])) == 0 ? [] : [
    {
      color        = "placeholder"
      name         = "placeholder"
      tag_id       = var.tag_id
      workspace_id = var.workspace_id
    }
  ]
}

output "source_id" {
  value = module.source_sftp_bulk.source_id
}

output "destination_id" {
  value = module.destination_postgres.destination_id
}

output "connection_id" {
  value = airbyte_connection.sftp_bulk_postgres_connection.connection_id
}
