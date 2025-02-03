#!/bin/bash

# Set timestamp for log file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/ansible_run_$TIMESTAMP.log"

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
LOCAL_ANSIBLE_DIR="$(pwd)/../ansible"
REMOTE_ANSIBLE_DIR="/ansible"

# Ensure the SSH key exists
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "❌ Error: SSH key not found at $SSH_KEY_PATH"
    exit 1
fi

# Default SCP to "yes"
read -p "📤 Do you want to sync $LOCAL_ANSIBLE_DIR to $DOCKER_SERVER_IP:$REMOTE_ANSIBLE_DIR? (Y/n): " SYNC_CONFIRM
SYNC_CONFIRM=${SYNC_CONFIRM:-y}  # Default to "yes" if empty
if [[ "$SYNC_CONFIRM" == "y" || "$SYNC_CONFIRM" == "Y" ]]; then
    echo "📤 Syncing Ansible directory to remote instance..."
    rsync -avz -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_ANSIBLE_DIR/" "ubuntu@$DOCKER_SERVER_IP:$REMOTE_ANSIBLE_DIR/"
    echo "✅ Files copied successfully."
fi

# Check if the remote docker image "ubuntu-ansible" exists
echo "🔍 Checking for Docker image 'ubuntu-ansible' on remote server..."
IMAGE_EXISTS=$(ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "docker images -q ubuntu-ansible")

if [[ -z "$IMAGE_EXISTS" ]]; then
    echo "⚠️  Docker image 'ubuntu-ansible' not found. Building it..."
    ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking no" ubuntu@"$DOCKER_SERVER_IP" "docker build -t ubuntu-ansible -f $REMOTE_ANSIBLE_DIR/ubuntu-ansible.dockerfile $REMOTE_ANSIBLE_DIR/"
    echo "✅ Docker image 'ubuntu-ansible' created successfully."
else
    echo "✅ Docker image 'ubuntu-ansible' already exists."
fi

# Generate the list of playbooks from local `../ansible/playbooks/`
PLAYBOOK_FILES=($(ls -1 "$LOCAL_ANSIBLE_DIR/playbooks/"*.yaml 2>/dev/null))

# Check if any playbooks exist
if [[ ${#PLAYBOOK_FILES[@]} -eq 0 ]]; then
    echo "❌ No playbooks found in $LOCAL_ANSIBLE_DIR/playbooks/"
    exit 1
fi

# Display available playbooks
echo "📜 Available playbooks:"
for i in "${!PLAYBOOK_FILES[@]}"; do
    echo "[$i] $(basename "${PLAYBOOK_FILES[$i]}")"
done

# Default playbook selection to "all"
read -p "Enter numbers separated by spaces to select playbooks (or press Enter to run all): " INPUT_SELECTION
INPUT_SELECTION=${INPUT_SELECTION:-all}  # Default to "all" if empty

# Parse selection
SELECTED_PLAYBOOKS=()
if [[ "$INPUT_SELECTION" == "all" ]]; then
    SELECTED_PLAYBOOKS=("${PLAYBOOK_FILES[@]}")
else
    for index in $INPUT_SELECTION; do
        if [[ $index -ge 0 && $index -lt ${#PLAYBOOK_FILES[@]} ]]; then
            SELECTED_PLAYBOOKS+=("${PLAYBOOK_FILES[$index]}")
        fi
    done
fi

# Confirm selected playbooks
echo "🚀 Running the following playbooks remotely inside Docker on Docker Server:"
for pb in "${SELECTED_PLAYBOOKS[@]}"; do
    echo "- $(basename "$pb")"
done

# Build the remote Docker execution command with correct inventory path
REMOTE_ANSIBLE_CMD="docker run --rm \
    -v $REMOTE_ANSIBLE_DIR/playbooks:/ansible/playbooks \
    -v $REMOTE_ANSIBLE_DIR/files_from_terraform:/ansible/files_from_terraform \
    ubuntu-ansible "

# Add playbooks to the command with correct inventory path
for PLAYBOOK in "${SELECTED_PLAYBOOKS[@]}"; do
    REMOTE_ANSIBLE_CMD+="ansible-playbook -i /ansible/files_from_terraform/inventory.ini /ansible/playbooks/$(basename "$PLAYBOOK") && "
done
REMOTE_ANSIBLE_CMD=${REMOTE_ANSIBLE_CMD%&& }  # Remove trailing '&&'

# Ensure Ansible directory permissions are correct on the remote server
echo "🔧 Setting correct permissions on remote Ansible directory..."
ssh -o "StrictHostKeyChecking no" -i "$SSH_KEY_PATH" "ubuntu@$DOCKER_SERVER_IP" "sudo chown -R ubuntu:ubuntu $REMOTE_ANSIBLE_DIR"

# Run Ansible remotely inside Docker with full live output streaming and logging
echo "🚀 Executing Ansible inside Docker remotely on $DOCKER_SERVER_IP..."
ssh -o "StrictHostKeyChecking no" -i "$SSH_KEY_PATH" "ubuntu@$DOCKER_SERVER_IP" "bash -c '$REMOTE_ANSIBLE_CMD 2>&1 | tee /ansible/ansible_run.log'" | tee "$LOG_FILE"

echo "✅ Ansible execution completed remotely."
echo "📜 Logs stored locally at: $LOG_FILE"
echo "📜 Logs stored remotely at: /ansible/ansible_run.log"

