resource "aws_apigatewayv2_api" "this" {
  name          = var.api_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["authorization", "content-type"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = var.cors_allow_origins
  }

  tags = merge(var.tags, {
    Name = var.api_name
  })
}

# JWT authorizer kept for the admin API (separate project) to attach routes to.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

resource "aws_apigatewayv2_integration" "contact" {
  count = var.enable_contact_route ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.contact_lambda_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact" {
  count = var.enable_contact_route ? 1 : 0

  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact[0].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  route_settings {
    route_key              = "POST /contact"
    throttling_burst_limit = var.contact_throttling_burst_limit
    throttling_rate_limit  = var.contact_throttling_rate_limit
  }

  tags = var.tags
}

resource "aws_apigatewayv2_domain_name" "this" {
  count = var.enable_custom_domain ? 1 : 0

  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = var.acm_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = var.enable_custom_domain ? 1 : 0

  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this[0].id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_route53_record" "api" {
  count = var.enable_custom_domain && var.route53_zone_id != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_lambda_permission" "contact" {
  count = var.enable_contact_route ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeContact"
  action        = "lambda:InvokeFunction"
  function_name = var.contact_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

data "aws_region" "current" {}
