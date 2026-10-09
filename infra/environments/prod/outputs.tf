output "www_url" {
  description = "Public website URL (www subdomain)."
  value       = "https://${local.www_domain}/"
}

output "site_url" {
  description = "Public website URL."
  value       = "https://${var.domain_name}/"
}

output "admin_url" {
  description = "Admin panel URL."
  value       = "https://${var.domain_name}/admin/"
}

output "photos_url" {
  description = "Photos CDN base URL."
  value       = "https://${var.domain_name}/photos/"
}

output "api_url" {
  description = "API base URL (via CloudFront path routing)."
  value       = "https://${var.domain_name}/api/"
}

output "site_bucket_name" {
  description = "S3 bucket for all static content (site, admin, photos prefixes)."
  value       = module.site_bucket.bucket_id
}

output "bucket_layout" {
  description = "S3 key prefix layout inside the single bucket."
  value = {
    site   = "/"
    admin  = "admin/"
    photos = "photos/"
  }
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for manual invalidations)."
  value       = try(module.cloudfront.distribution_id, null)
}

output "cloudfront_domain_name" {
  description = "CloudFront domain for registrar CNAME (available after cloudfront module is applied)."
  value       = try(module.cloudfront.domain_name, null)
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID."
  value       = try(module.cognito.user_pool_id, null)
}

output "cognito_admin_client_id" {
  description = "Cognito app client ID for admin SPA."
  value       = try(module.cognito.admin_client_id, null)
}

output "admin_email" {
  description = "Email for the Cognito admin account (create manually after apply)."
  value       = var.admin_email
}

output "ses_verification_note" {
  description = "SES email verification instructions."
  value       = try(module.ses.verification_note, null)
}

# Available after: tofu apply -target=module.acm
output "acm_dns_validation_records" {
  description = "ACM DNS validation CNAMEs — add at registrar before setting acm_wait_for_validation = true."
  value       = try(module.acm.dns_validation_records, [])
}

output "dns_records_manual" {
  description = "All DNS records for registrar (partial until full stack is applied)."
  value = {
    acm_validation = try(module.acm.dns_validation_records, [])
    site_apex = try(module.cloudfront.domain_name, null) != null ? {
      name  = var.domain_name
      type  = "CNAME"
      value = module.cloudfront.domain_name
      note  = "Often blocked at apex when MX exists — use registrar ALIAS or redirect apex to www"
    } : null
    site_www = try(module.cloudfront.domain_name, null) != null ? {
      name  = "www"
      type  = "CNAME"
      value = module.cloudfront.domain_name
    } : null
  }
}
