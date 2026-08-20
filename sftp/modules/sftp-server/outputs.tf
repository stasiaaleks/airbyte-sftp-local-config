output "machine_id" {
  description = "Juju machine ID"
  value       = juju_machine.sftp.machine_id
}

output "machine_name" {
  description = "Juju machine name"
  value       = juju_machine.sftp.name
}

output "sftp_user" {
  description = "SFTP account name"
  value       = var.sftp_server_config.sftp_user
}

output "chroot_path" {
  description = "SFTP account chroot path"
  value       = "${trimsuffix(var.sftp_server_config.sftp_root, "/")}/${var.sftp_server_config.sftp_user}"
}
