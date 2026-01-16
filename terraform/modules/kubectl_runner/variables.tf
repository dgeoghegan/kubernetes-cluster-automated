variable "kubectl_dockerfile_path" {
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

variable "manifests_dir" {
  description = "Absolute path to k8s manifests"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "service_cidr" {
  description = "IP range for service cluster"
  type        = string
  default     = "192.168.0.0/22"
}

variable "docker_ssh_key_path" {
  description = "Docker ssh key path"
  type        = string
}

variable "load_balancer_dns_name" {
  description = "DNS for load balancer"
  type        = string
}
