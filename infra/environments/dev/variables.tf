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
