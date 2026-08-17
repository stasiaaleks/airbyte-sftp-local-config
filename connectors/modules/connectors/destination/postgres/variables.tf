variable "workspace_id" {
  description = "Airbyte workspace ID"
  type        = string
}

variable "pg_config" {
  description = "Postgres configuration"
  type = object({
    name     = string
    host     = string
    port     = number
    database = string
    username = string
    password = string
    schema   = string
    ssl      = optional(bool)
    ssl_mode = optional(any, {
      require = {}
    })
    disable_type_dedupe  = optional(bool, false)
    drop_cascade         = optional(bool, false)
    jdbc_url_params      = optional(string)
    raw_data_schema      = optional(string)
    unconstrained_number = optional(bool, false)
  })
}
