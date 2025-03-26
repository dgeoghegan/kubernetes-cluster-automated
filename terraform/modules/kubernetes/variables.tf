variable "cloud_type" {
  description = "Cloud provider to use (e.g., aws, virtual box)"
  type        = string
  default     = "aws"
}

variable "load_balancer_dns_name" {
  description = "DNS name of load balancer"
  type        = string
}

variable "cluster_index" {
  description = "A unique index for this cluster (0, 1, 2, etc.), used to derive network CIDRs."
  type        = number
  default     = 0
}

variable "controller_max" { 
  description = "Maximum number of Kubernetes control plane instances."
  type        = number
  default     = 3

  validation {
    condition = (
      (var.ha_enabled && var.controller_max >= 3 && var.controller_max % 2 == 1) ||
      (!var.ha_enabled && var.controller_max >= 1 && var.controller_max % 2 == 1)
    )
    error_message = "If HA is enabled, controller_max must be an odd number >= 3. If HA is disabled, it must be an odd number >= 1."
  }
}

variable "worker_max" {
  description = "Maximum number of Kubernetes worker instances."
  type        = number
  default     = 3
}

variable "region" {
  description = "The cloud region where the infrastructure is deployed."
  type        = string
  default     = "us-east-1"
}

variable "ha_enabled" {
  description = "Enable HA mode (distributes controllers and workers across zones)."
  type        = bool
  default     = true
}

variable "private_key_pem" {
  description = "private_key_pem from certificate_authority module"
}

variable "cert_pem" {
  description = "cert_pem from certificate_authority module"
}

variable "instance_type" {
  description = "instance type to use for workers and controllers" 
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR of this cluster's VPC"
}

variable "service_cidr" {
  description = "IP range for service cluster"
  type        = string
  default     = "192.168.0.0/22"
}

variable "pod_cidr_cluster" {
  description = "IP range for all pod_cidr in this cluster"
  type        = string
  default     = "172.16.0.0/18"
}


variable "subnet" {
  description = "List of subnets in VPC"
}

variable "security_group_id" {
  description = "List of security groups in cluster"
}
