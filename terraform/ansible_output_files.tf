resource "local_file" "kubernetes_hosts" {
  filename = "${local.ansible_file_path}/inventory.ini"
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

resource "local_file" "kubernetes_admin_key_pem" {
  filename = "${local.ansible_file_path}/admin-key.pem"
  content = tls_private_key.kubernetes_admin_client.private_key_pem
}

resource "local_file" "kubernetes_admin_pem" {
  filename = "${local.ansible_file_path}/admin.pem"
  content = tls_locally_signed_cert.kubernetes_admin_client.cert_pem
}

resource "local_file" "kubernetes_kubelet_client_key_pem" {
  count = length(aws_instance.kubernetes_worker)
  filename = "${local.ansible_file_path}/${aws_instance.kubernetes_worker[count.index].tags["Name"]}-key.pem"
  content = tls_private_key.kubernetes_kubelet_client[count.index].private_key_pem
}

resource "local_file" "kubernetes_kubelet_client_pem" {
  count = length(aws_instance.kubernetes_worker)
  filename = "${local.ansible_file_path}/${aws_instance.kubernetes_worker[count.index].tags["Name"]}.pem"
  content = tls_locally_signed_cert.kubernetes_kubelet_client[count.index].cert_pem
}

resource "local_file" "kubernetes_controller_manager_key_pem" {
  filename = "${local.ansible_file_path}/kube-controller-manager-key.pem"
  content = tls_private_key.kubernetes_controller_manager_client.private_key_pem
}

resource "local_file" "kubernetes_controller_manager_pem" {
  filename = "${local.ansible_file_path}/kube-controller-manager.pem"
  content = tls_locally_signed_cert.kubernetes_controller_manager_client.cert_pem
}

resource "local_file" "kubernetes_kube_proxy_key_pem" {
  filename = "${local.ansible_file_path}/kube-proxy-key.pem"
  content = tls_private_key.kubernetes_kube_proxy_client.private_key_pem
}

resource "local_file" "kubernetes_kube_proxy_pem" {
  filename = "${local.ansible_file_path}/kube-proxy.pem"
  content = tls_locally_signed_cert.kubernetes_kube_proxy_client.cert_pem
}

resource "local_file" "kubernetes_kube_scheduler_key_pem" {
  filename = "${local.ansible_file_path}/kube-scheduler-key.pem"
  content = tls_private_key.kubernetes_kube_scheduler_client.private_key_pem
}

resource "local_file" "kubernetes_kube_scheduler_pem" {
  filename = "${local.ansible_file_path}/kube-scheduler.pem"
  content = tls_locally_signed_cert.kubernetes_kube_scheduler_client.cert_pem
}

resource "local_file" "kubernetes_api_server_key_pem" {
  filename = "${local.ansible_file_path}/kubernetes-key.pem"
  content = tls_private_key.kubernetes_api_server.private_key_pem
}

resource "local_file" "kubernetes_api_server_pem" {
  filename = "${local.ansible_file_path}/kubernetes.pem"
  content = tls_locally_signed_cert.kubernetes_api_server.cert_pem
}

resource "local_file" "kubernetes_service_accounts_key_pem" {
  filename = "${local.ansible_file_path}/service-account-key.pem"
  content = tls_private_key.kubernetes_service_accounts.private_key_pem
}

resource "local_file" "kubernetes_service_accounts_pem" {
  filename = "${local.ansible_file_path}/service-account.pem"
  content = tls_locally_signed_cert.kubernetes_service_accounts.cert_pem
}

resource "local_file" "kubernetes_ca_pem" {
  filename = "${local.ansible_file_path}/ca.pem"
  content = tls_self_signed_cert.kubernetes.cert_pem
}

resource "local_file" "kubernetes_ca_key_pem" {
  filename = "${local.ansible_file_path}/ca-key.pem"
  content = tls_private_key.kubernetes_ca.private_key_pem
}

resource "local_file" "kubernetes_worker_kubeconfig" {
  count = length(aws_instance.kubernetes_worker)
  filename = "${local.ansible_file_path}/${aws_instance.kubernetes_worker[count.index].tags.Name}.kubeconfig"
  content = <<EOT
apiVersion: v1
kind: Config

clusters:
- cluster:
    server: https://${aws_lb.kubernetes.dns_name}:${aws_lb_listener.kubernetes.port}
    certificate-authority-data: ${base64encode(tls_self_signed_cert.kubernetes.cert_pem)}
  name: kubernetes-the-hard-way

users:
- name: system:node:${local.kubernetes_worker_network_info[count.index].name}
  user:
    client-certificate-data: ${base64encode(tls_locally_signed_cert.kubernetes_kubelet_client[count.index].cert_pem)}
    client-key-data: ${base64encode(tls_private_key.kubernetes_kubelet_client[count.index].private_key_pem)}

contexts:
- name: default
  context:
    cluster: kubernetes-the-hard-way
    user: system:node:${local.kubernetes_worker_network_info[count.index].name}
    
current-context: default
EOT
}

resource "local_file" "kubernetes_kube_proxy_kubeconfig" {
  filename = "${local.ansible_file_path}/kube-proxy.kubeconfig"
  content = <<EOT
apiVersion: v1
kind: Config

clusters:
- name: kubernetes-the-hard-way
  cluster:
    server: https://${aws_lb.kubernetes.dns_name}:${aws_lb_listener.kubernetes.port}
    certificate-authority-data: ${base64encode(tls_self_signed_cert.kubernetes.cert_pem)}

users:
- name: system:kube-proxy
  user:
    client-certificate-data: ${base64encode(tls_locally_signed_cert.kubernetes_kube_proxy_client.cert_pem)}
    client-key-data: ${base64encode(tls_private_key.kubernetes_kube_proxy_client.private_key_pem)}

contexts:
- name: default
  context:
    cluster: kubernetes-the-hard-way
    user: system:kube-proxy
    
current-context: default
EOT
}

resource "local_file" "kubernetes_controller_manager_kubeconfig" {
  filename = "${local.ansible_file_path}/kube-controller-manager.kubeconfig"
  content = <<EOT
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

resource "local_file" "kubernetes_kube_scheduler_kubeconfig" {
  filename = "${local.ansible_file_path}/kube-scheduler.kubeconfig"
  content = <<EOT
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

resource "local_file" "kubernetes_admin_kubeconfig" {
  filename = "${local.ansible_file_path}/admin.kubeconfig"
  content = <<EOT
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
}

resource "local_file" "kube_apiserver_service" {
  count = length(local.kubernetes_controller_network_info)
  filename = "${local.ansible_file_path}/kube-apiserver.service${local.kubernetes_controller_network_info[count.index].name}"
  content = <<EOT
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=${local.kubernetes_controller_network_info[count.index].private_ip} \
  --allow-privileged=true \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/audit.log \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/var/lib/kubernetes/ca.pem \
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \
  --etcd-servers=${join(",", [for controller in local.kubernetes_controller_network_info: "https://${controller.private_ip}:2379"])} \
  --event-ttl=1h \
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \
  --runtime-config='api/all=true' \
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-account-issuer=https://${aws_lb.kubernetes.dns_name}:443 \
  --service-cluster-ip-range=10.32.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
}

resource "local_file" "kube_controller_manager_service" {
  filename = "${local.ansible_file_path}/kube-controller-manager.service"
  content = <<EOT
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --bind-address=0.0.0.0 \
  --cluster-cidr=10.200.0.0/16 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --use-service-account-credentials=true \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
}

resource "local_file" "kube_scheduler_service" {
  filename = "${local.ansible_file_path}/kube-scheduler.service"
  content = <<EOT
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
}

resource "local_file" "kube_scheduler_yaml" {
  filename = "${local.ansible_file_path}/kube-scheduler.yaml"
  content = <<EOT
apiVersion: kubescheduler.config.k8s.io/v1beta1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOT
}

resource "local_file" "workers_host_file" {
  filename = "${local.ansible_file_path}/workers.host"
  content = join("\n", local.kubernetes_worker_host_entries)
}
