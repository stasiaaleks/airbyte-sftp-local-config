variable "juju_model_name" {
  description = "Name of the Juju model created locally to host the SFTP machine."
  type        = string
  default     = "local-sftp"
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

variable "machine_name" {
  description = "Juju machine name for the SFTP server."
  type        = string
  default     = "local-test-sftp"
}

variable "ubuntu_base" {
  description = "Ubuntu base to deploy on the SFTP machine."
  type        = string
  default     = "ubuntu@24.04"
}

variable "sftp_user" {
  description = "Unix user created on the SFTP machine."
  type        = string
  default     = "sftpuser"
}

variable "sftp_group" {
  description = "Unix group for the SFTP user."
  type        = string
  default     = "sftpusers"
}

variable "sftp_root" {
  description = "Root directory for chrooted SFTP accounts."
  type        = string
  default     = "/srv/sftp"
}

variable "directories" {
  description = "Writable directories created under the SFTP user's chroot."
  type        = list(string)
  default     = ["uploads", "processed"]
}

variable "sftp_private_key_path" {
  description = "Path where the generated SFTP RSA private key is written. The public key is written alongside with a .pub suffix. RSA PEM is required by Airbyte source-sftp-bulk (ed25519 OpenSSH keys fail listing with 'unpack requires a buffer of 4 bytes')."
  type        = string
  default     = "~/.ssh/sftp-local-test"
}

variable "juju_ssh_public_key_path" {
  description = "Public key registered with the model so `juju ssh` can reach the machine. Defaults to the first of ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub that exists."
  type        = string
  default     = ""
}
