variable "cloud_type" {
  description = "Cloud provider to use (e.g., aws, virtual box)"
  type        = string
  default     = "aws"
}

variable "network_name" {
  description = "The name of the network (VPC, Vnet, etc.)"
  type        = string
  default     = "kubernetes-cluster-automated"
}

variable "network_cidr" {
  description = "CIDR block for the overall network (VPC in AWS/GCP, VNet in Azure). Not used for VirtualBox."
  type        = string
  default     = "10.0.0.0/16"
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

variable "virtualbox_adapter" {
  description = "VirtualBox network adapter type."
  type        = string
  default     = "host-only"
}
