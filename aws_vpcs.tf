resource "aws_vpc" "terraform_udemy" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "terraform_udemy"
  }
}

resource "aws_subnet" "terraform_udemy_subnet_1" {
  vpc_id            = aws_vpc.terraform_udemy.id
  availability_zone = "us-east-1f"
  cidr_block        = cidrsubnet(aws_vpc.terraform_udemy.cidr_block, 4, 1)
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "terraform_udemy_gateway" {
  vpc_id            = aws_vpc.terraform_udemy.id

  tags = {
    Name  = "terraform_udemy_gateway"
  }
}

resource "aws_route_table" "route-table-terraform-udemy" {
  vpc_id            = aws_vpc.terraform_udemy.id
  route {
    cidr_block  = "0.0.0.0/0"
    gateway_id  = aws_internet_gateway.terraform_udemy_gateway.id
  }

  tags = {
    Name  = "route-table-terraform-udemy"
  }
}

resource "aws_route_table_association" "subnet-association-terraform-udemy-ssh-gateway" {
  subnet_id       = aws_subnet.terraform_udemy_subnet_1.id
  route_table_id  = aws_route_table.route-table-terraform-udemy.id
}

/*
data "aws_instances" "terraform_udemy_ssh_gateway" {
  instance_tags = {
     Role  = "terraform_udemy_ssh_gateway"
  }
}
*/

output "terraform_udemy_ssh_gateways" {
  value = aws_instance.terraform_udemy_ssh_gateway.public_ip
}
