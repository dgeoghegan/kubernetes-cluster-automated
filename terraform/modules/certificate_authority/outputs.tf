output "cert_pem" {
  value     = tls_self_signed_cert.ca.cert_pem
  sensitive = true
}

output "private_key_pem" {
  value     = tls_private_key.ca.private_key_pem
  sensitive = true
}
