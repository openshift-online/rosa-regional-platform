# =============================================================================
# API Gateway Integrations
#
# HTTP_PROXY integration forwards requests to the internal ALB via VPC Link.
# Identity headers are passed to the backend for authorization decisions.
# =============================================================================

# -----------------------------------------------------------------------------
# Proxy Integration: {proxy+}
#
# Forwards all requests to the ALB, preserving the path.
# Passes AWS IAM identity information in headers.
# -----------------------------------------------------------------------------

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_apigatewayv2_vpc_link.main.id
  integration_target      = aws_lb.frontend.arn # Required for VPC Link v2 + ALB
  uri                     = "http://${aws_lb.frontend.dns_name}/{proxy}"

  # Pass the path parameter through
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"

    # Forward AWS IAM identity information to the backend
    "integration.request.header.X-Amz-Caller-Arn" = "context.identity.userArn"
    "integration.request.header.X-Amz-Account-Id" = "context.identity.accountId"
    "integration.request.header.X-Amz-User-Id"    = "context.identity.user"
    "integration.request.header.X-Amz-Source-Ip"  = "context.identity.sourceIp"
  }
}

# -----------------------------------------------------------------------------
# Root Integration: /
#
# Handles requests to the root path.
# -----------------------------------------------------------------------------

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_rest_api.main.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_apigatewayv2_vpc_link.main.id
  integration_target      = aws_lb.frontend.arn # Required for VPC Link v2 + ALB
  uri                     = "http://${aws_lb.frontend.dns_name}/"

  # Forward AWS IAM identity information to the backend
  request_parameters = {
    "integration.request.header.X-Amz-Caller-Arn" = "context.identity.userArn"
    "integration.request.header.X-Amz-Account-Id" = "context.identity.accountId"
    "integration.request.header.X-Amz-User-Id"    = "context.identity.user"
    "integration.request.header.X-Amz-Source-Ip"  = "context.identity.sourceIp"
  }
}
