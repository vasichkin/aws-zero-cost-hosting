resource "aws_acm_certificate" "this" {
  provider = aws

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = merge(var.tags, {
    Name = var.domain_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = var.route53_zone_id != "" ? {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "this" {
  count = local.wait_for_validation ? 1 : 0

  provider = aws

  certificate_arn = aws_acm_certificate.this.arn
  validation_record_fqdns = var.route53_zone_id != "" ? [
    for record in aws_route53_record.validation : record.fqdn
  ] : [for dvo in aws_acm_certificate.this.domain_validation_options : dvo.resource_record_name]
}
