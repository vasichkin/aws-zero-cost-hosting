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

output "website_sync" {
  description = "State of the website/ sync (aws s3 sync + CloudFront invalidation, run on apply)."
  value = {
    source_dir   = abspath("${path.module}/../../../website")
    file_count   = module.website_sync.file_count
    content_hash = module.website_sync.content_hash
  }
}

output "website_sync_command" {
  description = "Manual equivalent of the apply-time sync (aws s3 sync + CloudFront invalidation). Used by `make dev-sync` / `make prod-sync`."
  value       = "SOURCE_DIR='${abspath("${path.module}/../../../website")}' BUCKET='${module.site_bucket.bucket_id}' DISTRIBUTION_ID='${module.cloudfront.distribution_id}' AWS_REGION='${var.aws_region}' '${module.website_sync.script_path}'"
}
