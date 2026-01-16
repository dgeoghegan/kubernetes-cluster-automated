locals {
  # Directory containing the Dockerfile
  ansible_build_context   = abspath(dirname(var.ansible_dockerfile_path))

  # Hash the Dockerfile to know when to build a new version
  ansible_dockerfile_hash = filesha1(var.ansible_dockerfile_path)
  ansible_repo          = "ansible-runner"
  ansible_tag           = "latest"
  ansible_image_local   = "${local.ansible_repo}:${local.ansible_tag}"
  ansible_image_remote  = "${var.registry_address}/${local.ansible_repo}:${local.ansible_tag}"
  docker_ssh_key_path   = var.docker_ssh_key_path
}

resource "docker_image" "ansible_runner" {
  name          = local.ansible_image_local

  build {
    context     = local.ansible_build_context
    dockerfile  = var.ansible_dockerfile_path
    tag         = [ local.ansible_image_local,
                    local.ansible_image_remote ]
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
    image_id = docker_image.ansible_runner.image_id  # re-push on rebuild
  }

  provisioner "remote-exec" {
    inline = [ <<-EOT
      bash -lc '
        set -euo pipefail
        set -x

        { set +x; } 2>/dev/null
        printf "%s" "${var.registry_pass}" | \
          docker login ${var.registry_address} -u admin --password-stdin
        { set -x; } 2>/dev/null

        docker push ${local.ansible_image_remote}
      '
    EOT
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
