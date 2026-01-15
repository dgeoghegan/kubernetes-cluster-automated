output "flattened_kubernetes_file_contents" {
  value = local.flattened_kubernetes_file_contents
}

output "k8s_files_hash" {
  value = nonsensitive(sha1(jsonencode(local.flattened_kubernetes_file_contents)))
#  value = sha1(jsonencode([
#    for path, content in local.flattened_kubernetes_file_contents :
#    {
#      path    = path
#      length  = length(content)
#    }
#  ]))
}

output "controller_private_ips" {
  value = aws_instance.kubernetes_controller[*].private_ip
}
