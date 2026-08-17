terraform {
  required_version = ">= 1.5.0"

  required_providers {
    juju = {
      source  = "juju/juju"
      version = "~> 1.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
