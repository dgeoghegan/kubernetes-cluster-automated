resource "aws_security_group" "sg" {
  count       = var.cloud_type == "aws" ? 1 : 0
  name        = "${var.network_name}-cluster-${var.cluster_index}"
  description = "Kubernetes security group for cluster ${var.cluster_index}"
  vpc_id      = aws_vpc.vpc[0].id

  tags = {
    Name = "${var.network_name}-cluster-${var.cluster_index}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "all_from_cluster" {
  count             = var.cloud_type == "aws" ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = local.vpc_cidr
  ip_protocol       = -1 
}

resource "aws_vpc_security_group_ingress_rule" "all_from_service" {
  count             = var.cloud_type == "aws" ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = local.service_cidr
  ip_protocol       = -1 
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_anywhere" {
  count             = var.cloud_type == "aws" ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https_from_anywhere" {
  count             = var.cloud_type == "aws" ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "k8s_api_from_anywhere" {
  count             = var.cloud_type == "aws" ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "icmp_from_anywhere" {
  count             = var.cloud_type == "aws" ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_vpc_security_group_egress_rule" "all_to_anywhere" {
  count             = var.cloud_type == "aws" ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1
  to_port           = -1
  ip_protocol       = -1
}
