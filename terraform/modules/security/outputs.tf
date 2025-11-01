output "profile_id" {
  description = "ID of security profile, e.g., AWS iam instance profile"
  value       = var.cloud_type == "aws" && var.backend_type == "s3" ? aws_iam_instance_profile.kubernetes_s3_access_profile[0].id : null
}
