output "flattened_kubernetes_file_contents" {
  value = local.flattened_kubernetes_file_contents
}

output "k8s_files_hash" {
  value = sha1(jsonencode(local.flattened_kubernetes_file_contents))
}
