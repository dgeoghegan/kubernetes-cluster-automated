resource "aws_vpc" "ssh_gateway" {
  cidr_block       = "10.1.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "terraform_udemy"
  }
}

resource "aws_subnet" "ssh_gateway" {
  vpc_id            = aws_vpc.ssh_gateway.id
  availability_zone = "us-east-1f"
  cidr_block        = cidrsubnet(aws_vpc.ssh_gateway.cidr_block, 4, 1)
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "ssh_gateway" {
  vpc_id            = aws_vpc.ssh_gateway.id

  tags = {
    Name  = "ssh_gateway"
  }
}

resource "aws_route_table" "ssh_gateway" {
  vpc_id            = aws_vpc.ssh_gateway.id
  route {
    cidr_block  = "0.0.0.0/0"
    gateway_id  = aws_internet_gateway.ssh_gateway.id
  }

  tags = {
    Name  = "ssh_gateway"
  }
}

resource "aws_route_table_association" "ssh_gateway" {
  subnet_id       = aws_subnet.ssh_gateway.id
  route_table_id  = aws_route_table.ssh_gateway.id
}
