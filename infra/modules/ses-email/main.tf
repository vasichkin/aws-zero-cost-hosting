variable "email_address" {
  description = "Email address to verify for SES sending."
  type        = string
}

variable "tags" {
  description = "Tags applied to SES resources."
  type        = map(string)
  default     = {}
}

resource "aws_ses_email_identity" "this" {
  email = var.email_address
}

output "email_identity_arn" {
  description = "SES email identity ARN for IAM policies."
  value       = aws_ses_email_identity.this.arn
}

output "email_address" {
  description = "Verified SES email address."
  value       = aws_ses_email_identity.this.email
}

output "verification_note" {
  description = "Action required after first apply."
  value       = "Check the inbox for ${var.email_address} and click the AWS SES verification link."
}
