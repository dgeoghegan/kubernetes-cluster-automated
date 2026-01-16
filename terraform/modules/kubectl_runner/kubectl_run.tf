# Copy manifests to docker server if the contents have changed

#resource "local_file" "kubernetes_version_yaml" {
#  filename              = "${var.manifests_dir}/k8s_version.yaml"
#  content               = "var.kubernetes_version"
#  file_permission       = "0644"
#  directory_permission  = "0700"
#}

locals {
  manifest_files = concat(
    tolist(fileset(var.manifests_dir, "**/*.yaml")),
    tolist(fileset(var.manifests_dir, "**/*.yml"))
  )
    
  manifest_file_contents = [
    for f in local.manifest_files : {
      path      = f
      content   = file("${var.manifests_dir}/${f}")
    }
  ]
  sorted_manifest_file_contents = sort([
    for entry in local.manifest_file_contents : 
      "${entry.path}:${entry.content}"
    ])
  manifest_contents_file_hash = sha1(jsonencode(local.sorted_manifest_file_contents))
}

resource "null_resource" "sync_manifests" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    inline = [ <<-EOT
      bash -lc '
        set -euo pipefail
        set -x
        mkdir -p /ansible/manifests
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

  provisioner "local-exec" {
    command = <<-EOT
      rsync -az --delete \
        -e "ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i ${local.docker_ssh_key_path}" \
        "${var.manifests_dir}/" \
        "ubuntu@${var.docker_server_public_ip}:/ansible/manifests/"
    EOT
  }
}

resource "null_resource" "wait_for_apiserver" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {

    inline = [
      "set -e",
      "url=https://${var.load_balancer_dns_name}:6443/healthz",
      "i=1; while [ $i -le 60 ]; do curl -kfsS \"$url\" >/dev/null && echo apiserver-ready && exit 0; echo waiting... \"$i/60\"; i=$((i+1)); sleep 5; done; echo apiserver-not-ready >&2; exit 1",
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = var.docker_server_public_ip
    private_key = file(local.docker_ssh_key_path)
  }

  depends_on = [
    null_resource.sync_manifests
  ]

}


resource "null_resource" "run_manifests" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export CLUSTER_DNS=${cidrhost(var.service_cidr, 10)}",
      "printf '%s' '${var.registry_pass}' | docker login ${var.registry_address} -u admin --password-stdin",
      "docker pull ${local.kubectl_image_remote}",
      <<-EOC
        docker run --rm --entrypoint /bin/sh \
          -e CLUSTER_DNS \
          -v /ansible:/ansible \
          ${local.kubectl_image_remote} \
          -c 'set -eu
            for f in /ansible/manifests/*.y*ml; do
              [ -f "$f" ] || continue
              echo "Applying $f"
              tmp="$(mktemp)"
              envsubst < "$f" > "$tmp"
              kubectl --kubeconfig=/ansible/common/admin_kubeconfig \
                apply --server-side --force-conflicts -f "$tmp"
              rm -f "$tmp"
            done' 
    EOC
  ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.docker_server_public_ip
      private_key = file(local.docker_ssh_key_path)
    }
  }

  depends_on = [
    null_resource.sync_manifests,
    null_resource.push_kubectl_runner,
    null_resource.wait_for_apiserver
  ]
}
