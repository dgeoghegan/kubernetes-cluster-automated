output "kubectl_image_remote" {
  value = local.kubectl_image_remote
}
output "manifests_applied" {
  value = null_resource.run_manifests.id
}
