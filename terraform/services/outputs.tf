output "playbook_contents_file_hash" {
  value = module.ansible_runner.playbook_contents_file_hash
}

output "registry_address" {
  value = local.registry_address
}

output "registry_user" {
  value = module.registry.registry_user
}

output "registry_pass" {
  value     = random_password.registry_pass.result
  sensitive = true
}

output "kubectl_image_remote" {
  value = module.kubectl_runner.kubectl_image_remote
}
