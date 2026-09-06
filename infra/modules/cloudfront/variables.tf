variable "distribution_name" {
  description = "Short name used in CloudFront resource tags."
  type        = string
}

variable "aliases" {
  description = "Custom domain aliases for the distribution."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for custom domains. Leave empty to use CloudFront default certificate."
  type        = string
  default     = ""
}

variable "origin_domain_name" {
  description = "Origin domain name (S3 regional domain)."
  type        = string
}

variable "origin_access_control_id" {
  description = "Origin Access Control ID for the S3 origin."
  type        = string
}

variable "default_root_object" {
  description = "Default root object for the distribution."
  type        = string
  default     = "index.html"
}

variable "enable_spa_fallback" {
  description = "Map 403/404 errors to index.html for SPA routing."
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Tags applied to the distribution."
  type        = map(string)
  default     = {}
}

variable "bucket_id" {
  description = "S3 bucket ID for the origin access policy."
  type        = string
}

variable "bucket_arn" {
  description = "S3 bucket ARN for the origin access policy."
  type        = string
}
