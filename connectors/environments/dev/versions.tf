terraform {
  required_providers {
    airbyte = {
      source  = "airbytehq/airbyte"
      version = "0.12.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "airbyte" {
  server_url = "http://localhost:8000/api/public/v1"
}
