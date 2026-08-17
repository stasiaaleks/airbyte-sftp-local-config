output "workspace_id" {
  description = "Airbyte workspace used by the dev connection."
  value       = local.workspace_id
}

output "source_id" {
  description = "SFTP bulk source ID."
  value       = module.sftp_bulk_connection.source_id
}

output "destination_id" {
  description = "Local Postgres destination ID."
  value       = module.sftp_bulk_connection.destination_id
}

output "connection_id" {
  description = "Connection ID for Local SFTP bulk → Postgres."
  value       = module.sftp_bulk_connection.connection_id
}

output "trigger_sync_command" {
  description = "Kick off a manual sync via the public API."
  value       = "curl -s -X POST http://localhost:8000/api/public/v1/jobs -H 'Content-Type: application/json' -d '{\"connectionId\":\"${module.sftp_bulk_connection.connection_id}\",\"jobType\":\"sync\"}'"
}
