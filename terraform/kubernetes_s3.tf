variable "s3_force_destroy" {
  type    = bool
  default = false # Set to TRUE if we want it deleted along with Terraform
}

variable "s3_bucket_name" {
  type    = string
  default = "kubernetes-cluster-automated"
}

locals {
  s3_iam_role_name = "${var.s3_bucket_name}-s3-access"
}

resource "aws_iam_role" "kubernetes_s3_access" {
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

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "kubernetes_cluster_automated" {
  bucket         = var.s3_bucket_name
  force_destroy = var.s3_force_destroy
}

### ✅ IAM Policy (Attach to Role)
resource "aws_iam_policy" "s3_read_only" {
  name        = "S3ReadOnly"
  description = "Allows read-only access to the S3 bucket"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:GetEncryptionConfiguration"
      ],
      Resource = [
        "arn:aws:s3:::${var.s3_bucket_name}",
        "arn:aws:s3:::${var.s3_bucket_name}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_s3_read_only" {
  role       = aws_iam_role.kubernetes_s3_access.name
  policy_arn = aws_iam_policy.s3_read_only.arn
}

### ✅ S3 Bucket Policy (Directly on Bucket)
resource "aws_s3_bucket_policy" "kubernetes_cluster_automated_policy" {
  bucket = aws_s3_bucket.kubernetes_cluster_automated.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.s3_iam_role_name}"
      },
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      Resource = [
        "arn:aws:s3:::${var.s3_bucket_name}",
        "arn:aws:s3:::${var.s3_bucket_name}/*"
      ]
    }]
  })
}

resource "aws_s3_bucket_public_access_block" "kubernetes_cluster_automated" {
  bucket                  = aws_s3_bucket.kubernetes_cluster_automated.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kubernetes_cluster_automated" {
  bucket = aws_s3_bucket.kubernetes_cluster_automated.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_instance_profile" "kubernetes_s3_access_profile" {
  name = "${local.s3_iam_role_name}-profile"
  role = aws_iam_role.kubernetes_s3_access.name
}
