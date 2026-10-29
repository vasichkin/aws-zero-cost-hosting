variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "minimal-aws"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "site_bucket_name" {
  description = "Globally unique name of the S3 bucket for the site content."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.site_bucket_name)) && !can(regex("\\.\\.", var.site_bucket_name))
    error_message = "Must be a valid S3 bucket name: 3-63 chars, lowercase letters, digits, '.' and '-', starting and ending with a letter or digit."
  }
}

variable "aws_region" {
  description = "AWS region for regional resources."
  type        = string
  default     = "eu-west-3"
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
