#!/bin/bash

# Require the environment root path as an argument
if [[ -z "$1" ]]; then
    echo "❌ Error: You must pass the path to the environment root (e.g. envs/tier/cluster)"
    exit 1
fi

ENV_ROOT="$1"


# Paths based on env root
STATE_FILE="${ENV_ROOT}/terraform.tfstate"

# Get Docker server IP
DOCKER_SERVER_IP=$(terraform output --state="${STATE_FILE}" -raw docker_server_public_ip)

# Define SSH keys
SSH_KEY_PATH_DOCKER="${ENV_ROOT}/files_from_terraform/docker_ssh_key"
SSH_KEY_PATH_KUBERNETES="${ENV_ROOT}/files_from_terraform/kubernetes_ssh_key"

# Ensure Terraform extracted a valid IP
if [[ -z "$DOCKER_SERVER_IP" ]]; then
    echo "❌ Error: Could not retrieve Docker server IP from Terraform."
    exit 1
fi

# Read inventory file for workers & controllers
INVENTORY_FILE="${ENV_ROOT}/files_from_terraform/inventory.ini"

declare -A SERVERS
declare -A MENU_OPTIONS

INDEX=1  # Start numbering from 1

# First, add docker_server as option 1
MENU_OPTIONS[$INDEX]="docker_server"
SERVERS["docker_server"]="$DOCKER_SERVER_IP"
((INDEX++))

# Parse inventory file for workers and controllers
while IFS= read -r line; do
    if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+ansible_host=([^[:space:]]+)[[:space:]]+ansible_user=([^[:space:]]+) ]]; then
        HOSTNAME="${BASH_REMATCH[1]}"
        IP="${BASH_REMATCH[2]}"
        MENU_OPTIONS[$INDEX]="$HOSTNAME"
        SERVERS["$HOSTNAME"]="$IP"
        ((INDEX++))
    fi
done < "$INVENTORY_FILE"

# Add kubectl option at the end
MENU_OPTIONS[$INDEX]="kubectl"
SERVERS["kubectl"]="$DOCKER_SERVER_IP"
((INDEX++))

# Add exit option at the very end
MENU_OPTIONS[$INDEX]="exit"

# Display menu in proper ascending order
echo "📡 Select a server to SSH into:"
for i in $(seq 1 ${#MENU_OPTIONS[@]}); do
    echo "$i) ${MENU_OPTIONS[$i]}"
done

# Prompt user for choice
read -p "#? " CHOICE
CHOICE=${CHOICE:-1}  # Default to docker_server if Enter is pressed

# Get selected server
SELECTED_SERVER="${MENU_OPTIONS[$CHOICE]}"

# Handle exit
if [[ "$SELECTED_SERVER" == "exit" ]]; then
    echo "🚪 Exiting."
    exit 0
fi

# Get server IP
SERVER_IP="${SERVERS[$SELECTED_SERVER]}"

# SSH into the selected server
echo "🔗 Connecting to $SELECTED_SERVER ($SERVER_IP)..."

if [[ "$SELECTED_SERVER" == "docker_server" ]]; then
    ssh -i "$SSH_KEY_PATH_DOCKER" -o "StrictHostKeyChecking=no" ubuntu@"$SERVER_IP"

elif [[ "$SELECTED_SERVER" == "kubectl" ]]; then
    ssh -t -i "$SSH_KEY_PATH_DOCKER" -o "StrictHostKeyChecking=no" ubuntu@"$SERVER_IP" "docker exec -it kubectl-container sh"

else
    ssh -i "$SSH_KEY_PATH_KUBERNETES" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$SERVER_IP" \
    -o ProxyCommand="ssh -W%h:%p -i ${SSH_KEY_PATH_DOCKER} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${DOCKER_SERVER_IP}"
fi

