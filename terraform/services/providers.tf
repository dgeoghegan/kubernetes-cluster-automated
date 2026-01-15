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
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
    null = {
      source = "hashicorp/null"
      version = "3.2.3"
    }
    random = {
      source = "hashicorp/random"
      version = "3.6.3"
    }
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
  }
}

provider "aws" {
  shared_credentials_file = var.aws_credentials_file
}
