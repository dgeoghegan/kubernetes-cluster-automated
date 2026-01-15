output "docker_server_public_ip" {
  value = module.docker.docker_server_public_ip
}

output "private_key_pem" {
  value     = module.certificate_authority.private_key_pem
  sensitive = true
}

output "cert_pem" {
  value     = module.certificate_authority.cert_pem
  sensitive = true
}

output "service_cidr" {
  value = local.service_cidr
}
