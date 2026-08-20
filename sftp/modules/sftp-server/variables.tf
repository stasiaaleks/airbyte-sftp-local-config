variable "sftp_server_config" {
  description = "Configuration for the SFTP server"
  type = object({
    juju_model_name = string
    machine_name    = string
    sftp_user       = string
    sftp_group      = optional(string, "sftpusers")
    sftp_root       = optional(string, "/srv/sftp")
    directories     = optional(list(string), ["uploads", "processed"])
    ubuntu_base     = optional(string, "ubuntu@24.04")
  })

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.sftp_server_config.sftp_user))
    error_message = "sftp_user must be a valid Linux account name of at most 32 characters."
  }

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.sftp_server_config.sftp_group))
    error_message = "sftp_group must be a valid Linux group name of at most 32 characters."
  }

  validation {
    condition = (
      can(regex("^/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$", var.sftp_server_config.sftp_root)) &&
      alltrue([for segment in split("/", var.sftp_server_config.sftp_root) : segment != ".."])
    )
    error_message = "sftp_root must be an absolute single-line path using only [A-Za-z0-9._-] segments, without parent-directory traversal."
  }

  validation {
    condition = alltrue([
      for directory in var.sftp_server_config.directories :
      directory != "" &&
      !startswith(directory, "/") &&
      !strcontains(directory, "\n") &&
      alltrue([for segment in split("/", directory) : segment != ".." && segment != ""])
    ])
    error_message = "directories must contain non-empty relative paths without traversal."
  }
}

variable "ssh_public_keys" {
  description = "Public SSH keys authorized for the SFTP account"
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(compact(var.ssh_public_keys)) > 0
    error_message = "ssh_public_keys must contain at least one non-empty public key."
  }
}
