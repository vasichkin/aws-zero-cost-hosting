variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "minimal-aws"
}

variable "environment" {
  description = "Environment name (e.g. prod, dev)."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for regional resources."
  type        = string
  default     = "eu-west-3"
}

variable "domain_name" {
  description = "Primary domain name (e.g. example.com)."
  type        = string
}

variable "ses_email" {
  description = "Verified SES email for contact form send/receive."
  type        = string
}

variable "recaptcha_secret_key" {
  description = "Google reCAPTCHA v2 secret used only by the contact Lambda."
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Cognito admin user email."
  type        = string
}

variable "acm_wait_for_validation" {
  description = "Wait for ACM DNS validation. false = first apply (add registrar CNAMEs, then set true)."
  type        = bool
  default     = false
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for publish Lambda. Set after first apply from output."
  type        = string
  default     = ""
}

variable "iam_permissions_boundary_arn" {
  description = "Optional permissions boundary ARN applied to all Lambda execution roles."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default = {
    Owner   = "CHANGE_ME"
    Project = "minimal_aws_hosting"
  }
}
