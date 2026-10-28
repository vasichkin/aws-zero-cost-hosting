variable "api_name" {
  description = "HTTP API name."
  type        = string
}

variable "cors_allow_origins" {
  description = "Allowed CORS origins. Empty disables CORS."
  type        = list(string)
  default     = []
}

variable "contact_lambda_invoke_arn" {
  description = "Invoke ARN of the contact Lambda."
  type        = string
  default     = ""
}

variable "contact_lambda_function_name" {
  description = "Function name of the contact Lambda."
  type        = string
  default     = ""
}

variable "enable_contact_route" {
  description = "Whether to expose POST /contact on the API."
  type        = bool
  default     = true
}

variable "contact_throttling_burst_limit" {
  description = "Maximum burst requests for the public contact route."
  type        = number
  default     = 10
}

variable "contact_throttling_rate_limit" {
  description = "Sustained requests per second for the public contact route (fractions allowed, e.g. 1/60 = one per minute)."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags applied to API Gateway resources."
  type        = map(string)
  default     = {}
}
