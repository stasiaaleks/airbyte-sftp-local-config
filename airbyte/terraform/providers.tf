provider "kind" {}

# Configured from the cluster resource's own attributes rather than from the
# kubeconfig file: on a cold apply the file does not exist yet when the
# providers are initialised, which breaks a single-pass `terraform apply`.
# The file is still written (see kind_cluster.kubeconfig_path) for kubectl.
provider "kubernetes" {
  host                   = kind_cluster.airbyte.endpoint
  client_certificate     = kind_cluster.airbyte.client_certificate
  client_key             = kind_cluster.airbyte.client_key
  cluster_ca_certificate = kind_cluster.airbyte.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.airbyte.endpoint
    client_certificate     = kind_cluster.airbyte.client_certificate
    client_key             = kind_cluster.airbyte.client_key
    cluster_ca_certificate = kind_cluster.airbyte.cluster_ca_certificate
  }
}
