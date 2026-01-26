# =============================================================================
# IAM Roles for Maestro Components
#
# Creates IAM roles for use with EKS Pod Identity:
# - Maestro Server: Access to RDS, IoT Core (publish), Secrets Manager
# - Maestro Agent: Access to IoT Core (subscribe), Secrets Manager
# - External Secrets Operator: Access to Secrets Manager (read-only)
# =============================================================================

# =============================================================================
# Maestro Server IAM Role
# =============================================================================

resource "aws_iam_role" "maestro_server" {
  name        = "${var.resource_name_base}-maestro-server"
  description = "IAM role for Maestro Server with access to RDS, IoT, and Secrets Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.resource_name_base}-maestro-server-role"
      Component = "maestro-server"
    }
  )
}

# Maestro Server Policy - IoT Core publish permissions
resource "aws_iam_role_policy" "maestro_server_iot" {
  name = "${var.resource_name_base}-maestro-server-iot-policy"
  role = aws_iam_role.maestro_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Publish",
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:client/${var.resource_name_base}-maestro-server-*",
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topic/${var.mqtt_topic_prefix}/*",
          "arn:aws:iot:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:topicfilter/${var.mqtt_topic_prefix}/*"
        ]
      }
    ]
  })
}

# Maestro Server Policy - Secrets Manager read access
resource "aws_iam_role_policy" "maestro_server_secrets" {
  name = "${var.resource_name_base}-maestro-server-secrets-policy"
  role = aws_iam_role.maestro_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.maestro_server_mqtt_cert.arn,
          aws_secretsmanager_secret.maestro_db_credentials.arn,
          aws_secretsmanager_secret.maestro_consumers.arn
        ]
      }
    ]
  })
}

# Pod Identity Association for Maestro Server
resource "aws_eks_pod_identity_association" "maestro_server" {
  cluster_name    = var.eks_cluster_name
  namespace       = "maestro"
  service_account = "maestro-server"
  role_arn        = aws_iam_role.maestro_server.arn

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.resource_name_base}-maestro-server-pod-identity"
      Component = "maestro-server"
    }
  )
}

