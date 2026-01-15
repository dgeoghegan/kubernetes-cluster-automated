variable "registry_pass" {
  description = "Password for registry auth"
  type        = string
}

variable "docker_server_public_ip" {
  description = "Public IP for docker server"
  type        = string
}

variable "network_name" {
  description = "The name of the network (VPC, Vnet, etc.)"
  type        = string
  default     = "kubernetes-cluster-automated"
}
