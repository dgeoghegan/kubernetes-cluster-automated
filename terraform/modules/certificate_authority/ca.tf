
// *************************************************************************
// ****  CERTIFICATE AUTHORITY *********************************************
// *************************************************************************

resource "tls_private_key" "ca" {
  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem   = tls_private_key.ca.private_key_pem
  is_ca_certificate = true

  subject {
    common_name         = var.network_name
    country             = "US"
    locality            = "Boston"
    organization        = var.network_name
    organizational_unit = "CA"
    province            = "Massachusetts"
  }

  validity_period_hours = 8760

  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "server_auth",
    "client_auth",
    ]
}


