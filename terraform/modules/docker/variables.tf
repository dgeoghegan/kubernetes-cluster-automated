variable "cloud_type" {
  description = "Cloud provider to use (e.g., aws, virtual box)"
  type        = string
  default     = "aws"
}

variable "cluster_index" {
  description = "A unique index for this cluster (0, 1, 2, etc.), used to derive network CIDRs."
  type        = number
  default     = 0
}

variable "storage_name" {
  description = "The name of the storage resource (e.g., S3 bucket name, local folder)"
  type        = string
  default     = "kubernetes-cluster-automated"
}

variable "region" {
  description = "The cloud region where the infrastructure is deployed."
  type        = string
  default     = "us-east-1"
}

variable "docker_instance_type" {
  description = "The instance type to use for docker vm"
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR of this cluster's VPC"
  default     = null
}

variable "subnet" {
  description = "List of subnets in VPC"
  default     = null
}

variable "security_group_id" {
  description = "List of security groups in cluster"
  default     = null
}

variable "profile_id" {
  description = "ID of security profile, e.g., AWS iam instance profile"
  default     = null
}

variable "vpc_id" {
  description = "ID of this cluster's VPC"
  default     = null
}
