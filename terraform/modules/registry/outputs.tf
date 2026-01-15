output "registry_user" {
  value = local.registry_user
}
output "registry_ready" {
  value = docker_container.container_registry.id
}
