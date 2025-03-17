resource "aws_vpc" "kubernetes-the-hard-way" {
  cidr_block       = "${var.kubernetes_cidrblock_start}/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "kubernetes-the-hard-way"
  }
}

resource "aws_subnet" "kubernetes" {
  vpc_id            = aws_vpc.kubernetes-the-hard-way.id
  availability_zone = "us-east-1f"
  cidr_block        = cidrsubnet(aws_vpc.kubernetes-the-hard-way.cidr_block, 8, 1)
  map_public_ip_on_launch = true

  tags = {
    Name = "kubernetes"
  }
}

resource "aws_internet_gateway" "kubernetes" {
  vpc_id            = aws_vpc.kubernetes-the-hard-way.id

  tags = {
    Name  = "kubernetes"
  }
}

resource "aws_route_table" "kubernetes" {
  vpc_id            = aws_vpc.kubernetes-the-hard-way.id
  route {
    cidr_block  = "0.0.0.0/0"
    gateway_id  = aws_internet_gateway.kubernetes.id
  }

  tags = {
    Name  = "kubernetes"
  }
}

resource "aws_route_table_association" "kubernetes" {
  subnet_id       = aws_subnet.kubernetes.id
  route_table_id  = aws_route_table.kubernetes.id
}
