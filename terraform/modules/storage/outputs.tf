output "storage_id" {
  description = "The ID (name) of the storage resource"
  value       = var.backend_type == "s3" ? aws_s3_bucket.storage[0].id : null
}

output "file_urls" {
  description = "A map of file paths to their URLS"
  value       = var.backend_type == "s3" ? {for file in aws_s3_object.stored_files : file.key => "s3://${aws_s3_bucket.storage[0].id}/${file.key}" } : {}
}
