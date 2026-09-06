variable "user_pool_name" {
  description = "Cognito user pool name."
  type        = string
}

variable "admin_callback_urls" {
  description = "OAuth callback URLs for the admin SPA."
  type        = list(string)
}

variable "admin_logout_urls" {
  description = "OAuth logout URLs for the admin SPA."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to Cognito resources."
  type        = map(string)
  default     = {}
}

resource "aws_cognito_user_pool" "this" {
  name = var.user_pool_name

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  username_attributes = ["email"]

  tags = merge(var.tags, {
    Name = var.user_pool_name
  })
}

resource "aws_cognito_user_pool_client" "admin" {
  name         = "${var.user_pool_name}-admin-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.admin_callback_urls
  logout_urls   = var.admin_logout_urls

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]
}

resource "aws_cognito_user_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Administrators with publish access"
}

output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "Cognito user pool ARN."
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_endpoint" {
  description = "Cognito user pool endpoint."
  value       = aws_cognito_user_pool.this.endpoint
}

output "admin_client_id" {
  description = "Cognito app client ID for the admin SPA."
  value       = aws_cognito_user_pool_client.admin.id
}

output "admin_group_name" {
  description = "Name of the admin Cognito group."
  value       = aws_cognito_user_group.admins.name
}
