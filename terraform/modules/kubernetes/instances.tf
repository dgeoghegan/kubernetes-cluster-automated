data "aws_ami" "ubuntu-kubernetes" {
  count = var.cloud_type == "aws" ? 1 : 0
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
  count                       = var.cloud_type == "aws" ? var.controller_max : 0
  associate_public_ip_address = true
  ami                         = data.aws_ami.ubuntu-kubernetes[0].id  
  key_name                    = aws_key_pair.kubernetes_ssh_key.key_name
  vpc_security_group_ids      = [
    var.security_group_id[0],
  ]
  instance_type               = var.instance_type
  private_ip                  = cidrhost(var.subnet[count.index % length(var.subnet)].cidr_block, 100 + count.index)
  user_data                   = "name=cluster-$(var.cluster_index)-controller-$(count.index)"
  subnet_id                   = var.subnet[count.index % length(var.subnet)].id
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }

  tags          = {
    Name  = "cluster-${var.cluster_index}-controller-${count.index}"
  }
  source_dest_check           = false

  lifecycle {
    ignore_changes = [ami] # Prevent Terraform from forcing a rebuild due to AMI changes
  }
}

resource "aws_instance" "kubernetes_worker" {
  count                       = var.cloud_type == "aws" ? var.worker_max : 0
  associate_public_ip_address = true
  ami                         = data.aws_ami.ubuntu-kubernetes[0].id  
  key_name                    = aws_key_pair.kubernetes_ssh_key.key_name
  vpc_security_group_ids      = [
    var.security_group_id[0],
  ]
  instance_type               = var.instance_type
  private_ip                  = cidrhost(var.subnet[count.index % length(var.subnet)].cidr_block, 200 + count.index)
  user_data                   = "name=cluster-${var.cluster_index}-worker-${count.index}|pod-cidr=${cidrsubnet(var.pod_cidr_cluster, 6, count.index)}"
  subnet_id                   = var.subnet[count.index % length(var.subnet)].id
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }

  tags          = {
    Name  = "cluster-${var.cluster_index}-worker-${count.index}"
  }
  source_dest_check           = false

  lifecycle {
    ignore_changes = [ami] # Prevent Terraform from forcing a rebuild due to AMI changes
  }
}
