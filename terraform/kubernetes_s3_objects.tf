resource "aws_s3_object" "common_configs" {
  for_each = local.common_config_contents
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id
  key      = "configs/${each.key}"
  content  = each.value
}

resource "aws_s3_object" "per_worker_configs" {
  for_each = local.per_worker_configs
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "configs/workers/${each.key}/kubeconfig"
  content = each.value.kubeconfig
}

resource "aws_s3_object" "per_worker_certs" {
  for_each = local.per_worker_configs
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "configs/workers/${each.key}/key.pem"
  content = each.value.key_pem
}

resource "aws_s3_object" "per_worker_cert_pems" {
  for_each = local.per_worker_configs
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "configs/workers/${each.key}/cert.pem"
  content = each.value.cert_pem
}

resource "aws_s3_object" "per_controller_configs" {
  for_each = local.per_controller_configs
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "configs/controllers/${each.key}/kube-apiserver.service"
  content = each.value.kube_apiserver_service
}

resource "aws_s3_object" "per_controller_etcd" {
  for_each = local.per_controller_configs
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "configs/controllers/${each.key}/etcd.service"
  content = each.value.etcd_service
}

resource "aws_s3_object" "per_controller_kubeconfigs" {
  for_each = local.per_controller_configs
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "configs/controllers/${each.key}/kube-controller-manager.kubeconfig"
  content = each.value.kube_controller_manager_kubeconfig
}

resource "aws_s3_object" "per_controller_scheduler_kubeconfigs" {
  for_each = local.per_controller_configs
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "configs/controllers/${each.key}/kube-scheduler.kubeconfig"
  content = each.value.kube_scheduler_kubeconfig
}

resource "aws_s3_object" "ansible_inventory" {
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id
  key      = "ansible/inventory.ini"
  content  = local.kubernetes_inventory_ini_contents
}

resource "aws_s3_object" "dockerfiles" {
  for_each = local.dockerfiles
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "dockerfiles/${each.key}"
  content = each.value
}

# Dynamically upload Ansible playbooks
data "local_file" "ansible_playbooks" {
  for_each = fileset("../ansible/playbooks", "*.yaml")
  filename = "../ansible/playbooks/${each.value}"
}

resource "aws_s3_object" "ansible_playbooks" {
  for_each = data.local_file.ansible_playbooks
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id

  key     = "ansible/playbooks/${each.key}"
  content = each.value.content
}

locals {
  # Collect all files stored in S3
  all_s3_files = concat(
    keys(local.common_config_contents),                          # Common configs
    [for worker, files in local.per_worker_configs : "configs/workers/${worker}/kubeconfig"],
    [for worker, files in local.per_worker_configs : "configs/workers/${worker}/key.pem"],
    [for worker, files in local.per_worker_configs : "configs/workers/${worker}/cert.pem"],
    [for controller, files in local.per_controller_configs : "configs/controllers/${controller}/kube-apiserver.service"],
    [for controller, files in local.per_controller_configs : "configs/controllers/${controller}/etcd.service"],
    [for controller, files in local.per_controller_configs : "configs/controllers/${controller}/kube-controller-manager.kubeconfig"],
    [for controller, files in local.per_controller_configs : "configs/controllers/${controller}/kube-scheduler.kubeconfig"],
    ["ansible/inventory.ini"],
    keys(local.dockerfiles),                                    # Dockerfiles
    [for file in fileset("../ansible/playbooks", "*.yaml") : "ansible/playbooks/${file}"] # Ansible playbooks
  )
}

data "external" "presigned_s3_urls" {
  for_each = toset(local.all_s3_files)

  program = ["/bin/bash", "-c", <<EOT
#!/bin/bash
echo "{\"url\": \"$(aws s3 presign s3://${var.s3_bucket_name}/${each.key} --region ${data.aws_region.current.name} --expires-in 3600)\"}"
EOT
  ]
}

locals {
  presigned_s3_bucket_urls = [for file, data in data.external.presigned_s3_urls : data.result["url"]]
  s3_files_list_filename = "presigned_urls.txt"
}

resource "aws_s3_object" "s3_files_list" {
  bucket   = aws_s3_bucket.kubernetes_cluster_automated.id
  key      = "configs/${local.s3_files_list_filename}"
  content  = join("\n", local.presigned_s3_bucket_urls)
}

data "external" "s3_files_list_presigned_url" {
  program = ["/bin/bash", "-c", <<EOT
#!/bin/bash
echo "{\"url\": \"$(aws s3 presign s3://${var.s3_bucket_name}/${aws_s3_object.s3_files_list.key} --region ${data.aws_region.current.name} --expires-in 3600)\"}"
EOT
  ]
}
