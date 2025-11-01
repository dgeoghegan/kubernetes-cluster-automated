output "load_balancer_dns_name" {
  description = "DNS name of load balancer"
  value       = var.cloud_type == "aws" ? aws_lb.lb[0].dns_name : null
}

output "load_balancer_listener_port" {
  description = "Port number of load balancer listener"
  value       = var.cloud_type == "aws" ? aws_lb_listener.lb_listener[0].port: null
}

output "vpc_cidr" {
  description = "CIDR of this cluster's VPC"
  value       = local.vpc_cidr
}

output "security_group_id" {
  description = "List of all subnet ids"
  value       = aws_security_group.sg[*].id
}

output "subnet" {
  value = [
    for s in aws_subnet.subnet : {
      id         = s.id
      cidr_block = s.cidr_block
      az         = s.availability_zone
    }
  ]
}

output "vpc_id" {
  value = aws_vpc.vpc[0].id
}
