variable "ansible_dockerfile_path" {
  description = "Path to Ansible Dockerfile (absolute)"
  type        = string
}

variable "registry_address" {
  description = "host and port for registry (relative to docker-server)"
  type        = string
  default     = "127.0.0.1:5000"
}

variable "docker_server_public_ip" {
  description = "Public IP of the docker-server hosting registry"
  type        = string
}

variable "registry_pass" {
  description = "Password for registry"
  type        = string
}

variable "playbooks_dir" {
  description = "Absolute path to Ansible playbooks"
  type        = string
}

variable "static_configs_dir" {
  description = "Absolute path to Ansible files such as static configurations"
  type        = string
}
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "docker_ssh_key_path" {
  description = "Docker ssh key path"
  type        = string
}
