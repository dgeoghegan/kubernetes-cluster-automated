variable "s3_ansible_path" {
  type    = string
  default = "ansible/files_from_terraform"
}

resource "aws_s3_object" "kubernetes_hosts" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/inventory.ini"
  content = <<EOT
[kubernetes_workers]
%{for instance in local.kubernetes_worker_network_info}
${instance.name} ansible_host=${instance.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/ansible/files_from_terraform/kubernetes_ssh_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{endfor}

[kubernetes_controllers]
%{for instance in local.kubernetes_controller_network_info}
${instance.name} ansible_host=${instance.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/ansible/files_from_terraform/kubernetes_ssh_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{endfor}
EOT
}

# Convert all certificate and key files to S3 objects
resource "aws_s3_object" "kubernetes_certificates" {
  for_each = {
    "admin-key.pem" = tls_private_key.kubernetes_admin_client.private_key_pem
    "admin.pem" = tls_locally_signed_cert.kubernetes_admin_client.cert_pem
    "ca.pem" = tls_self_signed_cert.kubernetes.cert_pem
    "ca-key.pem" = tls_private_key.kubernetes_ca.private_key_pem
    "service-account.pem" = tls_locally_signed_cert.kubernetes_service_accounts.cert_pem
    "service-account-key.pem" = tls_private_key.kubernetes_service_accounts.private_key_pem
    "kubernetes.pem" = tls_locally_signed_cert.kubernetes_api_server.cert_pem
    "kubernetes-key.pem" = tls_private_key.kubernetes_api_server.private_key_pem
  }
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/${each.key}"
  content = each.value
}

# Convert all worker-specific keys and certs
resource "aws_s3_object" "kubernetes_worker_keys" {
  for_each = { for idx, instance in aws_instance.kubernetes_worker : instance.tags["Name"] => idx }
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/${each.key}-key.pem"
  content = tls_private_key.kubernetes_kubelet_client[each.value].private_key_pem
}

resource "aws_s3_object" "kubernetes_worker_certs" {
  for_each = { for idx, instance in aws_instance.kubernetes_worker : instance.tags["Name"] => idx }
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/${each.key}.pem"
  content = tls_locally_signed_cert.kubernetes_kubelet_client[each.value].cert_pem
}

# Convert kubeconfig files
resource "aws_s3_object" "kubernetes_kubeconfigs" {
  for_each = {
    "admin.kubeconfig" = <<EOT
apiVersion: v1
kind: Config
clusters:
- name: kubernetes-the-hard-way
  cluster:
    server: https://${aws_lb.kubernetes.dns_name}:${aws_lb_listener.kubernetes.port}
    certificate-authority-data: ${base64encode(tls_self_signed_cert.kubernetes.cert_pem)}
users:
- name: admin
  user:
    client-certificate-data: ${base64encode(tls_locally_signed_cert.kubernetes_admin_client.cert_pem)}
    client-key-data: ${base64encode(tls_private_key.kubernetes_admin_client.private_key_pem)}
contexts:
- name: default
  context:
    cluster: kubernetes-the-hard-way
    user: admin
current-context: default
EOT
    "kube-controller-manager.kubeconfig" = <<EOT
apiVersion: v1
kind: Config
clusters:
- name: kubernetes-the-hard-way
  cluster:
    server: https://${aws_lb.kubernetes.dns_name}:${aws_lb_listener.kubernetes.port}
    certificate-authority-data: ${base64encode(tls_self_signed_cert.kubernetes.cert_pem)}
users:
- name: system:kube-controller-manager
  user:
    client-certificate-data: ${base64encode(tls_locally_signed_cert.kubernetes_controller_manager_client.cert_pem)}
    client-key-data: ${base64encode(tls_private_key.kubernetes_controller_manager_client.private_key_pem)}
contexts:
- name: default
  context:
    cluster: kubernetes-the-hard-way
    user: system:kube-controller-manager
current-context: default
EOT
  }
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/${each.key}"
  content = each.value
}

# Convert service configuration files
resource "aws_s3_object" "kubernetes_services" {
  for_each = {
    "kube-apiserver.service" = "...full apiserver service config..."
    "kube-controller-manager.service" = "...full controller manager service config..."
    "kube-scheduler.service" = "...full scheduler service config..."
  }
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/${each.key}"
  content = each.value
}

resource "aws_s3_object" "kubernetes_kube_proxy_key_pem" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/kube-proxy-key.pem"
  content = tls_private_key.kubernetes_kube_proxy_client.private_key_pem
}

resource "aws_s3_object" "kubernetes_controller_manager_key_pem" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/kube-controller-manager-key.pem"
  content = tls_private_key.kubernetes_controller_manager_client.private_key_pem
}

resource "aws_s3_object" "kubernetes_controller_manager_pem" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/kube-controller-manager.pem"
  content = tls_locally_signed_cert.kubernetes_controller_manager_client.cert_pem
}

resource "aws_s3_object" "workers_host_file" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/workers.host"
  content = join("\n", local.kubernetes_worker_host_entries)
}

resource "aws_s3_object" "kubernetes_kube_scheduler_pem" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/kube-scheduler.pem"
  content = tls_locally_signed_cert.kubernetes_kube_scheduler_client.cert_pem
}

resource "aws_s3_object" "kubernetes_kube_scheduler_key_pem" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/kube-scheduler-key.pem"
  content = tls_private_key.kubernetes_kube_scheduler_client.private_key_pem
}

resource "aws_s3_object" "kubernetes_kube_proxy_pem" {
  bucket  = aws_s3_bucket.kubernetes_cluster_automated.id
  key     = "${var.s3_ansible_path}/kube-proxy.pem"
  content = tls_locally_signed_cert.kubernetes_kube_proxy_client.cert_pem
}
