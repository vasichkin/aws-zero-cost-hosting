output "site_url" {
  description = "Public website URL (CloudFront default domain)."
  value       = "https://${module.cloudfront.domain_name}/"
}

output "api_url" {
  description = "API path on CloudFront."
  value       = "https://${module.cloudfront.domain_name}/api/"
}

output "site_bucket_name" {
  description = "S3 bucket for site assets."
  value       = module.site_bucket.bucket_id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.cloudfront.distribution_id
}
