#!/bin/bash

# Set timestamp for log file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/kubectl_build_$TIMESTAMP.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Extract the public IP of the remote AWS instance from Terraform state
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
REMOTE_INVENTORY_DIR="/ansible/files_from_terraform"
REMOTE_INVENTORY_FILE="$REMOTE_INVENTORY_DIR/inventory.ini"
REMOTE_ORIG_INVENTORY_FILE="$REMOTE_INVENTORY_DIR/inventory.ini-orig"

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

# Build the Docker image on the remote server
echo "🚀 Building 'kubectl-container' image on $DOCKER_SERVER_IP..."
ssh -o "StrictHostKeyChecking no" -i "$SSH_KEY_PATH" ubuntu@"$DOCKER_SERVER_IP" "docker build -f $REMOTE_KUBECTL_DIR/kubectl-container.dockerfile -t kubectl-container $REMOTE_KUBECTL_DIR 2>&1 | tee /home/ubuntu/kubectl_build.log" | tee "$LOG_FILE"

echo "✅ Docker build completed remotely."
echo "📜 Logs stored locally at: $LOG_FILE"
echo "📜 Logs stored remotely at: /home/ubuntu/kubectl_build.log"

# Check if a running container is using the `kubectl-container` image
echo "🔍 Checking if a running container is using the 'kubectl-container' image..."
RUNNING_CONTAINER_ID=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "docker ps --filter 'ancestor=kubectl-container' --format '{{.ID}}'")

if [[ -z "$RUNNING_CONTAINER_ID" ]]; then
    echo "⚠️  No running container found for 'kubectl-container'. Starting one in detached mode..."
    ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "docker run -d --name kubectl-container kubectl-container tail -f /dev/null"

    # Wait and verify if the container started successfully
    sleep 5
    RUNNING_CONTAINER_ID=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "docker ps --filter 'name=kubectl-container' --format '{{.ID}}'")

    if [[ -z "$RUNNING_CONTAINER_ID" ]]; then
        echo "❌ Error: Failed to start kubectl-container. Exiting."
        exit 1
    fi

    echo "✅ kubectl-container is now running."
else
    echo "✅ kubectl-container is already running."
fi

# Retrieve kubectl-container IP
echo "🔍 Retrieving kubectl-container IP..."
KUBECTL_CONTAINER_IP=""
for i in {1..5}; do  # Retry up to 5 times
    KUBECTL_CONTAINER_IP=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kubectl-container" 2>/dev/null || echo '')

    if [[ -n "$KUBECTL_CONTAINER_IP" ]]; then
        break
    fi

    echo "⏳ Waiting for container IP... ($i/5)"
    sleep 2
done

if [[ -z "$KUBECTL_CONTAINER_IP" ]]; then
    echo "❌ Error: Could not retrieve kubectl-container IP. Is it running?"
    exit 1
fi

echo "✅ kubectl-container IP: $KUBECTL_CONTAINER_IP"

# Backup inventory.ini if it hasn't been backed up already
echo "🔍 Checking for existing inventory backup..."
ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "[[ -f $REMOTE_ORIG_INVENTORY_FILE ]] || cp $REMOTE_INVENTORY_FILE $REMOTE_ORIG_INVENTORY_FILE"

# Check if kubectl-inventory.ini is already in inventory.ini
echo "🔍 Updating inventory.ini with kubectl-container entry..."
EXISTING_ENTRY=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "grep -A1 '^[kubectl_container]' $REMOTE_INVENTORY_FILE | grep -F 'ansible_host=$KUBECTL_CONTAINER_IP'")

if [[ -z "$EXISTING_ENTRY" ]]; then
    # Remove old kubectl-container entry (if exists)
    ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "sed -i '/^\[kubectl_container\]/,/^$/d' $REMOTE_INVENTORY_FILE"

    # Append the new kubectl-container entry
    ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "echo -e '\n[kubectl_container]\nkubectl ansible_host=$KUBECTL_CONTAINER_IP ansible_connection=docker ansible_user=root' >> $REMOTE_INVENTORY_FILE"

    echo "✅ kubectl-container entry updated in inventory.ini."
else
    echo "✅ kubectl-container entry is already up to date in inventory.ini."
fi

echo "📜 Remote inventory file updated: $REMOTE_INVENTORY_FILE"

