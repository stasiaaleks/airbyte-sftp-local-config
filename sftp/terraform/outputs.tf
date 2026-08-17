output "sftp_host" {
  description = "Public address of the unit serving SFTP."
  value       = data.external.unit_address.result.address
}

output "sftp_user" {
  description = "Unix user to authenticate as."
  value       = var.sftp_user
}

output "sftp_landing_path" {
  description = "Directory clients land in after connecting."
  value       = local.landing_path
}

output "private_key_path" {
  description = "Path to the generated private key used for authentication."
  value       = local_sensitive_file.private_key.filename
}

output "sftp_command" {
  description = "Ready-to-run command for connecting to the SFTP server."
  value       = "sftp -i ${local.private_key_path} ${var.sftp_user}@${data.external.unit_address.result.address}"
}
