locals {
  kubernetes_worker_private_dns = var.cloud_type == "aws" ? [for instance in aws_instance.kubernetes_worker : instance.private_dns] : []
  kubernetes_worker_private_ip  = var.cloud_type == "aws" ? [for instance in aws_instance.kubernetes_worker : instance.private_ip] : []
  kubernetes_worker_public_ip   = var.cloud_type == "aws" ? [for instance in aws_instance.kubernetes_worker : instance.public_ip] : []

  kubernetes_worker_network_info = var.cloud_type == "aws" ? [ 
    for idx in range(length(aws_instance.kubernetes_worker)) : {
      private_dns = aws_instance.kubernetes_worker[idx].private_dns
      private_ip  = aws_instance.kubernetes_worker[idx].private_ip
      public_ip   = aws_instance.kubernetes_worker[idx].public_ip
      name        = aws_instance.kubernetes_worker[idx].tags["Name"]
      worker_pod_cidr = cidrsubnet(var.pod_cidr, 6, idx)
    }
  ] : []

  kubernetes_worker_host_entries = var.cloud_type == "aws" ? [
    for worker in local.kubernetes_worker_network_info : "${worker.private_ip} ${split(".", worker.private_dns)[0]}"
  ] : []

  kubernetes_controller_network_info = var.cloud_type == "aws"? [
    for idx in range(length(aws_instance.kubernetes_controller)) : {
      private_dns = aws_instance.kubernetes_controller[idx].private_dns
      private_ip  = aws_instance.kubernetes_controller[idx].private_ip
      public_ip   = aws_instance.kubernetes_controller[idx].public_ip
      name        = aws_instance.kubernetes_controller[idx].tags["Name"]
    }
  ] : []

  etcd_servers = var.cloud_type == "aws"? join(",", [ 
    for instance in aws_instance.kubernetes_controller : 
    "https://${instance.private_ip}:2379"
    ]) : ""

  kubernetes_initial_cluster = join(",", [
    for idx, controller in local.kubernetes_controller_network_info : 
      "${controller.name}=https://${controller.private_ip}:2380"
  ])

### OUTPUT LOCATION FOR ANSIBLE FILES (CERTS, HOSTS, ETC.) ####
#  ansible_file_path_default = "${path.module}/../ansible/files_from_terraform"
#  ansible_file_path = length(var.ansible_file_path_override) > 0 ? var.ansible_file_path_override : local.ansible_file_path_default

}
