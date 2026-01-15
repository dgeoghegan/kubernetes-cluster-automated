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
    inline = [
      "mkdir -p /ansible/manifests",
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
        "${var.manifests_dir}/" \
        "ubuntu@${var.docker_server_public_ip}:/ansible/manifests/"
    EOT
  }
}

resource "null_resource" "run_manifests" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    inline = [ <<-EOT
      # Authenticate to registry to pull kubectl image if needed
      export CLUSTER_DNS=${cidrhost(var.service_cidr, 10)}
      docker login ${var.registry_address} -u admin -p '${var.registry_pass}'
      docker run --rm \
        --entrypoint /bin/sh \
        -e CLUSTER_DNS \
        -v /ansible:/ansible \
        ${local.kubectl_image_remote} \
        -c "
          for f in /ansible/manifests/*.y*ml; do
            [ -f "$f" ] || continue
            echo \"Applying $f\"
            envsubst < \"\$f\" | \
              kubectl \
                --kubeconfig=/ansible/common/admin_kubeconfig \
                apply --server-side --force-conflicts -f -
          done
        " >  /tmp/kubectl_last_run.log 2>&1
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
    null_resource.sync_manifests,
    null_resource.push_kubectl_runner
  ]
}
