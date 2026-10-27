resource "aws_apigatewayv2_api" "this" {
  name          = var.api_name
  protocol_type = "HTTP"

  dynamic "cors_configuration" {
    for_each = length(var.cors_allow_origins) > 0 ? [1] : []

    content {
      allow_headers = ["content-type"]
      allow_methods = ["POST", "OPTIONS"]
      allow_origins = var.cors_allow_origins
    }
  }

  tags = merge(var.tags, {
    Name = var.api_name
  })
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

resource "aws_lambda_permission" "contact" {
  count = var.enable_contact_route ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeContact"
  action        = "lambda:InvokeFunction"
  function_name = var.contact_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
