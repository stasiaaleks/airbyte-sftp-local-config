variable "workspace_id" {
  description = "Airbyte workspace ID"
  type        = string
}

variable "sftp_config" {
  description = "Configuration for the SFTP bulk source"
  type = object({
    name        = optional(string, "Local SFTP")
    host        = string
    port        = optional(number, 22)
    username    = string
    private_key = string
    folder_path = optional(string, "/")
    start_date  = optional(string)
    streams = list(object({
      name                            = string
      globs                           = optional(list(string), ["**/*.csv"])
      format                          = optional(string, "csv")
      schemaless                      = optional(bool, false)
      validation_policy               = optional(string, "Emit Record")
      days_to_sync_if_history_is_full = optional(number, 3)
      recent_n_files_to_read_for_schema_discovery = optional(number, 10)
      input_schema                    = optional(string)
      csv_delimiter                   = optional(string, ",")
      csv_quote_char                  = optional(string, "\"")
    }))
  })
  sensitive = true
}
