output "uploaded_keys" {
  description = "S3 object keys uploaded from source_dir."
  value       = sort(keys(aws_s3_object.this))
}

output "object_count" {
  description = "Number of objects uploaded."
  value       = length(aws_s3_object.this)
}
