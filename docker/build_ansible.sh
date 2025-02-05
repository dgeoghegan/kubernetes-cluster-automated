#!/bin/bash

# Set timestamp for log file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/ansible_build_$TIMESTAMP.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Extract public IP of remote AWS instance from Terraform state
DOCKER_SERVER_IP=$(terraform output -state="$(pwd)/../terraform/terraform.tfstate" -raw docker_public_ip)

# Ensure the IP is retrieved
if [[ -z "$DOCKER_SERVER_IP" ]]; then
    echo "❌ Error: Could not retrieve Docker server IP from Terraform."
    exit 1
fi

# Define SSH key and paths
SSH_KEY_PATH="$(pwd)/files_from_terraform/docker_ssh_key"
LOCAL_ANSIBLE_DIR="$(pwd)/../ansible"
REMOTE_ANSIBLE_DIR="/ansible"

# Ensure the SSH key exists
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "❌ Error: SSH key not found at $SSH_KEY_PATH"
    exit 1
fi

# Default SCP to "yes"
read -p "📤 Do you want to sync $LOCAL_ANSIBLE_DIR/ubuntu-ansible.dockerfile to $DOCKER_SERVER_IP:/ansible/ubuntu-ansible.dockerfile? (Y/n): " SYNC_CONFIRM
SYNC_CONFIRM=${SYNC_CONFIRM:-y}  # Default to "yes" if empty
if [[ "$SYNC_CONFIRM" == "y" || "$SYNC_CONFIRM" == "Y" ]]; then
    echo "📤 Syncing ubuntu-ansible.dockerfile to remote instance..."
    rsync -avz -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_ANSIBLE_DIR/ubuntu-ansible.dockerfile" "ubuntu@$DOCKER_SERVER_IP:/ansible/"
    echo "✅ File copied successfully."
fi

# Check if the image already exists
# Ensure the EBS volume is mounted at /var/lib/docker before proceeding
EBS_MOUNTED=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "mount | grep '/var/lib/docker'")
if [[ -z "$EBS_MOUNTED" ]]; then
    echo "❌ Error: EBS volume is NOT mounted at /var/lib/docker. Docker images may be missing."
    exit 1
fi

# Check timestamps of Dockerfile and image
DOCKERFILE_TIMESTAMP=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "stat -c %Y /ansible/ubuntu-ansible.dockerfile")

# Get the timestamp of the existing Docker image (ubuntu-ansible)
EXISTING_IMAGE_TIMESTAMP=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
    "docker inspect --format='{{.Created}}' ubuntu-ansible 2>/dev/null" | \
    date -d "$(cat)" +%s)

if [[ -z "$EXISTING_IMAGE_TIMESTAMP" ]]; then
    echo "⚠️ No existing image found. Proceeding with build."
else
    if [[ "$DOCKERFILE_TIMESTAMP" -le "$EXISTING_IMAGE_TIMESTAMP" ]]; then
        echo "✅ Dockerfile is older or the same as the existing image. Skipping rebuild."
        exit 0
    else
        echo "🚀 Dockerfile is newer than the existing image. Proceeding with rebuild."
        read -p "Do you want to rebuild the image? (Y/n): " REBUILD_CONFIRM
        REBUILD_CONFIRM=${REBUILD_CONFIRM:-y}  # Default to "yes" if empty
        if [[ "$REBUILD_CONFIRM" != "y" && "$REBUILD_CONFIRM" != "Y" ]]; then
            echo "❌ Skipping rebuild."
            exit 0
        fi
    fi
fi

# Start timer for build process
START_TIME=$(date +%s)

# Run a full build
echo "🚀 Rebuilding 'ubuntu-ansible'..."
ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
    "docker build -f /ansible/ubuntu-ansible.dockerfile -t ubuntu-ansible $REMOTE_ANSIBLE_DIR 2>&1 | tee /home/ubuntu/ansible_build.log"

# End timer
END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))

echo "⏳ Build process took $BUILD_DURATION seconds."
echo "✅ Docker build completed remotely."
echo "📜 Logs stored locally at: $LOG_FILE"
echo "📜 Logs stored remotely at: /home/ubuntu/ansible_build.log"

