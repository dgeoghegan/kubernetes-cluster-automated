output "ssh_gateway" {
  value = aws_instance.ssh_gateway.public_ip
}

output "kubernetes_worker_network_info" {
  value = local.kubernetes_worker_network_info
}

output "kubernetes_public_dns" {
  value = aws_lb.kubernetes.dns_name
}

