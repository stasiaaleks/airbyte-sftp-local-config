terraform {
  required_providers {
    airbyte = {
      source  = "airbytehq/airbyte"
      version = "0.12.0"
    }
  }
}

output "source_id" {
  value = airbyte_source_sftp_bulk.source_sftp_bulk.source_id
}

resource "airbyte_source_sftp_bulk" "source_sftp_bulk" {
  name         = var.sftp_config.name
  workspace_id = var.workspace_id

  configuration = {
    host        = var.sftp_config.host
    port        = var.sftp_config.port
    username    = var.sftp_config.username
    folder_path = var.sftp_config.folder_path
    start_date  = var.sftp_config.start_date

    credentials = {
      authenticate_via_private_key = {
        private_key = var.sftp_config.private_key
      }
    }

    streams = [
      for stream in var.sftp_config.streams : merge(
        {
          name                            = stream.name
          globs                           = stream.globs
          schemaless                      = stream.schemaless
          validation_policy               = stream.validation_policy
          days_to_sync_if_history_is_full = stream.days_to_sync_if_history_is_full
          recent_n_files_to_read_for_schema_discovery = stream.recent_n_files_to_read_for_schema_discovery
          format = {
            csv_format = stream.format == "csv" ? {
              delimiter                        = stream.csv_delimiter
              quote_char                       = stream.csv_quote_char
              double_quote                     = true
              encoding                         = "utf8"
              skip_rows_before_header          = 0
              skip_rows_after_header           = 0
              strings_can_be_null              = true
              ignore_errors_on_fields_mismatch = false
              header_definition = {
                from_csv = {}
              }
            } : null
            jsonl_format = stream.format == "jsonl" ? {} : null
          }
        },
        stream.input_schema != null ? { input_schema = stream.input_schema } : {}
      )
    ]
  }
}
