# based on https://medium.com/@mariammbello/terraform-in-action-building-an-ec2-instance-with-docker-installed-part-2-2-f08f5cc46729

data "aws_ami" "ubuntu-docker" {
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

resource "tls_private_key" "docker_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "docker_ssh_key" {
  count = var.cloud_type == "aws" ? 1 : 0
  key_name    = "docker_ssh_key-${var.cluster_index}"
  public_key  = tls_private_key.docker_ssh_key.public_key_openssh
}

resource "local_file" "docker_ssh_key" {
  filename              = "${path.root}/files_from_terraform/docker_ssh_key"
  content               = tls_private_key.docker_ssh_key.private_key_pem
  file_permission       = "0400"
  directory_permission  = "0700"
}

data "template_file" "docker_server_user_data" {
  count = var.cloud_type == "aws" ? 1 : 0
  template = file("${path.module}/user_data.tpl")

  vars = {
    bucket_name         = var.storage_name
  }
}

data "aws_availability_zones" "available" {
  count = var.cloud_type == "aws" ? 1 : 0
  }

resource "aws_instance" "docker_server" {
  count = var.cloud_type == "aws" ? 1 : 0
  depends_on = [
  ]
  ami                     = data.aws_ami.ubuntu-docker[0].id
  instance_type           = var.docker_instance_type
  key_name                = aws_key_pair.docker_ssh_key[0].key_name
  vpc_security_group_ids  = [aws_security_group.docker_security_group[0].id]
  user_data               = data.template_file.docker_server_user_data[0].rendered
  subnet_id               = var.subnet[0].id

  iam_instance_profile    = var.profile_id

  tags = {
    Name = "EC2-Docker-Instance-cluster-${var.cluster_index}"
  }

  lifecycle {
    ignore_changes = [ami] # Prevent Terraform from forcing a rebuild due to AMI changes
  }
}

resource "aws_security_group" "docker_security_group" {
  count = var.cloud_type == "aws" ? 1 : 0
  name  = "docker_security_group-cluster-${var.cluster_index}"
  description = "Allow SSH access to docker server"
  vpc_id      = var.vpc_id 
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Docker-Security-Group"
  }
}

### SYNC CONFIGS FROM STORAGE
resource "null_resource" "sync_ansible_files_s3" {
  count = var.cloud_type == "aws" ? 1 : 0
  triggers = {
    hash    = nonsensitive(var.k8s_files_hash)
    server  = aws_instance.docker_server[0].id
  }

  connection {
    host        = aws_instance.docker_server[0].public_ip
    user        = "ubuntu"
    private_key = tls_private_key.docker_ssh_key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [<<-BASH
bash -lc 'set -euxo pipefail
command -v cloud-init >/dev/null 2>&1 && sudo cloud-init status --wait || true
until command -v aws >/dev/null 2>&1; do sleep 2; done
sudo mkdir -p /ansible
sudo aws s3 sync s3://${var.storage_name}/ /ansible/
if [ -f /ansible/common/kubernetes_ssh_key ]; then sudo chmod 600 /ansible/common/kubernetes_ssh_key; fi'
BASH
    ]
  }
}


### OUTPUT LOCATION FOR DOCKER FILES ####
#variable "docker_file_path_override" {
#  type = string
#  default = ""
#  description = "Full path for files created for docker. Defaults to $${path.module}/../docker/files_from_terraform"
#}

#locals {
#  docker_file_path_default = "${path.module}/../docker/files_from_terraform"
#  docker_file_path = length(var.docker_file_path_override) > 0 ? var.docker_file_path_override : local.docker_file_path_default
#  docker_ssh_key_path = "${local.docker_file_path}/docker_ssh_key"
#}

#output "docker_public_ip" {
#  value = aws_instance.docker_server.public_ip
#}

#locals {
#  dockerfiles = {
#    for file in fileset("../../../docker", "*.dockerfile") :
#    trimsuffix(file, ".dockerfile") => file("../docker/${file}")
#  }
#}
