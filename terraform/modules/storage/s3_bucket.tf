resource "aws_s3_bucket" "storage" {
  count   = var.backend_type == "s3" ? 1 : 0       
  bucket  = var.storage_name
}

