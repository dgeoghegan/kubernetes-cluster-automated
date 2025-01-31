#!/bin/bash

# Directories to check before mounting
LOCAL_PLAYBOOK_DIR="./playbooks"
LOCAL_TERRAFORM_DIR="./files_from_terraform"

# Ensure the required directories exist locally before mounting them
if [[ ! -d "$LOCAL_PLAYBOOK_DIR" ]]; then
    echo "Error: Directory '$LOCAL_PLAYBOOK_DIR' does not exist!"
    exit 1
fi

if [[ ! -d "$LOCAL_TERRAFORM_DIR" ]]; then
    echo "Error: Directory '$LOCAL_TERRAFORM_DIR' does not exist!"
    exit 1
fi

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

# List all YAML playbooks in the playbooks directory
PLAYBOOK_FILES=($(ls -1 "$LOCAL_PLAYBOOK_DIR"/*.yaml 2>/dev/null))

# Check if any playbooks exist
if [[ ${#PLAYBOOK_FILES[@]} -eq 0 ]]; then
    echo "No playbooks found in $LOCAL_PLAYBOOK_DIR"
    exit 1
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

# Run Ansible in Docker for each selected playbook
for PLAYBOOK in "${SELECTED_PLAYBOOKS[@]}"; do
    docker run --rm \
      -v $(pwd)/playbooks:/ansible/playbooks \
      -v $(pwd)/files_from_terraform:/ansible/files_from_terraform \
      ubuntu-ansible ansible-playbook -i "/ansible/files_from_terraform/$(basename "$INVENTORY_FILE")" "/ansible/playbooks/$(basename "$PLAYBOOK")"
done

