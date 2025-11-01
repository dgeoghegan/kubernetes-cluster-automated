#!/bin/bash

# Enable debugging mode to log each command
set -x

# Logging helper function for easier debugging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Started user-data script."

# Ensure /ansible is created
log "Creating /ansible directory."
mkdir -p /ansible
chown -R ubuntu:ubuntu /ansible
chmod 755 /ansible
log "Directory /ansible created and permissions set."

# Ensure /var/lib/docker exists (no separate volume)
log "Creating /var/lib/docker directory."
mkdir -p /var/lib/docker
chown -R root:root /var/lib/docker
chmod 755 /var/lib/docker
log "Directory /var/lib/docker created."

# Update system packages
log "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y
log "System packages updated."

# Install required dependencies
log "Installing required dependencies..."
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release unzip
log "Dependencies installed."

# Install AWS CLI
log "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
log "AWS CLI installed."
aws --version || log "⚠️ Failed to verify AWS CLI installation"

# Add Docker’s official GPG key
log "Adding Docker GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
log "Docker GPG key added."

# Add the Docker APT repository
log "Adding Docker APT repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
log "Docker APT repository added."

# Update and install Docker
log "Installing Docker..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
log "Docker installed."

# Enable and start Docker service
log "Enabling and starting Docker service..."
sudo systemctl enable --now docker
log "Docker service started."

# Add 'ubuntu' user to the Docker group
log "Adding user 'ubuntu' to the Docker group..."
sudo usermod -aG docker ubuntu
log "'ubuntu' user added to the Docker group."

# Install Buildx manually if needed
log "Checking for Buildx installation..."
if docker buildx version >/dev/null 2>&1; then
    log "✅ Buildx is already installed."
else
    log "⚠️ Buildx not found. Installing manually..."

    sudo mkdir -p /usr/lib/docker/cli-plugins

    # Determine system architecture
    ARCH=$(uname -m)
    log "System architecture: $ARCH"
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH="amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        ARCH="arm64"
    else
        log "❌ Unsupported architecture: $ARCH"
        exit 1
    fi

    # Fetch latest Buildx version
    BUILDX_VERSION=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    log "Latest Buildx version: $BUILDX_VERSION"

    if [[ -z "$BUILDX_VERSION" ]]; then
        log "❌ Error: Could not retrieve Buildx version from GitHub."
        exit 1
    fi

    # Download Buildx binary
    BUILDX_URL="https://github.com/docker/buildx/releases/download/$BUILDX_VERSION/buildx-linux-$ARCH"
    sudo curl -fsSL "$BUILDX_URL" -o /usr/lib/docker/cli-plugins/docker-buildx

    # Set permissions
    sudo chmod +x /usr/lib/docker/cli-plugins/docker-buildx
    log "✅ Buildx installed successfully."
fi

# Restart Docker service
log "Restarting Docker service..."
sudo systemctl restart docker

# Ensure user data script runs on every boot
log "Setting up user-data script to run on reboot..."
echo "@reboot root bash /var/lib/cloud/instance/scripts/part-001" | sudo tee -a /etc/crontab > /dev/null

log "User data script completed."

# Exit with success
exit 0
