output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "authorizer_id" {
  description = "Cognito JWT authorizer ID for admin routes."
  value       = aws_apigatewayv2_authorizer.cognito.id
}

output "api_endpoint" {
  description = "Default execute-api endpoint."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "custom_domain" {
  description = "Custom API domain name when enabled."
  value       = var.enable_custom_domain ? aws_apigatewayv2_domain_name.this[0].domain_name : ""
}

output "api_dns_record" {
  description = "DNS record to add at your registrar for the API custom domain."
  value = var.enable_custom_domain ? {
    name  = var.domain_name
    type  = "CNAME"
    value = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name
  } : null
}
