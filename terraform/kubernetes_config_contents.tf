locals {
    kubernetes_inventory_ini_contents = <<EOT
[kubernetes_workers]
%{for instance in local.kubernetes_worker_network_info}
${instance.name} ansible_host=${instance.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/ansible/files_from_terraform/kubernetes_ssh_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{endfor}

[kubernetes_controllers]
%{for instance in local.kubernetes_controller_network_info}
${instance.name} ansible_host=${instance.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/ansible/files_from_terraform/kubernetes_ssh_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{endfor}
EOT

  #################
  # Common Configs (Cluster-wide)
  #################
  common_config_contents = {
    "ca.pem"                      = tls_self_signed_cert.kubernetes.cert_pem
    "ca-key.pem"                  = tls_private_key.kubernetes_ca.private_key_pem
    "admin.pem"                   = tls_locally_signed_cert.kubernetes_admin_client.cert_pem
    "admin-key.pem"               = tls_private_key.kubernetes_admin_client.private_key_pem
    "service-account.pem"         = tls_locally_signed_cert.kubernetes_service_accounts.cert_pem
    "service-account-key.pem"     = tls_private_key.kubernetes_service_accounts.private_key_pem
    "kubernetes.pem"              = tls_locally_signed_cert.kubernetes_api_server.cert_pem
    "kubernetes-key.pem"          = tls_private_key.kubernetes_api_server.private_key_pem
    "kube-proxy.pem"              = tls_locally_signed_cert.kubernetes_kube_proxy_client.cert_pem
    "kube-proxy-key.pem"          = tls_private_key.kubernetes_kube_proxy_client.private_key_pem
    "kube-controller-manager.pem" = tls_locally_signed_cert.kubernetes_controller_manager_client.cert_pem
    "kube-controller-manager-key.pem" = tls_private_key.kubernetes_controller_manager_client.private_key_pem
    "kube-scheduler.pem"          = tls_locally_signed_cert.kubernetes_kube_scheduler_client.cert_pem
    "kube-scheduler-key.pem"      = tls_private_key.kubernetes_kube_scheduler_client.private_key_pem
    "encryption-config.yaml"      = <<EOT
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
          - name: key1
            secret: ${random_bytes.kubernetes_encryption_key.base64}
    - identity: {}
EOT
    "kube_scheduler_service" = <<EOT
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \
  --config=/etc/kubernetes/config/kube-scheduler.yaml \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
    "kube_scheduler_kubeconfig" = <<EOT
apiVersion: v1
kind: Config

clusters:
- name: kubernetes-the-hard-way
  cluster:
    server: https://${aws_lb.kubernetes.dns_name}:${aws_lb_listener.kubernetes.port}
    certificate-authority-data: ${base64encode(tls_self_signed_cert.kubernetes.cert_pem)}

users:
- name: system:kube-scheduler
  user:
    client-certificate-data: ${base64encode(tls_locally_signed_cert.kubernetes_kube_scheduler_client.cert_pem)}
    client-key-data: ${base64encode(tls_private_key.kubernetes_kube_scheduler_client.private_key_pem)}

contexts:
- name: default
  context:
    cluster: kubernetes-the-hard-way
    user: system:kube-scheduler
    
current-context: default
EOT
  }

  ############################
  # Per-Worker Certificates & Kubeconfigs
  ############################
  per_worker_configs = {
    for idx, worker in aws_instance.kubernetes_worker : worker.tags["Name"] => {
      "key_pem"     = tls_private_key.kubernetes_kubelet_client[idx].private_key_pem
      "cert_pem"    = tls_locally_signed_cert.kubernetes_kubelet_client[idx].cert_pem
      "kubeconfig"  = <<EOT
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${aws_lb.kubernetes.dns_name}:${aws_lb_listener.kubernetes.port}
    certificate-authority-data: ${base64encode(tls_self_signed_cert.kubernetes.cert_pem)}
  name: kubernetes-the-hard-way
users:
- name: system:node:${worker.tags["Name"]}
  user:
    client-certificate-data: ${base64encode(tls_locally_signed_cert.kubernetes_kubelet_client[idx].cert_pem)}
    client-key-data: ${base64encode(tls_private_key.kubernetes_kubelet_client[idx].private_key_pem)}
contexts:
- name: default
  context:
    cluster: kubernetes-the-hard-way
    user: system:node:${worker.tags["Name"]}
current-context: default
EOT
    }
  }

  ############################
  # Per-Controller Configs
  ############################
  per_controller_configs = {
    for idx, controller in aws_instance.kubernetes_controller : controller.tags["Name"] => {
      "kube_apiserver_service" = <<EOT
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=${controller.private_ip} \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/var/lib/kubernetes/ca.pem \
  --etcd-servers=https://${controller.private_ip}:2379 \
  --service-cluster-ip-range=10.32.0.0/24 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT

      "etcd_service" = <<EOT
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \
  --name=${controller.tags["Name"]} \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --listen-client-urls https://${controller.private_ip}:2379 \
  --advertise-client-urls https://${controller.private_ip}:2379 \
  --initial-cluster ${join(",", [for ctrl in aws_instance.kubernetes_controller : "${ctrl.tags["Name"]}=https://${ctrl.private_ip}:2380"])} \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT

      "kube_controller_manager_kubeconfig" = <<EOT
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
  }
}
