#!/bin/bash

# Set timestamp for log file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/kubectl_build_$TIMESTAMP.log"

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
LOCAL_KUBECTL_DIR="$(pwd)/../kubectl"
REMOTE_KUBECTL_DIR="/home/ubuntu/kubectl"

# Ensure the SSH key exists
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "❌ Error: SSH key not found at $SSH_KEY_PATH"
    exit 1
fi

# Default SCP to "yes"
read -p "📤 Do you want to sync $LOCAL_KUBECTL_DIR to $DOCKER_SERVER_IP:$REMOTE_KUBECTL_DIR? (Y/n): " SYNC_CONFIRM
SYNC_CONFIRM=${SYNC_CONFIRM:-y}  # Default to "yes" if empty
if [[ "$SYNC_CONFIRM" == "y" || "$SYNC_CONFIRM" == "Y" ]]; then
    echo "📤 Syncing kubectl directory to remote instance..."
    rsync -avz -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_KUBECTL_DIR/" "ubuntu@$DOCKER_SERVER_IP:$REMOTE_KUBECTL_DIR/"
    echo "✅ Files copied successfully."
fi

# Ensure the EBS volume is mounted at /var/lib/docker before proceeding
EBS_MOUNTED=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "mount | grep '/var/lib/docker'")
if [[ -z "$EBS_MOUNTED" ]]; then
    echo "❌ Error: EBS volume is NOT mounted at /var/lib/docker. Docker images may be missing."
    exit 1
fi

# Check timestamps of Dockerfile and image
DOCKERFILE_TIMESTAMP=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
"stat -c %Y /home/ubuntu/kubectl/kubectl-container.dockerfile")

EXISTING_IMAGE_TIMESTAMP=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
    "docker inspect --format='{{.Created}}' kubectl-container 2>/dev/null" | \
    date -d "$(cat)" +%s)

if [[ -z "$EXISTING_IMAGE_TIMESTAMP" ]]; then
    echo "⚠️ No existing image found. Proceeding with build."
else
    if [[ "$DOCKERFILE_TIMESTAMP" -le "$EXISTING_IMAGE_TIMESTAMP" ]]; then
        echo "✅ Dockerfile is older or the same as the existing image. Skipping rebuild."
    else
        echo "🚀 Dockerfile is newer than the existing image. Proceeding with rebuild."
        read -p "Do you want to rebuild the image? (Y/n): " REBUILD_CONFIRM
        REBUILD_CONFIRM=${REBUILD_CONFIRM:-y}  # Default to "yes" if empty
        if [[ "$REBUILD_CONFIRM" != "y" && "$REBUILD_CONFIRM" != "Y" ]]; then
            echo "❌ Skipping rebuild."
        else
            # Run a full build
            START_TIME=$(date +%s)
            echo "🚀 Rebuilding 'kubectl-container'..."
            ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
                "docker build -f /home/ubuntu/kubectl/kubectl-container.dockerfile -t kubectl-container $REMOTE_KUBECTL_DIR 2>&1 | tee /home/ubuntu/kubectl_build.log"
            END_TIME=$(date +%s)
            BUILD_DURATION=$((END_TIME - START_TIME))

            echo "⏳ Build process took $BUILD_DURATION seconds."
            echo "✅ Docker build completed remotely."
            echo "📜 Logs stored locally at: $LOG_FILE"
            echo "📜 Logs stored remotely at: /home/ubuntu/kubectl_build.log"
        fi
    fi
fi

# Check if there are any exited containers named `kubectl-container` and remove them
EXISTING_STOPPED_CONTAINER_ID=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
    "docker ps -a --filter 'name=kubectl-container' --filter 'status=exited' --format '{{.ID}}'")

if [[ -n "$EXISTING_STOPPED_CONTAINER_ID" ]]; then
    echo "🔄 Found exited container named kubectl-container. Removing it..."
    ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
        "docker rm -f kubectl-container"
fi

# Check if a running container is using the `kubectl-container` image
RUNNING_CONTAINER_ID=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
    "docker ps --filter 'ancestor=kubectl-container' --format '{{.ID}}'")

if [[ -n "$RUNNING_CONTAINER_ID" ]]; then
    echo "✅ kubectl-container is already running."
else
    echo "🚀 Starting a new 'kubectl-container'..."
    ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
        "docker run -d --name kubectl-container kubectl-container tail -f /dev/null"

    # Wait and verify if the container started successfully
    sleep 5
    RUNNING_CONTAINER_ID=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" \
        "docker ps --filter 'name=kubectl-container' --format '{{.ID}}'")

    if [[ -z "$RUNNING_CONTAINER_ID" ]]; then
        echo "❌ Error: Failed to start kubectl-container. Exiting."
        exit 1
    fi

    echo "✅ kubectl-container is now running."
fi
