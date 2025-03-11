data "aws_ami" "ubuntu-kubernetes" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "kubernetes_controller" {
  count                       = 3
  associate_public_ip_address = true
  ami                         = data.aws_ami.ubuntu-kubernetes.id  
  key_name                    = "kubernetes_ssh_key"
  vpc_security_group_ids      = [
    aws_security_group.kubernetes.id,
  ]
  instance_type               = "t3.micro"
  private_ip                  = "10.0.1.1${count.index}"
  user_data                   = "name=controller-$(count.index)"
  subnet_id                   = aws_subnet.kubernetes.id
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }

  tags          = {
    Name  = "controller-${count.index}"
  }
  source_dest_check           = false

  lifecycle {
    ignore_changes = [ami] # Prevent Terraform from forcing a rebuild due to AMI changes
  }
}

resource "aws_instance" "kubernetes_worker" {
  count                       = 3
  associate_public_ip_address = true
  ami                         = data.aws_ami.ubuntu-kubernetes.id  
  key_name                    = "kubernetes_ssh_key"
  vpc_security_group_ids      = [
    aws_security_group.kubernetes.id,
  ]
  instance_type               = "t3.micro"
  private_ip                  = "10.0.1.2${count.index}"
  user_data                   = "name=worker-$(count.index)|pod-cidr=10.200.$(count.index).0/24"
  subnet_id                   = aws_subnet.kubernetes.id
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }

  tags          = {
    Name  = "worker-${count.index}"
  }
  source_dest_check           = false

  lifecycle {
    ignore_changes = [ami] # Prevent Terraform from forcing a rebuild due to AMI changes
  }
}
