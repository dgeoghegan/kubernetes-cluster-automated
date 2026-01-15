locals {
  # Directory containing the Dockerfile
  ansible_build_context   = abspath(dirname(var.ansible_dockerfile_path))

  # Hash the Dockerfile to know when to build a new version
  ansible_dockerfile_hash = filesha1(var.ansible_dockerfile_path)

  # Tag image using hash
#  ansible_image_tag       = "ansible:${substr(local.ansible_dockerfile_hash, 0, 12)}"

#  ansible_image_remote_name             = "127.0.0.1:5000/${local.ansible_image_tag}"
#  ansible_image_remote_name             = local.ansible_image_tag

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

#resource "docker_registry_image" "ansible_runner" {
#  name          = local.ansible_image_local
#  name          = docker_tag.ansible_runner_remote.target_image
#  depends_on    = [docker_image.ansible_runner, docker_tag.ansible_runner_remote]
#  depends_on    = [docker_image.ansible_runner]
#  keep_remotely = false
#
#}

# Using null_resource instead of docker_registry_image to keep everything local on docker server
# docker_registry_image would require the registry to be accessible from my Terraform workstation

resource "null_resource" "push_ansible_runner" {
  triggers = {
    image_id = docker_image.ansible_runner.image_id  # re-push on rebuild
  }

  provisioner "remote-exec" {
    inline = [
      "docker login ${var.registry_address} -u admin -p '${var.registry_pass}'",
      "docker push ${local.ansible_image_remote}"
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
