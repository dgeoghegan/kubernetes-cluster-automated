# Copy playbooks to docker server if the contents have changed

locals {
  playbook_files = concat(
    tolist(fileset(var.playbooks_dir, "**/*.yaml")),
    tolist(fileset(var.playbooks_dir, "**/*.yml"))
  )
  playbook_file_contents = [
    for f in local.playbook_files : {
      path      = f
      content   = file("${var.playbooks_dir}/${f}")
    }
  ]
  sorted_playbook_file_contents = sort([
    for entry in local.playbook_file_contents : 
      "${entry.path}:${entry.content}"
    ])
  playbook_contents_file_hash = sha1(jsonencode(local.sorted_playbook_file_contents))

  static_config_files = concat(
    tolist(fileset(var.static_configs_dir, "**/*.yaml")),
    tolist(fileset(var.static_configs_dir, "**/*.yml"))
  )
  static_config_file_contents = [
    for f in local.static_config_files : {
      path      = f
      content   = file("${var.static_configs_dir}/${f}")
    }
  ]
  sorted_static_config_file_contents = sort([
    for entry in local.static_config_file_contents : 
      "${entry.path}:${entry.content}"
    ])
  static_config_contents_file_hash = sha1(jsonencode(local.sorted_static_config_file_contents))
}

resource "null_resource" "sync_playbooks" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /ansible/playbooks",
      "echo \"${var.registry_pass}\" > ~/reg_pass"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.docker_server_public_ip
      private_key = file(local.docker_ssh_key_path)
    }
  }

  provisioner "local-exec" {
    command = <<-EOT
      rsync -az --delete -e "ssh -o StrictHostKeyChecking=no -i ${local.docker_ssh_key_path}" \
        "${var.playbooks_dir}/" \
        "ubuntu@${var.docker_server_public_ip}:/ansible/playbooks/"
    EOT
  }
}

resource "null_resource" "sync_static_configs" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /ansible/static_configs",
      "echo \"${var.registry_pass}\" > ~/reg_pass"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.docker_server_public_ip
      private_key = file(local.docker_ssh_key_path)
    }
  }

  provisioner "local-exec" {
    command = <<-EOT
      rsync -az --delete -e "ssh -o StrictHostKeyChecking=no -i ${local.docker_ssh_key_path}" \
        "${var.static_configs_dir}/" \
        "ubuntu@${var.docker_server_public_ip}:/ansible/static_configs/"
    EOT
  }
}

resource "null_resource" "run_playbooks" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    inline = [ <<-EOT
      set -x
      export INVENTORY_FILE=/ansible/ansible/inventory.ini
      export PLAYBOOK=/ansible/playbooks/site.yaml
      docker login ${var.registry_address} -u admin -p '${var.registry_pass}'
      docker run --rm \
        -v /ansible:/ansible \
        ${local.ansible_image_remote} ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK" \
        --extra-vars "kubernetes_version=${var.kubernetes_version}" \
        | tee /tmp/ansible_last_run.log
    EOT
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.docker_server_public_ip
      private_key = file(local.docker_ssh_key_path)
    }
  }

  depends_on = [
    null_resource.sync_playbooks,
    null_resource.push_ansible_runner,
    null_resource.sync_static_configs
  ]
}
