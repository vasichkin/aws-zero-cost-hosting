output "certificate_arn" {
  description = "ACM certificate ARN (validated when wait_for_validation is true)."
  value       = var.wait_for_validation ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "certificate_status" {
  description = "Whether the certificate has completed DNS validation."
  value       = var.wait_for_validation ? "validated" : "pending_validation"
}

output "dns_validation_records" {
  description = "DNS records to add at your registrar for certificate validation."
  value = [
    for dvo in aws_acm_certificate.this.domain_validation_options : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
}
