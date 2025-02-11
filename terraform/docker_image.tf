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

variable "docker_ec2_user_data" {
  description = "User data for installing Docker and Buildx on new container"
  type        = string
  default     = <<-EOF
#!/bin/bash

# Ensure /ansible is created
mkdir -p /ansible
chown -R ubuntu:ubuntu /ansible
chmod 755 /ansible

# Update system packages
sudo apt-get update -y
sudo apt-get upgrade -y

# Install required dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add the Docker APT repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update and install Docker
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

# Enable and start Docker service
sudo systemctl enable --now docker

# Add 'ubuntu' user to the Docker group
sudo usermod -aG docker ubuntu

# Install Buildx manually if needed
if ! docker buildx version >/dev/null 2>&1; then
  echo "⚠️ Buildx not found. Installing manually..."

  # Create directory for Buildx
  sudo mkdir -p /usr/lib/docker/cli-plugins

  # Determine system architecture
  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="amd64"
  elif [[ "$ARCH" == "aarch64" ]]; then
    ARCH="arm64"
  else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
  fi

  # Fetch latest Buildx version
  BUILDX_VERSION=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
  
  if [[ -z "$BUILDX_VERSION" ]]; then
    echo "❌ Error: Could not retrieve Buildx version from GitHub."
    exit 1
  fi

  # Download Buildx binary
  BUILDX_URL="https://github.com/docker/buildx/releases/download/$BUILDX_VERSION/buildx-linux-$ARCH"
  sudo curl -fsSL "$BUILDX_URL" -o /usr/lib/docker/cli-plugins/docker-buildx

  # Set permissions
  sudo chmod +x /usr/lib/docker/cli-plugins/docker-buildx
  echo "✅ Buildx installed successfully."
else
  echo "✅ Buildx is already installed."
fi

# Ensure user data script runs on every boot (optional)
echo "@reboot root bash /var/lib/cloud/instance/scripts/part-001" | sudo tee -a /etc/crontab > /dev/null

EOF
}

resource "aws_instance" "docker_server" {
  depends_on = [
    aws_key_pair.docker_ssh_key
  ]
  ami                     = data.aws_ami.ubuntu-docker.id
  instance_type           = var.docker_instance_type
  key_name                = "docker_ssh_key"
  vpc_security_group_ids  = [aws_security_group.docker_security_group.id]
  user_data               = var.docker_ec2_user_data
  tags = {
    Name = "EC2-Docker-Instance"
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
}

output "docker_public_ip" {
  value = aws_instance.docker_server.public_ip
}

resource "null_resource" "copy_ansible_files_to_docker" {
  depends_on = [ aws_instance.docker_server ]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]  # Forces Terraform to use Bash (fixes unexpected token errors)
    command = <<EOT
    for i in $(seq 1 10); do
      echo "🔍 Checking SSH connectivity to docker_server (Attempt $i)..."
      if ssh -o "StrictHostKeyChecking=no" -i "${local.docker_ssh_key_path}" ubuntu@${aws_instance.docker_server.public_ip} "echo 'SSH Ready'"; then
        exit 0
      fi
      sleep 10
    done
    echo "❌ SSH is still not available after 10 attempts. Exiting."
    exit 1
    EOT
  }

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = tls_private_key.docker_ssh_key.private_key_openssh
    host = aws_instance.docker_server.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo '🔧 Setting correct permissions on /ansible'",
      "sudo mkdir -p /ansible",
      "sudo chown -R ubuntu:ubuntu /ansible",
      "sudo chmod -R 755 /ansible",
      "ls -ld /ansible"  # Debugging step to confirm permissions
    ]
  }

  provisioner "file" {
    source = "${local.ansible_file_path}/../"
    destination = "/ansible/"
  }
}
