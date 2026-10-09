variable "api_name" {
  description = "HTTP API name."
  type        = string
}

variable "cors_allow_origins" {
  description = "Allowed CORS origins."
  type        = list(string)
}

variable "cognito_user_pool_id" {
  description = "Cognito user pool ID for JWT issuer."
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito app client ID for JWT audience validation."
  type        = string
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
  description = "Sustained requests per second for the public contact route."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags applied to API Gateway resources."
  type        = map(string)
  default     = {}
}
