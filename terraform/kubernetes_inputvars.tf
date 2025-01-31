variable "kubernetes_cidrblock_start" {
  
  type = string
  default = "10.0.0.0"
  description = "Starting IP of kubernetes cidr block, like \"10.0.0.0\""

}

variable "ansible_file_path_override" {
  type = string
  default = ""
  description = "Full path for files created for ansible. Defaults to $${path.module}/../ansible/files_from_terraform"
}
