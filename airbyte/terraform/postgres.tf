locals {
  dest_postgres_labels = {
    "app.kubernetes.io/name"       = "dest-postgres"
    "app.kubernetes.io/instance"   = var.release_name
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/component"  = "sync-destination"
  }

  # In-cluster DNS name Airbyte workers use. Never point connectors at localhost.
  dest_postgres_host = "${var.dest_postgres_service_name}.${var.namespace}.svc.cluster.local"
}

resource "kubernetes_secret" "dest_postgres" {
  metadata {
    name      = var.dest_postgres_service_name
    namespace = kubernetes_namespace.airbyte.metadata[0].name
    labels    = local.dest_postgres_labels
  }

  data = {
    POSTGRES_DB       = var.dest_postgres_database
    POSTGRES_USER     = var.dest_postgres_username
    POSTGRES_PASSWORD = var.dest_postgres_password
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "dest_postgres" {
  metadata {
    name      = var.dest_postgres_service_name
    namespace = kubernetes_namespace.airbyte.metadata[0].name
    labels    = local.dest_postgres_labels
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = var.dest_postgres_storage
      }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment" "dest_postgres" {
  metadata {
    name      = var.dest_postgres_service_name
    namespace = kubernetes_namespace.airbyte.metadata[0].name
    labels    = local.dest_postgres_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = local.dest_postgres_labels["app.kubernetes.io/name"]
        "app.kubernetes.io/instance" = local.dest_postgres_labels["app.kubernetes.io/instance"]
      }
    }

    template {
      metadata {
        labels = local.dest_postgres_labels
      }

      spec {
        container {
          name  = "postgres"
          image = var.dest_postgres_image

          port {
            name           = "postgres"
            container_port = 5432
            protocol       = "TCP"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.dest_postgres.metadata[0].name
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }

          resources {
            requests = {
              cpu    = var.dest_postgres_cpu_request
              memory = var.dest_postgres_memory_request
            }
            limits = {
              cpu    = var.dest_postgres_cpu_limit
              memory = var.dest_postgres_memory_limit
            }
          }

          readiness_probe {
            exec {
              command = [
                "pg_isready",
                "-U", var.dest_postgres_username,
                "-d", var.dest_postgres_database,
              ]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          liveness_probe {
            exec {
              command = [
                "pg_isready",
                "-U", var.dest_postgres_username,
                "-d", var.dest_postgres_database,
              ]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.dest_postgres.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [helm_release.airbyte]
}

resource "kubernetes_service" "dest_postgres" {
  metadata {
    name      = var.dest_postgres_service_name
    namespace = kubernetes_namespace.airbyte.metadata[0].name
    labels    = local.dest_postgres_labels
  }

  spec {
    type = "ClusterIP"
    selector = {
      "app.kubernetes.io/name"     = local.dest_postgres_labels["app.kubernetes.io/name"]
      "app.kubernetes.io/instance" = local.dest_postgres_labels["app.kubernetes.io/instance"]
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = "postgres"
      protocol    = "TCP"
    }
  }
}
