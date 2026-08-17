terraform {
  required_providers {
    airbyte = {
      source = "airbytehq/airbyte"
    }
  }
}

output "destination_id" {
  value = airbyte_destination_postgres.destination_postgres.destination_id
}

resource "airbyte_destination_postgres" "destination_postgres" {
  configuration = {
    database             = var.pg_config.database
    disable_type_dedupe  = false
    drop_cascade         = false
    host                 = var.pg_config.host
    jdbc_url_params      = var.pg_config.jdbc_url_params
    password             = var.pg_config.password
    port                 = var.pg_config.port
    raw_data_schema      = var.pg_config.raw_data_schema
    schema               = var.pg_config.schema
    ssl                  = var.pg_config.ssl
    ssl_mode             = var.pg_config.ssl_mode
    unconstrained_number = var.pg_config.unconstrained_number
    username             = var.pg_config.username
  }
  name         = var.pg_config.name
  workspace_id = var.workspace_id
}
