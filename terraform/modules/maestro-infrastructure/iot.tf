# =============================================================================
# AWS IoT Core Resources
#
# Creates IoT Things, certificates, and policies for Maestro Server and Agents
# to communicate over MQTT on port 8883 with certificate-based authentication
# =============================================================================

# Get AWS IoT Core MQTT endpoint
data "aws_iot_endpoint" "mqtt" {
  endpoint_type = "iot:Data-ATS"
}

# Download AWS IoT Root CA certificate
data "http" "aws_iot_root_ca" {
  url = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
}

# =============================================================================
# Maestro Server - IoT Thing and Certificate
# =============================================================================

resource "aws_iot_thing" "maestro_server" {
  name = "${var.resource_name_base}-maestro-server"

  attributes = {
    component = "maestro-server"
    cluster   = var.resource_name_base
  }
}

resource "aws_iot_certificate" "maestro_server" {
  active = true
}

resource "aws_iot_thing_principal_attachment" "maestro_server" {
  thing     = aws_iot_thing.maestro_server.name
  principal = aws_iot_certificate.maestro_server.arn
}

# IoT Policy for Maestro Server (Publisher)
resource "aws_iot_policy" "maestro_server" {
  name = "${var.resource_name_base}-maestro-server-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:client/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topic/sources/maestro/consumers/*/sourceevents",
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topic/sources/maestro/consumers/*/agentevents"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Subscribe"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topicfilter/sources/maestro/consumers/*/agentevents"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Receive"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topic/sources/maestro/consumers/*/agentevents"
        ]
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.resource_name_base}-maestro-server-policy"
      Component = "maestro-server"
    }
  )
}

resource "aws_iot_policy_attachment" "maestro_server" {
  policy = aws_iot_policy.maestro_server.name
  target = aws_iot_certificate.maestro_server.arn
}

# =============================================================================
# Maestro Agent - IoT Things and Certificates (one per management cluster)
# =============================================================================

resource "aws_iot_thing" "maestro_agent" {
  count = var.management_cluster_count

  name = "${var.management_cluster_ids[count.index]}-maestro-agent"

  attributes = {
    component        = "maestro-agent"
    cluster          = var.management_cluster_ids[count.index]
    regional_cluster = var.resource_name_base
  }
}

resource "aws_iot_certificate" "maestro_agent" {
  count = var.management_cluster_count

  active = true
}

resource "aws_iot_thing_principal_attachment" "maestro_agent" {
  count = var.management_cluster_count

  thing     = aws_iot_thing.maestro_agent[count.index].name
  principal = aws_iot_certificate.maestro_agent[count.index].arn
}

# IoT Policy for Maestro Agents (Subscriber)
resource "aws_iot_policy" "maestro_agent" {
  count = var.management_cluster_count

  name = "${var.management_cluster_ids[count.index]}-maestro-agent-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:client/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Subscribe"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topicfilter/sources/maestro/consumers/${var.management_cluster_ids[count.index]}/sourceevents"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Receive"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topic/sources/maestro/consumers/${var.management_cluster_ids[count.index]}/sourceevents"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topic/sources/maestro/consumers/${var.management_cluster_ids[count.index]}/agentevents"
        ]
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name              = "${var.management_cluster_ids[count.index]}-maestro-agent-policy"
      Component         = "maestro-agent"
      ManagementCluster = var.management_cluster_ids[count.index]
    }
  )
}

resource "aws_iot_policy_attachment" "maestro_agent" {
  count = var.management_cluster_count

  policy = aws_iot_policy.maestro_agent[count.index].name
  target = aws_iot_certificate.maestro_agent[count.index].arn
}
