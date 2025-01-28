terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.84.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "4.0.6"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}
