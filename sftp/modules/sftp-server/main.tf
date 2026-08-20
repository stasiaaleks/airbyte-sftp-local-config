locals {
  ssh_public_keys = compact(var.ssh_public_keys)
}

resource "juju_machine" "sftp" {
  model             = var.sftp_server_config.juju_model_name
  base              = var.sftp_server_config.ubuntu_base
  name              = var.sftp_server_config.machine_name
  wait_for_hostname = true
}

resource "null_resource" "configure_sftp" {
  depends_on = [
    juju_machine.sftp,
  ]

  triggers = {
    machine_id      = juju_machine.sftp.machine_id
    model_name      = var.sftp_server_config.juju_model_name
    machine_name    = var.sftp_server_config.machine_name
    sftp_user       = var.sftp_server_config.sftp_user
    sftp_group      = var.sftp_server_config.sftp_group
    sftp_root       = var.sftp_server_config.sftp_root
    directories     = sha256(jsonencode(var.sftp_server_config.directories))
    ssh_public_keys = sha256(join("\n", local.ssh_public_keys))
    configure_script = sha256(join("", [
      filesha256("${path.module}/scripts/configure-sftp-server.sh"),
      filesha256("${path.module}/scripts/configure-sftp-server-remote.sh"),
    ]))
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/configure-sftp-server.sh"
    interpreter = ["/bin/bash", "-c"]

    environment = {
      MACHINE_ID          = juju_machine.sftp.machine_id
      MODEL_NAME          = var.sftp_server_config.juju_model_name
      MACHINE_NAME        = juju_machine.sftp.name
      SFTP_USER           = var.sftp_server_config.sftp_user
      SFTP_GROUP          = var.sftp_server_config.sftp_group
      SFTP_ROOT           = var.sftp_server_config.sftp_root
      SFTP_DIRECTORIES    = join("\n", var.sftp_server_config.directories)
      SSH_PUBLIC_KEYS_B64 = base64encode(join("\n", local.ssh_public_keys))
    }
  }

  # On replacement (e.g. sftp_user rename), reconcile the previous user before
  # the new one is configured, revoking its account, keys, and sshd drop-in.
  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/scripts/cleanup-sftp-user.sh"
    interpreter = ["/bin/bash", "-c"]

    environment = {
      MACHINE_ID   = self.triggers.machine_id
      MODEL_NAME   = self.triggers.model_name
      MACHINE_NAME = self.triggers.machine_name
      SFTP_USER    = self.triggers.sftp_user

    }
  }
}
