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

resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_validation ? 1 : 0

  provider = aws

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for dvo in aws_acm_certificate.this.domain_validation_options : dvo.resource_record_name]
}
