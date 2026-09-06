variable "project_name" {
  description = "Project name used as prefix for bootstrap resources."
  type        = string
  default     = "minimal-aws"
}

variable "aws_region" {
  description = "AWS region for the state bucket and lock table."
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
