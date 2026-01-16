locals {
  docker_server_public_ip = data.terraform_remote_state.infrastructure.outputs.docker_server_public_ip
  service_cidr            = data.terraform_remote_state.infrastructure.outputs.service_cidr
  registry_address        = "127.0.0.1:5000"
  playbooks_dir_abs       = abspath(var.playbooks_dir)
  static_configs_dir_abs  = abspath(var.static_configs_dir)
  manifests_dir_abs       = abspath(var.manifests_dir)
  charts_dir_abs          = abspath(var.charts_dir)
  docker_ssh_key_path_abs = abspath(var.docker_ssh_key_path)
  load_balancer_dns_name  = data.terraform_remote_state.infrastructure.outputs.load_balancer_dns_name
}

data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config  = {
    path  = "${path.root}/../../infra/root/terraform.tfstate"
  }
}

resource "random_password" "registry_pass" {
  length      = 24
  special     = true
}

provider "docker" {
  host  = "ssh://ubuntu@${local.docker_server_public_ip}"
  ssh_opts = [
  "-i", "${local.docker_ssh_key_path_abs}",
  "-o", "StrictHostKeyChecking=no",
  "-o", "UserKnownHostsFile=/dev/null"
  ]

  registry_auth {
    address             = local.registry_address
    username            = "admin"
    password            = random_password.registry_pass.result
  }
}

module "registry" {
  source                  = "../../../../terraform/modules/registry/"
  registry_pass           = random_password.registry_pass.result
  docker_server_public_ip = local.docker_server_public_ip

  providers = {
    docker = docker
  }
}

module "ansible_runner" {
  source                  = "../../../../terraform/modules/ansible_runner/"
  ansible_dockerfile_path = var.ansible_dockerfile_path
  registry_address        = local.registry_address
  registry_pass           = random_password.registry_pass.result
  docker_server_public_ip = local.docker_server_public_ip
  depends_on              = [module.registry.registry_ready]
  playbooks_dir           = local.playbooks_dir_abs
  static_configs_dir      = local.static_configs_dir_abs
  kubernetes_version      = var.kubernetes_version
  docker_ssh_key_path     = local.docker_ssh_key_path_abs
}

module "kubectl_runner" {
  source                  = "../../../../terraform/modules/kubectl_runner/"
  kubectl_dockerfile_path = var.kubectl_dockerfile_path
  registry_address        = local.registry_address
  registry_pass           = random_password.registry_pass.result
  docker_server_public_ip = local.docker_server_public_ip
  depends_on              = [ module.registry.registry_ready,
                              module.ansible_runner.playbooks_applied ]
  manifests_dir           = local.manifests_dir_abs
  kubernetes_version      = var.kubernetes_version
  service_cidr            = local.service_cidr
  docker_ssh_key_path     = local.docker_ssh_key_path_abs
  load_balancer_dns_name  = local.load_balancer_dns_name
}
