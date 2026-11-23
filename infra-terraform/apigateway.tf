# =============================================================================
# Patron 5 (API Gateway): HTTP API publica con throttling -> VPC Link -> ALB interno
# =============================================================================

resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpclink-sg"
  description = "ENIs del VPC Link de API Gateway"
  vpc_id      = aws_vpc.app.id

  egress {
    description = "Hacia el ALB interno"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.app_cidr]
  }

  tags = { Name = "${local.name}-vpclink-sg" }
}

resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${local.name}-vpc-link"
  subnet_ids         = aws_subnet.app_private[*].id
  security_group_ids = [aws_security_group.vpc_link.id]
}

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
  description   = "MiniStore Express - API publica de ordenes"
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.app.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.main.id
  payload_format_version = "1.0"
  timeout_milliseconds   = 29000
}

# Solo se expone /api/*: actuator y cualquier otra ruta del backend quedan ocultas
resource "aws_apigatewayv2_route" "api" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.name}-api"
  retention_in_days = 3
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # Control de tasa: protege al backend (y al legado) de picos de trafico
  default_route_settings {
    throttling_rate_limit  = var.api_throttle_rate
    throttling_burst_limit = var.api_throttle_burst
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      method           = "$context.httpMethod"
      path             = "$context.path"
      status           = "$context.status"
      latencyMs        = "$context.responseLatency"
      integrationMs    = "$context.integrationLatency"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}
