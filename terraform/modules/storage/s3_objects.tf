resource "aws_s3_object" "stored_files" {
  for_each = var.backend_type == "s3" ? var.files : {}

  bucket   = aws_s3_bucket.storage[0].id
  key      = each.key
  content  = each.value
}
