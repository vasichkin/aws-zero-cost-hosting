variable "domain_name" {
  description = "Primary domain name for the hosted zone."
  type        = string
}

variable "create_zone" {
  description = "Whether to create a new Route53 hosted zone. Set false if zone already exists."
  type        = bool
  default     = true
}

variable "zone_id" {
  description = "Existing Route53 zone ID when create_zone is false."
  type        = string
  default     = ""
}

variable "site_cloudfront" {
  description = "CloudFront distribution domain name and zone ID for the public site."
  type = object({
    domain_name    = string
    hosted_zone_id = string
  })
}

variable "admin_cloudfront" {
  description = "CloudFront distribution domain name and zone ID for the admin SPA."
  type = object({
    domain_name    = string
    hosted_zone_id = string
  })
}

variable "tags" {
  description = "Tags applied to DNS resources."
  type        = map(string)
  default     = {}
}

resource "aws_route53_zone" "this" {
  count = var.create_zone ? 1 : 0

  name = var.domain_name

  tags = merge(var.tags, {
    Name = var.domain_name
  })
}

locals {
  zone_id = var.create_zone ? aws_route53_zone.this[0].zone_id : var.zone_id
}

resource "aws_route53_record" "site" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.site_cloudfront.domain_name
    zone_id                = var.site_cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_ipv6" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = var.site_cloudfront.domain_name
    zone_id                = var.site_cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "admin" {
  zone_id = local.zone_id
  name    = "admin.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.admin_cloudfront.domain_name
    zone_id                = var.admin_cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "admin_ipv6" {
  zone_id = local.zone_id
  name    = "admin.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = var.admin_cloudfront.domain_name
    zone_id                = var.admin_cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}

output "zone_id" {
  description = "Route53 hosted zone ID."
  value       = local.zone_id
}

output "name_servers" {
  description = "Route53 name servers for the hosted zone."
  value       = var.create_zone ? aws_route53_zone.this[0].name_servers : []
}
