terraform {
  required_version = ">= 1.7.2"

  required_providers {
    juju = {
      version = ">= 0.18.0, < 1.0.0"
      source  = "juju/juju"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0, < 4.0.0"
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
