variable "cluster_name" {
  description = "Name of the kind cluster that hosts Airbyte."
  type        = string
  default     = "airbyte-local"
}

variable "kubernetes_version" {
  description = "kind node image tag (Kubernetes version) used for the cluster."
  type        = string
  default     = "v1.31.2"
}

variable "namespace" {
  description = "Kubernetes namespace Airbyte is installed into."
  type        = string
  default     = "airbyte"
}

variable "release_name" {
  description = "Helm release name for Airbyte."
  type        = string
  default     = "airbyte"
}

variable "chart_version" {
  description = "Version of the airbyte/airbyte Helm chart."
  type        = string
  default     = "1.8.5"
}

variable "host_port" {
  description = <<-EOT
    Host port Airbyte is published on. The connectors/environments/dev root
    dev environment expects http://localhost:8000, so only change this if
    something else already listens on 8000.
  EOT
  type        = number
  default     = 8000
}

variable "node_port" {
  description = "NodePort inside the kind cluster that host_port is mapped to."
  type        = number
  default     = 30080

  validation {
    condition     = var.node_port >= 30000 && var.node_port <= 32767
    error_message = "node_port must be within the Kubernetes NodePort range 30000-32767."
  }
}

variable "listen_address" {
  description = "Host address the mapped port is bound to. Keep this on loopback: the instance runs without authentication."
  type        = string
  default     = "127.0.0.1"
}

variable "helm_timeout" {
  description = "Seconds to wait for the Helm release. The first apply pulls several GB of images."
  type        = number
  default     = 1800
}

variable "minio_memory_request" {
  description = "Memory request for the bundled MinIO pod. Trimmed from the chart default of 1Gi so the stack fits a laptop."
  type        = string
  default     = "256Mi"
}

variable "minio_cpu_request" {
  description = "CPU request for the bundled MinIO pod."
  type        = string
  default     = "100m"
}

variable "dest_postgres_service_name" {
  description = "Kubernetes service/deployment name for the sync destination Postgres."
  type        = string
  default     = "airbyte-dest-postgres"
}

variable "dest_postgres_image" {
  description = "Container image for the sync destination Postgres."
  type        = string
  default     = "postgres:16-alpine"
}

variable "dest_postgres_database" {
  description = "Database name created in the sync destination Postgres."
  type        = string
  default     = "airbyte_dest"
}

variable "dest_postgres_username" {
  description = "Username for the sync destination Postgres."
  type        = string
  default     = "airbyte"
}

variable "dest_postgres_password" {
  description = "Password for the sync destination Postgres. Local-dev only; treat state as secret."
  type        = string
  default     = "airbyte-local-dest"
  sensitive   = true
}

variable "dest_postgres_storage" {
  description = "Persistent volume size for the sync destination Postgres."
  type        = string
  default     = "1Gi"
}

variable "dest_postgres_memory_request" {
  description = "Memory request for the sync destination Postgres."
  type        = string
  default     = "256Mi"
}

variable "dest_postgres_cpu_request" {
  description = "CPU request for the sync destination Postgres."
  type        = string
  default     = "100m"
}

variable "dest_postgres_memory_limit" {
  description = "Memory limit for the sync destination Postgres."
  type        = string
  default     = "512Mi"
}

variable "dest_postgres_cpu_limit" {
  description = "CPU limit for the sync destination Postgres."
  type        = string
  default     = "500m"
}
