output "playbook_contents_file_hash" {
  value = local.playbook_contents_file_hash
}
output "playbooks_applied" {
  value = null_resource.run_playbooks.id
}
