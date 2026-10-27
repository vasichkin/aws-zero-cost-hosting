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
  description = "Google reCAPTCHA v3 secret used only by the contact Lambda."
  type        = string
  sensitive   = true
}

variable "recaptcha_min_score" {
  description = "Minimum accepted Google reCAPTCHA v3 score for contact submissions."
  type        = number
  default     = 0.5

  validation {
    condition     = var.recaptcha_min_score >= 0 && var.recaptcha_min_score <= 1
    error_message = "recaptcha_min_score must be between 0 and 1."
  }
}

variable "admin_email" {
  description = "Email that receives AWS budget alerts."
  type        = string
}

variable "acm_wait_for_validation" {
  description = "Wait for ACM DNS validation. false = first apply (add registrar CNAMEs, then set true)."
  type        = bool
  default     = false
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
