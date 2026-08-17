variable "workspace_id" {
  description = "Airbyte workspace ID. Leave empty to discover the Default Workspace from the local API."
  type        = string
  default     = ""
}

variable "tag_id" {
  description = "Optional Airbyte tag ID. Leave null to create an untagged connection."
  type        = string
  default     = null
}

variable "SFTP_HOST" {
  description = "SFTP server address reachable from Airbyte pods (the Juju/LXD unit IP, not localhost)."
  type        = string
}

variable "SFTP_PORT" {
  description = "SFTP server port."
  type        = number
  default     = 22
}

variable "SFTP_USER" {
  description = "SFTP username."
  type        = string
  default     = "sftpuser"
}

variable "SFTP_PRIVATE_KEY" {
  description = "OpenSSH private key contents for the SFTP user. Prefer export-airbyte-env.sh; alternatively set sftp_private_key_path."
  type        = string
  default     = ""
  sensitive   = true
}

variable "sftp_private_key_path" {
  description = "Path to the SFTP private key file when SFTP_PRIVATE_KEY is unset."
  type        = string
  default     = "~/.ssh/sftpuser"
}

variable "SFTP_FOLDER_PATH" {
  description = "Absolute directory on the SFTP server to read. sftp/ root has no chroot, so use the landing path (e.g. /home/sftpuser/upload), not '/'."
  type        = string
  default     = "/home/sftpuser/upload"
}

variable "SFTP_START_DATE" {
  description = "Optional UTC start date (2017-01-25T00:00:00.000000Z). Files modified before this are skipped."
  type        = string
  default     = null
}

variable "DEST_PG_HOST" {
  description = "In-cluster DNS name of the destination Postgres (from airbyte-local dest_postgres_host output)."
  type        = string
  default     = "airbyte-dest-postgres.airbyte.svc.cluster.local"
}

variable "DEST_PG_PORT" {
  description = "Destination Postgres port."
  type        = number
  default     = 5432
}

variable "DEST_PG_DATABASE" {
  description = "Destination Postgres database."
  type        = string
  default     = "airbyte_dest"
}

variable "DEST_PG_USERNAME" {
  description = "Destination Postgres username."
  type        = string
  default     = "airbyte"
}

variable "DEST_PG_PASSWORD" {
  description = "Destination Postgres password (airbyte-local default unless overridden)."
  type        = string
  default     = "airbyte-local-dest"
  sensitive   = true
}

variable "DEST_PG_SCHEMA" {
  description = "Destination schema for synced tables."
  type        = string
  default     = "public"
}
