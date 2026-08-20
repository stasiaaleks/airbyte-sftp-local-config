locals {
  private_key_path = pathexpand(var.sftp_private_key_path)
  public_key_path  = "${local.private_key_path}.pub"
  chroot_path      = "${trimsuffix(var.sftp_root, "/")}/${var.sftp_user}"
  scripts_dir      = abspath("${path.module}/../../../scripts")

  candidate_client_keys = [
    for candidate in compact([
      var.juju_ssh_public_key_path,
      "~/.ssh/id_ed25519.pub",
      "~/.ssh/id_rsa.pub",
    ]) : pathexpand(candidate)
  ]
  client_key_path = try(
    [for candidate in local.candidate_client_keys : candidate if fileexists(candidate)][0],
    null,
  )
}

# The prod plans repo reuses a pre-existing shared model on prodstack6. Locally
# we own the model too so `terraform apply` is fully self-contained.
resource "juju_model" "sftp" {
  name = var.juju_model_name

  cloud {
    name   = var.juju_cloud
    region = var.juju_cloud_region
  }
}

# Register a client SSH key with the model so the module's local-exec
# provisioners can reach the new machine via `juju ssh`.
resource "juju_ssh_key" "client" {
  model   = juju_model.sftp.name
  payload = local.client_key_path == null ? "" : trimspace(file(local.client_key_path))

  lifecycle {
    precondition {
      condition     = local.client_key_path != null
      error_message = "No client SSH public key found. Generate one with `ssh-keygen` or set juju_ssh_public_key_path."
    }
  }
}

# RSA PEM is required by Airbyte source-sftp-bulk (OpenSSH ed25519 keys fail
# listing with "unpack requires a buffer of 4 bytes" in the connector).
resource "tls_private_key" "sftp" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  filename        = local.private_key_path
  content         = tls_private_key.sftp.private_key_pem
  file_permission = "0600"
}

resource "local_file" "public_key" {
  filename        = local.public_key_path
  content         = "${trimspace(tls_private_key.sftp.public_key_openssh)} sftp-${var.sftp_user}\n"
  file_permission = "0644"
}

module "sftp" {
  source = "../../../modules/sftp-server"

  sftp_server_config = {
    juju_model_name = juju_model.sftp.name
    machine_name    = var.machine_name
    sftp_user       = var.sftp_user
    sftp_group      = var.sftp_group
    sftp_root       = var.sftp_root
    directories     = var.directories
    ubuntu_base     = var.ubuntu_base
  }

  ssh_public_keys = [trimspace(tls_private_key.sftp.public_key_openssh)]

  depends_on = [juju_ssh_key.client]
}

# Resolve the machine's public address for client convenience. Runs after the
# module has finished configuring the machine.
data "external" "unit_address" {
  program = ["/usr/bin/env", "bash", "${local.scripts_dir}/machine-address.sh"]

  query = {
    model      = juju_model.sftp.name
    machine_id = module.sftp.machine_id
  }
}
