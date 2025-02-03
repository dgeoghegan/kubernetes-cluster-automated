#!/bin/bash
ssh -o "StrictHostKeyChecking no" ubuntu@$(terraform output -state="$(pwd)/../terraform/terraform.tfstate" | grep "docker_public_ip" | cut -d "\"" -f 2) -i "$(pwd)/files_from_terraform/docker_ssh_key" docker build -f /ansible/ubuntu-ansible.dockerfile -t ubuntu-ansible /ansible/
