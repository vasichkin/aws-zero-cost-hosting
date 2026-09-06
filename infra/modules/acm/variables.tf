variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS validation records. Leave empty for external DNS."
  type        = string
  default     = ""
}

variable "wait_for_validation" {
  description = "Block until ACM DNS validation completes. Set false on first apply with external DNS."
  type        = bool
  default     = null
}

variable "tags" {
  description = "Tags applied to the certificate."
  type        = map(string)
  default     = {}
}

locals {
  wait_for_validation = coalesce(var.wait_for_validation, var.route53_zone_id != "")
}
