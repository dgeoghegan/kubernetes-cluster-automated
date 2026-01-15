variable "ansible_dockerfile_path" {
  type        = string
  description = "Absolute path to Ansible Dockerfile"
  default     = "../../../../ansible/ubuntu-ansible.dockerfile"
}

variable "kubectl_dockerfile_path" {
  type        = string
  description = "Absolute path to Ansible Dockerfile"
  default     = "../../../../kubectl/kubectl-container.dockerfile"
}

variable "helm_dockerfile_path" {
  type        = string
  description = "Absolute path to Helm Dockerfile"
  default     = "../../../../helm/helm-runner.dockerfile"
}

variable "playbooks_dir" {
  type        = string
  description = "Absolute path to Ansible playbooks directory"
  default     = "../../../../ansible/playbooks"
}

variable "manifests_dir" {
  type        = string
  description = "Absolute path to Kubernetes manifests directory"
  default     = "../../../../kubectl/manifests"
}

variable "static_configs_dir" {
  type        = string
  description = "Absolute path to Ansible static_files directory"
  default     = "../../../../ansible/static_configs"
}

variable "charts_dir" {
  type        = string
  description = "Absolute path to Helm charts directory"
  default     = "../../../../helm/charts"
}

# The following are variables used by the infrastructure root
# They are included here to avoid warnings when using a common env.tfvars

variable "cloud_type" {
  type        = string
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "controller_max" {
  type        = number
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "worker_max" {
  type        = number
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "ha_enabled" {
  type        = bool
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "network_name" {
  type        = string
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "instance_type" {
  type        = string
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "backend_type" {
  type        = string
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "cluster_index" {
  type        = number
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "aws_credentials_file" {
  type        = string
  description = "Unused in services; passed through env.tfvars"
  default     = null
}
variable "kubernetes_version" {
  type        = string
  description = "K8s version in format 'x.y.z'"
  default     = "1.34.2"
}
variable "coredns_version" {
  type          = string
  description   = "CoreDNS version in format 'x.y.z'"
  default       = "1.45.0"
}
variable "helm_version" {
  type          = string
  description   = "Helm version in format 'x.y.z'"
  default       = "4.0.0"
}
variable "docker_ssh_key_path" {
  type          = string
  description   = "Docker SSH key path"
  default       = "../../infra/root/files_from_terraform/docker_ssh_key"
}
