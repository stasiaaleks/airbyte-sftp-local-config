locals {
  kubeconfig_path = abspath("${path.module}/kubeconfig")
  kube_context    = "kind-${var.cluster_name}"
  airbyte_url     = "http://localhost:${var.host_port}"
  api_url         = "${local.airbyte_url}/api/public/v1"

  # The chart labels every component with app.kubernetes.io/name=<component>
  # and app.kubernetes.io/instance=<release>. airbyte-server serves both the
  # UI and the public API on port 8001; the webapp component is disabled by
  # default in this chart line.
  server_selector = {
    "app.kubernetes.io/name"     = "server"
    "app.kubernetes.io/instance" = var.release_name
  }
}

resource "kind_cluster" "airbyte" {
  name            = var.cluster_name
  node_image      = "kindest/node:${var.kubernetes_version}"
  kubeconfig_path = local.kubeconfig_path
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = var.node_port
        host_port      = var.host_port
        listen_address = var.listen_address
        protocol       = "TCP"
      }
    }
  }
}

resource "kubernetes_namespace" "airbyte" {
  metadata {
    name = var.namespace
  }

  depends_on = [kind_cluster.airbyte]
}

resource "helm_release" "airbyte" {
  name       = var.release_name
  namespace  = kubernetes_namespace.airbyte.metadata[0].name
  repository = "https://airbytehq.github.io/helm-charts"
  chart      = "airbyte"
  version    = var.chart_version

  timeout       = var.helm_timeout
  wait          = true
  wait_for_jobs = true
  atomic        = false

  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      minio_memory_request = var.minio_memory_request
      minio_cpu_request    = var.minio_cpu_request
    })
  ]
}

# Published separately rather than by flipping the chart's service type: the
# chart only exposes ClusterIP/port knobs, not nodePort, and an explicit
# resource keeps the host-port contract visible in one place.
resource "kubernetes_service" "airbyte_nodeport" {
  metadata {
    name      = "airbyte-server-nodeport"
    namespace = kubernetes_namespace.airbyte.metadata[0].name

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    type     = "NodePort"
    selector = local.server_selector

    port {
      name        = "http"
      port        = 80
      target_port = "http"
      node_port   = var.node_port
      protocol    = "TCP"
    }
  }

  depends_on = [helm_release.airbyte]
}
