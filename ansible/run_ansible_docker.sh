#!/bin/bash

# Directories to check before mounting
LOCAL_PLAYBOOK_DIR="./playbooks"
LOCAL_TERRAFORM_DIR="./files_from_terraform"
REMOTE_PLAYBOOK_DIR="/ansible/playbooks"
REMOTE_TERRAFORM_DIR="/ansible/files_from_terraform"
LOG_DIR="./logs"

# Ensure the required directories exist locally before mounting them
if [[ ! -d "$LOCAL_PLAYBOOK_DIR" ]]; then
    echo "Error: Directory '$LOCAL_PLAYBOOK_DIR' does not exist!"
    exit 1
fi

if [[ ! -d "$LOCAL_TERRAFORM_DIR" ]]; then
    echo "Error: Directory '$LOCAL_TERRAFORM_DIR' does not exist!"
    exit 1
fi

# Ensure the logs directory exists
mkdir -p "$LOG_DIR"

# Default inventory path inside the container
DEFAULT_INVENTORY="/ansible/files_from_terraform/inventory.ini"

# Prompt for inventory file (default if empty)
read -p "Enter inventory file [default: $DEFAULT_INVENTORY]: " INVENTORY_FILE
INVENTORY_FILE=${INVENTORY_FILE:-$DEFAULT_INVENTORY}

# Ensure the inventory file exists locally before proceeding
if [[ ! -f "$LOCAL_TERRAFORM_DIR/$(basename "$INVENTORY_FILE")" ]]; then
    echo "Error: Inventory file '$LOCAL_TERRAFORM_DIR/$(basename "$INVENTORY_FILE")' not found!"
    exit 1
fi

# Get AWS server IP dynamically from Terraform output
AWS_SERVER_IP=$(terraform output -state=../terraform/terraform.tfstate | grep docker_public_ip | cut -f 2 -d "\"")
SSH_KEY_PATH="../docker/files_from_terraform/docker_ssh_key"
SSH_USER="ubuntu"

# List all YAML playbooks in the playbooks directory
PLAYBOOK_FILES=($(ls -1 "$LOCAL_PLAYBOOK_DIR"/*.yaml 2>/dev/null))

# List all files in the files_from_terraform directory
TERRAFORM_FILES=($(ls -1 "$LOCAL_TERRAFORM_DIR"/* 2>/dev/null))

# Check if any playbooks or terraform files exist
if [[ ${#PLAYBOOK_FILES[@]} -eq 0 && ${#TERRAFORM_FILES[@]} -eq 0 ]]; then
    echo "No files found to update."
    exit 1
fi

# Prompt user if they want to update the files
read -p "Do you want to proceed with updating the files in the playbooks and files_from_terraform directories? (Y/n): " UPDATE_CONFIRM
UPDATE_CONFIRM=${UPDATE_CONFIRM:-y}

if [[ "$UPDATE_CONFIRM" == "y" || "$UPDATE_CONFIRM" == "Y" ]]; then
    echo "Updating files..."
    # Update playbooks directory (with --delete to remove superfluous files)
    rsync -avzc --delete -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_PLAYBOOK_DIR/" "$SSH_USER@$AWS_SERVER_IP:$REMOTE_PLAYBOOK_DIR/"

    # Update terraform files directory (with --delete to remove superfluous files)
    rsync -avzc --delete -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_TERRAFORM_DIR/" "$SSH_USER@$AWS_SERVER_IP:$REMOTE_TERRAFORM_DIR/"
else
    echo "Skipping file update."
fi

# Present playbook choices using a menu
echo "Select playbooks to run (use space to select, ENTER to confirm):"
SELECTED_PLAYBOOKS=()
PLAYBOOK_OPTIONS=("ALL" "${PLAYBOOK_FILES[@]}")

for i in "${!PLAYBOOK_OPTIONS[@]}"; do
    echo "[$i] ${PLAYBOOK_OPTIONS[$i]}"
done

# Read user selection
read -p "Enter numbers separated by spaces (e.g., '0 2 3'): " INPUT_SELECTION

# Parse selection
for index in $INPUT_SELECTION; do
    if [[ $index -ge 0 && $index -lt ${#PLAYBOOK_OPTIONS[@]} ]]; then
        SELECTED_PLAYBOOKS+=("${PLAYBOOK_OPTIONS[$index]}")
    fi
done

# If "ALL" was selected, run all playbooks
if [[ " ${SELECTED_PLAYBOOKS[@]} " =~ " ALL " ]]; then
    SELECTED_PLAYBOOKS=("${PLAYBOOK_FILES[@]}")
fi

# Confirm selected playbooks
echo "Running selected playbooks:"
for pb in "${SELECTED_PLAYBOOKS[@]}"; do
    echo "- $(basename "$pb")"
done

# Get timestamp for log filenames
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Run Ansible in Docker for each selected playbook, display output, and capture it in logs
for PLAYBOOK in "${SELECTED_PLAYBOOKS[@]}"; do
    LOG_FILE="$LOG_DIR/$(basename "$PLAYBOOK" .yaml)_$TIMESTAMP.log"

    # Run the playbook and display output as it runs, also saving it to a log file
    docker run --rm \
      -v $(pwd)/playbooks:/ansible/playbooks \
      -v $(pwd)/files_from_terraform:/ansible/files_from_terraform \
      ubuntu-ansible ansible-playbook -i "/ansible/files_from_terraform/$(basename "$INVENTORY_FILE")" "/ansible/playbooks/$(basename "$PLAYBOOK")" \
      | tee "$LOG_FILE"  # Tee to show output and write it to the log file

    echo "Ansible playbook output saved to $LOG_FILE"
done

