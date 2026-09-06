terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws]
    }
  }
}

variable "domain_name" {
  description = "Primary domain name for the certificate."
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional SANs for the certificate (e.g. *.example.com)."
  type        = list(string)
  default     = []
}
