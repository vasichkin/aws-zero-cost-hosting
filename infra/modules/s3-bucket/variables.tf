variable "bucket_name" {
  description = "Globally unique S3 bucket name."
  type        = string
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}

variable "enable_cors" {
  description = "Whether to enable CORS rules on the bucket."
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "Allowed origins for CORS when enable_cors is true."
  type        = list(string)
  default     = []
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for rollback safety."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Days before noncurrent object versions are permanently deleted. 0 disables expiry."
  type        = number
  default     = 30
}

