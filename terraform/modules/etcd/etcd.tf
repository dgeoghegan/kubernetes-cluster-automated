resource "local_file" "kubernetes_etcd_service" {
  count = length(aws_instance.kubernetes_controller)
  filename = "${local.ansible_file_path}/etcd.service${local.kubernetes_controller_network_info[count.index].name}"
  content = <<EOT
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \
  --name=${local.kubernetes_controller_network_info[count.index].name} \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --initial-advertise-peer-urls https://${local.kubernetes_controller_network_info[count.index].private_ip}:2380 \
  --listen-peer-urls https://${local.kubernetes_controller_network_info[count.index].private_ip}:2380 \
  --listen-client-urls https://${local.kubernetes_controller_network_info[count.index].private_ip}:2379,https://127.0.0.1:2379 \
  --advertise-client-urls https://${local.kubernetes_controller_network_info[count.index].private_ip}:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster ${local.kubernetes_initial_cluster} \
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
}
