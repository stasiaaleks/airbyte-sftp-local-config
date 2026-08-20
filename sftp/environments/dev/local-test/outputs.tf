output "sftp_host" {
  description = "Public address of the SFTP machine."
  value       = data.external.unit_address.result.address
}

output "sftp_user" {
  description = "Unix user to authenticate as."
  value       = module.sftp.sftp_user
}

output "sftp_chroot_path" {
  description = "The chroot directory the user is locked into (host-side path)."
  value       = module.sftp.chroot_path
}

output "sftp_landing_path" {
  description = "Default landing directory the client sees (relative to chroot)."
  value       = "/${var.directories[0]}"
}

output "private_key_path" {
  description = "Path to the generated RSA private key used for authentication."
  value       = local_sensitive_file.private_key.filename
}

output "sftp_command" {
  description = "Ready-to-run command for connecting to the SFTP server."
  value       = "sftp -i ${local.private_key_path} ${var.sftp_user}@${data.external.unit_address.result.address}"
}
