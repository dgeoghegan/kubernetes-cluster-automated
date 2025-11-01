locals {
  s3_iam_role_name = var.backend_type == "s3" ? "${var.storage_name}-s3-access" : null
}

data "aws_s3_bucket" "existing" {
  count = var.cloud_type == "aws" && var.backend_type == "s3" ? 1 : 0
  bucket = var.storage_id
}

resource "aws_iam_role" "kubernetes_s3_access" {
  count = var.cloud_type == "aws" && var.backend_type == "s3" ? 1 : 0
  name = local.s3_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

data "aws_caller_identity" "current" {
  count = var.cloud_type == "aws" && var.backend_type == "s3" ? 1 : 0
  }

### ✅ IAM Policy

resource "aws_iam_role_policy" "s3_real_only" {
  count = var.cloud_type == "aws" && var.backend_type == "s3" ? 1 : 0
  name  = "${var.storage_name}-s3-readonly"
  role  = aws_iam_role.kubernetes_s3_access[0].name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:GetEncryptionConfiguration"
      ],
      Resource = [
        "arn:aws:s3:::${var.storage_name}",
        "arn:aws:s3:::${var.storage_name}/*"
      ]
    }]
  })
}

resource "aws_s3_bucket_public_access_block" "kubernetes_cluster_automated" {
  count = var.cloud_type == "aws" && var.backend_type == "s3" ? 1 : 0
  bucket                  = var.storage_id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kubernetes_cluster_automated" {
  count = var.cloud_type == "aws" && var.backend_type == "s3" ? 1 : 0
  bucket = var.storage_id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_instance_profile" "kubernetes_s3_access_profile" {
  count = var.cloud_type == "aws" && var.backend_type == "s3" ? 1 : 0
  name = "${local.s3_iam_role_name}-profile"
  role = aws_iam_role.kubernetes_s3_access[0].name
}
