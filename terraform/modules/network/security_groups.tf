resource "aws_security_group" "kubernetes" {
  name        = "kubernetes"
  description = "Kubernetes security group"
  vpc_id      = aws_vpc.kubernetes-the-hard-way.id

  tags = {
    Name = "kubernetes"
  }
}

resource "aws_vpc_security_group_ingress_rule" "kubernetes_all_0" {
  security_group_id = aws_security_group.kubernetes.id
  cidr_ipv4         = aws_vpc.kubernetes-the-hard-way.cidr_block
  ip_protocol       = -1 
}

resource "aws_vpc_security_group_ingress_rule" "kubernetes_all_200" {
  security_group_id = aws_security_group.kubernetes.id
  cidr_ipv4         = "10.200.0.0/16"
  ip_protocol       = -1 
}

resource "aws_vpc_security_group_ingress_rule" "kubernetes_22_all" {
  security_group_id = aws_security_group.kubernetes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kubernetes_443_all" {
  security_group_id = aws_security_group.kubernetes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kubernetes_6443_all" {
  security_group_id = aws_security_group.kubernetes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kubernetes_icmp_all" {
  security_group_id = aws_security_group.kubernetes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_vpc_security_group_egress_rule" "kubernetes_outbound_all" {
  security_group_id = aws_security_group.kubernetes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1
  to_port           = -1
  ip_protocol       = -1
}
