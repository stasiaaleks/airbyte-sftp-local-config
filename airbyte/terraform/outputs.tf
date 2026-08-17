output "airbyte_url" {
  description = "Airbyte UI."
  value       = local.airbyte_url
}

output "airbyte_api_url" {
  description = "Public API base URL. Matches the server_url in connectors/environments/dev."
  value       = local.api_url
}

output "kubeconfig_path" {
  description = "Kubeconfig for the kind cluster. Export it as KUBECONFIG to use kubectl against this cluster only."
  value       = local.kubeconfig_path
}

output "kube_context" {
  description = "Kubeconfig context name for the cluster."
  value       = local.kube_context
}

output "kind_cluster_name" {
  description = "Name of the kind cluster."
  value       = kind_cluster.airbyte.name
}

output "health_check_command" {
  description = "Ready-to-run health check."
  value       = "curl -sf ${local.api_url}/health"
}

output "kubectl_command" {
  description = "Ready-to-run pod listing."
  value       = "kubectl --kubeconfig ${local.kubeconfig_path} -n ${var.namespace} get pods"
}

output "dest_postgres_host" {
  description = "In-cluster DNS name for the sync destination Postgres. Use this as the Airbyte destination host (not localhost)."
  value       = local.dest_postgres_host
}

output "dest_postgres_port" {
  description = "Port of the sync destination Postgres service."
  value       = 5432
}

output "dest_postgres_database" {
  description = "Database name on the sync destination Postgres."
  value       = var.dest_postgres_database
}

output "dest_postgres_username" {
  description = "Username for the sync destination Postgres."
  value       = var.dest_postgres_username
}

output "dest_postgres_password" {
  description = "Password for the sync destination Postgres."
  value       = var.dest_postgres_password
  sensitive   = true
}

output "dest_postgres_service_name" {
  description = "Kubernetes service name of the sync destination Postgres."
  value       = kubernetes_service.dest_postgres.metadata[0].name
}

output "dest_postgres_psql_command" {
  description = "Ready-to-run psql via kubectl exec against the destination Postgres."
  value       = "kubectl --kubeconfig ${local.kubeconfig_path} -n ${var.namespace} exec -it deploy/${var.dest_postgres_service_name} -- psql -U ${var.dest_postgres_username} -d ${var.dest_postgres_database}"
}

output "export_dest_postgres_env_command" {
  description = "Prints TF_VAR exports for connectors/environments/dev."
  value       = <<-EOT
    export TF_VAR_DEST_PG_HOST='${local.dest_postgres_host}'
    export TF_VAR_DEST_PG_PORT='5432'
    export TF_VAR_DEST_PG_DATABASE='${var.dest_postgres_database}'
    export TF_VAR_DEST_PG_USERNAME='${var.dest_postgres_username}'
    export TF_VAR_DEST_PG_PASSWORD='${var.dest_postgres_password}'
  EOT
  sensitive   = true
}
