resource "aws_vpc" "vpc" {
  count                 = var.cloud_type == "aws" ? 1 : 0
  cidr_block            = var.network_cidr
  instance_tenancy      = "default"
  enable_dns_hostnames  = true
  enable_dns_support    = true

  tags = {
    Name = var.network_name
  }
}

data "aws_availability_zones" "available" {
}

locals {
  az_names  = var.cloud_type == "aws" && length(data.aws_availability_zones.available.names) > 0 ? data.aws_availability_zones.available.names : []
  max_zones = min(length(local.az_names), max(var.controller_max, var.worker_max))
  azs       = length(local.az_names) > 0 ? slice(local.az_names, 0, local.max_zones) : []

  # Calculate the number of bits needed to split the VPC CIDR into smaller subnets
  subnet_newbits = ceil(log(local.max_zones, 2)) # Determines subnet size dynamically

  # Generate a subnet CIDR for each zone
  subnets = [
    for i in range(local.max_zones) :
    cidrsubnet(var.network_cidr, local.subnet_newbits, i)
  ]
}


resource "aws_subnet" "subnet" {
  count             = var.cloud_type == "aws" ? local.max_zones : 0
  vpc_id            = aws_vpc.vpc[0].id
  availability_zone = local.azs[count.index]
  cidr_block        = local.subnets[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-${count.index}"
  }

  lifecycle {
    precondition {
      condition     = local.max_zones > 0
      error_message = "Error: No valid availability zones found for the selected instance types!"
    }
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  count = var.cloud_type == "aws" ? 1 : 0
  vpc_id            = aws_vpc.vpc[0].id

  tags = {
    Name  = var.network_name
  }
}

resource "aws_route_table" "route_table" {
  count = var.cloud_type == "aws" ? 1 : 0
  vpc_id            = aws_vpc.vpc[0].id
  route {
    cidr_block  = "0.0.0.0/0"
    gateway_id  = aws_internet_gateway.internet_gateway[0].id
  }

  tags = {
    Name  = var.network_name
  }
}

resource "aws_route_table_association" "route_table_association" {
  count           = var.cloud_type == "aws" ? length(aws_subnet.subnet) : 0
  subnet_id       = aws_subnet.subnet[count.index].id
  route_table_id  = aws_route_table.route_table[0].id
}
