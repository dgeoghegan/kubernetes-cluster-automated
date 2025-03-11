# based on https://medium.com/@mariammbello/terraform-in-action-building-an-ec2-instance-with-docker-installed-part-2-2-f08f5cc46729

variable "docker_instance_type" {
  description = "The instance type to use for docker vm"
  type        = string
  default     = "t3.micro"
}

data "aws_ami" "ubuntu-docker" {
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

resource "local_file" "docker_ssh_key" {
  filename = local.docker_ssh_key_path
  content = tls_private_key.docker_ssh_key.private_key_openssh
  file_permission = "0400"
}

resource "aws_key_pair" "docker_ssh_key" {
  key_name    = "docker_ssh_key"
  public_key  = tls_private_key.docker_ssh_key.public_key_openssh
}

data "aws_region" "current" {}

data "aws_s3_objects" "s3_files" {
  bucket = var.s3_bucket_name
  prefix = "ansible/"
}

data "external" "presigned_s3_urls" {
  for_each = toset(data.aws_s3_objects.s3_files.keys)

  program = ["/bin/bash", "-c", <<EOT
#!/bin/bash
echo "{\"url\": \"$(aws s3 presign s3://${var.s3_bucket_name}/${each.key} --region ${data.aws_region.current.name} --expires-in 3600)\"}"
EOT
  ]
}

locals {
  presigned_s3_bucket_urls = [for file, data in data.external.presigned_s3_urls : data.result["url"]]
}

data "template_file" "docker_server_user_data" {
  template = file("${path.module}/docker_server_user_data.tpl")

  vars = {
    volume_id = replace(aws_ebs_volume.docker_images.id, "-", "") # Remove hyphen for volume symlink,
    volume_size = var.docker_images_volume_size
    presigned_urls = join("\n",local.presigned_s3_bucket_urls)
    bucket_name    = var.s3_bucket_name
  }
}

data "aws_ebs_volume" "docker_images" {
  filter {
    name    = "tag:Name"
    values  = ["docker_images"]
  }
}

data "aws_availability_zones" "available" {}

resource "aws_instance" "docker_server" {
  depends_on = [
    aws_key_pair.docker_ssh_key,
    aws_ebs_volume.docker_images
  ]
  ami                     = data.aws_ami.ubuntu-docker.id
  instance_type           = var.docker_instance_type
  key_name                = "docker_ssh_key"
  vpc_security_group_ids  = [aws_security_group.docker_security_group.id]
  user_data               = data.template_file.docker_server_user_data.rendered
  availability_zone       = aws_ebs_volume.docker_images.availability_zone

  iam_instance_profile    = aws_iam_instance_profile.kubernetes_s3_access_profile.name

  tags = {
    Name = "EC2-Docker-Instance"
  }

  lifecycle {
    ignore_changes = [ami] # Prevent Terraform from forcing a rebuild due to AMI changes
  }
}

resource "aws_security_group" "docker_security_group" {
  name  = "docker_security_group"
  description = "Allow SSH access to docker server"
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

### OUTPUT LOCATION FOR DOCKER FILES ####
variable "docker_file_path_override" {
  type = string
  default = ""
  description = "Full path for files created for docker. Defaults to $${path.module}/../docker/files_from_terraform"
}

locals {
  docker_file_path_default = "${path.module}/../docker/files_from_terraform"
  docker_file_path = length(var.docker_file_path_override) > 0 ? var.docker_file_path_override : local.docker_file_path_default
  docker_ssh_key_path = "${local.docker_file_path}/docker_ssh_key"
  docker_images_ebs_availability_zone = try(data.aws_ebs_volume.docker_images.availability_zone, data.aws_availability_zones.available.names[0])
}

output "docker_public_ip" {
  value = aws_instance.docker_server.public_ip
}

resource "aws_ebs_volume" "docker_images" {
  availability_zone = local.docker_images_ebs_availability_zone
  size              = var.docker_images_volume_size
  type              = "gp3"
  tags = {
    Name = "docker_images"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "docker_images" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.docker_images.id
  instance_id = aws_instance.docker_server.id
}
