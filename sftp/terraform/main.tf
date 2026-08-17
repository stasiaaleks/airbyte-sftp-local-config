locals {
  private_key_path = pathexpand(var.ssh_key_path)
  public_key_path  = "${local.private_key_path}.pub"
  unit_name        = "${var.app_name}/0"
  landing_path     = "/home/${var.sftp_user}/${var.sftp_dir}"
  scripts_dir      = abspath("${path.module}/../scripts")

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

resource "juju_model" "sftp" {
  name = var.model_name

  cloud {
    name   = var.juju_cloud
    region = var.juju_cloud_region
  }
}

resource "juju_application" "sftp" {
  name       = var.app_name
  model_uuid = juju_model.sftp.uuid

  charm {
    name    = "ubuntu"
    channel = var.charm_channel
    base    = var.charm_base
  }

  units       = 1
  constraints = var.machine_constraints
}

resource "juju_ssh_key" "client" {
  model_uuid = juju_model.sftp.uuid
  payload    = local.client_key_path == null ? "" : trimspace(file(local.client_key_path))

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

# The Juju provider cannot run commands inside a unit, so the in-unit SFTP
# setup is applied by piping the remote script over `juju ssh`. Re-runs are
# idempotent, and any change to the key, user or landing directory replaces
# this resource and reapplies the configuration.
resource "terraform_data" "sftp_config" {
  triggers_replace = {
    application = juju_application.sftp.id
    public_key  = local_file.public_key.content
    sftp_user   = var.sftp_user
    sftp_dir    = var.sftp_dir
    setup_hash  = filesha256("${local.scripts_dir}/remote-sftp-setup.sh")
  }

  depends_on = [juju_ssh_key.client]

  provisioner "local-exec" {
    command     = "${local.scripts_dir}/apply-sftp.sh"
    interpreter = ["/usr/bin/env", "bash"]

    environment = {
      JUJU_MODEL          = juju_model.sftp.name
      SFTP_UNIT           = local.unit_name
      SFTP_USER           = var.sftp_user
      SFTP_DIR            = var.sftp_dir
      SFTP_PUBKEY_FILE    = local_file.public_key.filename
      SFTP_WAIT_TIMEOUT   = var.wait_timeout
      REMOTE_SETUP_SCRIPT = "${local.scripts_dir}/remote-sftp-setup.sh"
    }
  }
}

data "external" "unit_address" {
  program = ["/usr/bin/env", "bash", "${local.scripts_dir}/unit-address.sh"]

  query = {
    model = juju_model.sftp.name
    app   = var.app_name
    unit  = local.unit_name
  }

  depends_on = [terraform_data.sftp_config]
}
