variable "cloud_type" {
  type        = string
  description = "The cloud provider to use (e.g., aws, gcp, azure)."
  default     = "aws"
}

variable "controller_max" {
  type        = number
  description = "The maximum number of Kubernetes control plane instances to create."
  default     = 3
}

variable "worker_max" {
  type        = number
  description = "The maximum number of Kubernetes worker nodes to create."
  default     = 3
}

variable "ha_enabled" {
  type        = bool
  description = "Whether to enable high availability mode for the Kubernetes control plane."
  default     = true
}

variable "network_name" {
  type        = string
  description = "A base name to use for network-related resources (VPCs, security groups, etc)."
  default     = "kubernetes-cluster"
}

variable "instance_type" {
  type        = string
  description = "The instance type for the controllers and workers"
  default     = "t3.micro"
}

variable "backend_type" {
  type        = string
  description = "The storage backend to use (currently just 's3')"
  default     = "s3"
}

variable "cluster_index" {
  type        = number
  description = "A unique index for this cluster (0, 1, 2, etc.), used to derive network names and CIDRs."
  default     = 0
}

variable "aws_credentials_file" {
  description = "Path to an AWS credentials file"
  type        = string
}

variable "pod_cidr" {
  description = "IP range for pods in this cluster"
  type        = string
  default     = "172.16.0.0/18"
}
variable "kubernetes_version" {
  type        = string
  description = "Unused in infrastructure; passed through env.tfvars"
  default     = null
}
variable "coredns_version" {
  type          = string
  description = "Unused in infrastructure; passed through env.tfvars"
  default     = null
}
    
