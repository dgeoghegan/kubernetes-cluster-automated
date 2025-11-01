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

variable "backend_type" {
  description = "The storage backend to use (currently just 's3')"
  type        = string
  default     = "s3"
}

variable "storage_name" {
  description = "The name of the storage resource (e.g., S3 bucket name, local folder)"
  type        = string
}

variable "storage_id" {
  description = "Identifier of storage, e.g., S3 bucket ID"
  type        = string
}
