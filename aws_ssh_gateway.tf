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

resource "aws_instance" "terraform_udemy_ssh_gateway" {
  ami             = data.aws_ami.ubuntu.id  
  instance_type   = "t3.micro"
  subnet_id       = aws_subnet.terraform_udemy_subnet_1.id
  key_name        = "terraform-udemy-denis"
  vpc_security_group_ids  = [
    aws_security_group.ssh_gateway.id,
  ]

  tags          = {
    Name  = "terraform_udemy_ssh_gateway"
    Role  = "terraform_udemy_ssh_gateway"
  }
}
