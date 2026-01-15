locals {
  # Directory containing the Dockerfile
  kubectl_build_context   = abspath(dirname(var.kubectl_dockerfile_path))

  # Hash the Dockerfile + K8s version to know when to build a new image
  kubectl_dockerfile_hash = sha1(jsonencode({
    dockerfile_hash = filesha1(var.kubectl_dockerfile_path)
    k8s_version     = var.kubernetes_version
  }))

  # Tag image using hash
  kubectl_repo          = "kubectl-runner"
  kubectl_tag           = "v${var.kubernetes_version}"
  kubectl_image_local   = "${local.kubectl_repo}:${local.kubectl_tag}"
  kubectl_image_remote  = "${var.registry_address}/${local.kubectl_repo}:${local.kubectl_tag}"
  docker_ssh_key_path   = var.docker_ssh_key_path
}

resource "docker_image" "kubectl_runner" {
  name          = local.kubectl_image_local

  build {
    context     = local.kubectl_build_context
    dockerfile  = var.kubectl_dockerfile_path
    tag         = [ local.kubectl_image_local,
                    local.kubectl_image_remote ]

    build_args = {
      KUBECTL_VERSION = var.kubernetes_version
    }
  }

  triggers = {
    dockerfile_sha1 = local.kubectl_dockerfile_hash
  }

  keep_locally  = true
}

resource "docker_tag" "kubectl_runner_remote" {
  source_image  = docker_image.kubectl_runner.name
  target_image  = local.kubectl_image_remote

  depends_on = [docker_image.kubectl_runner]
}

# Using null_resource instead of docker_registry_image to keep everything local on docker server
# docker_registry_image would require the registry to be accessible from my Terraform workstation

resource "null_resource" "push_kubectl_runner" {
  triggers = {
    image_id = docker_image.kubectl_runner.image_id  # re-push on rebuild
  }

  provisioner "remote-exec" {
    inline = [
    # First kill stale containers
      "docker rm -f $(docker ps -aq --filter ancestor=${local.kubectl_image_remote}) || true",
      "docker login ${var.registry_address} -u admin -p '${var.registry_pass}'",
      "docker push ${local.kubectl_image_remote}"
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.docker_server_public_ip
      private_key = file(local.docker_ssh_key_path)
    }
  }

  depends_on = [docker_tag.kubectl_runner_remote]
}
