variable "backend_type" {
  description = "The storage backend to use (currently just 's3')"
  type        = string
  default     = "s3"
}

variable "storage_name" {
  description = "The name of the storage resource (e.g., S3 bucket name, local folder)"
  type        = string
  default     = "kubernetes-cluster-automated"
}

variable "files" {
  type        = map(string)
  description = "Files to be stored"
  default     = {}
}
