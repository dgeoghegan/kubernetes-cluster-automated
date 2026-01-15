locals {
    kubernetes_inventory_ini_contents = <<EOT
[kubernetes_workers]
%{for instance in local.kubernetes_worker_network_info}
${instance.name} ansible_host=${instance.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/ansible/common/kubernetes_ssh_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{endfor}

[kubernetes_controllers]
%{for instance in local.kubernetes_controller_network_info}
${instance.name} ansible_host=${instance.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/ansible/common/kubernetes_ssh_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{endfor}
EOT

  #################
  # Common Configs (Cluster-wide)
  #################
  common_configs = {
    "kubernetes_ssh_key"          = tls_private_key.kubernetes_ssh_key.private_key_pem
    "ca.pem"                      = var.cert_pem
    "ca-key.pem"                  = var.private_key_pem
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
    "kube_scheduler_yaml" = <<EOT
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOT
    "kube_scheduler_kubeconfig" = <<EOT
apiVersion: v1
kind: Config

clusters:
- name: kubernetes-the-hard-way
  cluster:
    server: https://${var.load_balancer_dns_name}:${var.load_balancer_listener_port}
    certificate-authority-data: ${base64encode(var.cert_pem)}

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
    "workers.host"                = <<EOT
%{for instance in local.kubernetes_worker_network_info}
${instance.private_ip} ${instance.private_dns} ${split(".", instance.private_dns)[0]} ${instance.name}
%{endfor}
EOT
    "kube_controller_manager_service" = <<EOT
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --bind-address=0.0.0.0 \
  --cluster-cidr=${var.pod_cidr} \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-cluster-ip-range=${var.service_cidr} \
  --use-service-account-credentials=true \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
    "kube_proxy_kubeconfig" = <<EOT
apiVersion: v1
kind: Config

clusters:
- name: kubernetes-the-hard-way
  cluster:
    server: https://${var.load_balancer_dns_name}:${var.load_balancer_listener_port}
    certificate-authority-data: ${base64encode(var.cert_pem)}

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
    "admin_kubeconfig" = <<EOT
apiVersion: v1
kind: Config

clusters:
- name: kubernetes-the-hard-way
  cluster:
    server: https://${var.load_balancer_dns_name}:${var.load_balancer_listener_port}
    certificate-authority-data: ${base64encode(var.cert_pem)}

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
    "kube-proxy-config.yaml" = <<EOT
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "${var.pod_cidr}"
EOT
  }

  ############################
  # Per-Worker Certificates & Kubeconfigs
  ############################
  per_worker_configs = {
    for idx, worker in aws_instance.kubernetes_worker : worker.tags["Name"] => {
      "key.pem"     = tls_private_key.kubernetes_kubelet_client[idx].private_key_pem
      "cert.pem"    = tls_locally_signed_cert.kubernetes_kubelet_client[idx].cert_pem
      "kubeconfig"  = <<EOT
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${var.load_balancer_dns_name}:${var.load_balancer_listener_port}
    certificate-authority-data: ${base64encode(var.cert_pem)}
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
    "10-bridge.conf" = <<EOT
{
    "cniVersion": "0.4.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${cidrsubnet(var.pod_cidr, 6, idx)}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOT
    "kubelet-config.yaml" = <<EOT
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "${cidrhost(var.service_cidr, 10)}"
podCIDR: "${cidrsubnet(var.pod_cidr, 6, idx)}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/cert.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/key.pem"
EOT
    "kubelet.service" = <<EOT
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \
  --config=/var/lib/kubelet/kubelet-config.yaml \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --hostname-override=${worker.tags["Name"]} \
  --register-node=true \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
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
  --api-audiences=api \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/var/lib/kubernetes/ca.pem \
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \
  --etcd-servers=${local.etcd_servers} \
  --event-ttl=1h \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \
  --runtime-config='api/all=true' \
  --service-account-issuer=https://${var.load_balancer_dns_name}:${var.load_balancer_listener_port} \
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-cluster-ip-range=${var.service_cidr} \
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
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --initial-advertise-peer-urls https://${controller.private_ip}:2380 \
  --listen-peer-urls https://${controller.private_ip}:2380 \
  --listen-client-urls https://${controller.private_ip}:2379,https://127.0.0.1:2379 \
  --advertise-client-urls https://${controller.private_ip}:2379 \
  --initial-cluster-token etcd-cluster-${var.cluster_index} \
  --initial-cluster ${join(",", [for ctrl in aws_instance.kubernetes_controller : "${ctrl.tags["Name"]}=https://${ctrl.private_ip}:2380"])} \
  --initial-cluster-state new \
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
    server: https://${var.load_balancer_dns_name}:${var.load_balancer_listener_port}
    certificate-authority-data: ${base64encode(var.cert_pem)}
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

  ############################
  # Flattened File Paths for Storage Upload
  ############################

  # Flatten per-worker configs into file path => content
  per_worker_configs_contents = merge([
    for worker_name, files in local.per_worker_configs : {
      for filename, content in files :
      "configs/worker/${worker_name}/${filename}" => content
    }
  ]...)

  # Flatten per-controller configs
  per_controller_configs_contents = merge([
    for controller_name, files in local.per_controller_configs : {
      for filename, content in files :
      "configs/controller/${controller_name}/${filename}" => content
    }
  ]...)

  # Flatten common files
  common_configs_contents = {
    for filename, content in local.common_configs:
    "common/${filename}" => content
  }

  # Flatten inventory file
  inventory_file_contents = {
    "ansible/inventory.ini" = local.kubernetes_inventory_ini_contents
  }

  # Final map to pass to S3
  flattened_kubernetes_file_contents = merge(
    local.common_configs_contents,
    local.per_worker_configs_contents,
    local.per_controller_configs_contents,
    local.inventory_file_contents
  )
}

# These files help local scripts ssh to hosts

resource "local_file" "kubernetes_ssh_key" {
  filename              = "${path.root}/files_from_terraform/kubernetes_ssh_key"
  content               = tls_private_key.kubernetes_ssh_key.private_key_pem
  file_permission       = "0400"
  directory_permission  = "0700"
}

resource "local_file" "inventory_ini" {
  filename              = "${path.root}/files_from_terraform/inventory.ini"
  content               = local.kubernetes_inventory_ini_contents
  file_permission       = "0400"
  directory_permission  = "0700"
}
