data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "ssh_gateway" {
  ami             = data.aws_ami.ubuntu.id  
  instance_type   = "t3.micro"
  subnet_id       = aws_subnet.ssh_gateway.id
  key_name        = "ssh_gateway"
  vpc_security_group_ids  = [
    aws_security_group.ssh_gateway.id,
  ]

  tags          = {
    Name  = "ssh_gateway"
    Role  = "ssh_gateway"
  }
}
