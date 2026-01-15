locals {
  service_cidr  = cidrsubnet("192.168.0.0/16", 6, var.cluster_index)
  storage_name  = "k8s-cluster-${var.cluster_index}-${substr(md5(var.network_name), 0, 6)}"
  default_credentials_file = "$(path.module)/aws_credentials.tf"
}

module "network" {
  source         = "../../../../terraform/modules/network/"
  cloud_type     = var.cloud_type
  network_name   = var.network_name
  cluster_index  = var.cluster_index
  service_cidr   = local.service_cidr
  pod_cidr       = var.pod_cidr
  controller_max = var.controller_max
  worker_max     = var.worker_max
  ha_enabled     = var.ha_enabled
}

module "storage" {
  source        = "../../../../terraform/modules/storage"
  backend_type  = var.backend_type
  storage_name  = local.storage_name
  files         = module.kubernetes.flattened_kubernetes_file_contents
  depends_on    = [module.kubernetes]
}

module "certificate_authority" {
  source       = "../../../../terraform/modules/certificate_authority"
  network_name = var.network_name
}

module "kubernetes" {
  source                 = "../../../../terraform/modules/kubernetes"
  cloud_type             = var.cloud_type
  controller_max         = var.controller_max
  worker_max             = var.worker_max
  ha_enabled             = var.ha_enabled
  instance_type          = var.instance_type
  load_balancer_dns_name = module.network.load_balancer_dns_name
  vpc_cidr               = module.network.vpc_cidr
  cluster_index          = var.cluster_index
  service_cidr           = local.service_cidr
  pod_cidr               = var.pod_cidr
  route_table_id         = module.network.route_table_id
  subnet                 = module.network.subnet
  security_group_id      = module.network.security_group_id
  private_key_pem        = module.certificate_authority.private_key_pem
  cert_pem               = module.certificate_authority.cert_pem
  load_balancer_listener_port = module.network.load_balancer_listener_port
}

# Link kubernetes controllers to LB
resource "aws_lb_target_group_attachment" "lb_target_group_attachment" {
  count            = length(module.kubernetes.controller_private_ips)
  target_group_arn = module.network.controller_target_group_arn
  target_id        = module.kubernetes.controller_private_ips[count.index]
  port             = 6443
}

module "security" {
  source                 = "../../../../terraform/modules/security"
  cloud_type             = var.cloud_type
  backend_type           = var.backend_type
  storage_name           = local.storage_name
  storage_id             = module.storage.storage_id
  depends_on             = [module.storage]
}

module "docker" {
  source                = "../../../../terraform/modules/docker"
  cloud_type            = var.cloud_type
  cluster_index         = var.cluster_index
  storage_name          = local.storage_name
  region                = null
  docker_instance_type  = var.instance_type
  vpc_cidr              = module.network.vpc_cidr
  subnet                = module.network.subnet
  security_group_id     = module.network.security_group_id
  profile_id            = module.security.profile_id
  depends_on            = [module.storage]
  vpc_id                = module.network.vpc_id
  k8s_files_hash        = module.kubernetes.k8s_files_hash
}
