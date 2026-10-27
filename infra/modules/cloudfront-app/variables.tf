variable "distribution_name" {
  description = "CloudFront distribution name tag."
  type        = string
}

variable "aliases" {
  description = "Custom domain aliases (empty for CloudFront default domain)."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1. Empty uses CloudFront default certificate."
  type        = string
  default     = ""
}

variable "site_bucket" {
  description = "S3 bucket for all static content (/ and /photos/ prefixes)."
  type = object({
    id                       = string
    arn                      = string
    regional_domain_name     = string
    origin_access_control_id = string
  })
}

variable "api_origin_domain" {
  description = "API Gateway execute-api hostname without scheme."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Tags applied to CloudFront resources."
  type        = map(string)
  default     = {}
}
