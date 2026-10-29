variable "project_name" {
  description = "Project name used as prefix for bootstrap resources."
  type        = string
  default     = "minimal-aws"
}

variable "state_bucket_name" {
  description = "Globally unique name of the S3 bucket that holds the OpenTofu remote state. Must match `bucket` in infra/environments/prod/backend.hcl."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name)) && !can(regex("\\.\\.", var.state_bucket_name))
    error_message = "Must be a valid S3 bucket name: 3-63 chars, lowercase letters, digits, '.' and '-', starting and ending with a letter or digit."
  }
}

variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-3"
}

variable "tags" {
  description = "Tags applied to all bootstrap resources."
  type        = map(string)
  default = {
    Owner   = "CHANGE_ME"
    Project = "minimal_aws_hosting"
  }
}
