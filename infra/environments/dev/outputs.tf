output "site_url" {
  description = "Public website URL (CloudFront default domain)."
  value       = "https://${module.cloudfront.domain_name}/"
}

output "admin_url" {
  description = "Admin path on CloudFront (use localhost:5173 for local dev)."
  value       = "https://${module.cloudfront.domain_name}/admin/"
}

output "api_url" {
  description = "API path on CloudFront."
  value       = "https://${module.cloudfront.domain_name}/api/"
}

output "site_bucket_name" {
  description = "S3 bucket for site + admin assets."
  value       = module.site_bucket.bucket_id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.cloudfront.distribution_id
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID."
  value       = module.cognito.user_pool_id
}

output "cognito_admin_client_id" {
  description = "Cognito app client ID."
  value       = module.cognito.admin_client_id
}
