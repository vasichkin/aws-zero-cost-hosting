output "state_bucket_name" {
  description = "Name of the S3 bucket used for OpenTofu remote state."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket used for OpenTofu remote state."
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for OpenTofu state locking."
  value       = aws_dynamodb_table.lock.name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB table used for OpenTofu state locking."
  value       = aws_dynamodb_table.lock.arn
}
