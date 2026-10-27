output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Default execute-api endpoint."
  value       = aws_apigatewayv2_api.this.api_endpoint
}
