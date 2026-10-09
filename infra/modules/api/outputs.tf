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
