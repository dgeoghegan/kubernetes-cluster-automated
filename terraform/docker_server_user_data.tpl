#!/bin/bash

# Enable debugging mode to log each command
set -x

# Logging helper function for easier debugging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Use AWS NVMe device symlink
VOLUME_ID="${volume_id}"  # Replace with the Terraform-defined volume ID
DEVICE_PATH="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_$VOLUME_ID"
MOUNT_POINT="/var/lib/docker"

log "Started user-data script."

# Wait for the device to appear, extend retries and give more time
log "Waiting for $DEVICE_PATH to be available..."
RETRIES=60  # Try up to 60 times (60 seconds)
SLEEP_TIME=5  # Wait for 5 seconds between each attempt

for i in $(seq 1 $RETRIES); do
    if [ -e "$DEVICE_PATH" ]; then
        log "$DEVICE_PATH is available."
        break
    else
        log "Waiting for $DEVICE_PATH to appear... ($i/$RETRIES)"
        sleep $SLEEP_TIME
    fi
done

# If the device is not found after all retries, exit with error
if [ ! -e "$DEVICE_PATH" ]; then
    log "Error: $DEVICE_PATH not found after $RETRIES attempts."
    exit 1
fi

log "$DEVICE_PATH is available."

# Ensure /ansible is created
log "Creating /ansible directory."
mkdir -p /ansible
chown -R ubuntu:ubuntu /ansible
chmod 755 /ansible
log "Directory /ansible created and permissions set."

# Update system packages
log "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y
log "System packages updated."

# Install required dependencies
log "Installing required dependencies..."
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
log "Dependencies installed."

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

# Check if the device is mounted at the desired mount point
log "Checking if $DEVICE_PATH is mounted at $MOUNT_POINT..."

# Resolve the symlink to the actual device path
DEVICE_PATH_RESOLVED=$(readlink -f "$DEVICE_PATH")

# Check if the device is mounted
if mount | grep -q "$DEVICE_PATH_RESOLVED"; then
    log "✅ $DEVICE_PATH_RESOLVED is already mounted at $MOUNT_POINT."
else
    log "❌ $DEVICE_PATH_RESOLVED is not mounted at $MOUNT_POINT. Attempting to mount."

    # Mount the device if it's not already mounted
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "$DEVICE_PATH_RESOLVED" "$MOUNT_POINT"
    if [ $? -eq 0 ]; then
        log "✅ Successfully mounted $DEVICE_PATH_RESOLVED at $MOUNT_POINT."
    else
        log "❌ Failed to mount $DEVICE_PATH_RESOLVED at $MOUNT_POINT."
        exit 1
    fi
fi

log "Updating fstab for persistence..."
sudo sed -i '/\/var\/lib\/docker/d' /etc/fstab
echo "$DEVICE_PATH_RESOLVED $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null

log "Restarting Docker service..."
sudo systemctl start docker

log "Copying Ansible files from S3 bucket..."
ANSIBLE_DIR="/ansible"
sudo mkdir -p "$ANSIBLE_DIR"
sudo chown -R ubuntu:ubuntu "$ANSIBLE_DIR"
sudo chmod 755 "$ANSIBLE_DIR"

# Presigned URLs passed from Terraform
PRESIGNED_URLS=("${presigned_urls}")

# Download all files
log "Downloading Ansible files from S3..."
echo "$PRESIGNED_URLS" | while read -r URL; do
  FILE_NAME=$(basename "$URL" | cut -d '?' -f1)  # Extract filename
  log "Downloading $FILE_NAME..."
  curl -o "/ansible/$FILE_NAME" "$URL"
done
log "✅ All files downloaded successfully to $ANSIBLE_DIR."

# Ensure user data script runs on every boot
log "Setting up user-data script to run on reboot..."
echo "@reboot root bash /var/lib/cloud/instance/scripts/part-001" | sudo tee -a /etc/crontab > /dev/null

log "User data script completed."

# Exit with success
exit 0
