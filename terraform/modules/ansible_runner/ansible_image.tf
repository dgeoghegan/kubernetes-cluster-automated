locals {
  # Directory containing the Dockerfile
  ansible_build_context   = abspath(dirname(var.ansible_dockerfile_path))

  # Hash the Dockerfile to know when to build a new version
  ansible_dockerfile_hash = filesha1(var.ansible_dockerfile_path)
  ansible_repo          = "ansible-runner"
  ansible_image_local   = "${local.ansible_repo}:build"
  ansible_tag           = substr(docker_image.ansible_runner.image_id, 7, 12)
  ansible_image_remote  = "${var.registry_address}/${local.ansible_repo}:${local.ansible_tag}"
  docker_ssh_key_path   = var.docker_ssh_key_path
}

resource "docker_image" "ansible_runner" {
  name          = local.ansible_image_local

  build {
    context     = local.ansible_build_context
    dockerfile  = var.ansible_dockerfile_path
    tag         = [ local.ansible_image_local ]
  }

  triggers = {
    dockerfile_sha1 = local.ansible_dockerfile_hash
  }

  keep_locally  = true
}

resource "docker_tag" "ansible_runner_remote" {
  source_image  = docker_image.ansible_runner.name
  target_image  = local.ansible_image_remote
}

resource "null_resource" "push_ansible_runner" {
  triggers = {
    image_id = docker_image.ansible_runner.image_id
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "set +x",

      "REGISTRY_ADDR=127.0.0.1:5000",
      "REGISTRY_USER=admin",
      "IMAGE='${local.ansible_image_remote}'",

      "tmp=$(mktemp)",
      "trap 'rm -f \"$tmp\"' EXIT",

      # Write the password literally. Quoted heredoc prevents $ expansion.
      "cat > \"$tmp\" <<'EOF'\n${var.registry_pass}\nEOF",

      # No pipe here, so /bin/sh captures errors correctly.
      "docker login \"$REGISTRY_ADDR\" -u \"$REGISTRY_USER\" --password-stdin < \"$tmp\"",

      "rm -f \"$tmp\"",
      "trap - EXIT",

      "docker push \"$IMAGE\" 2>&1 | tee /tmp/ansible_runner_push.log",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.docker_server_public_ip
      private_key = file(local.docker_ssh_key_path)
    }
  }

  depends_on = [docker_tag.ansible_runner_remote]
}
