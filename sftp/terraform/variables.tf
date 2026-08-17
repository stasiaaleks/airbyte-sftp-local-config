variable "model_name" {
  description = "Name of the Juju model that hosts the SFTP unit."
  type        = string
  default     = "sftp"
}

variable "juju_cloud" {
  description = "Juju cloud to create the model on. Defaults to the local LXD cloud."
  type        = string
  default     = "localhost"
}

variable "juju_cloud_region" {
  description = "Region within the Juju cloud. For LXD this is also 'localhost'."
  type        = string
  default     = "localhost"
}

variable "app_name" {
  description = "Name of the Juju application running the SFTP server."
  type        = string
  default     = "ubuntu"
}

variable "charm_channel" {
  description = "Charmhub channel for the ubuntu charm."
  type        = string
  default     = "latest/stable"
}

variable "charm_base" {
  description = "Base (OS/series) the charm is deployed on."
  type        = string
  default     = "ubuntu@24.04"
}

variable "machine_constraints" {
  description = "Juju constraints applied to the application's machine."
  type        = string
  default     = ""
}

variable "sftp_user" {
  description = "Unix user created on the unit for SFTP access."
  type        = string
  default     = "sftpuser"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.sftp_user))
    error_message = "sftp_user must be a valid lowercase Unix username."
  }
}

variable "sftp_dir" {
  description = "Landing directory, relative to the SFTP user's home, that clients are dropped into."
  type        = string
  default     = "upload"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.sftp_dir))
    error_message = "sftp_dir must be a single path segment without slashes."
  }
}

variable "ssh_key_path" {
  description = "Path where the generated SFTP private key is written. The public key is written alongside it with a .pub suffix."
  type        = string
  default     = "~/.ssh/sftpuser"
}

variable "juju_ssh_public_key_path" {
  description = "Public key registered with the model so `juju ssh` can reach the unit. Defaults to the first of ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub that exists."
  type        = string
  default     = ""
}

variable "wait_timeout" {
  description = "How long to wait for the unit to reach active/idle before failing, as a Go duration."
  type        = string
  default     = "20m"
}
