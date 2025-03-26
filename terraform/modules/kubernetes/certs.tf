// *************************************************************************
// ****  ADMIN CLIENT CERTIFICATE ******************************************
// *************************************************************************

resource "tls_private_key" "kubernetes_admin_client" {

  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_cert_request" "kubernetes_admin_client" {
  private_key_pem   = tls_private_key.kubernetes_admin_client.private_key_pem

  subject {
    common_name         = "admin"
    country             = "US"
    locality            = "Boston"
    organization        = "system:masters"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Massachusetts"
  }
}

resource "tls_locally_signed_cert" "kubernetes_admin_client" {
  cert_request_pem      = tls_cert_request.kubernetes_admin_client.cert_request_pem
  ca_private_key_pem    = var.private_key_pem
  ca_cert_pem           = var.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "client_auth",
    ]
}

// *************************************************************************
// ****  KUBELET CLIENT CERTIFICATES ***************************************
// *************************************************************************

resource "tls_private_key" "kubernetes_kubelet_client" {
  count = length(local.kubernetes_worker_private_dns)
  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_cert_request" "kubernetes_kubelet_client" {
  count = length(local.kubernetes_worker_private_dns)
  private_key_pem   = tls_private_key.kubernetes_kubelet_client[count.index].private_key_pem

  subject {
    common_name         = "system:nodes:${local.kubernetes_worker_private_dns[count.index]}"
    country             = "US"
    locality            = "Boston"
    organization        = "system:nodes"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Massachusetts"
  }

  dns_names = [
  local.kubernetes_worker_private_dns[count.index],
  ]

  ip_addresses = [
  local.kubernetes_worker_private_ip[count.index],
  local.kubernetes_worker_public_ip[count.index],
  ]
}

resource "tls_locally_signed_cert" "kubernetes_kubelet_client" {
  count = length(tls_cert_request.kubernetes_kubelet_client)
  cert_request_pem      = tls_cert_request.kubernetes_kubelet_client[count.index].cert_request_pem
  ca_private_key_pem    = var.private_key_pem
  ca_cert_pem           = var.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "client_auth",
    ]
}

// *************************************************************************
// **** CONTROLLER MANAGER CLIENT CERTIFICATE ******************************
// *************************************************************************


resource "tls_private_key" "kubernetes_controller_manager_client" {

  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_cert_request" "kubernetes_controller_manager_client" {
    
  private_key_pem   = tls_private_key.kubernetes_controller_manager_client.private_key_pem

  subject {
    common_name         = "system:kube-controller-manager"
    country             = "US"
    locality            = "Boston"
    organization        = "system:kube-controller-manager"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Massachusetts"
  }
}

resource "tls_locally_signed_cert" "kubernetes_controller_manager_client" {
  cert_request_pem      = tls_cert_request.kubernetes_controller_manager_client.cert_request_pem
  ca_private_key_pem    = var.private_key_pem
  ca_cert_pem           = var.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "client_auth",
    ]
}

// *************************************************************************
// **** KUBE PROXY CLIENT CERTIFICATE **************************************
// *************************************************************************


resource "tls_private_key" "kubernetes_kube_proxy_client" {

  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_cert_request" "kubernetes_kube_proxy_client" {
    
  private_key_pem   = tls_private_key.kubernetes_kube_proxy_client.private_key_pem

  subject {
    common_name         = "system:kube-proxy"
    country             = "US"
    locality            = "Boston"
    organization        = "system:kube-proxier"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Massachusetts"
  }
}

resource "tls_locally_signed_cert" "kubernetes_kube_proxy_client" {
  cert_request_pem      = tls_cert_request.kubernetes_kube_proxy_client.cert_request_pem
  ca_private_key_pem    = var.private_key_pem
  ca_cert_pem           = var.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "client_auth",
    ]
}

// *************************************************************************
// **** SCHEDULER CLIENT CERTIFICATE ***************************************
// *************************************************************************


resource "tls_private_key" "kubernetes_kube_scheduler_client" {

  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_cert_request" "kubernetes_kube_scheduler_client" {
    
  private_key_pem   = tls_private_key.kubernetes_kube_scheduler_client.private_key_pem

  subject {
    common_name         = "system:kube-scheduler"
    country             = "US"
    locality            = "Boston"
    organization        = "system:kube-scheduler"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Massachusetts"
  }
}

resource "tls_locally_signed_cert" "kubernetes_kube_scheduler_client" {
  cert_request_pem      = tls_cert_request.kubernetes_kube_scheduler_client.cert_request_pem
  ca_private_key_pem    = var.private_key_pem
  ca_cert_pem           = var.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "client_auth",
    ]
}

// *************************************************************************
// **** API SERVER CERTIFICATE *********************************************
// *************************************************************************


resource "tls_private_key" "kubernetes_api_server" {

  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_cert_request" "kubernetes_api_server" {
    
  private_key_pem   = tls_private_key.kubernetes_api_server.private_key_pem

  subject {
    common_name         = "Kubernetes"
    country             = "US"
    locality            = "Boston"
    organization        = "Kubernetes"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Massachusetts"
  }
  
  dns_names = [
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.svc.cluster.local",
    var.load_balancer_dns_name
  ]
  ip_addresses = flatten([
    ["127.0.0.1"],
    [for controller in local.kubernetes_controller_network_info : controller.private_ip]
  ])
}

resource "tls_locally_signed_cert" "kubernetes_api_server" {
  cert_request_pem      = tls_cert_request.kubernetes_api_server.cert_request_pem
  ca_private_key_pem    = var.private_key_pem
  ca_cert_pem           = var.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "client_auth",
    "server_auth",
    "key_encipherment",
    "digital_signature"
    ]
}

// *************************************************************************
// **** SERVICE ACCOUNT KEY PAIR *******************************************
// *************************************************************************


resource "tls_private_key" "kubernetes_service_accounts" {

  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_cert_request" "kubernetes_service_accounts" {
    
  private_key_pem   = tls_private_key.kubernetes_service_accounts.private_key_pem

  subject {
    common_name         = "service-accounts"
    country             = "US"
    locality            = "Boston"
    organization        = "service-accounts"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Massachusetts"
  }
}

resource "tls_locally_signed_cert" "kubernetes_service_accounts" {
  cert_request_pem      = tls_cert_request.kubernetes_service_accounts.cert_request_pem
  ca_private_key_pem    = var.private_key_pem
  ca_cert_pem           = var.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "client_auth",
    ]
}
