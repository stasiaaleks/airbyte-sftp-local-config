variable "workspace_id" {
  description = "Airbyte workspace ID"
  type        = string
}

variable "tag_id" {
  description = "Optional tag ID associated with the connection. Leave null for untagged local connections."
  type        = string
  default     = null
}

variable "pg_config" {
  description = "Postgres destination configuration"
  type = object({
    name                 = string
    host                 = string
    port                 = optional(number, 5432)
    database             = string
    username             = string
    password             = string
    schema               = optional(string, "public")
    ssl                  = optional(bool, false)
    ssl_mode             = optional(any)
    disable_type_dedupe  = optional(bool, false)
    drop_cascade         = optional(bool, false)
    jdbc_url_params      = optional(string)
    raw_data_schema      = optional(string)
    unconstrained_number = optional(bool, false)
  })
  sensitive = true
}

variable "connection_config" {
  description = "Values for the connection configuration"
  type = object({
    name                                 = string
    status                               = optional(string, "active")
    non_breaking_schema_updates_behavior = optional(string, "ignore")
    schedule_type                        = optional(string, "manual")
    schedule_cron                        = optional(string)
    streams = list(object({
      name         = string
      sync_mode    = string
      primary_key  = optional(list(list(string)))
      cursor_field = optional(list(string))
    }))
  })
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
